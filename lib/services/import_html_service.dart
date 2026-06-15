import 'package:fluent_editor/factories.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' show parse;

/// Service for importing HTML into FluentEditor nodes.
class ImportHtmlService {
  Root importFromHtml(String html) {
    final document = parse(html);
    final body = document.body;
    if (body == null) return Root(nodes: [Paragraph(text: '')]);
    final nodes = _elementsToNodes(body.children);
    // Filter out empty paragraphs (whitespace-only) that create unwanted spacing
    final filtered = nodes.where((n) => !_isEmptyParagraph(n)).toList();
    return Root(nodes: filtered.isEmpty ? [Paragraph(text: '')] : filtered);
  }

  bool _isEmptyParagraph(FNode node) {
    // Only check exact Paragraph type, not subclasses (FluentList, Link, etc.)
    if (node.runtimeType != Paragraph) return false;
    final p = node as Paragraph;
    if (p.styleName != null) return false; // Styled paragraphs (headings, etc.) are never empty
    final text = p.fragments
        .whereType<Fragment>()
        .map((f) => f.text)
        .join()
        .trim();
    return text.isEmpty;
  }

  /// Collapses whitespace according to HTML rules:
  /// Replace sequences of \n, \r, \t and multiple spaces with a single space.
  /// If [trim] is true (default), also trims leading/trailing whitespace.
  String _collapseWhitespace(String text, {bool trim = true}) {
    if (text.isEmpty) return text;
    // Replace \n, \r, \t with space, then collapse multiple spaces
    final normalized = text.replaceAll(RegExp(r'[\n\r\t]+'), ' ');
    // Collapse multiple spaces to single space
    final collapsed = normalized.replaceAll(RegExp(r' +'), ' ');
    if (trim) {
      return collapsed.trim();
    }
    return collapsed;
  }

  List<FNode> _elementsToNodes(List<html_dom.Element> elements) {
    final result = <FNode>[];
    for (final el in elements) {
      final node = _elementToNode(el);
      if (node != null) result.add(node);
    }
    return result;
  }

  FNode? _elementToNode(html_dom.Element el) {
    switch (el.localName) {
      case 'p':
        return _paragraph(el);
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return _heading(el);
      case 'blockquote':
        return _blockquote(el);
      case 'pre':
        return _pre(el);
      case 'ul':
      case 'ol':
        return _list(el);
      case 'table':
        return _table(el);
      case 'img':
        return _image(el);
      case 'hr':
        return HorizontalRule();
      case 'div':
        final nodes = _elementsToNodes(el.children);
        if (nodes.isEmpty) return null;
        if (nodes.length == 1) return nodes.first;
        return Paragraph(text: '')..fragments = _inlineElementsToFragments(el.nodes);
      case 'a':
        return _link(el);
      case 'strong':
      case 'b':
      case 'em':
      case 'i':
      case 's':
      case 'del':
      case 'u':
      case 'span':
      case 'sup':
      case 'sub':
        return Paragraph(text: '')..fragments = _inlineElementsToFragments([el]);
      default:
        final nodes = _elementsToNodes(el.children);
        if (nodes.isEmpty) return null;
        return nodes.length == 1 ? nodes.first : Paragraph(text: '');
    }
  }

  Paragraph _paragraph(html_dom.Element el) {
    final align = _parseTextAlign(el);
    final indent = _parseIndent(el);
    return Paragraph(
      text: '',
      textAlign: align,
      indent: indent,
    )..fragments = _inlineElementsToFragments(el.nodes);
  }

  int _parseIndent(html_dom.Element el) {
    // Check data-indent attribute first
    final dataIndent = el.attributes['data-indent'];
    if (dataIndent != null) {
      final indent = int.tryParse(dataIndent);
      if (indent != null && indent > 0) return indent;
    }
    // Parse CSS padding-left or margin-left from style attribute
    final styleAttr = el.attributes['style'] ?? '';
    final paddingMatch = RegExp(r'padding-left:\s*(\d+)px').firstMatch(styleAttr);
    if (paddingMatch != null) {
      final px = int.tryParse(paddingMatch.group(1)!);
      if (px != null) return (px / 24).round(); // 24px per indent level
    }
    final marginMatch = RegExp(r'margin-left:\s*(\d+)px').firstMatch(styleAttr);
    if (marginMatch != null) {
      final px = int.tryParse(marginMatch.group(1)!);
      if (px != null) return (px / 24).round();
    }
    // Check for indent-N class
    final classAttr = el.attributes['class'] ?? '';
    final classMatch = RegExp(r'indent-(\d+)').firstMatch(classAttr);
    if (classMatch != null) {
      final indent = int.tryParse(classMatch.group(1)!);
      if (indent != null) return indent;
    }
    return 0;
  }

