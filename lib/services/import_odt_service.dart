import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fluent_editor/factories.dart';
import 'package:xml/xml.dart';

/// Service for importing ODT into FluentEditor nodes.
class ImportOdtService {
  // Maps ODT style-name → resolved text properties (bold, italic, etc.)
  final Map<String, Map<String, String>> _styleProps = {};

  // Maps list style-name → listType ('ordered' | 'unordered')
  // Populated by parsing <text:list-style> elements in automatic-styles.
  final Map<String, String> _listStyleType = {};

  // Archive reference kept for image extraction
  Archive? _archive;

  Root importFromOdt(List<int> bytes) {
    _archive = ZipDecoder().decodeBytes(bytes);

    // --- Parse styles.xml first to build the style map ---
    final stylesFile = _archive!.files
        .where((f) => f.name == 'styles.xml')
        .firstOrNull;
    if (stylesFile != null) {
      _parseStylesXml(utf8.decode(stylesFile.content as Uint8List));
    }

    // --- Also parse automatic styles from content.xml ---
    final contentXml = _archive!.files
        .where((f) => f.name == 'content.xml')
        .firstOrNull;
    if (contentXml == null) return Root(nodes: [Paragraph(text: '')]);

    final xmlString = utf8.decode(contentXml.content as Uint8List);
    final document = XmlDocument.parse(xmlString);

    // Parse automatic-styles block inside content.xml
    final autoStyles =
        document.findAllElements('office:automatic-styles').firstOrNull;
    if (autoStyles != null) _parseStyleElements(autoStyles.children);

    final body = document.findAllElements('office:body').firstOrNull;
    if (body == null) return Root(nodes: [Paragraph(text: '')]);

    final textEl = body.findElements('office:text').firstOrNull;
    if (textEl == null) return Root(nodes: [Paragraph(text: '')]);

    final nodes = _elementsToNodes(textEl.children);
    return Root(nodes: nodes.isEmpty ? [Paragraph(text: '')] : nodes);
  }

  // ---------------------------------------------------------------------------
  // Style parsing
  // ---------------------------------------------------------------------------

  void _parseStylesXml(String xml) {
    try {
      final doc = XmlDocument.parse(xml);
      for (final styles in doc.findAllElements('office:styles')) {
        _parseStyleElements(styles.children);
      }
      for (final styles in doc.findAllElements('office:automatic-styles')) {
        _parseStyleElements(styles.children);
      }
    } catch (_) {}
  }

  void _parseStyleElements(Iterable<XmlNode> nodes) {
    for (final node in nodes) {
      if (node is! XmlElement) continue;

      // --- text:list-style: resolve ordered vs unordered from level-1 format ---
      // FIX: list type detection from actual XML structure, not style name string
      if (node.name.local == 'list-style') {
        final name = node.getAttribute('style:name');
        if (name != null) {
          // Check the first level child to determine type
          final firstLevel = node.children
              .whereType<XmlElement>()
              .firstOrNull;
          if (firstLevel != null) {
            // list-level-style-number → ordered
            // list-level-style-bullet / list-level-style-image → unordered
            _listStyleType[name] =
                firstLevel.name.local == 'list-level-style-number'
                    ? 'ordered'
                    : 'unordered';
          }
        }
        continue;
      }

      // --- style:style: text properties ---
      if (node.name.local == 'style') {
        final name = node.getAttribute('style:name');
        if (name == null) continue;
        final props = <String, String>{};

        // Inherit from parent style
        final parentName = node.getAttribute('style:parent-style-name');
        if (parentName != null && _styleProps.containsKey(parentName)) {
          props.addAll(_styleProps[parentName]!);
        }

        // Read paragraph-properties for indent/alignment
        for (final child in node.children) {
          if (child is XmlElement && child.name.local == 'paragraph-properties') {
            final marginLeft = child.getAttribute('fo:margin-left');
            if (marginLeft != null) props['marginLeft'] = marginLeft;
            final align = child.getAttribute('fo:text-align');
            if (align != null) props['textAlign'] = align;
          }
        }

        // Read text-properties
        for (final child in node.children) {
          if (child is XmlElement && child.name.local == 'text-properties') {
            final fw = child.getAttribute('fo:font-weight');
            if (fw == 'bold') props['bold'] = 'true';
            final fs = child.getAttribute('fo:font-style');
            if (fs == 'italic') props['italic'] = 'true';
            final td = child.getAttribute('style:text-underline-style');
            if (td != null && td != 'none') props['underline'] = 'true';
            final lt = child.getAttribute('style:text-line-through-style');
            if (lt != null && lt != 'none') props['strikethrough'] = 'true';
            final va = child.getAttribute('style:text-position');
            if (va != null) {
              if (va.startsWith('super') || va.startsWith('33%')) {
                props['superscript'] = 'true';
              } else if (va.startsWith('sub') || va.startsWith('-33%')) {
                props['subscript'] = 'true';
              }
            }
            // fo:font-variant: small-caps
            final fv = child.getAttribute('fo:font-variant');
            if (fv == 'small-caps') props['smallcaps'] = 'true';
            final color = child.getAttribute('fo:color');
            if (color != null) props['color'] = color;
            final fontSize = child.getAttribute('fo:font-size');
            if (fontSize != null) props['fontSize'] = fontSize;
            final fontFamily = child.getAttribute('fo:font-family') ??
                child.getAttribute('style:font-name');
            if (fontFamily != null) props['fontFamily'] = fontFamily;
          }
        }
        _styleProps[name] = props;
      }
    }
  }

