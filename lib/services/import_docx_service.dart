import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fluent_editor/factories.dart';
import 'package:xml/xml.dart';

/// Service for importing DOCX into FluentEditor nodes.
class ImportDocxService {
  Root importFromDocx(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
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

  List<FNode> _elementsToNodes(Iterable<XmlNode> nodes) {
    final result = <FNode>[];
    for (final node in nodes) {
      if (node is XmlElement) {
        switch (node.name.local) {
          case 'p':
            result.add(_paragraph(node));
          case 'tbl':
            result.add(_table(node));
        }
      }
    }
    return result;
  }

  Paragraph _paragraph(XmlElement el) {
    final pPr = el.getElement('w:pPr');
    String? styleName;
    String textAlign = 'left';

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
    }

    final fragments = <Fragment>[];
    for (final child in el.children) {
      if (child is XmlElement) {
        switch (child.name.local) {
          case 'r':
            fragments.addAll(_runToFragments(child));
          case 'hyperlink':
            final link = _hyperlink(child);
            if (link != null) fragments.addAll(link.fragments.whereType<Fragment>());
        }
      }
    }

    return Paragraph(
      text: '',
      textAlign: textAlign,
      styleName: styleName,
    )..fragments = fragments;
  }

  List<Fragment> _runToFragments(XmlElement el) {
    final rPr = el.getElement('w:rPr');
    final styles = <String>[];
    String? color;
    String? highlightColor;
    double fontSize = 14.0;

    if (rPr != null) {
      if (rPr.getElement('w:b') != null) styles.add('bold');
      if (rPr.getElement('w:i') != null) styles.add('italic');
      if (rPr.getElement('w:strike') != null) styles.add('strikethrough');
      if (rPr.getElement('w:u') != null) styles.add('underline');
      if (rPr.getElement('w:smallCaps') != null) styles.add('smallcaps');

      final colorEl = rPr.getElement('w:color');
      if (colorEl != null) color = colorEl.getAttribute('w:val');
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

  Link? _hyperlink(XmlElement el) {
    final url = el.getAttribute('r:id') ?? '';
    final fragments = <Fragment>[];
    for (final child in el.children) {
      if (child is XmlElement && child.name.local == 'r') {
        fragments.addAll(_runToFragments(child));
      }
    }
    if (fragments.isEmpty) return null;
    return Link(url: url)..fragments = fragments;
  }

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
    final children = <FNode>[];
    for (final child in el.children) {
      if (child is XmlElement && child.name.local == 'p') {
        children.add(_paragraph(child));
      }
    }
    return FluentCell(children: children.isEmpty ? [Paragraph()] : children);
  }
}