  String _parseTextAlign(html_dom.Element el) {
    // Check deprecated align attribute first
    final alignAttr = el.attributes['align'];
    if (alignAttr != null) {
      return switch (alignAttr.toLowerCase()) {
        'center' => 'center',
        'right' => 'right',
        'justify' => 'justify',
        _ => 'left',
      };
    }
    // Parse CSS text-align from style attribute
    final styleAttr = el.attributes['style'] ?? '';
    final textAlignMatch = RegExp(r'text-align:\s*([^;]+)').firstMatch(styleAttr);
    if (textAlignMatch != null) {
      return switch (textAlignMatch.group(1)!.trim().toLowerCase()) {
        'center' => 'center',
        'right' => 'right',
        'justify' => 'justify',
        _ => 'left',
      };
    }
    return 'left';
  }

  /// Parse font-size from style attribute (e.g., "font-size:24px" -> 24.0)
  double? _parseFontSize(String styleAttr) {
    final match = RegExp(r'font-size:\s*(\d+(?:\.\d+)?)(?:px|pt)?').firstMatch(styleAttr);
    if (match != null) {
      final size = double.tryParse(match.group(1)!);
      return size;
    }
    return null;
  }

  /// Parse color from style attribute (e.g., "color:#666666" -> "#666666")
  String? _parseColor(String styleAttr) {
    final match = RegExp(r'color:\s*([#\w]+)').firstMatch(styleAttr);
    return match?.group(1);
  }

  Paragraph _heading(html_dom.Element el) {
    final level = int.tryParse(el.localName?.substring(1) ?? '') ?? 1;
    final align = _parseTextAlign(el);
    return Paragraph(
      text: '',
      styleName: 'heading$level',
      textAlign: align,
    )..fragments = _inlineElementsToFragments(el.nodes);
  }

  Paragraph _blockquote(html_dom.Element el) {
    return Paragraph(
      text: '',
      styleName: 'quote',
    )..fragments = _inlineElementsToFragments(el.nodes);
  }

  Paragraph _pre(html_dom.Element el) {
    return Paragraph(
      text: '',
      styleName: 'code',
    )..fragments = _inlineElementsToFragments(el.nodes);
  }

  FluentList _list(html_dom.Element el) {
    final listType = el.localName == 'ol' ? 'ordered' : 'unordered';
    final list = FluentList(listType: listType);
    final liElements = el.children.where((c) => c.localName == 'li').toList();
    final items = <ListItem>[];
    for (var i = 0; i < liElements.length; i++) {
      final index = listType == 'ordered' ? i + 1 : 1;
      items.add(_listItem(liElements[i], listType, index));
    }
    list.items.addAll(items);
    return list;
  }

