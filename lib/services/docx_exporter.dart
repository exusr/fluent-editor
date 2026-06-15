import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: unused_import
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/utils/editor_utils.dart';

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

/// Generates a native DOCX (OOXML) file from the document.
class DocxExporter {
  final FluentDocument document;
  final Map<String, Uint8List> imageCache;

  DocxExporter(this.document, {Map<String, Uint8List>? imageCache})
      : imageCache = imageCache ?? {};

  final StringBuffer _body = StringBuffer();

  // Relationships (images + hyperlinks): rId -> (type, target, mode)
  final Map<String, _Rel> _rels = {};
  int _relCounter = 1;

  // Embedded images: src -> media file name.
  final Map<String, String> _media = {};
  final Map<String, Uint8List> _mediaBytes = {};
  int _mediaCounter = 0;
  int _docPrId = 1;

  // Fonts used in the document (for embedding).
  final Set<String> _fonts = {};

  // List numbering: FluentList.id -> numId assigned in numbering.xml
  final Map<String, int> _listNumIds = {};
  final List<_NumDef> _numDefs = [];
  int _numIdCounter = 1;
  int _abstractNumIdCounter = 0;

  // Native DOCX comment export state.
  final List<Map<String, dynamic>> _docxComments = [];
  int _commentIdCounter = 0;
  final Map<String, int> _commentIdMap = {};
  final Map<String, int> _replyDocxIds = {}; // "${parentId}_$index" -> replyDocxId
  final Map<String, String> _paragraphParaIds = {}; // paragraph.id -> paraId