  List<String> _stylesFromName(String? styleName) {
    if (styleName == null) return [];
    final props = _styleProps[styleName];
    if (props == null) return [];
    final styles = <String>[];
    if (props['bold'] == 'true') styles.add('bold');
    if (props['italic'] == 'true') styles.add('italic');
    if (props['underline'] == 'true') styles.add('underline');
    if (props['strikethrough'] == 'true') styles.add('strikethrough');
    if (props['superscript'] == 'true') styles.add('superscript');
    if (props['subscript'] == 'true') styles.add('subscript');
    if (props['smallcaps'] == 'true') styles.add('smallcaps');
    return styles;
  }

  double? _fontSizeFromName(String? styleName) {
    if (styleName == null) return null;
    final raw = _styleProps[styleName]?['fontSize'];
    if (raw == null) return null;
    final num = double.tryParse(raw.replaceAll(RegExp(r'[a-zA-Z]'), ''));
    return num;
  }

  String? _colorFromName(String? styleName) {
    if (styleName == null) return null;
    return _styleProps[styleName]?['color'];
  }

  /// Converts an ODT SVG/cm length string (e.g. "3.651cm") to points.
  double? _lengthToPt(String? value) {
    if (value == null) return null;
    if (value.endsWith('cm')) {
      final cm = double.tryParse(value.replaceAll('cm', '').trim());
      if (cm != null) return cm * 28.3465; // 1 cm = 28.3465 pt
    }
    if (value.endsWith('mm')) {
      final mm = double.tryParse(value.replaceAll('mm', '').trim());
      if (mm != null) return mm * 2.83465;
    }
    if (value.endsWith('in')) {
      final inch = double.tryParse(value.replaceAll('in', '').trim());
      if (inch != null) return inch * 72;
    }
    if (value.endsWith('pt')) {
      return double.tryParse(value.replaceAll('pt', '').trim());
    }
    return double.tryParse(value);
  }

  // ---------------------------------------------------------------------------
  // Node building
  // ---------------------------------------------------------------------------