  ListItem _listItem(html_dom.Element el, String listType, int index) {
    final children = <FNode>[];
    for (final node in el.nodes) {
      if (node is html_dom.Element) {
        switch (node.localName) {
          case 'ul':
          case 'ol':
            children.add(_list(node));
          case 'p':
            children.add(_paragraph(node));
          case 'div':
            children.addAll(_elementsToNodes(node.children));
          default:
            children.add(Paragraph(text: '')..fragments = _inlineElementsToFragments([node]));
        }
      } else if (node is html_dom.Text) {
        final text = _collapseWhitespace(node.text);
        if (text.isNotEmpty) {
          children.add(Paragraph(text: text)..fragments = [Fragment(text)]);
        }
      }
    }

    // Remove trailing empty paragraphs (phantom whitespace from HTML parser)
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

  FluentTable _table(html_dom.Element el) {
    final rows = <FluentRow>[];
    for (final child in el.children) {
      if (child.localName == 'tr') {
        rows.add(_tableRow(child));
      } else if (child.localName == 'tbody' || child.localName == 'thead') {
        rows.addAll(child.children.where((c) => c.localName == 'tr').map(_tableRow));
      }
    }
    return FluentTable(rows: rows);
  }

  FluentRow _tableRow(html_dom.Element el) {
    final cells = el.children
        .where((c) => c.localName == 'td' || c.localName == 'th')
        .map(_tableCell)
        .toList();
    return FluentRow(cells: cells);
  }

  FluentCell _tableCell(html_dom.Element el) {
    final children = <FNode>[];
    for (final node in el.nodes) {
      if (node is html_dom.Element) {
        final n = _elementToNode(node);
        if (n != null) children.add(n);
      } else if (node is html_dom.Text) {
        final text = _collapseWhitespace(node.text);
        if (text.isNotEmpty) {
          children.add(Paragraph(text: text)..fragments = [Fragment(text)]);
        }
      }
    }
    final cell = FluentCell(children: children.isEmpty ? [Paragraph()] : children);
    // Parse colspan and rowspan attributes
    final colspanAttr = el.attributes['colspan'];
    if (colspanAttr != null) {
      final colspan = int.tryParse(colspanAttr);
      if (colspan != null && colspan > 1) {
        cell.colSpan = colspan;
      }
    }
    final rowspanAttr = el.attributes['rowspan'];
    if (rowspanAttr != null) {
      final rowspan = int.tryParse(rowspanAttr);
      if (rowspan != null && rowspan > 1) {
        cell.rowSpan = rowspan;
      }
    }
    return cell;
  }

  FluentImage _image(html_dom.Element el) {
    final img = FluentImage(el.attributes['src'] ?? '');
    // Parse width and height attributes
    final widthAttr = el.attributes['width'];
    if (widthAttr != null) {
      final width = double.tryParse(widthAttr);
      if (width != null) img.width = width;
    }
    final heightAttr = el.attributes['height'];
    if (heightAttr != null) {
      final height = double.tryParse(heightAttr);
      if (height != null) img.height = height;
    }
    // Set required fields for JSON serialization
    img.text = '\u200b'; // Zero-width space
    img.textAlign = 'left';
    img.styles = null;
    img.fontFamily = 'DejaVu Sans';
    img.fontSize = 14.0;
    img.color = null;
    img.highlightColor = null;
    return img;
  }

  Link _link(html_dom.Element el) {
    return Link(url: el.attributes['href'] ?? '')
      ..fragments = _inlineElementsToFragments(el.nodes);
  }

  List<FNode> _inlineElementsToFragments(List<html_dom.Node> nodes) {
    final result = <FNode>[];
    final buffer = StringBuffer();

    void flushBuffer({bool trim = true}) {
      if (buffer.isNotEmpty) {
        final text = _collapseWhitespace(buffer.toString(), trim: trim);
        if (text.isNotEmpty) result.add(Fragment(text));
        buffer.clear();
      }
    }

    for (final node in nodes) {
      if (node is html_dom.Text) {
        buffer.write(node.text);
      } else if (node is html_dom.Element) {
        // Don't trim when buffer is interrupted by an element (preserve trailing space)
        flushBuffer(trim: false);
        if (node.localName == 'img') {
          result.add(_image(node));
        } else if (node.localName == 'a') {
          final href = node.attributes['href'] ?? '';
          final linkText = _collapseWhitespace(node.text);
          if (linkText.isNotEmpty || href.isNotEmpty) {
            final link = Link(url: href)
              ..text = linkText
              ..textAlign = 'left'
              ..styles = null
              ..fontFamily = 'DejaVu Sans'
              ..fontSize = 14.0
              ..color = null
              ..highlightColor = null;
            link.fragments = [Fragment(linkText)];
            result.add(link);
          }
        } else {
          result.addAll(_inlineElementToFragments(node));
        }
      }
    }
    // Trim at the end of the paragraph
    flushBuffer(trim: true);
    return result;
  }

  List<FNode> _inlineElementToFragments(html_dom.Element el) {
    final styles = <String>[];
    switch (el.localName) {
      case 'strong':
      case 'b':
        styles.add('bold');
      case 'em':
      case 'i':
        styles.add('italic');
      case 's':
      case 'del':
        styles.add('strikethrough');
      case 'u':
        styles.add('underline');
      case 'sup':
        styles.add('superscript');
      case 'sub':
        styles.add('subscript');
      case 'span':
        final styleAttr = el.attributes['style'] ?? '';
        if (styleAttr.contains('small-caps')) styles.add('smallcaps');
      case 'a':
        // Links are handled specially below - don't add to styles
        break;
    }

    // Parse font-size and color from element style
    final styleAttr = el.attributes['style'] ?? '';
    final fontSize = _parseFontSize(styleAttr);
    final color = _parseColor(styleAttr);

    final result = <FNode>[];
    final buffer = StringBuffer();

    for (final child in el.nodes) {
      if (child is html_dom.Text) {
        // Don't collapse yet - preserve spaces that may be adjacent to links
        buffer.write(child.text);
      } else if (child is html_dom.Element) {
        if (buffer.isNotEmpty) {
          final text = _collapseWhitespace(buffer.toString());
          if (text.isNotEmpty) {
            final fragment = Fragment(text, styles: styles.isEmpty ? null : List.from(styles));
            if (fontSize != null) fragment.fontSize = fontSize;
            if (color != null) fragment.color = color;
            result.add(fragment);
          }
          buffer.clear();
        }
        if (child.localName == 'img') {
          result.add(_image(child));
        } else if (child.localName == 'a') {
          final href = child.attributes['href'] ?? '';
          final linkText = _collapseWhitespace(child.text);
          if (linkText.isNotEmpty || href.isNotEmpty) {
            final link = Link(url: href)
              ..text = linkText
              ..textAlign = 'left'
              ..styles = null
              ..fontFamily = 'DejaVu Sans'
              ..fontSize = 14.0
              ..color = null
              ..highlightColor = null;
            link.fragments = [Fragment(linkText)];
            result.add(link);
          }
        } else {
          final childFragments = _inlineElementToFragments(child);
          for (final f in childFragments) {
            if (f is Fragment) {
              final combined = <String>[...styles, ...(f.styles ?? [])];
              result.add(Fragment(f.text, styles: combined.isEmpty ? null : combined));
            } else {
              result.add(f);
            }
          }
        }
      }
    }

    if (buffer.isNotEmpty) {
      final text = _collapseWhitespace(buffer.toString());
      if (text.isNotEmpty) {
        final fragment = Fragment(text, styles: styles.isEmpty ? null : List.from(styles));
        if (fontSize != null) fragment.fontSize = fontSize;
        if (color != null) fragment.color = color;
        result.add(fragment);
      }
    }

    return result;
  }
}
