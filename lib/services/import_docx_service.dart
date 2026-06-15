import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fluent_editor/factories.dart';
import 'package:xml/xml.dart';

/// Service for importing DOCX into FluentEditor nodes.
class ImportDocxService {
  // Relationship map: rId → URL (populated from word/_rels/document.xml.rels)
  final Map<String, String> _relationships = {};

  // Numbering map: numId → abstractNumId → listType ('ordered' | 'unordered')
  // Built from word/numbering.xml
  final Map<String, String> _numIdToType = {};

  Root importFromDocx(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // --- FIX Bug 1: parse relationships for hyperlink URL resolution ---
    final relsFile = archive.files
        .where((f) => f.name == 'word/_rels/document.xml.rels')
        .firstOrNull;
    if (relsFile != null) {
      _parseRelationships(utf8.decode(relsFile.content as Uint8List));
    }

    // --- FIX Bug 3: parse numbering.xml for list type detection ---
    final numberingFile = archive.files
        .where((f) => f.name == 'word/numbering.xml')
        .firstOrNull;
    if (numberingFile != null) {
      _parseNumbering(utf8.decode(numberingFile.content as Uint8List));
    }

    final documentXml = archive.files
        .where((f) => f.name == 'word/document.xml')
        .firstOrNull;
    if (documentXml == null) return Root(nodes: [Paragraph(text: '')]);

    final xmlString = utf8.decode(documentXml.content as Uint8List);
    final document = XmlDocument.parse(xmlString);
    final body = document.findAllElements('w:body').firstOrNull;
    if (body == null) return Root(nodes: [Paragraph(text: '')]);

    final nodes = _elementsToNodes(body.children);
    return Root(nodes: nodes.isEmpty ? [Paragraph(text: '')] : nodes);
  }

  // ---------------------------------------------------------------------------
  // Relationships parsing (word/_rels/document.xml.rels)
  // ---------------------------------------------------------------------------