  List<FNode> _elementsToNodes(Iterable<XmlNode> nodes) {
    final result = <FNode>[];
    for (final node in nodes) {
      if (node is XmlElement) {
        switch (node.name.local) {
          case 'p':
            // FIX: a <text:p> may contain a <draw:frame> with an image;
            // if so, emit a FluentImage node instead of a Paragraph.
            final imageNode = _extractImageFromParagraph(node);
            if (imageNode != null) {
              result.add(imageNode);
            } else {
              final para = _paragraph(node);
              // Skip empty sentinel paragraphs with no fragments
              if (para.fragments.isNotEmpty || para.text.isNotEmpty) {
                result.add(para);
              }
            }
          case 'h':
            result.add(_heading(node));
          case 'table':
            result.add(_table(node));
          case 'list':
            result.add(_list(node));
        }
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // FIX: Image extraction from <draw:frame><draw:image>
  // ---------------------------------------------------------------------------

  FluentImage? _extractImageFromParagraph(XmlElement p) {
    // A paragraph that contains only a draw:frame is an image paragraph.
    final frame = p.children
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'frame')
        .firstOrNull;
    if (frame == null) return null;

    final drawImage = frame.children
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'image')
        .firstOrNull;
    if (drawImage == null) return null;

    // href is the path inside the ODT zip (e.g. "Pictures/img0.png")
    final href = drawImage.getAttribute('xlink:href') ?? '';

    // Extract the image bytes from the archive and encode as data-URI
    String src = href;
    if (_archive != null && href.isNotEmpty) {
      final imageFile = _archive!.files
          .where((f) => f.name == href)
          .firstOrNull;
      if (imageFile != null) {
        final ext = href.split('.').last.toLowerCase();
        final mime = switch (ext) {
          'png' => 'image/png',
          'jpg' || 'jpeg' => 'image/jpeg',
          'gif' => 'image/gif',
          'webp' => 'image/webp',
          'svg' => 'image/svg+xml',
          _ => 'application/octet-stream',
        };
        final b64 = base64Encode(imageFile.content as Uint8List);
        src = 'data:$mime;base64,$b64';
      }
    }

    // Dimensions from svg:width / svg:height on the frame
    final widthRaw = frame.getAttribute('svg:width');
    final heightRaw = frame.getAttribute('svg:height');
    final width = _lengthToPt(widthRaw) ?? 100.0;
    final height = _lengthToPt(heightRaw) ?? 100.0;

    final img = FluentImage(src);
    img.width = width;
    img.height = height;
    return img;
  }

  Paragraph _paragraph(XmlElement el) {
    final styleName = el.getAttribute('text:style-name');
    String? mappedStyle;
    String textAlign = 'left';
    int indent = 0;

    if (styleName != null) {
      if (styleName.toLowerCase().contains('quote')) mappedStyle = 'quote';
      if (styleName.toLowerCase().contains('code')) mappedStyle = 'code';
      // Read alignment and indent from the paragraph style props
      final props = _styleProps[styleName];
      if (props != null) {
        final align = props['textAlign'];
        if (align == 'center') textAlign = 'center';
        if (align == 'end') textAlign = 'right';
        if (align == 'justify') textAlign = 'justify';
        final marginLeft = props['marginLeft'];
        if (marginLeft != null) {
          final pt = _lengthToPt(marginLeft) ?? 0;
          // 0.63cm ≈ 17.9pt per indent level (FluentEditor uses ~18pt steps)
          indent = (pt / 17.86).round();
        }
      }
    }

    final fragments = _collectFragments(el.children);

    return Paragraph(
      text: fragments.map((f) => f.text).join(),
      styleName: mappedStyle,
      textAlign: textAlign,
      indent: indent,
    )..fragments = fragments;
  }

  Paragraph _heading(XmlElement el) {
    final levelStr = el.getAttribute('text:outline-level');
    final level = int.tryParse(levelStr ?? '1') ?? 1;

    final fragments = _collectFragments(el.children);

    return Paragraph(
      text: fragments.map((f) => f.text).join(),
      styleName: 'heading$level',
    )..fragments = fragments;
  }

  /// Collects all Fragment/Link nodes from a mixed list of XmlNode children.
  List<Fragment> _collectFragments(Iterable<XmlNode> children) {
    final result = <Fragment>[];
    for (final child in children) {
      if (child is XmlText) {
        final text = child.value;
        if (text.isNotEmpty) result.add(Fragment(text));
      } else if (child is XmlElement) {
        switch (child.name.local) {
          case 'span':
            result.addAll(_spanToFragments(child));
          case 'a':
            final link = _link(child);
            if (link != null) result.add(link);
          case 's':
            final count =
                int.tryParse(child.getAttribute('text:c') ?? '1') ?? 1;
            result.add(Fragment(' ' * count));
          case 'tab':
            result.add(Fragment('\t'));
          case 'line-break':
            result.add(Fragment('\n'));
          // draw:frame inside inline context (rare) — skip here,
          // handled at paragraph level by _extractImageFromParagraph
        }
      }
    }
    return result;
  }

  List<Fragment> _spanToFragments(XmlElement el) {
    final styleName = el.getAttribute('text:style-name');

    final styles = _stylesFromName(styleName);
    final fontSize = _fontSizeFromName(styleName);
    final color = _colorFromName(styleName);

    final innerFragments = _collectFragments(el.children);
    if (innerFragments.isEmpty) return [];

    return innerFragments.map((f) {
      final mergedStyles = [
        ...styles,
        ...?f.styles?.where((s) => !styles.contains(s)),
      ];
      return Fragment(
        f.text,
        styles: mergedStyles.isEmpty ? null : mergedStyles,
        fontSize: f.fontSize ?? fontSize ?? 14.0,
        color: f.color ?? color,
        fontFamily: f.fontFamily,
        highlightColor: f.highlightColor,
      );
    }).toList();
  }

  Link? _link(XmlElement el) {
    final url = el.getAttribute('xlink:href') ?? '';
    final fragments = _collectFragments(el.children);
    if (fragments.isEmpty) return null;
    final text = fragments.map((f) => f.text).join();
    return Link(url: url, text: text)..fragments = fragments;
  }

  FluentList _list(XmlElement el) {
    // FIX: resolve listType from _listStyleType map built by _parseStyleElements,
    // not from a string-contains check on the style name.
    final styleAttr = el.getAttribute('text:style-name');
    final listType = _listStyleType[styleAttr] ?? 'unordered';

    final list = FluentList(listType: listType);

    var index = 1;
    for (final child in el.children) {
      if (child is XmlElement && child.name.local == 'list-item') {
        final item = _listItem(child, listType, index);
        list.items.add(item);
        if (listType == 'ordered') index++;
      }
    }
    return list;
  }

  ListItem _listItem(XmlElement el, String listType, int index) {
    final children = <FNode>[];
    for (final child in el.children) {
      if (child is XmlElement) {
        switch (child.name.local) {
          case 'p':
            children.add(_paragraph(child));
          case 'list':
            children.add(_list(child));
        }
      }
    }
    // Remove trailing empty paragraphs (whitespace artefacts from the ODT)
    while (children.isNotEmpty &&
        children.last is Paragraph &&
        (children.last as Paragraph).fragments.isEmpty) {
      children.removeLast();
    }

    final bulletType = listType == 'ordered' ? 'ordered' : 'unordered';
    return ListItem(
      bulletType: bulletType,
      indexList: [index],
      children: children.isEmpty ? [Paragraph()] : children,
    );
  }

  FluentTable _table(XmlElement el) {
    final rows = <FluentRow>[];
    for (final child in el.children) {
      if (child is XmlElement && child.name.local == 'table-row') {
        rows.add(_tableRow(child));
      }
    }
    return FluentTable(rows: rows);
  }

  FluentRow _tableRow(XmlElement el) {
    final cells = <FluentCell>[];
    for (final child in el.children) {
      if (child is XmlElement) {
        // Skip covered-table-cell (colspan/rowspan placeholders)
        if (child.name.local == 'table-cell') {
          cells.add(_tableCell(child));
        }
      }
    }
    return FluentRow(cells: cells);
  }

  FluentCell _tableCell(XmlElement el) {
    final colSpan =
        int.tryParse(el.getAttribute('table:number-columns-spanned') ?? '1') ??
            1;
    final rowSpan =
        int.tryParse(el.getAttribute('table:number-rows-spanned') ?? '1') ?? 1;

    final children = <FNode>[];
    for (final child in el.children) {
      if (child is XmlElement) {
        switch (child.name.local) {
          case 'p':
            final imageNode = _extractImageFromParagraph(child);
            if (imageNode != null) {
              children.add(imageNode);
            } else {
              children.add(_paragraph(child));
            }
          case 'list':
            children.add(_list(child));
        }
      }
    }
    final cell = FluentCell(
      children: children.isEmpty ? [Paragraph()] : children,
    );
    cell.colSpan = colSpan;
    cell.rowSpan = rowSpan;
    return cell;
  }
}