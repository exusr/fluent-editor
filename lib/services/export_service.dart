import 'dart:convert';
import 'dart:io' show File, HttpClient, Platform, Process;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_selector/file_selector.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/utils/editor_utils.dart';
import 'package:flutter/services.dart';

// Conditional import for web-specific download functionality
import 'export_service_web_stub.dart'
    if (dart.library.html) 'export_service_web_html.dart'
    // ignore: unused_import
    ;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:vector_math/vector_math_64.dart';

import 'docx_exporter.dart';
import 'odt_exporter.dart';
import 'pdf_font_provider.dart';

/// Service for exporting the document to various formats.
class _CommentSeg {
  final int start;
  final int end;
  final Map<String, dynamic> comment;
  _CommentSeg(this.start, this.end, this.comment);
}

class _TextSeg {
  final String text;
  final Map<String, dynamic>? comment;
  _TextSeg(this.text, this.comment);
}

List<_TextSeg> _extractSegments(String text, int baseOffset, List<_CommentSeg> segs) {
  final result = <_TextSeg>[];
  int pos = 0;
  final textLen = text.length;
  for (final seg in segs) {
    if (seg.end <= baseOffset || seg.start >= baseOffset + textLen) continue;
    final segStartLocal = (seg.start - baseOffset).clamp(0, textLen);
    final segEndLocal = (seg.end - baseOffset).clamp(0, textLen);
    if (pos < segStartLocal) {
      result.add(_TextSeg(text.substring(pos, segStartLocal), null));
    }
    if (segStartLocal < segEndLocal) {
      result.add(_TextSeg(text.substring(segStartLocal, segEndLocal), seg.comment));
    }
    pos = segEndLocal;
    if (pos >= textLen) break;
  }
  if (pos < textLen) {
    result.add(_TextSeg(text.substring(pos), null));
  }
  if (result.isEmpty) {
    result.add(_TextSeg(text, null));
  }
  return result;
}

/// Invisible inline widget that adds a PdfAnnotText (sticky note) on the
/// right margin of the page at the exact Y where the text is rendered.
class _CommentAnnotWidget extends pw.Widget {
  _CommentAnnotWidget({
    required this.commentText,
    required this.authorName,
    required this.subject,
    required this.usedYs,
  });

  final String commentText;
  final String authorName;
  final String subject;
  final Map<dynamic, List<double>> usedYs;

  @override
  void layout(pw.Context context, pw.BoxConstraints constraints, {bool parentUsesSize = false}) {
    box = PdfRect(0, 0, 0, 0);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    final mat = context.canvas.getTransform();
    final lt = mat.transform3(Vector3(box!.left, box!.top, 0));
    final page = context.page;
    final existing = usedYs.putIfAbsent(page, () => <double>[]);
    const step = 18.0;
    const threshold = 28.0;
    double y = lt.y;
    while (existing.any((ey) => (ey - y).abs() < threshold)) {
      y -= step;
    }
    existing.add(y);
    final x = page.pageFormat.width - 130; // right margin
    final annot = PdfAnnotText(
      rect: PdfRect(x, y, 110, 35),
      content: commentText,
      author: authorName.isNotEmpty ? authorName : 'Anonimo',
      subject: subject.isNotEmpty ? subject : 'Comment',
      color: PdfColor.fromHex('#FFEB3B'),
    );
    PdfAnnot(page, annot);
  }
}

class ExportService {
  final FluentDocument document;

  /// Cache for images downloaded from external URLs.
  final Map<String, Uint8List> _imageCache = {};

  /// Provider for TTF fonts with Unicode support.
  final PdfFontProvider _fontProvider = PdfFontProvider();

  ExportService(this.document);

