import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fluent_editor/factories.dart';
import 'package:xml/xml.dart';

/// Service for importing ODT into FluentEditor nodes.
class ImportOdtService {
  Root importFromOdt(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final contentXml = archive.files
        .where((f) => f.name == 'content.xml')
        .firstOrNull;
    if (contentXml == null) return Root(nodes: [Paragraph(text: '')]);

    final xmlString = utf8.decode(contentXml.content as Uint8List);
    final document = XmlDocument.parse(xmlString);
    final body = document.findAllElements('office:body').firstOrNull;
    if (body == null) return Root(nodes: [Paragraph(text: '')]);

    final textEl = body.findElements('office:text').firstOrNull;
    if (textEl == null) return Root(nodes: [Paragraph(text: '')]);

    final nodes = _elementsToNodes(textEl.children);
    return Root(nodes: nodes.isEmpty ? [Paragraph(text: '')] : nodes);
  }

  List<FNode> _elementsToNodes(Iterable<XmlNode> nodes) {
    final result = <FNode>[];
    for (final node in nodes) {
      if (node is XmlElement) {
        switch (node.name.local) {
          case 'p':
            result.add(_paragraph(node));
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

  Paragraph _paragraph(XmlElement el) {
    final styleName = el.getAttribute('text:style-name');
    String? mappedStyle;
    if (styleName != null) {
      if (styleName.toLowerCase().contains('quote')) mappedStyle = 'quote';
      if (styleName.toLowerCase().contains('code')) mappedStyle = 'code';
    }

    final fragments = <Fragment>[];
    for (final child in el.children) {
      if (child is XmlElement) {
        switch (child.name.local) {
          case 'span':
            fragments.addAll(_spanToFragments(child));
          case 'a':
            final link = _link(child);
            if (link != null) fragments.addAll(link.fragments.whereType<Fragment>());
          case 's':
            fragments.add(Fragment(' '));
          case 'tab':
            fragments.add(Fragment('\t'));
          case 'line-break':
            fragments.add(Fragment('\n'));
        }
      }
    }

    return Paragraph(
      text: '',
      styleName: mappedStyle,
    )..fragments = fragments;
  }

  Paragraph _heading(XmlElement el) {
    final levelStr = el.getAttribute('text:outline-level');
    final level = int.tryParse(levelStr ?? '1') ?? 1;
    final fragments = <Fragment>[];
    for (final child in el.children) {
      if (child is XmlElement && child.name.local == 'span') {
        fragments.addAll(_spanToFragments(child));
      }
    }
    return Paragraph(
      text: '',
      styleName: 'heading$level',
    )..fragments = fragments;
  }

  List<Fragment> _spanToFragments(XmlElement el) {
    final styles = <String>[];

    final styleName = el.getAttribute('text:style-name');
    if (styleName != null) {
      if (styleName.toLowerCase().contains('bold')) styles.add('bold');
      if (styleName.toLowerCase().contains('italic')) styles.add('italic');
      if (styleName.toLowerCase().contains('strike')) styles.add('strikethrough');
      if (styleName.toLowerCase().contains('underline')) styles.add('underline');
    }

    final textNodes = el.children.whereType<XmlText>().map((t) => t.value).join();
    final text = textNodes.isEmpty ? el.innerText : textNodes;
    if (text.isEmpty) return [];

    return [Fragment(text, styles: styles.isEmpty ? null : styles)];
  }

  Link? _link(XmlElement el) {
    final url = el.getAttribute('xlink:href') ?? '';
    final fragments = <Fragment>[];
    for (final child in el.children) {
      if (child is XmlElement && child.name.local == 'span') {
        fragments.addAll(_spanToFragments(child));
      }
    }
    if (fragments.isEmpty) return null;
    return Link(url: url)..fragments = fragments;
  }

  FluentList _list(XmlElement el) {
    final listType = el.getAttribute('text:style-name')?.toLowerCase().contains('ordered') ?? false
        ? 'ordered'
        : 'bullet';
    final list = FluentList(listType: listType);

    for (final child in el.children) {
      if (child is XmlElement && child.name.local == 'list-item') {
        final item = _listItem(child, listType);
        list.items.add(item);
      }
    }
    return list;
  }

  ListItem _listItem(XmlElement el, String listType) {
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
    final bulletType = listType == 'ordered' ? 'ordered' : 'bullet';
    return ListItem(
      bulletType: bulletType,
      indexList: [1],
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
      if (child is XmlElement && child.name.local == 'table-cell') {
        cells.add(_tableCell(child));
      }
    }
    return FluentRow(cells: cells);
  }

  FluentCell _tableCell(XmlElement el) {
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
    return FluentCell(children: children.isEmpty ? [Paragraph()] : children);
  }
}
