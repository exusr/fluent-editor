import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: unused_import
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/utils/editor_utils.dart';
import 'package:flutter/services.dart';

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

/// Generates a native ODT (OpenDocument Text) file from the document.
///
/// An ODT is a ZIP archive containing:
/// - `mimetype` (uncompressed, first entry)
/// - `META-INF/manifest.xml`
/// - `content.xml` (content + automatic styles)
/// - `styles.xml`
/// - `Pictures/` (embedded images)
class OdtExporter {
  final FluentDocument document;

  /// Cache of external images already downloaded (src -> bytes).
  final Map<String, Uint8List> imageCache;

  OdtExporter(this.document, {Map<String, Uint8List>? imageCache})
      : imageCache = imageCache ?? {};

  // Registered automatic styles: property key -> style name.
  final Map<String, String> _textStyles = {};
  final Map<String, String> _paragraphStyles = {};
  int _textStyleCounter = 0;
  int _paragraphStyleCounter = 0;

  // Image frame styles: align key -> style name.
  final Map<String, String> _imageFrameStyles = {};
  final Map<String, String> _imageFrameStyleDefs = {};
  int _imageFrameStyleCounter = 0;

  // Embedded images: src -> file name in Pictures/.
  final Map<String, String> _pictures = {};
  final Map<String, Uint8List> _pictureBytes = {};
  int _pictureCounter = 0;

  // Fonts used in the document (for declaration in font-face-decls).
  final Set<String> _fonts = {};

  // Embedded fonts: font name -> asset path.
  final Map<String, String> _embeddedFonts = {};

  // Comment index by paragraph node id (built once at export start).
  Map<String, List<Map<String, dynamic>>> _commentsByNode = {};

  // Document body buffer.
  final StringBuffer _body = StringBuffer();

