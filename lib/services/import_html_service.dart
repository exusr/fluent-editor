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
    return Root(nodes: nodes.isEmpty ? [Paragraph(text: '')] : nodes);
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
    return Paragraph(
      text: '',
      textAlign: el.attributes['align'] ?? 'left',
    )..fragments = _inlineElementsToFragments(el.nodes);
  }

  Paragraph _heading(html_dom.Element el) {
    final level = int.tryParse(el.localName?.substring(1) ?? '') ?? 1;
    return Paragraph(
      text: '',
      styleName: 'heading$level',
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
    final listType = el.localName == 'ol' ? 'ordered' : 'bullet';
    final list = FluentList(listType: listType);
    final items = el.children
        .where((c) => c.localName == 'li')
        .map((li) => _listItem(li, listType))
        .toList();
    list.items.addAll(items);
    return list;
  }

  ListItem _listItem(html_dom.Element el, String listType) {
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
        final text = node.text.trim();
        if (text.isNotEmpty) {
          children.add(Paragraph(text: '')..fragments = [Fragment(text)]);
        }
      }
    }
    final bulletType = listType == 'ordered' ? 'ordered' : 'bullet';
    return ListItem(
      bulletType: bulletType,
      indexList: [1],
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
        final text = node.text.trim();
        if (text.isNotEmpty) {
          children.add(Paragraph(text: '')..fragments = [Fragment(text)]);
        }
      }
    }
    return FluentCell(children: children.isEmpty ? [Paragraph()] : children);
  }

  FluentImage _image(html_dom.Element el) {
    return FluentImage(el.attributes['src'] ?? '');
  }

  Link _link(html_dom.Element el) {
    return Link(url: el.attributes['href'] ?? '')
      ..fragments = _inlineElementsToFragments(el.nodes);
  }

  List<Fragment> _inlineElementsToFragments(List<html_dom.Node> nodes) {
    final result = <Fragment>[];
    for (final node in nodes) {
      if (node is html_dom.Text) {
        if (node.text.isNotEmpty) result.add(Fragment(node.text));
      } else if (node is html_dom.Element) {
        result.addAll(_inlineElementToFragments(node));
      }
    }
    return result;
  }

  List<Fragment> _inlineElementToFragments(html_dom.Element el) {
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
    }

    final result = <Fragment>[];
    final buffer = StringBuffer();

    for (final child in el.nodes) {
      if (child is html_dom.Text) {
        buffer.write(child.text);
      } else if (child is html_dom.Element) {
        if (buffer.isNotEmpty) {
          result.add(Fragment(buffer.toString(), styles: styles.isEmpty ? null : List.from(styles)));
          buffer.clear();
        }
        result.addAll(_inlineElementToFragments(child).map((f) {
          final combined = <String>[...styles, ...(f.styles ?? [])];
          return Fragment(f.text, styles: combined.isEmpty ? null : combined);
        }));
      }
    }

    if (buffer.isNotEmpty) {
      result.add(Fragment(buffer.toString(), styles: styles.isEmpty ? null : List.from(styles)));
    }

    return result;
  }
}