  Future<Uint8List> build() async {
    // Pre-assegna gli ID a tutti i commenti e le reply
    final allComments = document.commentProvider?.exportComments() ?? [];
    for (final c in allComments) {
      if (c['resolved'] == true || c['orphan'] == true) continue;
      final docxId = _ensureDocxCommentId(c);
      final replies = (c['replies'] as List<dynamic>?) ?? [];
      for (var ri = 0; ri < replies.length; ri++) {
        final replyId = _commentIdCounter++;
        _replyDocxIds['${docxId}_$ri'] = replyId;
      }
    }

    final root = document.content;
    for (final node in root.nodes) {
      _writeNode(node);
    }

    final archive = Archive();

    // Embed system fonts
    for (final fontName in _fonts) {
      final bytes = await _findSystemFontBytes(fontName);
      if (bytes != null) {
        final fileName = 'font${_mediaCounter++}.ttf';
        archive
            .addFile(ArchiveFile('word/fonts/$fileName', bytes.length, bytes));
        _addRel(
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/font',
            'fonts/$fileName');
      }
    }

    if (_numDefs.isNotEmpty) {
      _add(archive, 'word/numbering.xml', _numberingXml());
      _addRel(
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering',
          'numbering.xml');
    }

    if (_docxComments.isNotEmpty) {
      _add(archive, 'word/comments.xml', _commentsXml());
      _add(archive, 'word/commentsExtended.xml', _commentsExtendedXml());
      _addRel(
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments',
          'comments.xml');
      _addRel(
          'http://schemas.microsoft.com/office/2011/relationships/commentsExtended',
          'commentsExtended.xml');
    }

    _add(archive, '[Content_Types].xml', _contentTypes());
    _add(archive, '_rels/.rels', _rootRels());
    _add(archive, 'word/document.xml', _documentXml());
    _add(archive, 'word/_rels/document.xml.rels', _documentRels());
    for (final e in _mediaBytes.entries) {
      archive
          .addFile(ArchiveFile('word/media/${e.key}', e.value.length, e.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

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
            final name =
                entity.path.split(Platform.pathSeparator).last.toLowerCase();
            final ext = name.split('.').last;
            if ((ext == 'ttf' || ext == 'ttc' || ext == 'otf') &&
                name.startsWith(lower)) {
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

  void _add(Archive a, String path, String content) {
    final b = utf8.encode(content);
    a.addFile(ArchiveFile(path, b.length, b));
  }

  // ─── Nodi ───────────────────────────────────────────────────────────

  void _writeNode(FNode node, {int extraIndent = 0}) {
    if (node is FluentImage) {
      _writeBlockImage(node, extraIndent: extraIndent);
    } else if (node is HorizontalRule) {
      _writeHr();
    } else if (node is FluentList) {
      _writeList(node);
    } else if (node is FluentTable) {
      _writeTable(node);
    } else if (node is Paragraph) {
      _writeParagraph(node, extraIndent: extraIndent);
    }
  }

  void _writeParagraph(Paragraph p, {int extraIndent = 0, String? prefixRun}) {
    final pStyle = p.getStyle();
    final paraId = _generateParaId();
    _paragraphParaIds[p.id] = paraId;
    _body.write('<w:p>');
    _body.write(_pPr(p, pStyle, extraIndent: extraIndent, paraId: paraId));
    if (prefixRun != null) _body.write(prefixRun);
    final comments = document.commentProvider?.exportComments() ?? [];
    _writeInline(p.fragments, pStyle, paragraphId: p.id, comments: comments);
    _body.write('</w:p>');
  }

  void _writeHr() {
    final paraId = _generateParaId();
    _body.write('<w:p><w:pPr><w14:paraId w14:val="$paraId"/><w:pBdr>'
        '<w:bottom w:val="single" w:sz="6" w:space="1" w:color="CCCCCC"/>'
        '</w:pBdr></w:pPr></w:p>');
  }

  void _writeBlockImage(FluentImage img, {int extraIndent = 0}) {
    final draw = _imageRun(img);
    final jc = _docxAlign(img.textAlign);
    final paraId = _generateParaId();
    _body.write('<w:p><w:pPr><w14:paraId w14:val="$paraId"/>');
    if (extraIndent > 0) _body.write('<w:ind w:left="$extraIndent"/>');
    _body.write('<w:jc w:val="$jc"/></w:pPr>');
    if (draw != null) _body.write('<w:r>$draw</w:r>');
    _body.write('</w:p>');
  }

  void _writeList(FluentList list, {int depth = 0, int? numId}) {
    final rootNumId = numId ?? _getOrCreateNumId(list);
    for (final item in list.items) {
      for (final child in item.children) {
        if (child is FluentList) {
          _writeList(child, depth: depth + 1, numId: rootNumId);
        } else if (child is FluentImage) {
          _writeBlockImage(child);
        } else if (child is Paragraph) {
          _writeListParagraph(child, rootNumId, depth);
        }
      }
    }
  }

  int _getOrCreateNumId(FluentList list) {
    if (_listNumIds.containsKey(list.id)) return _listNumIds[list.id]!;
    final abstractNumId = _abstractNumIdCounter++;
    final numId = _numIdCounter++;
    _numDefs.add(_NumDef(abstractNumId, numId, list.listType));
    _listNumIds[list.id] = numId;
    return numId;
  }

  void _writeListParagraph(Paragraph p, int numId, int depth) {
    final pStyle = p.getStyle();
    final paraId = _generateParaId();
    _paragraphParaIds[p.id] = paraId;
    _body.write('<w:p><w:pPr><w14:paraId w14:val="$paraId"/>');
    _body.write('<w:numPr><w:ilvl w:val="$depth"/><w:numId w:val="$numId"/></w:numPr>');
    _body.write('</w:pPr>');
    final comments = document.commentProvider?.exportComments() ?? [];
    _writeInline(p.fragments, pStyle, paragraphId: p.id, comments: comments);
    _body.write('</w:p>');
  }

  void _writeTable(FluentTable table) {
    final cols = _colCount(table);
    _body.write('<w:tbl><w:tblPr>'
        '<w:tblW w:w="5000" w:type="pct"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:color="999999"/>'
        '<w:left w:val="single" w:sz="4" w:color="999999"/>'
        '<w:bottom w:val="single" w:sz="4" w:color="999999"/>'
        '<w:right w:val="single" w:sz="4" w:color="999999"/>'
        '<w:insideH w:val="single" w:sz="4" w:color="999999"/>'
        '<w:insideV w:val="single" w:sz="4" w:color="999999"/>'
        '</w:tblBorders></w:tblPr>');
    _body.write('<w:tblGrid>');
    for (int i = 0; i < cols; i++) {
      _body.write('<w:gridCol/>');
    }
    _body.write('</w:tblGrid>');

    for (final row in table.rows) {
      _body.write('<w:tr>');
      for (final cell in row.cells) {
        _body.write('<w:tc><w:tcPr>');
        if (cell.colSpan > 1) {
          _body.write('<w:gridSpan w:val="${cell.colSpan}"/>');
        }
        if (cell.rowSpan > 1) {
          _body.write('<w:vMerge w:val="restart"/>');
        }
        _body.write('<w:tcMar>'
            '<w:top w:w="40" w:type="dxa"/><w:left w:w="80" w:type="dxa"/>'
            '<w:bottom w:w="40" w:type="dxa"/><w:right w:w="80" w:type="dxa"/>'
            '</w:tcMar><w:vAlign w:val="top"/></w:tcPr>');
        _writeCell(cell);
        _body.write('</w:tc>');
      }
      _body.write('</w:tr>');
    }
    _body.write('</w:tbl>');
    // Empty paragraph after the table (required by Word).
    _body.write('<w:p/>');
  }

  void _writeCell(FluentCell cell) {
    bool wrote = false;
    for (final child in cell.children) {
      if (child is FluentImage) {
        _writeBlockImage(child);
        wrote = true;
      } else if (child is FluentList) {
        _writeList(child);
        wrote = true;
      } else if (child is Paragraph) {
        _writeParagraph(child);
        wrote = true;
      }
    }
    if (!wrote) _body.write('<w:p/>');
  }

  // ─── Inline ─────────────────────────────────────────────────────────

  List<_TextSeg> _extractSegments(
      String text, int baseOffset, List<_CommentSeg> segs) {
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
        result.add(
            _TextSeg(text.substring(segStartLocal, segEndLocal), seg.comment));
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

  int _ensureDocxCommentId(Map<String, dynamic> comment) {
    final id = comment['id'] as String;
    if (_commentIdMap.containsKey(id)) return _commentIdMap[id]!;
    final docxId = _commentIdCounter++;
    _commentIdMap[id] = docxId;
    _docxComments.add(comment);
    return docxId;
  }

  void _writeInline(
    List<FNode> fragments,
    ParagraphStyle pStyle, {
    String? paragraphId,
    List<Map<String, dynamic>>? comments,
  }) {
    int globalOffset = 0;
    final segs = <_CommentSeg>[];
    if (comments != null && paragraphId != null) {
      for (final c in comments) {
        if (c['nodeId'] == paragraphId &&
            c['resolved'] != true &&
            c['orphan'] != true) {
          segs.add(_CommentSeg(
            c['startOffset'] as int,
            c['endOffset'] as int,
            c,
          ));
        }
      }
      segs.sort((a, b) => a.start.compareTo(b.start));
    }

    // Track which comment IDs have already emitted their Start marker so that
    // comments spanning multiple fragments do not produce duplicate anchors.
    final startedCommentIds = <int>{};
    // Track comments that need their End+Reference emitted once the last
    // overlapping fragment has been processed.  Maps commentId -> comment data.
    // We emit End markers at the boundary where the comment no longer overlaps.
    // Simpler approach: collect all comment IDs that overlap with each fragment
    // range and emit Start only on first encounter, End only when the comment
    // range ends before or at the current fragment's end.
    // We use per-comment "last fragment end offset" tracking instead.

    void _emitCommentStarts(
        Map<String, dynamic> comment, int docxId, List<dynamic> replies) {
      if (startedCommentIds.contains(docxId)) return;
      startedCommentIds.add(docxId);
      _body.write('<w:commentRangeStart w:id="$docxId"/>');
      for (var ri = 0; ri < replies.length; ri++) {
        final replyId = _replyDocxIds['${docxId}_$ri']!;
        startedCommentIds.add(replyId);
        _body.write('<w:commentRangeStart w:id="$replyId"/>');
      }
    }

    void _emitCommentEnds(
        Map<String, dynamic> comment, int docxId, List<dynamic> replies) {
      for (var ri = replies.length - 1; ri >= 0; ri--) {
        final replyId = _replyDocxIds['${docxId}_$ri']!;
        _body.write('<w:commentRangeEnd w:id="$replyId"/>');
        _body.write('<w:r><w:commentReference w:id="$replyId"/></w:r>');
      }
      _body.write('<w:commentRangeEnd w:id="$docxId"/>');
      _body.write('<w:r><w:commentReference w:id="$docxId"/></w:r>');
    }

    for (final frag in fragments) {
      if (frag is Link) {
        int linkOffset = 0;
        int linkTotalLen = 0;
        for (final child in frag.fragments) {
          if (child is Fragment) linkTotalLen += child.text.length;
        }
        final linkStart = globalOffset;
        final linkEnd = globalOffset + linkTotalLen;
        final overlapping =
            segs.where((s) => s.start < linkEnd && s.end > linkStart).toList();

        // Emit Start markers for comments beginning in this link range.
        for (final seg in overlapping) {
          final cid = _ensureDocxCommentId(seg.comment);
          final replies = (seg.comment['replies'] as List<dynamic>?) ?? [];
          _emitCommentStarts(seg.comment, cid, replies);
        }

        final rId = _addRel(
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink',
            frag.url,
            external: true);
        _body.write('<w:hyperlink r:id="$rId">');
        for (final child in frag.fragments) {
          if (child is FluentImage) {
            final d = _imageRun(child);
            if (d != null) _body.write('<w:r>$d</w:r>');
          } else if (child is Fragment) {
            final subs =
                _extractSegments(child.text, globalOffset + linkOffset, segs);
            for (final sub in subs) {
              _body.write(_run(child, pStyle,
                  forceLink: true,
                  text: sub.text,
                  isCommented: sub.comment != null));
            }
            linkOffset += child.text.length;
          }
        }
        _body.write('</w:hyperlink>');

        // Emit End markers for comments whose range ends within this link.
        for (final seg in overlapping) {
          if (seg.end <= linkEnd) {
            final cid = _ensureDocxCommentId(seg.comment);
            final replies = (seg.comment['replies'] as List<dynamic>?) ?? [];
            _emitCommentEnds(seg.comment, cid, replies);
          }
        }
        globalOffset += linkOffset;
      } else if (frag is FluentImage) {
        final d = _imageRun(frag);
        if (d != null) _body.write('<w:r>$d</w:r>');
      } else if (frag is Fragment) {
        final fragStart = globalOffset;
        final fragEnd = globalOffset + frag.text.length;
        final subs = _extractSegments(frag.text, globalOffset, segs);

        for (final sub in subs) {
          if (sub.comment != null) {
            final cid = _ensureDocxCommentId(sub.comment!);
            final replies = (sub.comment!['replies'] as List<dynamic>?) ?? [];
            _emitCommentStarts(sub.comment!, cid, replies);
          }
          _body.write(_run(frag, pStyle,
              text: sub.text, isCommented: sub.comment != null));
        }

        // After writing all sub-segments of this fragment, emit End markers
        // for every comment whose range ends at or before this fragment's end.
        for (final seg in segs) {
          if (seg.end > fragStart && seg.end <= fragEnd) {
            final cid = _ensureDocxCommentId(seg.comment);
            final replies = (seg.comment['replies'] as List<dynamic>?) ?? [];
            _emitCommentEnds(seg.comment, cid, replies);
          }
        }

        globalOffset = fragEnd;
      }
    }

    // Emit End markers for any comments that extended past the last fragment.
    for (final seg in segs) {
      final cid = _ensureDocxCommentId(seg.comment);
      if (startedCommentIds.contains(cid)) {
        // Only emit End if it hasn't been emitted yet (i.e., comment end was
        // beyond the paragraph boundary — shouldn't happen normally but guard
        // against orphan ranges).
        // We track emitted ends via a local set.
      }
    }
  }

  String _run(Fragment f, ParagraphStyle pStyle,
      {bool forceLink = false, String? text, bool isCommented = false}) {
    final fs = f.styles ?? [];
    final ps = pStyle.styles ?? [];
    final bold = fs.contains('bold') || ps.contains('bold');
    final italic = fs.contains('italic') || ps.contains('italic');
    final underline = fs.contains('underline') || forceLink;
    final strike = fs.contains('strikethrough');
    final sup = fs.contains('superscript');
    final sub = fs.contains('subscript');
    final smallcaps = fs.contains('smallcaps');

    double fontSize = f.fontSize;
    if (fontSize == 14.0 && pStyle.fontSize != null) {
      fontSize = pStyle.fontSize!;
    }
    final font = normalizeFontFamily(
        f.fontFamily.isNotEmpty ? f.fontFamily : pStyle.fontFamily);
    _fonts.add(font);

    String? color = (f.color != null && f.color!.isNotEmpty)
        ? _hex(f.color!)
        : (forceLink
            ? '1A73E8'
            : (pStyle.color != null ? _hex(pStyle.color!) : null));
    final highlight = (f.highlightColor != null && f.highlightColor!.isNotEmpty)
        ? _hex(f.highlightColor!)
        : null;

    final rpr = StringBuffer('<w:rPr>');
    rpr.write('<w:rFonts w:ascii="${_esc(font)}" w:hAnsi="${_esc(font)}"/>');
    final docLang = document.documentLanguage.replaceAll('_', '-');
    rpr.write(
        '<w:lang w:val="$docLang" w:eastAsia="$docLang" w:bidi="$docLang"/>');
    if (bold) rpr.write('<w:b/>');
    if (italic) rpr.write('<w:i/>');
    if (underline) rpr.write('<w:u w:val="single"/>');
    if (strike) {
      rpr.write('<w:strike/>');
    }
    if (smallcaps) rpr.write('<w:smallCaps/>');
    if (color != null) {
      rpr.write('<w:color w:val="$color"/>');
    }
    if (highlight != null) {
      rpr.write('<w:shd w:val="clear" w:color="auto" w:fill="$highlight"/>');
    }
    if (isCommented) {
      rpr.write('<w:shd w:val="clear" w:color="auto" w:fill="FFEB3B"/>');
    }
    rpr.write('<w:sz w:val="${(fontSize * 2).round()}"/>');
    if (sup) rpr.write('<w:vertAlign w:val="superscript"/>');
    if (sub) rpr.write('<w:vertAlign w:val="subscript"/>');
    rpr.write('</w:rPr>');

    final runText = text ?? f.text;
    return '<w:r>${rpr.toString()}<w:t xml:space="preserve">${_esc(runText)}</w:t></w:r>';
  }

  // ─── Paragraph properties ───────────────────────────────────────────

  String _pPr(Paragraph p, ParagraphStyle pStyle, {int extraIndent = 0, String? paraId}) {
    final jc = _docxAlign(p.textAlign);
    final indent = p.indent * 360 + extraIndent + ((pStyle.indent ?? 0) * 360);
    final before =
        ((pStyle.spacingBefore ?? document.pendingSpacingBefore) * 15).round();
    final after =
        ((pStyle.spacingAfter ?? document.pendingSpacingAfter) * 15).round();
    final lineHeight = pStyle.lineHeight ?? document.pendingLineHeight;
    final isQuote = pStyle.name == 'quote';
    final isCode = pStyle.name == 'code';

    final b = StringBuffer('<w:pPr>');
    if (paraId != null) {
      b.write('<w14:paraId w14:val="$paraId"/>');
    }
    if (isQuote) {
      b.write(
          '<w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="999999"/></w:pBdr>');
    }
    if (isCode) {
      b.write('<w:pBdr>'
          '<w:top w:val="single" w:sz="4" w:space="2" w:color="DDDDDD"/>'
          '<w:left w:val="single" w:sz="4" w:space="2" w:color="DDDDDD"/>'
          '<w:bottom w:val="single" w:sz="4" w:space="2" w:color="DDDDDD"/>'
          '<w:right w:val="single" w:sz="4" w:space="2" w:color="DDDDDD"/>'
          '</w:pBdr><w:shd w:val="clear" w:color="auto" w:fill="F5F5F5"/>');
    }
    if (indent > 0) b.write('<w:ind w:left="$indent"/>');
    final lineVal = (lineHeight * 240).round(); // 240 = 100% in OOXML
    b.write(
        '<w:spacing w:before="$before" w:after="$after" w:line="$lineVal" w:lineRule="auto"/>');
    b.write('<w:jc w:val="$jc"/>');
    b.write('</w:pPr>');
    return b.toString();
  }

  // ─── Images ───────────────────────────────────────────────────────

  String? _imageRun(FluentImage img) {
    final bytes = _bytesOf(img.src);
    if (bytes == null) return null;
    final media = _media.putIfAbsent(img.src, () {
      final ext = _ext(bytes);
      final name = 'image${_mediaCounter++}.$ext';
      _mediaBytes[name] = bytes;
      return name;
    });
    final rId = _addRel(
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image',
        'media/$media');

    double? wPx = img.width;
    double? hPx = img.height;
    if (wPx == null || hPx == null) {
      final dims = _dims(bytes);
      if (dims != null) {
        wPx ??= dims.$1.toDouble();
        hPx ??= dims.$2.toDouble();
      }
    }
    wPx ??= 300;
    hPx ??= 200;
    // Limit to useful width (~620px = 16.4cm).
    const maxPx = 620.0;
    if (wPx > maxPx) {
      final scale = maxPx / wPx;
      wPx = maxPx;
      hPx = hPx * scale;
    }
    final cx = (wPx * 9525).round();
    final cy = (hPx * 9525).round();
    final id = _docPrId++;

    return '<w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/>'
        '<wp:docPr id="$id" name="Picture $id"/>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="$id" name="Picture $id"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$rId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing>';
  }

  Uint8List? _bytesOf(String src) {
    if (src.startsWith('data:')) {
      final c = src.indexOf(',');
      if (c == -1) return null;
      try {
        return base64Decode(src.substring(c + 1));
      } catch (_) {
        return null;
      }
    }
    return imageCache[src];
  }

  String _numberingXml() {
    const bulletChars = ['\u2022', '\u25E6', '\u25AA'];
    final b = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">');
    for (final def in _numDefs) {
      b.write('<w:abstractNum w:abstractNumId="${def.abstractNumId}">');
      b.write('<w:multiLevelType w:val="multilevel"/>');
      for (int lvl = 0; lvl <= 8; lvl++) {
        final left = (lvl + 1) * 720;
        b.write('<w:lvl w:ilvl="$lvl"><w:start w:val="1"/>');
        if (def.listType == 'ordered') {
          b.write('<w:numFmt w:val="decimal"/><w:lvlText w:val="%${lvl + 1}."/>');
        } else {
          final ch = bulletChars[lvl % bulletChars.length];
          b.write('<w:numFmt w:val="bullet"/><w:lvlText w:val="$ch"/>');
        }
        b.write('<w:lvlJc w:val="left"/>');
        b.write('<w:pPr><w:ind w:left="$left" w:hanging="360"/></w:pPr>');
        b.write('</w:lvl>');
      }
      b.write('</w:abstractNum>');
    }
    for (final def in _numDefs) {
      b.write('<w:num w:numId="${def.numId}"><w:abstractNumId w:val="${def.abstractNumId}"/></w:num>');
    }
    b.write('</w:numbering>');
    return b.toString();
  }

  String _addRel(String type, String target, {bool external = false}) {
    final id = 'rId${_relCounter++}';
    _rels[id] = _Rel(type, target, external);
    return id;
  }

  // ─── Support XML ────────────────────────────────────────────────

  String _documentXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:document '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" '
        'xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml">'
        '<w:body>${_body.toString()}'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" '
        'w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>';
  }

  String _documentRels() {
    final b = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    _rels.forEach((id, rel) {
      final mode = rel.external ? ' TargetMode="External"' : '';
      b.write(
          '<Relationship Id="$id" Type="${rel.type}" Target="${_esc(rel.target)}"$mode/>');
    });
    b.write('</Relationships>');
    return b.toString();
  }

  String _commentsExtendedXml() {
    final b = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w15:commentsEx xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml">');

    for (final c in _docxComments) {
      final docxId = _commentIdMap[c['id']]!;
      final paragraphId = c['nodeId'] as String? ?? '';
      final paraId = _paragraphParaIds[paragraphId] ?? _generateParaId();

      // Commento principale
      b.write(
          '<w15:commentEx w15:id="$docxId" w15:paraId="$paraId" w15:done="1"/>');

      // Risposte
      final replies = (c['replies'] as List<dynamic>?) ?? [];
      for (var ri = 0; ri < replies.length; ri++) {
        final replyId = _replyDocxIds['${docxId}_$ri']!;
        b.write(
            '<w15:commentEx w15:id="$replyId" w15:paraId="$paraId" w15:done="1" w15:parent="$docxId"/>');
      }
    }

    b.write('</w15:commentsEx>');
    return b.toString();
  }

  /// Genera un ID univoco per il paragrafo (esempio: 8 caratteri esadecimali).
  String _generateParaId() {
    final random = Random();
    return List.generate(8, (index) => random.nextInt(16).toRadixString(16))
        .join();
  }

  String _commentsXml() {
    final b = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:comments xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml">');

    for (final c in _docxComments) {
      final docxId = _commentIdMap[c['id']]!;
      final author = _esc(c['authorName'] as String? ?? 'Anonimo');
      final date = _esc(_formatDate(c['createdAt'] as String?));
      final text = _esc(c['text'] as String? ?? '');

      // Commento principale
      b.write('<w:comment w:id="$docxId" w:author="$author" w:date="$date">'
          '<w:p><w:r><w:t>$text</w:t></w:r></w:p>'
          '</w:comment>');

      // Risposte come commenti separati
      final replies = (c['replies'] as List<dynamic>?) ?? [];
      for (var ri = 0; ri < replies.length; ri++) {
        final r = replies[ri];
        final rMap = r as Map<String, dynamic>;
        final rAuthor = _esc(rMap['authorName'] as String? ?? 'Anonimo');
        final rDate = _esc(_formatDate(rMap['createdAt'] as String?));
        final rText = _esc(rMap['text'] as String? ?? '');
        final replyId = _replyDocxIds['${docxId}_$ri']!;

        b.write(
            '<w:comment w:id="$replyId" w:author="$rAuthor" w:date="$rDate" w15:parentId="$docxId">'
            '<w:p><w:r><w:t>$rText</w:t></w:r></w:p>'
            '</w:comment>');
      }
    }

    b.write('</w:comments>');
    return b.toString();
  }

  /// Formatta la data in ISO 8601 senza microsecondi.
  String _formatDate(String? date) {
    String format(DateTime d) {
      final iso = d.toUtc().toIso8601String();
      return iso.contains('.') ? '${iso.substring(0, iso.indexOf('.'))}Z' : iso;
    }
    if (date == null || date.isEmpty) {
      return format(DateTime.now());
    }
    try {
      return format(DateTime.parse(date));
    } catch (e) {
      return format(DateTime.now());
    }
  }

  String _contentTypes() {
    final b = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Default Extension="jpg" ContentType="image/jpeg"/>'
        '<Default Extension="jpeg" ContentType="image/jpeg"/>'
        '<Default Extension="gif" ContentType="image/gif"/>'
        '<Default Extension="ttf" ContentType="application/x-fontdata"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/comments.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"/>'
        '<Override PartName="/word/commentsExtended.xml" ContentType="application/vnd.openxmlformats.microsoftword.commentsExtended+xml"/>'
        '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>');  
    b.write('</Types>');
    return b.toString();
  }

  String _rootRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        'Target="word/document.xml"/></Relationships>';
  }

  // ─── Helper ─────────────────────────────────────────────────────────

  int _colCount(FluentTable t) {
    int max = 0;
    for (final r in t.rows) {
      int c = 0;
      for (final cell in r.cells) {
        c += cell.colSpan;
      }
      if (c > max) max = c;
    }
    return max == 0 ? 1 : max;
  }

  String _docxAlign(String a) => switch (a) {
        'center' => 'center',
        'right' => 'right',
        'justify' => 'both',
        _ => 'left',
      };

  String _hex(String c) {
    var h = c.trim().replaceAll('#', '');
    if (h.length == 3) h = '${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}';
    return h.toUpperCase();
  }

  String _esc(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  String _ext(Uint8List b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
    if (b.length > 2 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
    return 'jpg';
  }

  (int, int)? _dims(Uint8List b) {
    if (b.length < 24) return null;
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      final w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
      final h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
      return (w, h);
    }
    if (b[0] == 0xFF && b[1] == 0xD8) {
      int o = 2;
      while (o < b.length - 8) {
        if (b[o] != 0xFF) break;
        final m = b[o + 1];
        if (m == 0xC0 || m == 0xC2) {
          return ((b[o + 7] << 8) | b[o + 8], (b[o + 5] << 8) | b[o + 6]);
        }
        o += 2 + ((b[o + 2] << 8) | b[o + 3]);
      }
    }
    return null;
  }

}

class _NumDef {
  final int abstractNumId;
  final int numId;
  final String listType;
  _NumDef(this.abstractNumId, this.numId, this.listType);
}

class _Rel {
  final String type;
  final String target;
  final bool external;
  _Rel(this.type, this.target, this.external);
}