  /// Attempts to find a TTF/OTF file for [fontName] on the current OS.
  Future<Uint8List?> _findSystemFontBytes(String fontName) async {
    if (kIsWeb) return null; // Web doesn't have file system access

    final lower = fontName.toLowerCase().replaceAll(' ', '');
    final candidates = <String>[];

    if (Platform.isWindows) {
      final windir = Platform.environment['WINDIR'] ?? r'C:\Windows';
      final fontsDir = '$windir\\Fonts';
      candidates.addAll([
        '$fontsDir\\$lower.ttf',
        '$fontsDir\\$lower.TTF',
        '$fontsDir\\$lower.otf',
        '$fontsDir\\$lower.OTF',
      ]);
    } else if (Platform.isMacOS) {
      candidates.addAll([
        '/System/Library/Fonts/$fontName.ttf',
        '/Library/Fonts/$fontName.ttf',
        '/System/Library/Fonts/$fontName.ttc',
        '/Library/Fonts/$fontName.ttc',
        '/System/Library/Fonts/$fontName.otf',
        '/Library/Fonts/$fontName.otf',
      ]);
    } else if (Platform.isLinux) {
      candidates.addAll([
        '/usr/share/fonts/truetype/$lower/$fontName.ttf',
        '/usr/share/fonts/$fontName.ttf',
        '/usr/share/fonts/opentype/$lower/$fontName.otf',
      ]);
    }

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        try {
          return await file.readAsBytes();
        } catch (_) {}
      }
    }

    // Deep search on Windows
    if (Platform.isWindows) {
      final windir = Platform.environment['WINDIR'] ?? r'C:\Windows';
      final fontsDir = Directory('$windir\\Fonts');
      if (await fontsDir.exists()) {
        await for (final entity in fontsDir.list()) {
          if (entity is File) {
            final name = entity.path.split(Platform.pathSeparator).last.toLowerCase();
            final ext = name.split('.').last;
            if ((ext == 'ttf' || ext == 'ttc' || ext == 'otf') && name.startsWith(lower)) {
              try {
                return await entity.readAsBytes();
              } catch (_) {}
            }
          }
        }
      }
    }

    return null;
  }

  /// Maps editor fonts to available DejaVu TTF files.
  String? _mapFontToAsset(String fontName) {
    final name = fontName.toLowerCase();
    if (name.contains('arial') || name.contains('sans')) {
      return 'assets/fonts/DejaVuSans.ttf';
    } else if (name.contains('times') || name.contains('serif')) {
      return 'assets/fonts/DejaVuSerif.ttf';
    } else if (name.contains('courier') || name.contains('mono')) {
      return 'assets/fonts/DejaVuSansMono.ttf';
    } else if (name.contains('georgia')) {
      return 'assets/fonts/DejaVuSerif.ttf';
    } else if (name.contains('roboto')) {
      return 'assets/fonts/DejaVuSans.ttf';
    }
    return 'assets/fonts/DejaVuSans.ttf';
  }

  /// Registers a font for embedding.
  void _registerFont(String fontName) {
    final asset = _mapFontToAsset(fontName);
    if (asset != null) {
      _embeddedFonts[fontName] = asset;
    }
  }

  /// Generates the ODT file bytes.
  Future<Uint8List> build() async {
    // Index comments by paragraph node id so every paragraph can
    // quickly look up its own annotations without re-exporting.
    _commentsByNode = {};
    final commentProvider = document.commentProvider;
    if (commentProvider != null) {
      for (final c in commentProvider.exportComments()) {
        if (c['resolved'] == true || c['orphan'] == true) continue;
        final nodeId = c['nodeId'] as String? ?? '';
        if (nodeId.isNotEmpty) {
          _commentsByNode.putIfAbsent(nodeId, () => []).add(c);
        }
      }
    }

    final root = document.content;
    for (final node in root.nodes) {
      _writeNode(node);
    }

    // Ensure DejaVu Sans as default font always present.
    _fonts.add('DejaVu Sans');

    // Resolve fonts: try system fonts first, then bundled fallback.
    final fontBytesMap = <String, Uint8List>{};
    for (final fontName in _fonts) {
      final sysBytes = await _findSystemFontBytes(fontName);
      if (sysBytes != null) {
        fontBytesMap[fontName] = sysBytes;
      } else {
        final asset = _mapFontToAsset(fontName);
        if (asset != null) {
          try {
            final bytes = await rootBundle.load(asset);
            fontBytesMap[fontName] = bytes.buffer.asUint8List();
          } catch (_) {}
        }
      }
    }

    final contentXml = _buildContentXml();
    final stylesXml = _buildStylesXml();
    final manifestXml = _buildManifestXml();

    final archive = Archive();

    // mimetype MUST be the first entry and uncompressed.
    final mimeBytes = utf8.encode('application/vnd.oasis.opendocument.text');
    final mimeFile = ArchiveFile('mimetype', mimeBytes.length, mimeBytes);
    mimeFile.compress = false;
    archive.addFile(mimeFile);

    _addText(archive, 'META-INF/manifest.xml', manifestXml);
    _addText(archive, 'content.xml', contentXml);
    _addText(archive, 'styles.xml', stylesXml);

    // Embed resolved fonts.
    for (final entry in fontBytesMap.entries) {
      final fileName = 'Fonts/${entry.key.replaceAll(' ', '_')}.ttf';
      archive.addFile(ArchiveFile(fileName, entry.value.length, entry.value));
    }

    for (final entry in _pictureBytes.entries) {
      final name = 'Pictures/${entry.key}';
      archive.addFile(ArchiveFile(name, entry.value.length, entry.value));
    }

    final zipData = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipData!);
  }

  void _addText(Archive archive, String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  // ─── Node generation ───────────────────────────────────────────────

  void _writeNode(FNode node, {double extraIndentCm = 0}) {
    if (node is FluentImage) {
      _writeBlockImage(node);
    } else if (node is HorizontalRule) {
      _writeHr();
    } else if (node is FluentList) {
      _writeList(node, 0);
    } else if (node is FluentTable) {
      _writeTable(node);
    } else if (node is Paragraph) {
      _writeParagraph(node, extraIndentCm: extraIndentCm);
    }
  }

  void _writeParagraph(Paragraph paragraph, {double extraIndentCm = 0}) {
    final pStyle = paragraph.getStyle();
    final headingLevel = _headingLevel(pStyle.name);
    final styleName = _registerParagraphStyle(paragraph, pStyle, extraIndentCm);
    final comments = _commentsByNode[paragraph.id] ?? [];
    final inline = _buildInline(
      paragraph.fragments,
      pStyle,
      paragraphId: paragraph.id,
      comments: comments,
    );

    if (headingLevel > 0) {
      _body.writeln(
          '<text:h text:style-name="$styleName" text:outline-level="$headingLevel">$inline</text:h>');
    } else {
      _body.writeln('<text:p text:style-name="$styleName">$inline</text:p>');
    }
  }

  void _writeHr() {
    // Prefix "HR_" to avoid collisions with auto paragraph style names.
    const key = 'HR_hr';
    final styleName = _paragraphStyles.putIfAbsent(key, () {
      return 'P${_paragraphStyleCounter++}';
    });
    _hrStyleName = styleName;
    _body.writeln('<text:p text:style-name="$styleName"/>');
  }

  String? _hrStyleName;

  void _writeBlockImage(FluentImage image, {double extraIndentCm = 0}) {
    final frame = _imageFrame(image, anchor: 'paragraph');
    if (frame == null) {
      _body.writeln('<text:p/>');
      return;
    }
    final pStyleName = _registerImageParagraphStyle(image.textAlign, extraIndentCm);
    _body.writeln('<text:p text:style-name="$pStyleName">$frame</text:p>');
  }

  void _writeList(FluentList list, int depth) {
    final listStyleName = _registerListStyle(list.listType, depth);
    _body.writeln('<text:list text:style-name="$listStyleName">');
    for (final item in list.items) {
      _body.writeln('<text:list-item>');
      for (final child in item.children) {
        if (child is FluentList) {
          _writeList(child, depth + 1);
        } else if (child is FluentImage) {
          _writeBlockImage(child);
        } else if (child is Paragraph) {
          final pStyle = child.getStyle();
          final styleName = _registerListParagraphStyle(child, pStyle);
          final comments = _commentsByNode[child.id] ?? [];
          final inline = _buildInline(
            child.fragments,
            pStyle,
            paragraphId: child.id,
            comments: comments,
          );
          _body.writeln('<text:p text:style-name="$styleName">$inline</text:p>');
        }
      }
      _body.writeln('</text:list-item>');
    }
    _body.writeln('</text:list>');
  }

  void _writeTable(FluentTable table) {
    final colCount = _tableColumnCount(table);
    final tableName = 'Tbl${_tableCounter++}';
    _body.writeln('<table:table table:name="$tableName" table:style-name="$_tableStyleName">');
    _body.writeln(
        '<table:table-column table:style-name="$_tableColStyleName" table:number-columns-repeated="$colCount"/>');

    for (final row in table.rows) {
      _body.writeln('<table:table-row>');
      for (final cell in row.cells) {
        final spanAttr = StringBuffer();
        if (cell.colSpan > 1) {
          spanAttr.write(' table:number-columns-spanned="${cell.colSpan}"');
        }
        if (cell.rowSpan > 1) {
          spanAttr.write(' table:number-rows-spanned="${cell.rowSpan}"');
        }
        _body.writeln(
            '<table:table-cell table:style-name="$_tableCellStyleName"$spanAttr office:value-type="string">');
        _writeCellContent(cell);
        _body.writeln('</table:table-cell>');

        for (int c = 1; c < cell.colSpan; c++) {
          _body.writeln('<table:covered-table-cell/>');
        }
      }
      _body.writeln('</table:table-row>');
    }
    _body.writeln('</table:table>');
  }

  void _writeCellContent(FluentCell cell) {
    bool wroteSomething = false;
    for (final child in cell.children) {
      if (child is FluentImage) {
        _writeBlockImage(child);
        wroteSomething = true;
      } else if (child is FluentList) {
        _writeList(child, 0);
        wroteSomething = true;
      } else if (child is Paragraph) {
        _writeParagraph(child);
        wroteSomething = true;
      }
    }
    if (!wroteSomething) {
      _body.writeln('<text:p/>');
    }
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

  // ─── Inline (fragments) ─────────────────────────────────────────────

  String _buildInline(
    List<FNode> fragments,
    ParagraphStyle pStyle, {
    String? paragraphId,
    List<Map<String, dynamic>>? comments,
  }) {
    final buffer = StringBuffer();
    int globalOffset = 0;
    final emitted = <String>{};

    final segs = <_CommentSeg>[];
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

    // Build a lookup map so we can find comment metadata (including replies)
    // when we close an annotation and need to emit replies after it.
    final commentById = <String, Map<String, dynamic>>{};
    for (final seg in segs) {
      final cid = seg.comment['id'] as String? ?? '';
      if (cid.isNotEmpty) commentById[cid] = seg.comment;
    }

    final openCommentIds = <String>[];
    void closeOpenAnnotations() {
      for (final id in openCommentIds.reversed) {
        buffer.write('<office:annotation-end office:name="comment_$id"/>');
        final comment = commentById[id];
        if (comment != null) {
          final replies = (comment['replies'] as List<dynamic>?) ?? [];
          for (final r in replies) {
            final rMap = r as Map<String, dynamic>;
            final rId = rMap['id'] as String? ?? '';
            if (rId.isEmpty || emitted.contains(rId)) continue;
            emitted.add(rId);
            buffer.write(_replyAnnotationOpen(rMap, id));
          }
        }
      }
      openCommentIds.clear();
    }

    void emitCommentAnnotations(Map<String, dynamic> comment) {
      final id = comment['id'] as String? ?? '';
      if (id.isEmpty || emitted.contains(id)) return;
      emitted.add(id);
      buffer.write(_annotationOpen(comment));
      openCommentIds.add(id);
    }

    for (final frag in fragments) {
      if (frag is Link) {
        final linkInner = StringBuffer();
        int linkOffset = 0;
        final linkOpenIds = <String>[];
        void closeLinkAnnotations() {
          for (final id in linkOpenIds.reversed) {
            linkInner.write('<office:annotation-end office:name="comment_$id"/>');
            final comment = commentById[id];
            if (comment != null) {
              final replies = (comment['replies'] as List<dynamic>?) ?? [];
              for (final r in replies) {
                final rMap = r as Map<String, dynamic>;
                final rId = rMap['id'] as String? ?? '';
                if (rId.isEmpty || emitted.contains(rId)) continue;
                emitted.add(rId);
                linkInner.write(_replyAnnotationOpen(rMap, id));
              }
            }
          }
          linkOpenIds.clear();
        }

        void emitLinkCommentAnnotations(Map<String, dynamic> comment) {
          final id = comment['id'] as String? ?? '';
          if (id.isEmpty || emitted.contains(id)) return;
          emitted.add(id);
          linkInner.write(_annotationOpen(comment));
          linkOpenIds.add(id);
        }

        for (final child in frag.fragments) {
          if (child is FluentImage) {
            closeLinkAnnotations();
            final f = _imageFrame(child, anchor: 'as-char');
            if (f != null) linkInner.write(f);
          } else if (child is Fragment) {
            final subs = _extractSegments(child.text, globalOffset + linkOffset, segs);
            for (final sub in subs) {
              if (sub.comment == null || !linkOpenIds.contains(sub.comment!['id'] as String)) {
                closeLinkAnnotations();
              }
              if (sub.comment != null) {
                emitLinkCommentAnnotations(sub.comment!);
              }
              linkInner.write(_span(child, pStyle,
                  forceLink: true, text: sub.text, isCommented: sub.comment != null));
            }
            linkOffset += child.text.length;
          }
        }
        closeLinkAnnotations();
        buffer.write(
            '<text:a xlink:type="simple" xlink:href="${_esc(frag.url)}">${linkInner.toString()}</text:a>');
        globalOffset += linkOffset;
      } else if (frag is FluentImage) {
        closeOpenAnnotations();
        final f = _imageFrame(frag, anchor: 'as-char');
        if (f != null) buffer.write(f);
      } else if (frag is Fragment) {
        final subs = _extractSegments(frag.text, globalOffset, segs);
        for (final sub in subs) {
          if (sub.comment == null || !openCommentIds.contains(sub.comment!['id'] as String)) {
            closeOpenAnnotations();
          }
          if (sub.comment != null) {
            emitCommentAnnotations(sub.comment!);
          }
          buffer.write(_span(frag, pStyle,
              text: sub.text, isCommented: sub.comment != null));
        }
        globalOffset += frag.text.length;
      }
    }
    closeOpenAnnotations();
    return buffer.toString();
  }

  String _formatDateOdt(dynamic raw) {
    DateTime? dt;
    if (raw is DateTime) {
      dt = raw;
    } else if (raw is String && raw.isNotEmpty) {
      dt = DateTime.tryParse(raw);
    }
    if (dt == null) return '';
    return dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
  }

  String _annotationOpen(Map<String, dynamic> comment) {
    final author = _esc(comment['authorName'] as String? ?? 'Anonymous');
    final date = _formatDateOdt(comment['createdAt']);
    final text = _esc(comment['text'] as String? ?? '');
    final id = comment['id'] as String? ?? '0';
    final buf = StringBuffer();
    buf.write('<office:annotation office:name="comment_$id"');
    if (author.isNotEmpty) {
      buf.write(' office:author="$author"');
    }
    if (date.isNotEmpty) {
      buf.write(' office:date="$date"');
    }
    buf.write(' loext:resolved="false">');
    buf.write('<dc:creator>$author</dc:creator>');
    if (date.isNotEmpty) {
      buf.write('<dc:date>$date</dc:date>');
    }
    buf.write('<text:p>$text</text:p>');
    buf.write('</office:annotation>');
    return buf.toString();
  }

  String _replyAnnotationOpen(Map<String, dynamic> reply, String parentId) {
    final author = _esc(reply['authorName'] as String? ?? 'Anonymous');
    final date = _formatDateOdt(reply['createdAt']);
    final text = _esc(reply['text'] as String? ?? '');
    final id = reply['id'] as String? ?? '0';
    final buf = StringBuffer();
    buf.write('<office:annotation office:name="reply_$id" '
        'officeooo:paraIdParent="comment_$parentId" '
        'office:parent-name="comment_$parentId"');
    if (author.isNotEmpty) {
      buf.write(' office:author="$author"');
    }
    if (date.isNotEmpty) {
      buf.write(' office:date="$date"');
    }
    buf.write(' loext:resolved="false">');
    buf.write('<dc:creator>$author</dc:creator>');
    if (date.isNotEmpty) {
      buf.write('<dc:date>$date</dc:date>');
    }
    buf.write('<text:p>$text</text:p>');
    buf.write('</office:annotation>');
    return buf.toString();
  }

  String _span(Fragment frag, ParagraphStyle pStyle,
      {bool forceLink = false, String? text, bool isCommented = false}) {
    final styleName = _registerTextStyle(frag, pStyle,
        forceLink: forceLink, isCommented: isCommented);
    final spanText = text ?? frag.text;
    final escaped = _escWithSpaces(spanText);
    return '<text:span text:style-name="$styleName">$escaped</text:span>';
  }

  // ─── Style registration ────────────────────────────────────────────

  String _registerTextStyle(Fragment frag, ParagraphStyle pStyle,
      {bool forceLink = false, bool isCommented = false}) {
    final fragStyles = frag.styles ?? [];
    final pStyles = pStyle.styles ?? [];
    final bold = fragStyles.contains('bold') || pStyles.contains('bold');
    final italic = fragStyles.contains('italic') || pStyles.contains('italic');
    final underline = fragStyles.contains('underline') || forceLink;
    final strike = fragStyles.contains('strikethrough');
    final sup = fragStyles.contains('superscript');
    final sub = fragStyles.contains('subscript');
    final smallcaps = fragStyles.contains('smallcaps');

    double fontSize = frag.fontSize;
    if (fontSize == 14.0 && pStyle.fontSize != null) fontSize = pStyle.fontSize!;

    final fontFamily =
        normalizeFontFamily(frag.fontFamily.isNotEmpty ? frag.fontFamily : pStyle.fontFamily);
    _fonts.add(fontFamily);
    _registerFont(fontFamily);

    String? color = (frag.color != null && frag.color!.isNotEmpty)
        ? _normColor(frag.color!)
        : (forceLink ? '#1a73e8' : (pStyle.color));
    if (color != null) color = _normColor(color);

    final highlight = (frag.highlightColor != null &&
            frag.highlightColor!.isNotEmpty)
        ? _normColor(frag.highlightColor!)
        : null;

    final props = StringBuffer();
    props.write('style:font-name="${_esc(fontFamily)}"');
    props.write(' fo:font-size="${_fmt(fontSize)}pt"');
    props.write(' ${_languageAttrs()}');
    if (bold) props.write(' fo:font-weight="bold"');
    if (italic) props.write(' fo:font-style="italic"');
    if (underline) {
      props.write(
          ' style:text-underline-style="solid" style:text-underline-width="auto" style:text-underline-color="font-color"');
    }
    if (strike) {
      props.write(' style:text-line-through-style="solid"');
    }
    if (sup) props.write(' style:text-position="super 58%"');
    if (sub) props.write(' style:text-position="sub 58%"');
    if (smallcaps) props.write(' fo:font-variant="small-caps"');
    if (color != null) props.write(' fo:color="$color"');
    if (highlight != null) props.write(' fo:background-color="$highlight"');
    if (isCommented) props.write(' fo:background-color="#FFEB3B"');

    final key = props.toString();
    return _textStyles.putIfAbsent(key, () {
      final name = 'T${_textStyleCounter++}';
      _textStyleDefs[name] = key;
      return name;
    });
  }

  final Map<String, String> _textStyleDefs = {};

  String _registerParagraphStyle(
      Paragraph paragraph, ParagraphStyle pStyle, double extraIndentCm) {
    final align = _odtAlign(paragraph.textAlign);
    final indentCm = paragraph.indent * 0.63 + extraIndentCm +
        ((pStyle.indent ?? 0) * 0.63);
    final spacingBefore = pStyle.spacingBefore ?? document.pendingSpacingBefore;
    final spacingAfter = pStyle.spacingAfter ?? document.pendingSpacingAfter;
    final lineHeight = pStyle.lineHeight ?? document.pendingLineHeight;
    final isQuote = pStyle.name == 'quote';
    final isCode = pStyle.name == 'code';

    final props = StringBuffer();
    props.write('fo:text-align="$align"');
    if (indentCm > 0) props.write(' fo:margin-left="${_fmt(indentCm)}cm"');
    if (spacingBefore > 0) {
      props.write(' fo:margin-top="${_fmt(_pxToCm(spacingBefore))}cm"');
    }
    if (spacingAfter > 0) {
      props.write(' fo:margin-bottom="${_fmt(_pxToCm(spacingAfter))}cm"');
    } else {
      props.write(' fo:margin-bottom="0.1cm"');
    }
    if (isQuote) {
      props.write(
          ' fo:border-left="0.06cm solid #999999" fo:padding-left="0.3cm"');
    }
    if (isCode) {
      props.write(
          ' fo:background-color="#f5f5f5" fo:border="0.02cm solid #dddddd" fo:padding="0.2cm"');
    }

    final textProps = StringBuffer();
    textProps.write(' ${_languageAttrs()}');
    if (pStyle.fontSize != null) {
      textProps.write(' fo:font-size="${_fmt(pStyle.fontSize!)}pt"');
    }
    if (pStyle.fontFamily != null) {
      textProps.write(' style:font-name="${_esc(pStyle.fontFamily!)}"');
      _fonts.add(pStyle.fontFamily!);
      _registerFont(pStyle.fontFamily!);
    }
    if ((pStyle.styles ?? []).contains('bold')) {
      textProps.write(' fo:font-weight="bold"');
    }
    if ((pStyle.styles ?? []).contains('italic')) {
      textProps.write(' fo:font-style="italic"');
    }
    if (lineHeight > 0) {
      textProps.write(' fo:line-height="${_fmt(lineHeight)}"');
    }

    final key = 'P|${props.toString()}|${textProps.toString()}';
    return _paragraphStyles.putIfAbsent(key, () {
      final name = 'P${_paragraphStyleCounter++}';
      _paragraphStyleDefs[name] = (props.toString(), textProps.toString());
      return name;
    });
  }

  final Map<String, (String, String)> _paragraphStyleDefs = {};

  /// Returns `fo:language` and `fo:country` attributes based on
  /// [document.documentLanguage] (e.g. `it` → `fo:language="it" fo:country="IT"`).
  String _languageAttrs() {
    final code = document.documentLanguage;
    final parts = code.split('_');
    final language = parts.first;
    final country = parts.length > 1 ? parts.last.toUpperCase() : language.toUpperCase();
    return 'fo:language="$language" fo:country="$country"';
  }

  String _registerImageParagraphStyle(String textAlign, double extraIndentCm) {
    final align = _odtAlign(textAlign);
    final props = StringBuffer();
    props.write('fo:text-align="$align"');
    if (extraIndentCm > 0) {
      props.write(' fo:margin-left="${_fmt(extraIndentCm)}cm"');
    }
    props.write(' fo:margin-top="0.2cm" fo:margin-bottom="0.2cm"');
    final key = 'PIMG|${props.toString()}';
    return _paragraphStyles.putIfAbsent(key, () {
      final name = 'P${_paragraphStyleCounter++}';
      _paragraphStyleDefs[name] = (props.toString(), '');
      return name;
    });
  }

  String _registerListParagraphStyle(Paragraph paragraph, ParagraphStyle pStyle) {
    final align = _odtAlign(paragraph.textAlign);
    final props = StringBuffer();
    props.write('fo:text-align="$align"');
    props.write(' fo:margin-top="0cm" fo:margin-bottom="0cm"');

    final textProps = StringBuffer();
    if (pStyle.fontSize != null) {
      textProps.write(' fo:font-size="${_fmt(pStyle.fontSize!)}pt"');
    }
    if (pStyle.fontFamily != null) {
      textProps.write(' style:font-name="${_esc(pStyle.fontFamily!)}"');
      _fonts.add(pStyle.fontFamily!);
      _registerFont(pStyle.fontFamily!);
    }
    if ((pStyle.styles ?? []).contains('bold')) {
      textProps.write(' fo:font-weight="bold"');
    }
    if ((pStyle.styles ?? []).contains('italic')) {
      textProps.write(' fo:font-style="italic"');
    }
    final lineHeight = pStyle.lineHeight ?? document.pendingLineHeight;
    if (lineHeight > 0) {
      textProps.write(' fo:line-height="${_fmt(lineHeight)}"');
    }

    final key = 'PLIST|${props.toString()}|${textProps.toString()}';
    return _paragraphStyles.putIfAbsent(key, () {
      final name = 'P${_paragraphStyleCounter++}';
      _paragraphStyleDefs[name] = (props.toString(), textProps.toString());
      return name;
    });
  }

  // ─── List styles ───────────────────────────────────────────────────

  final Map<String, String> _listStyles = {};
  final Map<String, (String, int)> _listStyleDefs = {};
  int _listStyleCounter = 0;

  String _registerListStyle(String listType, int depth) {
    final key = '$listType|$depth';
    return _listStyles.putIfAbsent(key, () {
      final name = 'L${_listStyleCounter++}';
      _listStyleDefs[name] = (listType, depth);
      return name;
    });
  }

  String _buildListLevelStyle(String listType) {
    final ordered = listType.startsWith('ordered');
    if (ordered) {
      String format;
      String suffix;
      switch (listType) {
        case 'ordered-alpha':
          format = 'a'; suffix = '.';
          break;
        case 'ordered-alpha-parenthesis':
          format = 'a'; suffix = ')';
          break;
        case 'ordered-alpha-upper':
          format = 'A'; suffix = '.';
          break;
        case 'ordered-alpha-upper-parenthesis':
          format = 'A'; suffix = ')';
          break;
        case 'ordered-roman':
          format = 'i'; suffix = '.';
          break;
        case 'ordered-roman-parenthesis':
          format = 'i'; suffix = ')';
          break;
        case 'ordered-roman-upper':
          format = 'I'; suffix = '.';
          break;
        case 'ordered-roman-upper-parenthesis':
          format = 'I'; suffix = ')';
          break;
        case 'ordered-parenthesis':
          format = '1'; suffix = ')';
          break;
        default:
          format = '1'; suffix = '.';
      }
      return '<text:list-level-style-number text:level="1" style:num-format="$format" style:num-suffix="$suffix" text:display-levels="1"/>';
    }

    String bullet;
    switch (listType) {
      case 'bullet-circle':
        bullet = '\u25CB';
        break;
      case 'bullet-square':
        bullet = '\u25A1';
        break;
      case 'checkbox':
        bullet = '\u2610';
        break;
      case 'checkbox-checked':
        bullet = '\u2611';
        break;
      case 'checkbox-crossed':
        bullet = '\u2612';
        break;
      default:
        bullet = '\u2022';
    }
    return '<text:list-level-style-bullet text:level="1" text:bullet-char="$bullet"/>';
  }

  // ─── Images ───────────────────────────────────────────────────────

  String? _imageFrame(FluentImage image, {required String anchor}) {
    final bytes = _imageBytes(image.src);
    if (bytes == null) return null;

    final pic = _pictures.putIfAbsent(image.src, () {
      final ext = _imageExt(bytes);
      final name = 'img${_pictureCounter++}.$ext';
      _pictureBytes[name] = bytes;
      return name;
    });

    double? wPx = image.width;
    double? hPx = image.height;
    if (wPx == null || hPx == null) {
      final dims = _readImageDimensions(bytes);
      if (dims != null) {
        wPx ??= dims.$1.toDouble();
        hPx ??= dims.$2.toDouble();
      }
    }
    wPx ??= 300;
    hPx ??= 200;

    double wCm = _pxToCm(wPx);
    double hCm = _pxToCm(hPx);
    const maxCm = 17.0;
    if (wCm > maxCm) {
      final scale = maxCm / wCm;
      wCm = maxCm;
      hCm = hCm * scale;
    }

    final styleName = _registerImageFrameStyle(image.textAlign);
    final frameName = 'fr${_frameCounter++}';
    return '<draw:frame draw:style-name="$styleName" draw:name="$frameName" '
        'text:anchor-type="$anchor" svg:width="${_fmt(wCm)}cm" svg:height="${_fmt(hCm)}cm">'
        '<draw:image xlink:href="Pictures/$pic" xlink:type="simple" '
        'xlink:show="embed" xlink:actuate="onLoad"/></draw:frame>';
  }

  Uint8List? _imageBytes(String src) {
    if (src.startsWith('data:')) {
      final comma = src.indexOf(',');
      if (comma == -1) return null;
      try {
        return base64Decode(src.substring(comma + 1));
      } catch (_) {
        return null;
      }
    }
    return imageCache[src];
  }

  // ─── Final XML construction ─────────────────────────────────────────

  /// Builds the <office:font-face-decls> block to use in both files.
  String _buildFontFaceDecls() {
    final buf = StringBuffer();
    buf.write('<office:font-face-decls>');
    for (final font in _fonts) {
      final fileName = 'Fonts/${font.replaceAll(' ', '_')}.ttf';
      buf.write(
          '<style:font-face style:name="${_esc(font)}" svg:font-family="${_esc(font)}">'
          '<style:font-face-src>'
          '<svg:font-face-uri xlink:href="$fileName" svg:format="truetype"/>'
          '</style:font-face-src>'
          '</style:font-face>');
    }
    buf.write('</office:font-face-decls>');
    return buf.toString();
  }

  String _buildContentXml() {
    final styles = StringBuffer();

    // Automatic text styles.
    _textStyleDefs.forEach((name, props) {
      styles.write('<style:style style:name="$name" style:family="text">');
      styles.write('<style:text-properties $props/>');
      styles.write('</style:style>');
    });

    // Automatic paragraph styles.
    _paragraphStyleDefs.forEach((name, defs) {
      final (pProps, tProps) = defs;
      styles.write(
          '<style:style style:name="$name" style:family="paragraph" style:parent-style-name="Standard">');
      if (pProps.isNotEmpty) {
        styles.write('<style:paragraph-properties $pProps/>');
      }
      if (tProps.isNotEmpty) {
        styles.write('<style:text-properties $tProps/>');
      }
      styles.write('</style:style>');
    });

    // List styles.
    _listStyleDefs.forEach((name, def) {
      final (listType, _) = def;
      final levelStyle = _buildListLevelStyle(listType);
      styles.write('<text:list-style style:name="$name">');
      styles.write(levelStyle);
      styles.write('</text:list-style>');
    });

    // HR style (bottom border).
    if (_hrStyleName != null) {
      styles.write(
          '<style:style style:name="$_hrStyleName" style:family="paragraph" style:parent-style-name="Standard">');
      styles.write(
          '<style:paragraph-properties fo:border-bottom="0.02cm solid #cccccc" fo:margin-top="0.3cm" fo:margin-bottom="0.3cm" fo:padding="0cm"/>');
      styles.write('</style:style>');
    }

    // Table styles.
    styles.write(
        '<style:style style:name="$_tableStyleName" style:family="table">'
        '<style:table-properties style:width="17cm" fo:margin-top="0.2cm" fo:margin-bottom="0.2cm" table:align="margins"/>'
        '</style:style>');
    styles.write(
        '<style:style style:name="$_tableColStyleName" style:family="table-column">'
        '<style:table-column-properties style:use-optimal-column-width="true"/>'
        '</style:style>');
    styles.write(
        '<style:style style:name="$_tableCellStyleName" style:family="table-cell">'
        '<style:table-cell-properties fo:border="0.02cm solid #999999" fo:padding="0.1cm" style:vertical-align="top"/>'
        '</style:style>');

      // Image frame styles.
    for (final entry in _imageFrameStyleDefs.entries) {
      styles.write(entry.value);
    }

    // FIX: font-face-decls must also be present in content.xml,
    // otherwise style:font-name in automatic styles are not resolved.
    final fontFaceDecls = _buildFontFaceDecls();

    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<office:document-content '
        'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
        'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
        'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
        'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
        'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
        'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" '
        'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:officeooo="urn:openofficeorg:names:experimental:ooo-ms-interop:xmlns:field:1.0" '
        'xmlns:loext="urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0" '
        'office:version="1.2">'
        '$fontFaceDecls'
        '<office:automatic-styles>${styles.toString()}</office:automatic-styles>'
        '<office:body><office:text>${_body.toString()}</office:text></office:body>'
        '</office:document-content>';
  }

  String _buildStylesXml() {
    // FIX: font-face go in <office:font-face-decls>, NOT inside
    // <office:styles>. In the previous version they were inside office:styles,
    // which is syntactically invalid for the ODF standard and causes
    // LibreOffice/Writer to silently ignore all font declarations.
    final fontFaceDecls = _buildFontFaceDecls();

    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<office:document-styles '
        'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
        'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
        'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
        'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
        'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" '
        'xmlns:xlink="http://www.w3.org/1999/xlink" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:officeooo="urn:openofficeorg:names:experimental:ooo-ms-interop:xmlns:field:1.0" '
        'office:version="1.2">'
        '$fontFaceDecls'
        '<office:styles>'
        '<style:default-style style:family="paragraph">'
        '<style:paragraph-properties fo:margin-bottom="0.1cm"/>'
        '<style:text-properties style:font-name="DejaVu Sans" fo:font-size="14pt" ${_languageAttrs()}/>'
        '</style:default-style>'
        '<style:style style:name="Standard" style:family="paragraph" style:class="text">'
        '<style:text-properties style:font-name="DejaVu Sans" fo:font-size="14pt" ${_languageAttrs()}/>'
        '</style:style>'
        '</office:styles>'
        '<office:automatic-styles>'
        '<style:page-layout style:name="pm1">'
        '<style:page-layout-properties fo:page-width="21cm" fo:page-height="29.7cm" '
        'fo:margin-top="2cm" fo:margin-bottom="2cm" fo:margin-left="2cm" fo:margin-right="2cm"/>'
        '</style:page-layout>'
        '</office:automatic-styles>'
        '<office:master-styles>'
        '<style:master-page style:name="Standard" style:page-layout-name="pm1"/>'
        '</office:master-styles>'
        '</office:document-styles>';
  }

  String _buildManifestXml() {
    final entries = StringBuffer();
    entries.write(
        '<manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>');
    entries.write(
        '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>');
    entries.write(
        '<manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>');
    for (final entry in _pictureBytes.entries) {
      final mime = _mimeFromName(entry.key);
      entries.write(
          '<manifest:file-entry manifest:full-path="Pictures/${entry.key}" manifest:media-type="$mime"/>');
    }
    for (final fontName in _embeddedFonts.keys) {
      final fileName = 'Fonts/${fontName.replaceAll(' ', '_')}.ttf';
      entries.write(
          '<manifest:file-entry manifest:full-path="$fileName" manifest:media-type="application/vnd.oasis.opendocument.font"/>');
    }
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<manifest:manifest '
        'xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" '
        'manifest:version="1.2">${entries.toString()}</manifest:manifest>';
  }

  // ─── Helper ─────────────────────────────────────────────────────────

  static const _tableStyleName = 'TableStyle';
  static const _tableColStyleName = 'TableCol';
  static const _tableCellStyleName = 'TableCell';
  int _tableCounter = 0;
  int _frameCounter = 0;

  int _tableColumnCount(FluentTable table) {
    int max = 0;
    for (final row in table.rows) {
      int count = 0;
      for (final cell in row.cells) {
        count += cell.colSpan;
      }
      if (count > max) max = count;
    }
    return max == 0 ? 1 : max;
  }

  int _headingLevel(String styleName) {
    return switch (styleName) {
      'heading1' => 1,
      'heading2' => 2,
      'heading3' => 3,
      _ => 0,
    };
  }

  String _odtAlign(String align) {
    return switch (align) {
      'center' => 'center',
      'right' => 'end',
      'justify' => 'justify',
      _ => 'start',
    };
  }

  double _pxToCm(double px) => px * 2.54 / 96.0;

  String _fmt(double v) {
    final s = v.toStringAsFixed(3);
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  String _normColor(String hex) {
    var h = hex.trim();
    if (!h.startsWith('#')) h = '#$h';
    if (h.length == 4) {
      h = '#${h[1]}${h[1]}${h[2]}${h[2]}${h[3]}${h[3]}';
    }
    return h.toLowerCase();
  }

  String _esc(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Escape preserving multiple spaces with <text:s/>.
  String _escWithSpaces(String text) {
    final escaped = _esc(text);
    return escaped.replaceAllMapped(RegExp(r'  +'), (m) {
      final n = m.group(0)!.length;
      return ' <text:s text:c="${n - 1}"/>';
    });
  }

  String _registerImageFrameStyle(String align) {
    final pos = switch (align) {
      'center' => 'center',
      'right' => 'right',
      _ => 'left',
    };
    final key = 'IFRAME|$pos';
    return _imageFrameStyles.putIfAbsent(key, () {
      final name = 'G${_imageFrameStyleCounter++}';
      _imageFrameStyleDefs[name] =
          '<style:style style:name="$name" style:family="graphic">'
          '<style:graphic-properties style:vertical-pos="top" style:horizontal-pos="$pos" '
          'fo:border="none" style:wrap="none"/>'
          '</style:style>';
      return name;
    });
  }

  String _imageExt(Uint8List bytes) {
    if (bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50) return 'png';
    if (bytes.length > 2 && bytes[0] == 0x47 && bytes[1] == 0x49) return 'gif';
    return 'jpg';
  }

  String _mimeFromName(String name) {
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  (int, int)? _readImageDimensions(Uint8List bytes) {
    if (bytes.length < 24) return null;
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      return (w, h);
    }
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
}