  /// Downloads an image from external URL or loads a local asset and puts it in cache.
  Future<Uint8List?> _fetchImage(String url) async {
    if (_imageCache.containsKey(url)) return _imageCache[url];
    if (kIsWeb) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 5);
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode == 200) {
          final builder = BytesBuilder();
          await for (final chunk in response) {
            builder.add(chunk);
          }
          final bytes = builder.toBytes();
          _imageCache[url] = bytes;
          return bytes;
        }
      } catch (_) {}
    } else {
      // Local asset
      try {
        final data = await rootBundle.load(url);
        final bytes = data.buffer.asUint8List();
        _imageCache[url] = bytes;
        return bytes;
      } catch (_) {}
    }
    return null;
  }

  /// Pre-fetches all images of the document.
  Future<void> _prefetchImages() async {
    final root = document.content;
    final urls = <String>{};
    _collectImageUrls(root.nodes, urls);
    await Future.wait(urls.map((url) => _fetchImage(url)));
  }

  void _collectImageUrls(List<FNode> nodes, Set<String> urls) {
    for (final node in nodes) {
      if (node is FluentImage && !node.src.startsWith('data:')) {
        urls.add(node.src);
      } else if (node is Link) {
        _collectImageUrls(node.fragments, urls);
      } else if (node is Paragraph) {
        _collectImageUrls(node.fragments, urls);
      } else if (node is FluentList) {
        for (final item in node.items) {
          _collectImageUrls(item.children, urls);
        }
      } else if (node is FluentTable) {
        for (final row in node.rows) {
          for (final cell in row.cells) {
            _collectImageUrls(cell.children, urls);
          }
        }
      }
    }
  }

  /// Collects all unique font families used in the document (fragments + styles).
  Set<String> _collectFontFamilies(List<FNode> nodes) {
    final families = <String>{};

    void scanFragments(List<FNode> fragments) {
      for (final frag in fragments) {
        if (frag is Fragment && frag.fontFamily.isNotEmpty) {
          families.add(frag.fontFamily);
        } else if (frag is Link) {
          scanFragments(frag.fragments);
        }
      }
    }

    for (final node in nodes) {
      if (node is Paragraph) {
        final style = node.getStyle();
        if (style.fontFamily != null && style.fontFamily!.isNotEmpty) {
          families.add(style.fontFamily!);
        }
        scanFragments(node.fragments);
      } else if (node is FluentList) {
        for (final item in node.items) {
          families.addAll(_collectFontFamilies(item.children));
        }
      } else if (node is FluentTable) {
        for (final row in node.rows) {
          for (final cell in row.cells) {
            families.addAll(_collectFontFamilies(cell.children));
          }
        }
      } else if (node is Link) {
        scanFragments(node.fragments);
      }
    }

    return families;
  }

  // ─── PDF ────────────────────────────────────────────────────────────

  FluentEditorLabels? get _labels => document.labels;

  Future<Uint8List> exportToPdf() async {
    final fontFamilies = _collectFontFamilies(document.content.nodes);

    // Initialize TTF fonts (with document-specific families) and pre-fetch images in parallel
    await Future.wait([
      _fontProvider.init(fontFamilies),
      _prefetchImages(),
    ]);

    final pdf = pw.Document();
    final root = document.content;

    final usedAnnotYs = <dynamic, List<double>>{};
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => _buildPdfNodes(root.nodes, 0, usedAnnotYs: usedAnnotYs),
      ),
    );

    // Sticky-note annotations are added dynamically during paint by
    // _CommentAnnotWidget placed inline at the start of each commented range.
    return await pdf.save();
  }

  /// Converts a list of nodes to PDF widgets.
  /// [depth] is the nesting level (for lists).
  List<pw.Widget> _buildPdfNodes(List<FNode> nodes, int depth, {
    List<Map<String,dynamic>>? comments,
    Map<dynamic, List<double>>? usedAnnotYs,
  }) {
    final widgets = <pw.Widget>[];
    final allComments = comments ?? document.commentProvider?.exportComments() ?? [];

    for (final node in nodes) {
      if (node is FluentImage) {
        widgets.add(_buildPdfImage(node));
      } else if (node is HorizontalRule) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Divider(thickness: 1, color: PdfColors.grey400),
        ));
      } else if (node is FluentList) {
        widgets.addAll(_buildPdfList(node, depth, comments: allComments, usedAnnotYs: usedAnnotYs));
      } else if (node is FluentTable) {
        widgets.add(_buildPdfTable(node, comments: allComments, usedAnnotYs: usedAnnotYs));
      } else if (node is Paragraph) {
        widgets.add(_buildPdfParagraph(node, comments: allComments, usedAnnotYs: usedAnnotYs));
      }
    }

    return widgets;
  }

  pw.Widget _buildPdfParagraph(Paragraph paragraph, {
    bool suppressIndent = false,
    bool inListItem = false,
    List<Map<String,dynamic>>? comments,
    Map<dynamic, List<double>>? usedAnnotYs,
  }) {
    final style = paragraph.getStyle();
    final isQuote = style.name == 'quote';
    final isCode = style.name == 'code';

    final spans = _buildPdfSpans(
      paragraph.fragments, style,
      paragraphId: paragraph.id,
      comments: comments,
      usedAnnotYs: usedAnnotYs,
    );

    if (spans.isEmpty) {
      return pw.SizedBox(height: (style.spacingAfter ?? document.pendingSpacingAfter));
    }

    final spacingBefore = inListItem ? 0.0 : (style.spacingBefore ?? document.pendingSpacingBefore);
    final spacingAfter = style.spacingAfter ?? document.pendingSpacingAfter;

    final lineHeight = style.lineHeight ?? document.pendingLineHeight;

    // SizedBox(width: infinity) to make textAlign work
    pw.Widget content = pw.SizedBox(
      width: double.infinity,
      child: pw.RichText(
        text: pw.TextSpan(
          children: spans,
          style: pw.TextStyle(lineSpacing: lineHeight),
        ),
        textAlign: _getPdfTextAlign(paragraph.textAlign),
      ),
    );

    // Quotation: gray left border + padding
    if (isQuote) {
      content = pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            left: pw.BorderSide(color: PdfColors.grey400, width: 3),
          ),
        ),
        padding: const pw.EdgeInsets.only(left: 12),
        child: content,
      );
    }

    // Code: light gray background + monospace font
    if (isCode) {
      content = pw.Container(
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        padding: const pw.EdgeInsets.all(8),
        child: content,
      );
    }

    return pw.Padding(
      padding: pw.EdgeInsets.only(
        left: (suppressIndent || inListItem) ? 0 : paragraph.indent * 24.0,
        top: spacingBefore,
        bottom: spacingAfter,
      ),
      child: content,
    );
  }

  /// Builds inline spans from a list of fragments.
  List<pw.InlineSpan> _buildPdfSpans(
    List<FNode> fragments,
    ParagraphStyle pStyle, {
    String? paragraphId,
    List<Map<String,dynamic>>? comments,
    Map<dynamic, List<double>>? usedAnnotYs,
  }) {
    final spans = <pw.InlineSpan>[];
    int globalOffset = 0;
    final segs = <_CommentSeg>[];
    final emittedAnnots = <String>{};
    if (comments != null && paragraphId != null) {
      for (final c in comments) {
        if (c['nodeId'] == paragraphId && c['resolved'] != true && c['orphan'] != true) {
          segs.add(_CommentSeg(
            c['startOffset'] as int,
            c['endOffset'] as int,
            c,
          ));
        }
      }
      segs.sort((a, b) => a.start.compareTo(b.start));
    }

    void _maybeEmitAnnot(Map<String, dynamic>? comment) {
      if (comment == null) return;
      final id = comment['id'] as String? ?? '';
      if (id.isEmpty || emittedAnnots.contains(id)) return;
      emittedAnnots.add(id);
      spans.add(pw.WidgetSpan(
        child: _CommentAnnotWidget(
          commentText: comment['text'] as String? ?? '',
          authorName: comment['authorName'] as String? ?? 'Anonimo',
          subject: _labels?.pdfCommentSubject ?? 'Comment',
          usedYs: usedAnnotYs ?? {},
        ),
      ));
    }

    for (final frag in fragments) {
      if (frag is Link) {
        int linkOffset = 0;
        for (final linkFrag in frag.fragments) {
          if (linkFrag is FluentImage) {
            final imgWidget = _buildPdfInlineImage(linkFrag);
            if (imgWidget != null) spans.add(pw.WidgetSpan(child: imgWidget));
          } else if (linkFrag is Fragment) {
            final subs = _extractSegments(linkFrag.text, globalOffset + linkOffset, segs);
            for (final sub in subs) {
              _maybeEmitAnnot(sub.comment);
              spans.add(pw.TextSpan(
                text: sub.text,
                style: _getPdfFragmentStyle(linkFrag, pStyle).copyWith(
                  color: PdfColors.blue,
                  decoration: pw.TextDecoration.underline,
                  background: sub.comment != null ? pw.BoxDecoration(color: PdfColor.fromHex('#FFEB3B')) : null,
                ),
              ));
            }
            linkOffset += linkFrag.text.length;
          }
        }
        globalOffset += linkOffset;
      } else if (frag is FluentImage) {
        final imgWidget = _buildPdfInlineImage(frag);
        if (imgWidget != null) spans.add(pw.WidgetSpan(child: imgWidget));
      } else if (frag is Fragment) {
        final fragStyles = frag.styles ?? [];
        if (fragStyles.contains('superscript') || fragStyles.contains('subscript')) {
          final isSup = fragStyles.contains('superscript');
          final style = _getPdfFragmentStyle(frag, pStyle);
          final baseFontSize = pStyle.fontSize ?? 14.0;
          final hasComment = segs.any((s) => s.start < globalOffset + frag.text.length && s.end > globalOffset);
          final widget = pw.Transform.translate(
            offset: PdfPoint(0, isSup ? baseFontSize * 0.35 : -(baseFontSize * 0.15)),
            child: pw.Text(frag.text, style: style),
          );
          if (hasComment) {
            _maybeEmitAnnot(segs.firstWhere(
              (s) => s.start < globalOffset + frag.text.length && s.end > globalOffset,
              orElse: () => _CommentSeg(0, 0, {}),
            ).comment);
            spans.add(pw.WidgetSpan(
              child: pw.Container(
                color: PdfColor.fromHex('#FFEB3B'),
                child: widget,
              ),
            ));
          } else {
            spans.add(pw.WidgetSpan(child: widget));
          }
        } else {
          final subs = _extractSegments(frag.text, globalOffset, segs);
          for (final sub in subs) {
            _maybeEmitAnnot(sub.comment);
            final style = _getPdfFragmentStyle(frag, pStyle);
            if (sub.comment != null) {
              spans.add(pw.TextSpan(
                text: sub.text,
                style: style.copyWith(background: pw.BoxDecoration(color: PdfColor.fromHex('#FFEB3B'))),
              ));
            } else {
              spans.add(pw.TextSpan(
                text: sub.text,
                style: style,
              ));
            }
          }
        }
        globalOffset += frag.text.length;
      }
    }
    return spans;
  }

  /// Creates an inline image widget for the PDF.
  pw.Widget? _buildPdfInlineImage(FluentImage image) {
    Uint8List? bytes;
    if (image.src.startsWith('data:')) {
      try {
        final dataStart = image.src.indexOf(',');
        if (dataStart > 0) {
          bytes = base64Decode(image.src.substring(dataStart + 1));
        }
      } catch (_) {}
    } else {
      bytes = _imageCache[image.src];
    }

    if (bytes == null) return null;

    try {
      final pdfImage = pw.MemoryImage(bytes);
      return pw.Image(
        pdfImage,
        width: image.width,
        height: image.height,
        fit: pw.BoxFit.contain,
      );
    } catch (_) {
      return null;
    }
  }

  /// PDF style for a single fragment, with fallback from ParagraphStyle.
  pw.TextStyle _getPdfFragmentStyle(Fragment fragment, ParagraphStyle pStyle) {
    final fragStyles = fragment.styles ?? [];
    final pStyles = pStyle.styles ?? [];

    final isBold = fragStyles.contains('bold') || pStyles.contains('bold');
    final isItalic = fragStyles.contains('italic') || pStyles.contains('italic');
    final hasUnderline = fragStyles.contains('underline');
    final hasStrikethrough = fragStyles.contains('strikethrough');

    // Combine underline and strikethrough
    pw.TextDecoration? decoration;
    if (hasUnderline && hasStrikethrough) {
      decoration = pw.TextDecoration.combine([
        pw.TextDecoration.underline,
        pw.TextDecoration.lineThrough,
      ]);
    } else if (hasUnderline) {
      decoration = pw.TextDecoration.underline;
    } else if (hasStrikethrough) {
      decoration = pw.TextDecoration.lineThrough;
    }

    // Font size: use the fragment's, or the ParagraphStyle's
    double fontSize = fragment.fontSize;
    if (fontSize == 14.0 && pStyle.fontSize != null) {
      fontSize = pStyle.fontSize!;
    }

    // Color: fragment > paragraphStyle > black
    PdfColor? color;
    if (fragment.color != null && fragment.color!.isNotEmpty) {
      color = _parsePdfColor(fragment.color!);
    } else if (pStyle.color != null && pStyle.color!.isNotEmpty) {
      color = _parsePdfColor(pStyle.color!);
    }

    // Font: use TTF from provider (full Unicode support)
    final fontFamily = normalizeFontFamily(fragment.fontFamily.isNotEmpty ? fragment.fontFamily : pStyle.fontFamily);
    final selectedFont = _fontProvider.selectFont(
      fontFamily,
      pStyle.name,
      bold: isBold,
      italic: isItalic,
    );

    // Superscript and subscript: reduce font
    if (fragStyles.contains('superscript') || fragStyles.contains('subscript')) {
      fontSize = fontSize * 0.65;
    }

    // Highlight color (background)
    PdfColor? backgroundColor;
    if (fragment.highlightColor != null && fragment.highlightColor!.isNotEmpty) {
      backgroundColor = _parsePdfColor(fragment.highlightColor!);
    }

    return pw.TextStyle(
      font: selectedFont,
      fontFallback: [
        _fontProvider.sansRegular ?? pw.Font.helvetica(),
      ],
      fontSize: fontSize,
      decoration: decoration,
      color: color,
      background: backgroundColor != null
          ? pw.BoxDecoration(color: backgroundColor)
          : null,
      letterSpacing: fragStyles.contains('smallcaps') ? 1.5 : null,
    );
  }

  pw.Widget _buildPdfImage(FluentImage image) {
    Uint8List? bytes;

    // Try to decode data URI
    if (image.src.startsWith('data:')) {
      try {
        final dataStart = image.src.indexOf(',');
        if (dataStart > 0) {
          bytes = base64Decode(image.src.substring(dataStart + 1));
        }
      } catch (_) {}
    } else {
      // External URL: use the cache
      bytes = _imageCache[image.src];
    }

    if (bytes != null) {
      try {
        final pdfImage = pw.MemoryImage(bytes);

        // Useful width of A4 page (595 - margins ~72 pt)
        const maxWidth = 452.0;

        // Use width and height from the model (set by resize in the editor).
        // The editor shows the image with BoxFit.cover in a SizedBox(w, h),
        // the PDF must replicate the exact same dimensions.
        double? imgWidth = image.width;
        double? imgHeight = image.height;

        if (imgWidth == null && imgHeight == null) {
          final dims = _readImageDimensions(bytes);
          if (dims != null) {
            imgWidth = dims.$1.toDouble();
            imgHeight = dims.$2.toDouble();
          }
        }

        // Scale proportionally if exceeds page width
        if (imgWidth != null && imgWidth > maxWidth) {
          final scale = maxWidth / imgWidth;
          if (imgHeight != null) imgHeight = imgHeight * scale;
          imgWidth = maxWidth;
        }

        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.SizedBox(
            width: double.infinity,
            child: pw.Align(
              alignment: _getPdfAlignment(image.textAlign),
              child: pw.Image(
                pdfImage,
                width: imgWidth,
                height: imgHeight,
                fit: pw.BoxFit.cover,
              ),
            ),
          ),
        );
      } catch (_) {}
    }

    // Fallback: placeholder with URL
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.SizedBox(
        width: double.infinity,
        child: pw.Align(
          alignment: _getPdfAlignment(image.textAlign),
          child: pw.Container(
            width: image.width ?? 200,
            height: image.height ?? 80,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              color: PdfColors.grey100,
            ),
            child: pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    '[Image not available]',
                    style: pw.TextStyle(
                      font: _fontProvider.sansRegular ?? pw.Font.helvetica(),
                      fontSize: 9,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    image.src.length > 60 ? '${image.src.substring(0, 60)}...' : image.src,
                    style: pw.TextStyle(
                      font: _fontProvider.sansRegular ?? pw.Font.helvetica(),
                      fontSize: 7,
                      color: PdfColors.grey400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<pw.Widget> _buildPdfList(FluentList list, int depth, {
    List<Map<String,dynamic>>? comments,
    Map<dynamic, List<double>>? usedAnnotYs,
  }) {
    final widgets = <pw.Widget>[];
    final indent = 24.0 + (depth * 20.0);

    for (int i = 0; i < list.items.length; i++) {
      final item = list.items[i];
      final bullet = _resolveBulletLabel(item, list.listType);
      bool firstChild = true;

      for (final child in item.children) {
        if (child is FluentImage) {
          widgets.add(pw.Padding(
            padding: pw.EdgeInsets.only(left: indent + 24),
            child: _buildPdfImage(child),
          ));
          firstChild = false;
        } else if (child is FluentList) {
          widgets.addAll(_buildPdfList(child, depth + 1, comments: comments, usedAnnotYs: usedAnnotYs));
          firstChild = false;
        } else if (child is Paragraph) {
          final pStyle = child.getStyle();
          final markerFont = _fontProvider.selectFont(
            pStyle.fontFamily ?? 'Arial',
            pStyle.name,
            bold: pStyle.styles?.contains('bold') ?? false,
            italic: pStyle.styles?.contains('italic') ?? false,
          );
          final markerStyle = pw.TextStyle(
            font: markerFont,
            fontSize: pStyle.fontSize ?? 14,
          );
          widgets.add(pw.Padding(
            padding: pw.EdgeInsets.only(left: indent),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (firstChild)
                  pw.SizedBox(
                    width: 24,
                    child: pw.Text(bullet, style: markerStyle),
                  )
                else
                  pw.SizedBox(width: 24),
                pw.Expanded(child: _buildPdfParagraph(child, inListItem: true, comments: comments, usedAnnotYs: usedAnnotYs)),
              ],
            ),
          ));
          firstChild = false;
        }
      }
    }
    return widgets;
  }

  /// Resolves the bullet/marker label based on the bulletType of the ListItem.
  String _resolveBulletLabel(ListItem item, String listType) {
    final bulletType = item.bulletType;
    final depth = item.indexList.length;
    final index = item.indexList.isNotEmpty ? item.indexList.last : 1;

    switch (bulletType) {
      case 'ordered':
        return '$index.';
      case 'ordered-parenthesis':
        return '$index)';
      case 'ordered-alpha':
        return '${String.fromCharCode(96 + index)}.';
      case 'ordered-alpha-parenthesis':
        return '${String.fromCharCode(96 + index)})';
      case 'ordered-alpha-upper':
        return '${String.fromCharCode(64 + index)}.';
      case 'ordered-alpha-upper-parenthesis':
        return '${String.fromCharCode(64 + index)})';
      case 'ordered-roman':
        return '${_toRoman(index)}.';
      case 'ordered-roman-parenthesis':
        return '${_toRoman(index)})';
      case 'ordered-roman-upper':
        return '${_toRoman(index).toUpperCase()}.';
      case 'ordered-roman-upper-parenthesis':
        return '${_toRoman(index).toUpperCase()})';
      case 'bullet':
      case 'unordered':
        const bullets = ['\u2022', '\u25E6', '\u25AA']; // \u2022, \u25E6, \u25AA
        return bullets[depth % bullets.length];
      case 'bullet-circle':
        const circles = ['\u25CB', '\u25E6', '\u25CF']; // \u25CB, \u25E6, \u25CF
        return circles[depth % circles.length];
      case 'bullet-square':
        const squares = ['\u25A1', '\u25AB', '\u25A0']; // \u25A1, \u25AB, \u25A0
        return squares[depth % squares.length];
      case 'checkbox':
        return '\u2610'; // \u2610
      case 'checkbox-checked':
        return '\u2611'; // \u2611
      case 'checkbox-crossed':
        return '\u2612'; // \u2612
      default:
        const defaultBullets = ['\u2022', '\u25E6', '\u25AA'];
        return defaultBullets[depth % defaultBullets.length];
    }
  }

  String _toRoman(int number) {
    if (number <= 0 || number > 3999) return number.toString();
    final values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    final symbols = ['m', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix', 'v', 'iv', 'i'];
    String result = '';
    int n = number;
    for (int i = 0; i < values.length; i++) {
      while (n >= values[i]) {
        n -= values[i];
        result += symbols[i];
      }
    }
    return result;
  }

  pw.Widget _buildPdfTable(FluentTable table, {
    List<Map<String,dynamic>>? comments,
    Map<dynamic, List<double>>? usedAnnotYs,
  }) {
    final rows = <pw.TableRow>[];

    for (final row in table.rows) {
      final cells = <pw.Widget>[];
      for (final cell in row.cells) {
        final cellWidgets = <pw.Widget>[];
        for (final child in cell.children) {
          if (child is FluentImage) {
            cellWidgets.add(_buildPdfImage(child));
          } else if (child is FluentList) {
            cellWidgets.addAll(_buildPdfList(child, 0, comments: comments, usedAnnotYs: usedAnnotYs));
          } else if (child is Paragraph) {
            cellWidgets.add(_buildPdfParagraph(child, comments: comments, usedAnnotYs: usedAnnotYs));
          }
        }
        cells.add(pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: cellWidgets.isEmpty
              ? pw.SizedBox(height: 14)
              : pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: cellWidgets,
                ),
        ));
      }
      rows.add(pw.TableRow(children: cells));
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey600),
        children: rows,
      ),
    );
  }

  /// Reads the dimensions (width, height) from a JPEG or PNG image.
  (int, int)? _readImageDimensions(Uint8List bytes) {
    if (bytes.length < 24) return null;

    // PNG: header 8 bytes + IHDR chunk with width/height
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      return (w, h);
    }

    // JPEG: search for SOF0 marker (0xFF 0xC0) or SOF2 (0xFF 0xC2)
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int offset = 2;
      while (offset < bytes.length - 8) {
        if (bytes[offset] != 0xFF) break;
        final marker = bytes[offset + 1];
        if (marker == 0xC0 || marker == 0xC2) {
          final h = (bytes[offset + 5] << 8) | bytes[offset + 6];
          final w = (bytes[offset + 7] << 8) | bytes[offset + 8];
          return (w, h);
        }
        final segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
        offset += 2 + segLen;
      }
    }

    return null;
  }

  pw.Alignment _getPdfAlignment(String align) {
    return switch (align) {
      'center' => pw.Alignment.center,
      'right' => pw.Alignment.centerRight,
      _ => pw.Alignment.centerLeft,
    };
  }

  PdfColor _parsePdfColor(String hex) {
    if (hex.startsWith('#') && hex.length == 7) {
      final r = int.parse(hex.substring(1, 3), radix: 16);
      final g = int.parse(hex.substring(3, 5), radix: 16);
      final b = int.parse(hex.substring(5, 7), radix: 16);
      return PdfColor.fromInt((0xFF000000 | (r << 16) | (g << 8) | b));
    }
    return PdfColors.black;
  }

  pw.TextAlign _getPdfTextAlign(String align) {
    return switch (align) {
      'center' => pw.TextAlign.center,
      'right' => pw.TextAlign.right,
      'justify' => pw.TextAlign.justify,
      _ => pw.TextAlign.left,
    };
  }

  int _headingLevel(String styleName) {
    return switch (styleName) {
      'heading1' => 1,
      'heading2' => 2,
      'heading3' => 3,
      _ => 0,
    };
  }

  // ─── DOCX / ODT (native formats) ────────────────────────────────────

  /// Exports as native DOCX (OOXML) file.
  Future<Uint8List> exportToDocx() async {
    await _prefetchImages();
    return await DocxExporter(document, imageCache: _imageCache).build();
  }

  /// Exports as native ODT (OpenDocument) file.
  Future<Uint8List> exportToOdt() async {
    await _prefetchImages();
    return await OdtExporter(document, imageCache: _imageCache).build();
  }

  // ─── Markdown ───────────────────────────────────────────────────────

  String exportToMarkdown() {
    final root = document.content;
    final buffer = StringBuffer();
    final nodes = root.nodes;
    for (var i = 0; i < nodes.length; i++) {
      final md = _nodeToMarkdown(nodes[i]);
      if (md.isEmpty) continue;
      buffer.write(md);
      // Separate blocks with a blank line so Markdown renders them
      // as distinct paragraphs / lists / tables.
      if (i < nodes.length - 1) buffer.write('\n\n');
    }
    return buffer.toString().trim();
  }

  String _nodeToMarkdown(FNode node) {
    if (node is FluentImage) {
      return _imageToMarkdown(node);
    } else if (node is HorizontalRule) {
      return '---';
    } else if (node is FluentList) {
      return _listToMarkdown(node, 0);
    } else if (node is FluentTable) {
      return _tableToMarkdown(node);
    } else if (node is Paragraph) {
      return _paragraphToMarkdown(node);
    }
    return '';
  }

  String _paragraphToMarkdown(Paragraph paragraph) {
    final pStyle = paragraph.getStyle();
    final headingLevel = _headingLevel(pStyle.name);
    final inline = _fragmentsToMarkdown(paragraph.fragments);

    if (headingLevel > 0) {
      return '${'#' * headingLevel} $inline';
    }
    if (pStyle.name == 'quote') {
      return inline.split('\n').map((l) => '> $l').join('\n');
    }
    if (pStyle.name == 'code') {
      return '```\n$inline\n```';
    }
    return inline;
  }

  String _fragmentsToMarkdown(List<FNode> fragments) {
    final buffer = StringBuffer();
    for (final frag in fragments) {
      if (frag is Link) {
        buffer.write(_linkToMarkdown(frag));
      } else if (frag is FluentImage) {
        buffer.write(_imageToMarkdown(frag));
      } else if (frag is Fragment) {
        buffer.write(_fragmentToMarkdown(frag));
      }
    }
    return buffer.toString();
  }

  String _fragmentToMarkdown(Fragment fragment) {
    var text = _escapeMarkdown(fragment.text);
    final styles = fragment.styles ?? [];

    // Empty fragments with styles would emit bare syntax (e.g. ****).
    if (text.isEmpty) return '';

    // Apply inline styles that Markdown natively supports.
    // underline, superscript, subscript and smallcaps have no
    // native Markdown equivalent, so they are kept as plain text.
    if (styles.contains('bold')) text = '**$text**';
    if (styles.contains('italic')) text = '*$text*';
    if (styles.contains('strikethrough')) text = '~~$text~~';

    return text;
  }

  String _linkToMarkdown(Link link) {
    final text = _fragmentsToMarkdown(link.fragments);
    if (text.isEmpty) {
      // Empty link text — skip it entirely so it does not pollute
      // the Markdown output with useless `[]()` syntax.
      return '';
    }
    return '[$text](${link.url})';
  }

  String _listToMarkdown(FluentList list, int depth) {
    final buffer = StringBuffer();
    final indent = '    ' * depth;
    final isOrdered = list.listType == 'ordered';
    final isCheckbox = list.items.isNotEmpty &&
        (list.items.first.bulletType.startsWith('checkbox'));

    for (var i = 0; i < list.items.length; i++) {
      final item = list.items[i];
      final prefix = isCheckbox
          ? _checkboxPrefix(item.bulletType)
          : (isOrdered ? '${i + 1}.' : '-');
      final children = item.children;

      // Inline content (Paragraph / Image) goes on the same line as the bullet.
      // Block content (sub-list) goes on a new line so Markdown parsers
      // treat it as a nested list.
      final inlineChildren = children.where((c) => c is Paragraph || c is FluentImage).toList();
      final blockChildren = children.where((c) => c is FluentList).toList();

      if (inlineChildren.isNotEmpty) {
        // Write bullet + inline content on one line.
        buffer.write('$indent$prefix ');
        for (var j = 0; j < inlineChildren.length; j++) {
          final child = inlineChildren[j];
          if (child is Paragraph) {
            buffer.write(_fragmentsToMarkdown(child.fragments));
          } else if (child is FluentImage) {
            buffer.write(_imageToMarkdown(child));
          }
          if (j < inlineChildren.length - 1) {
            buffer.write(' ');
          }
        }
      } else if (blockChildren.isNotEmpty) {
        // No inline text — bullet on its own line.
        buffer.write('$indent$prefix');
      }

      // Sub-lists (and any remaining block children) on new lines.
      for (final child in blockChildren) {
        if (child is FluentList) {
          buffer.write('\n');
          buffer.write(_listToMarkdown(child, depth + 1));
        }
      }

      if (i < list.items.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  String _checkboxPrefix(String bulletType) {
    return switch (bulletType) {
      'checkbox-checked' => '- [x]',
      'checkbox-crossed' => '- [~]',
      _ => '- [ ]',
    };
  }

  String _tableToMarkdown(FluentTable table) {
    final rows = table.rows;
    if (rows.isEmpty) return '';

    // Compute the total number of visible columns from all rows,
    // respecting colSpan so a single cell spanning 3 columns
    // contributes 3 to the total.
    int visualColumns(FluentRow row) =>
        row.cells.map((c) => c.colSpan).fold<int>(0, (a, b) => a + b);

    final colCount = rows.map(visualColumns).reduce(math.max);

    final buffer = StringBuffer();
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      buffer.write('| ');
      var writtenCols = 0;
      for (var c = 0; c < row.cells.length; c++) {
        final cell = row.cells[c];
        final text = cell.children
            .whereType<Paragraph>()
            .map((p) => _fragmentsToMarkdown(p.fragments))
            .join(' ');
        // _fragmentsToMarkdown already escapes raw text; do NOT
        // call _escapeMarkdown again or it would break bold/link syntax.
        buffer.write('$text | ');
        writtenCols += cell.colSpan;
        // Pad empty cells for colspan > 1 (Markdown has no colspan support).
        for (var e = 1; e < cell.colSpan; e++) {
          buffer.write('| ');
        }
      }
      // Pad remaining columns if the row is shorter than colCount.
      for (; writtenCols < colCount; writtenCols++) {
        buffer.write('| ');
      }
      buffer.writeln();

      // Separator after first row (header)
      if (r == 0) {
        buffer.write('|');
        for (var c = 0; c < colCount; c++) {
          buffer.write(' --- |');
        }
        buffer.writeln();
      }
    }
    return buffer.toString().trim();
  }

  String _imageToMarkdown(FluentImage image) {
    return '![${_escapeMarkdown(image.src)}](${image.src})';
  }

  String _escapeMarkdown(String text) {
    // Escape characters that have special meaning in Markdown
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('*', '\\*')
        .replaceAll('_', '\\_')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]')
        .replaceAll('|', '\\|')
        .replaceAll('`', '\\`');
  }

  // ─── HTML ───────────────────────────────────────────────────────────

  Future<String> exportToHtml() async {
    // Pre-fetch all images to embed them as data URI
    await _prefetchImages();

    final root = document.content;
    final buffer = StringBuffer();
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html><head><meta charset="utf-8"><title>Document</title>');
    buffer.writeln('<style>');
    buffer.writeln('p { margin: 0 0 4px 0; }');
    buffer.writeln('body { font-family: DejaVu Sans, Helvetica, sans-serif; font-size: 14px; margin: 40px; line-height: 1.4; color: #222; }');
    buffer.writeln('h1 { font-size: 28px; margin: 24px 0 12px; }');
    buffer.writeln('h2 { font-size: 22px; margin: 20px 0 10px; }');
    buffer.writeln('h3 { font-size: 18px; margin: 16px 0 8px; }');
    buffer.writeln('blockquote { border-left: 3px solid #999; margin: 12px 0; padding: 8px 16px; font-style: italic; font-family: Georgia, serif; color: #555; }');
    buffer.writeln('pre { background: #f5f5f5; border: 1px solid #ddd; border-radius: 4px; padding: 12px; font-family: "Courier New", monospace; font-size: 13px; white-space: pre-wrap; margin: 8px 0; }');
    buffer.writeln('table { border-collapse: collapse; margin: 12px 0; }');
    buffer.writeln('td, th { border: 1px solid #999; padding: 4px 8px; vertical-align: top; }');
    buffer.writeln('img { max-width: 100%; }');
    buffer.writeln('a { color: #1a73e8; }');
    buffer.writeln('hr { border: none; border-top: 1px solid #ccc; margin: 16px 0; }');
    buffer.writeln('</style>');
    buffer.writeln('</head><body>');

    _writeHtmlNodes(root.nodes, buffer);

    buffer.writeln('</body></html>');
    return buffer.toString();
  }

  void _writeHtmlNodes(List<FNode> nodes, StringBuffer buffer) {
    for (final node in nodes) {
      if (node is FluentImage) {
        buffer.writeln(_imageToHtml(node));
      } else if (node is HorizontalRule) {
        buffer.writeln('<hr>');
      } else if (node is FluentList) {
        buffer.writeln(_listToHtml(node));
      } else if (node is FluentTable) {
        buffer.writeln(_tableToHtml(node));
      } else if (node is Paragraph) {
        buffer.writeln(_paragraphToHtml(node));
      }
    }
  }

  /// Converts an external URL to base64 data URI using the cache,
  /// or returns the original URL if already data URI or not in cache.
  String _resolveImageSrc(String src) {
    if (src.startsWith('data:')) return src;
    final bytes = _imageCache[src];
    if (bytes == null) return src;
    // Detect MIME type from header
    String mime = 'image/jpeg';
    if (bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50) {
      mime = 'image/png';
    } else if (bytes.length > 3 && bytes[0] == 0x47 && bytes[1] == 0x49) {
      mime = 'image/gif';
    }
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  String _imageToHtml(FluentImage image) {
    final resolvedSrc = _resolveImageSrc(image.src);
    final attrs = <String>[];
    if (image.width != null) attrs.add('width="${image.width!.toInt()}"');
    if (image.height != null) attrs.add('height="${image.height!.toInt()}"');
    final attrStr = attrs.isNotEmpty ? ' ${attrs.join(' ')}' : '';
    final imgTag = '<img src="$resolvedSrc"$attrStr alt="">';

    // Alignment
    final align = image.textAlign;
    if (align == 'center') {
      return '<p style="text-align:center">$imgTag</p>';
    } else if (align == 'right') {
      return '<p style="text-align:right">$imgTag</p>';
    }
    return '<p>$imgTag</p>';
  }

  String _paragraphToHtml(Paragraph paragraph) {
    final pStyle = paragraph.getStyle();
    final headingLevel = _headingLevel(pStyle.name);
    final isQuote = pStyle.name == 'quote';
    final isCode = pStyle.name == 'code';

    // CSS styles for the paragraph
    final cssProps = <String>[];
    if (paragraph.textAlign != 'left') {
      cssProps.add('text-align:${paragraph.textAlign}');
    }
    if (paragraph.indent > 0) {
      cssProps.add('margin-left:${paragraph.indent * 24}px');
    }
    // Line height from ParagraphStyle
    if (pStyle.lineHeight != null && pStyle.lineHeight != 1.4) {
      cssProps.add('line-height:${pStyle.lineHeight}');
    }
    // Spacing from ParagraphStyle
    if (pStyle.spacingBefore != null && pStyle.spacingBefore! > 0 && headingLevel == 0) {
      cssProps.add('margin-top:${pStyle.spacingBefore!.toInt()}px');
    }
    if (pStyle.spacingAfter != null && pStyle.spacingAfter! > 0 && headingLevel == 0) {
      cssProps.add('margin-bottom:${pStyle.spacingAfter!.toInt()}px');
    }

    final styleAttr = cssProps.isNotEmpty ? ' style="${cssProps.join(';')}"' : '';
    final inlineContent = _fragmentsToHtml(paragraph.fragments, pStyle);

    // Choose the tag
    if (headingLevel > 0) {
      return '<h$headingLevel$styleAttr>$inlineContent</h$headingLevel>';
    }
    if (isQuote) {
      return '<blockquote$styleAttr>$inlineContent</blockquote>';
    }
    if (isCode) {
      return '<pre$styleAttr>$inlineContent</pre>';
    }
    return '<p$styleAttr>$inlineContent</p>';
  }

  /// Converts a list of fragments to inline HTML.
  String _fragmentsToHtml(List<FNode> fragments, ParagraphStyle pStyle) {
    final buffer = StringBuffer();

    for (final frag in fragments) {
      if (frag is Link) {
        // Render all children of the link in the correct order
        final linkBuffer = StringBuffer();
        for (final linkChild in frag.fragments) {
          if (linkChild is FluentImage) {
            final resolvedSrc = _resolveImageSrc(linkChild.src);
            final imgAttrs = <String>[];
            if (linkChild.width != null) imgAttrs.add('width="${linkChild.width!.toInt()}"');
            if (linkChild.height != null) imgAttrs.add('height="${linkChild.height!.toInt()}"');
            final imgAttrStr = imgAttrs.isNotEmpty ? ' ${imgAttrs.join(' ')}' : '';
            linkBuffer.write('<img src="$resolvedSrc"$imgAttrStr alt="">');
          } else if (linkChild is Fragment) {
            linkBuffer.write(_fragmentToHtml(linkChild, pStyle));
          }
        }
        buffer.write('<a href="${_escapeHtml(frag.url)}">${linkBuffer.toString()}</a>');
      } else if (frag is FluentImage) {
        // Inline image
        final resolvedSrc = _resolveImageSrc(frag.src);
        final imgAttrs = <String>[];
        if (frag.width != null) imgAttrs.add('width="${frag.width!.toInt()}"');
        if (frag.height != null) imgAttrs.add('height="${frag.height!.toInt()}"');
        final imgAttrStr = imgAttrs.isNotEmpty ? ' ${imgAttrs.join(' ')}' : '';
        buffer.write('<img src="$resolvedSrc"$imgAttrStr alt="">');
      } else if (frag is Fragment) {
        buffer.write(_fragmentToHtml(frag, pStyle));
      }
    }

    return buffer.toString();
  }

  String _fragmentToHtml(Fragment fragment, ParagraphStyle pStyle) {
    var text = _escapeHtml(fragment.text);
    final fragStyles = fragment.styles ?? [];
    final fontSize = fragment.fontSize;

    // Inline CSS
    final cssStyles = <String>[];

    // Font size: show if different from default (14) and paragraph style
    final pFontSize = pStyle.fontSize ?? 14.0;
    if (fontSize != pFontSize) {
      cssStyles.add('font-size:${fontSize}px');
    }

    // Font family: if different from paragraph style
    final pFontFamily = pStyle.fontFamily ?? 'Arial';
    if (fragment.fontFamily.isNotEmpty && fragment.fontFamily != pFontFamily) {
      cssStyles.add("font-family:'${fragment.fontFamily}'");
    }

    // Text color
    if (fragment.color != null && fragment.color!.isNotEmpty) {
      cssStyles.add('color:${fragment.color}');
    }
    // Highlight color
    if (fragment.highlightColor != null && fragment.highlightColor!.isNotEmpty) {
      cssStyles.add('background-color:${fragment.highlightColor}');
    }

    if (cssStyles.isNotEmpty) {
      text = '<span style="${cssStyles.join(';')}">$text</span>';
    }

    // Semantic tags
    if (fragStyles.contains('bold')) text = '<strong>$text</strong>';
    if (fragStyles.contains('italic')) text = '<em>$text</em>';
    if (fragStyles.contains('underline')) text = '<u>$text</u>';
    if (fragStyles.contains('strikethrough')) text = '<s>$text</s>';
    if (fragStyles.contains('superscript')) text = '<sup>$text</sup>';
    if (fragStyles.contains('subscript')) text = '<sub>$text</sub>';
    if (fragStyles.contains('smallcaps')) {
      text = '<span style="font-variant:small-caps">$text</span>';
    }

    return text;
  }

  String _listToHtml(FluentList list) {
    // Checkbox list: use ul without marker + HTML checkbox
    final isCheckbox = list.items.isNotEmpty && _isCheckboxType(list.items.first.bulletType);
    final tag = list.listType == 'ordered' ? 'ol' : 'ul';

    final buffer = StringBuffer();
    if (isCheckbox) {
      buffer.writeln('<ul style="list-style:none;padding-left:20px">');
    } else {
      // CSS marker type for bullet variants
      final listStyleType = _htmlListStyleType(list.items.isNotEmpty ? list.items.first.bulletType : 'bullet');
      if (listStyleType != null) {
        buffer.writeln('<$tag style="list-style-type:$listStyleType">');
      } else {
        buffer.writeln('<$tag>');
      }
    }

    for (final item in list.items) {
      if (isCheckbox) {
        final checkMark = switch (item.bulletType) {
          'checkbox-checked' => '&#9745; ', // ☑
          'checkbox-crossed' => '&#9746; ', // ☒
          _ => '&#9744; ', // ☐
        };
        buffer.write('<li>$checkMark');
      } else {
        buffer.write('<li>');
      }
      for (final child in item.children) {
        if (child is FluentImage) {
          buffer.write(_imageToHtml(child));
        } else if (child is FluentList) {
          buffer.write(_listToHtml(child));
        } else if (child is Paragraph) {
          buffer.write(_fragmentsToHtml(child.fragments, child.getStyle()));
        }
      }
      buffer.writeln('</li>');
    }
    buffer.writeln(isCheckbox ? '</ul>' : '</$tag>');
    return buffer.toString();
  }

  bool _isCheckboxType(String bulletType) {
    return bulletType == 'checkbox' || bulletType == 'checkbox-checked' || bulletType == 'checkbox-crossed';
  }

  String? _htmlListStyleType(String bulletType) {
    return switch (bulletType) {
      'bullet' || 'unordered' => 'disc',
      'bullet-circle' => 'circle',
      'bullet-square' => 'square',
      'dash' => '"–"',
      'ordered' => 'decimal',
      'ordered-parenthesis' => 'decimal',
      'ordered-alpha' || 'ordered-alpha-parenthesis' => 'lower-alpha',
      'ordered-alpha-upper' || 'ordered-alpha-upper-parenthesis' => 'upper-alpha',
      'ordered-roman' || 'ordered-roman-parenthesis' => 'lower-roman',
      'ordered-roman-upper' || 'ordered-roman-upper-parenthesis' => 'upper-roman',
      _ => null,
    };
  }

  String _tableToHtml(FluentTable table) {
    final buffer = StringBuffer();
    buffer.writeln('<table width="100%" border="1" cellpadding="0" cellspacing="0">');
    for (final row in table.rows) {
      buffer.writeln('<tr>');
      for (final cell in row.cells) {
        final attrs = <String>[];
        if (cell.colSpan > 1) attrs.add('colspan="${cell.colSpan}"');
        if (cell.rowSpan > 1) attrs.add('rowspan="${cell.rowSpan}"');
        final attrStr = attrs.isNotEmpty ? ' ${attrs.join(' ')}' : '';

        buffer.write('<td$attrStr>');
        for (final child in cell.children) {
          if (child is FluentImage) {
            buffer.write(_imageToHtml(child));
          } else if (child is FluentList) {
            buffer.write(_listToHtml(child));
          } else if (child is Paragraph) {
            buffer.write('<p style="margin:0;padding:2px 6px;line-height:1.15;font-size:14px">');
            buffer.write(_fragmentsToHtml(child.fragments, child.getStyle()));
            buffer.write('</p>');
          }
        }
        buffer.writeln('</td>');
      }
      buffer.writeln('</tr>');
    }
    buffer.writeln('</table>');
    return buffer.toString();
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  // ─── File I/O ───────────────────────────────────────────────────────

  Future<String?> saveFileNative(Uint8List bytes, String defaultName, String extension) async {
    if (kIsWeb) {
      // Web: use HTML5 download
      downloadFileWeb(bytes, '$defaultName.$extension');
      return null; // Web doesn't return a path
    }

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Save file',
          fileName: defaultName,
          type: FileType.custom,
          allowedExtensions: [extension],
          bytes: bytes, // Required on Android/iOS
        );
        if (result != null) {
          return result;
        }
      } catch (e) {
        // Ignore errors, return null
      }
      return null;
    }

    if (Platform.isLinux) {
      // Try zenity
      try {
        final result = await Process.run('zenity', [
          '--file-selection',
          '--save',
          '--confirm-overwrite',
          '--filename=$defaultName',
          '--file-filter=*.$extension',
          '--title=Save file',
        ]);
        if (result.exitCode == 0) {
          var path = (result.stdout as String).trim();
          if (path.isNotEmpty) {
            if (!path.endsWith('.$extension')) path += '.$extension';
            final file = File(path);
            await file.writeAsBytes(bytes);
            return path;
          }
        }
      } catch (_) {}

      // Try kdialog
      try {
        final result = await Process.run('kdialog', [
          '--getsavefilename',
          defaultName,
          '*.$extension',
        ]);
        if (result.exitCode == 0) {
          var path = (result.stdout as String).trim();
          if (path.isNotEmpty) {
            if (!path.endsWith('.$extension')) path += '.$extension';
            final file = File(path);
            await file.writeAsBytes(bytes);
            return path;
          }
        }
      } catch (_) {}
    } else if (Platform.isMacOS || Platform.isWindows) {
      try {
        final location = await getSaveLocation(suggestedName: defaultName);
        if (location != null) {
          var path = location.path;
          if (!path.endsWith('.$extension')) path += '.$extension';
          final file = File(path);
          await file.writeAsBytes(bytes);
          return path;
        }
      } catch (_) {}
    }

    return null;
  }

  Future<String?> saveTextFileNative(String content, String defaultName, String extension) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    return saveFileNative(bytes, defaultName, extension);
  }
}