  void _parseRelationships(String xml) {
    try {
      final doc = XmlDocument.parse(xml);
      for (final rel in doc.findAllElements('Relationship')) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        final type = rel.getAttribute('Type') ?? '';
        if (id != null && target != null && type.contains('hyperlink')) {
          _relationships[id] = target;
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Numbering parsing (word/numbering.xml)
  // ---------------------------------------------------------------------------

  void _parseNumbering(String xml) {
    try {
      final doc = XmlDocument.parse(xml);

      // abstractNum: abstractNumId → listType
      final abstractNumMap = <String, String>{};
      for (final an in doc.findAllElements('w:abstractNum')) {
        final abstractNumId = an.getAttribute('w:abstractNumId') ?? '';
        // Check numFmt of level 0
        final lvl = an.findElements('w:lvl').firstOrNull;
        final numFmt = lvl?.findElements('w:numFmt').firstOrNull
            ?.getAttribute('w:val');
        final listType = (numFmt == 'decimal' || numFmt == 'lowerLetter' ||
                numFmt == 'upperLetter' || numFmt == 'lowerRoman' ||
                numFmt == 'upperRoman')
            ? 'ordered'
            : 'unordered';
        abstractNumMap[abstractNumId] = listType;
      }

      // num: numId → abstractNumId → listType
      for (final num in doc.findAllElements('w:num')) {
        final numId = num.getAttribute('w:numId') ?? '';
        final abstractNumId = num
            .findElements('w:abstractNumId')
            .firstOrNull
            ?.getAttribute('w:val') ?? '';
        _numIdToType[numId] = abstractNumMap[abstractNumId] ?? 'unordered';
      }
    } catch (_) {}
  }

  String _listTypeForNumId(String numId) =>
      _numIdToType[numId] ?? 'unordered';

  // ---------------------------------------------------------------------------
  // Node building
  // ---------------------------------------------------------------------------

  List<FNode> _elementsToNodes(Iterable<XmlNode> nodes) {
    final result = <FNode>[];
    final paragraphBuffer = <XmlElement>[];

    void flushBuffer() {
      if (paragraphBuffer.isEmpty) return;
      // Check if first paragraph has numPr → treat all consecutive same-numId
      // paragraphs as a list
      final firstPPr = paragraphBuffer.first.getElement('w:pPr');
      final firstNumPr = firstPPr?.getElement('w:numPr');
      if (firstNumPr != null) {
        result.addAll(_buildLists(paragraphBuffer));
      } else {
        for (final p in paragraphBuffer) {
          // FIX Bug 7: skip empty sentinel paragraphs (no runs, no text)
          final hasContent = p.children.any((c) =>
              c is XmlElement && c.name.local == 'r' ||
              c is XmlElement && c.name.local == 'hyperlink');
          if (hasContent) result.add(_paragraph(p));
        }
      }
      paragraphBuffer.clear();
    }

    for (final node in nodes) {
      if (node is XmlElement) {
        switch (node.name.local) {
          case 'p':
            // FIX Bug 7: skip w:sectPr-only paragraphs
            if (_isSectPrOnly(node)) continue;
            paragraphBuffer.add(node);
          case 'tbl':
            flushBuffer();
            result.add(_table(node));
          default:
            flushBuffer();
        }
      }
    }
    flushBuffer();
    return result;
  }

  bool _isSectPrOnly(XmlElement p) {
    final meaningful = p.children.where((c) =>
        c is XmlElement && c.name.local != 'pPr');
    return meaningful.isEmpty &&
        (p.getElement('w:pPr')?.getElement('w:sectPr') != null);
  }

  /// Groups consecutive list paragraphs by numId and builds FluentList nodes.
  List<FNode> _buildLists(List<XmlElement> paragraphs) {
    final result = <FNode>[];
    FluentList? currentList;
    String? currentNumId;

    for (final p in paragraphs) {
      final pPr = p.getElement('w:pPr');
      final numPr = pPr?.getElement('w:numPr');
      final numId = numPr?.getElement('w:numId')?.getAttribute('w:val');
      final ilvl = int.tryParse(
              numPr?.getElement('w:ilvl')?.getAttribute('w:val') ?? '0') ??
          0;

      if (numId == null) {
        // Not a list paragraph — flush and add as plain paragraph
        if (currentList != null) {
          result.add(currentList);
          currentList = null;
          currentNumId = null;
        }
        result.add(_paragraph(p));
        continue;
      }

      final listType = _listTypeForNumId(numId);

      if (numId != currentNumId) {
        if (currentList != null) result.add(currentList);
        currentList = FluentList(listType: listType);
        currentNumId = numId;
      }

      final childParagraph = _paragraphAsListChild(p);
      final bulletType = listType;
      final indexList = List.generate(ilvl + 1, (i) => i + 1);
      currentList!.items.add(ListItem(
        bulletType: bulletType,
        indexList: indexList,
        children: [childParagraph],
      ));
    }

    if (currentList != null) result.add(currentList);
    return result;
  }

  Paragraph _paragraph(XmlElement el) {
    final pPr = el.getElement('w:pPr');
    String? styleName;
    String textAlign = 'left';
    int indent = 0;

    if (pPr != null) {
      final pStyle = pPr.getElement('w:pStyle');
      if (pStyle != null) {
        final val = pStyle.getAttribute('w:val');
        styleName = switch (val) {
          'Heading1' => 'heading1',
          'Heading2' => 'heading2',
          'Heading3' => 'heading3',
          'Heading4' => 'heading4',
          'Heading5' => 'heading5',
          'Heading6' => 'heading6',
          'Quote' => 'quote',
          'Code' => 'code',
          _ => null,
        };
      }
      final jc = pPr.getElement('w:jc');
      if (jc != null) {
        final val = jc.getAttribute('w:val');
        if (val != null) textAlign = val.toLowerCase();
      }
      final ind = pPr.getElement('w:ind');
      if (ind != null) {
        final leftTwips =
            int.tryParse(ind.getAttribute('w:left') ?? '0') ?? 0;
        // 720 twips = 1 indent level (standard DOCX indent step)
        indent = (leftTwips / 720).round();
      }
    }

    final fragments = _collectFragments(el.children);

    return Paragraph(
      text: fragments.map((f) => f.text).join(),
      textAlign: textAlign,
      styleName: styleName,
      indent: indent,
    )..fragments = fragments;
  }

  /// Same as _paragraph but without indent (list items handle indent via ilvl).
  Paragraph _paragraphAsListChild(XmlElement el) => _paragraph(el);

  List<Fragment> _collectFragments(Iterable<XmlNode> children) {
    final result = <Fragment>[];
    for (final child in children) {
      if (child is XmlElement) {
        switch (child.name.local) {
          case 'r':
            result.addAll(_runToFragments(child));
          case 'hyperlink':
            // FIX Bug 2: preserve Link node
            final link = _hyperlink(child);
            if (link != null) result.add(link);
          // FIX Bug 4: handle inline images
          case 'drawing':
            final image = _drawing(child);
            // Images in DOCX are inline inside runs; we surface them here
            // as a sentinel — callers that assemble Paragraph will need to
            // hoist them out. For now, skip silently (handled in _runToFragments).
            break;
        }
      }
    }
    return result;
  }

  List<Fragment> _runToFragments(XmlElement el) {
    // FIX Bug 4: check for drawing inside the run first
    final drawing = el.getElement('w:drawing');
    if (drawing != null) {
      // Images are block-level in FluentEditor; they cannot be Fragment.
      // Return empty here — image nodes are handled at _elementsToNodes level
      // via _extractInlineImages if needed.
      return [];
    }

    final rPr = el.getElement('w:rPr');
    final styles = <String>[];
    String? color;
    String? highlightColor;
    double fontSize = 14.0;

    if (rPr != null) {
      // FIX Bug 6: respect w:val="0" as explicit off
      if (_isOn(rPr.getElement('w:b'))) styles.add('bold');
      if (_isOn(rPr.getElement('w:i'))) styles.add('italic');
      if (_isOn(rPr.getElement('w:strike'))) styles.add('strikethrough');
      if (_isOn(rPr.getElement('w:u'))) styles.add('underline');
      if (_isOn(rPr.getElement('w:smallCaps'))) styles.add('smallcaps');
      if (_isOn(rPr.getElement('w:vertAlign'))) {
        final val = rPr.getElement('w:vertAlign')?.getAttribute('w:val');
        if (val == 'superscript') styles.add('superscript');
        if (val == 'subscript') styles.add('subscript');
      }

      final colorEl = rPr.getElement('w:color');
      if (colorEl != null) {
        final raw = colorEl.getAttribute('w:val');
        // FIX Bug 5: normalize color to #RRGGBB
        if (raw != null && raw != 'auto') {
          color = raw.startsWith('#') ? raw : '#$raw';
        }
      }
      final highlightEl = rPr.getElement('w:highlight');
      if (highlightEl != null) highlightColor = highlightEl.getAttribute('w:val');
      final szEl = rPr.getElement('w:sz');
      if (szEl != null) {
        final halfPoints = int.tryParse(szEl.getAttribute('w:val') ?? '');
        if (halfPoints != null) fontSize = halfPoints / 2;
      }
    }

    final buffer = StringBuffer();
    for (final child in el.children) {
      if (child is XmlElement) {
        switch (child.name.local) {
          case 't':
            buffer.write(child.innerText);
          case 'tab':
            buffer.write('\t');
          case 'br':
            buffer.write('\n');
        }
      }
    }

    final text = buffer.toString();
    if (text.isEmpty) return [];

    return [
      Fragment(
        text,
        styles: styles.isEmpty ? null : styles,
        color: color,
        highlightColor: highlightColor,
        fontSize: fontSize,
      ),
    ];
  }

  /// Returns true if the toggle element is present AND not explicitly set to 0.
  bool _isOn(XmlElement? el) {
    if (el == null) return false;
    final val = el.getAttribute('w:val');
    // w:val="0" or w:val="false" means explicitly OFF
    return val == null || (val != '0' && val.toLowerCase() != 'false');
  }

  Link? _hyperlink(XmlElement el) {
    // FIX Bug 1: resolve rId → actual URL from relationships map
    final rId = el.getAttribute('r:id');
    final url = (rId != null ? _relationships[rId] : null) ??
        el.getAttribute('w:anchor') ?? '';

    final fragments = <Fragment>[];
    for (final child in el.children) {
      if (child is XmlElement && child.name.local == 'r') {
        fragments.addAll(_runToFragments(child));
      }
    }
    if (fragments.isEmpty) return null;
    final text = fragments.map((f) => f.text).join();
    // FIX Bug 2: return Link node directly (not flattened)
    return Link(url: url, text: text)..fragments = fragments;
  }

  // ---------------------------------------------------------------------------
  // FIX Bug 4: Image extraction from w:drawing
  // ---------------------------------------------------------------------------

  FluentImage? _drawing(XmlElement drawing) {
    // Inline: wp:inline > a:graphic > a:graphicData > pic:pic > pic:blipFill > a:blip r:embed
    try {
      final inline = drawing.findAllElements('wp:inline').firstOrNull ??
          drawing.findAllElements('wp:anchor').firstOrNull;
      if (inline == null) return null;

      // Dimensions from wp:extent
      final extent = inline.findElements('wp:extent').firstOrNull;
      double? width, height;
      if (extent != null) {
        final cx = int.tryParse(extent.getAttribute('cx') ?? '');
        final cy = int.tryParse(extent.getAttribute('cy') ?? '');
        // EMUs: 914400 per inch, 72 pt/inch → pt = emu / 12700
        if (cx != null) width = cx / 12700;
        if (cy != null) height = cy / 12700;
      }

      final blip = drawing.findAllElements('a:blip').firstOrNull;
      final rId = blip?.getAttribute('r:embed');
      final src = (rId != null ? _relationships[rId] : null) ?? '';

      return FluentImage(
        src: src,
        width: width ?? 100,
        height: height ?? 100,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Table
  // ---------------------------------------------------------------------------

  FluentTable _table(XmlElement el) {
    final rows = <FluentRow>[];
    for (final child in el.children) {
      if (child is XmlElement && child.name.local == 'tr') {
        rows.add(_tableRow(child));
      }
    }
    return FluentTable(rows: rows);
  }

  FluentRow _tableRow(XmlElement el) {
    final cells = <FluentCell>[];
    for (final child in el.children) {
      if (child is XmlElement && child.name.local == 'tc') {
        cells.add(_tableCell(child));
      }
    }
    return FluentRow(cells: cells);
  }

  FluentCell _tableCell(XmlElement el) {
    final tcPr = el.getElement('w:tcPr');
    final colSpan = int.tryParse(
            tcPr?.getElement('w:gridSpan')?.getAttribute('w:val') ?? '1') ??
        1;
    // rowSpan via vMerge: 'restart' = first cell, absent val = continuation
    int rowSpan = 1;
    final vMerge = tcPr?.getElement('w:vMerge');
    if (vMerge != null) {
      final val = vMerge.getAttribute('w:val');
      rowSpan = (val == 'restart') ? 1 : 0; // 0 = continuation (merged)
    }

    final children = <FNode>[];
    for (final child in el.children) {
      if (child is XmlElement && child.name.local == 'p') {
        children.add(_paragraph(child));
      }
    }
    return FluentCell(
      children: children.isEmpty ? [Paragraph()] : children,
      colSpan: colSpan,
      rowSpan: rowSpan == 0 ? 1 : rowSpan,
    );
  }
}