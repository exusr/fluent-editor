import 'dart:convert';

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/plugins/plugin_api.dart';
import 'package:fluent_editor/services/import_service.dart';
import 'package:fluent_editor/services/export_service.dart';
import 'package:fluent_editor/widgets/nodes/fluent_cell_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_fragment_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_hr_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_image_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_link_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_list_item_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_list_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_paragraph_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_table_widget.dart';
import 'package:flutter/widgets.dart';

class FluentBuiltInPlugin extends FluentEditorPlugin {
  @override
  String get id => 'fluent_editor.built_in';

  @override
  String get version => '1.0.0';

  @override
  List<FluentFormatContribution> get formats => [
    FluentFormatContribution(
      id: 'fluent_editor.json',
      label: 'JSON',
      extensions: ['json'],
      kind: FluentPluginFormatKind.text,
      import: (payload, registry) {
        final json = jsonDecode(payload.text!) as Map<String, dynamic>;
        FNodeJsonConverter.activeRegistry = registry;
        try {
          return Root.fromJson(json);
        } finally {
          FNodeJsonConverter.activeRegistry = null;
        }
      },
      export: (document) =>
          FluentExportPayload.text(document.toJson()),
    ),
    FluentFormatContribution(
      id: 'fluent_editor.html',
      label: 'HTML',
      extensions: ['html', 'htm'],
      kind: FluentPluginFormatKind.text,
      import: (payload, _) =>
          ImportService().importFromHtml(payload.text!),
      export: (document) async {
        final html = await ExportService(document).exportToHtml();
        return FluentExportPayload.text(html);
      },
    ),
    FluentFormatContribution(
      id: 'fluent_editor.markdown',
      label: 'Markdown',
      extensions: ['md', 'markdown'],
      kind: FluentPluginFormatKind.text,
      import: (payload, _) =>
          ImportService().importFromMarkdown(payload.text!),
      export: (document) =>
          FluentExportPayload.text(ExportService(document).exportToMarkdown()),
    ),
    FluentFormatContribution(
      id: 'fluent_editor.pdf',
      label: 'PDF',
      extensions: ['pdf'],
      kind: FluentPluginFormatKind.binary,
      export: (document) async {
        final bytes = await ExportService(document).exportToPdf();
        return FluentExportPayload.binary(bytes);
      },
    ),
    FluentFormatContribution(
      id: 'fluent_editor.docx',
      label: 'DOCX',
      extensions: ['docx'],
      kind: FluentPluginFormatKind.binary,
      import: (payload, _) =>
          ImportService().importFromDocx(payload.bytes!),
      export: (document) async {
        final bytes = await ExportService(document).exportToDocx();
        return FluentExportPayload.binary(bytes);
      },
    ),
    FluentFormatContribution(
      id: 'fluent_editor.odt',
      label: 'ODT',
      extensions: ['odt'],
      kind: FluentPluginFormatKind.binary,
      import: (payload, _) =>
          ImportService().importFromOdt(payload.bytes!),
      export: (document) async {
        final bytes = await ExportService(document).exportToOdt();
        return FluentExportPayload.binary(bytes);
      },
    ),
  ];

  @override
  late final List<FluentNodeDefinition<FNode>> nodes = [
    FluentNodeDefinition<FNode>(
      type: 'root',
      nodeClass: Root,
      decode: _decodeRoot,
      create: (_) => Root(),
      buildWidget: (_, _, _, _) => const SizedBox.shrink(),
      children: (node) => (node as Root).nodes,
      mutableChildren: (node) => (node as Root).nodes,
    ),
    FluentNodeDefinition<FNode>(
      type: 'fragment',
      nodeClass: Fragment,
      decode: (json, _) => Fragment.fromJson(json),
      create: (options) => Fragment(options['text'] as String? ?? ''),
      buildWidget: (node, document, anchor, focus) => FluentFragmentWidget(
        key: document.getKeyForNode(node.id),
        node: node as Fragment,
        anchorOffset: anchor,
        focusOffset: focus,
      ),
      inline: true,
    ),
    FluentNodeDefinition<FNode>(
      type: 'paragraph',
      nodeClass: Paragraph,
      decode: _decodeParagraph,
      create: (options) => Paragraph(text: options['text'] as String? ?? ''),
      buildWidget: (node, document, _, _) => FluentParagraphWidget(
        key: document.getKeyForNode(node.id),
        node: node,
        document: document,
      ),
      children: (node) => (node as Paragraph).fragments,
      mutableChildren: (node) => (node as Paragraph).fragments,
    ),
    FluentNodeDefinition<FNode>(
      type: 'link',
      nodeClass: Link,
      decode: _decodeLink,
      create: (options) => Link(
        url: options['url'] as String? ?? '',
        text: options['text'] as String?,
      ),
      buildWidget: (node, document, _, _) => FluentLinkWidget(
        key: document.getKeyForNode(node.id),
        node: node as Link,
        document: document,
      ),
      children: (node) => (node as Link).fragments,
      mutableChildren: (node) => (node as Link).fragments,
      inline: true,
    ),
    FluentNodeDefinition<FNode>(
      type: 'image',
      nodeClass: FluentImage,
      decode: (json, _) => FluentImage.fromJson(json),
      create: (options) => FluentImage(options['src'] as String? ?? ''),
      buildWidget: (node, document, _, _) => FluentImageWidget(
        key: document.getKeyForNode(node.id),
        node: node as FluentImage,
        document: document,
      ),
      inline: true,
      atomic: true,
    ),
    FluentNodeDefinition<FNode>(
      type: 'hr',
      nodeClass: HorizontalRule,
      decode: (json, _) => HorizontalRule.fromJson(json),
      create: (_) => HorizontalRule(),
      buildWidget: (node, document, _, _) => FluentHrWidget(
        key: document.getKeyForNode(node.id),
        node: node as HorizontalRule,
        document: document,
      ),
      atomic: true,
    ),
    FluentNodeDefinition<FNode>(
      type: 'list',
      nodeClass: FluentList,
      decode: _decodeList,
      create: (options) {
        final type = options['listType'] as String? ?? 'bullet';
        return FluentList(listType: type)
          ..items = [
            ListItem(
              bulletType: type,
              indexList: const [1],
              children: [Paragraph()],
            ),
          ];
      },
      buildWidget: (node, document, _, _) => FluentListWidget(
        key: document.getKeyForNode(node.id),
        node: node as FluentList,
        document: document,
      ),
      children: (node) => (node as FluentList).items,
      mutableChildren: (node) => (node as FluentList).items,
    ),
    FluentNodeDefinition<FNode>(
      type: 'listItem',
      nodeClass: ListItem,
      decode: _decodeListItem,
      create: (options) => ListItem(
        bulletType: options['bulletType'] as String? ?? 'bullet',
        indexList: (options['indexList'] as List<int>?) ?? const [1],
      ),
      buildWidget: (node, document, _, _) => FluentListItemWidget(
        key: document.getKeyForNode(node.id),
        node: node as ListItem,
        document: document,
      ),
      children: (node) => (node as ListItem).children,
      mutableChildren: (node) => (node as ListItem).children,
    ),
    FluentNodeDefinition<FNode>(
      type: 'table',
      nodeClass: FluentTable,
      decode: _decodeTable,
      create: _createTable,
      buildWidget: (node, document, _, _) => FluentTableWidget(
        key: document.getKeyForNode(node.id),
        node: node as FluentTable,
        document: document,
      ),
      children: (node) => (node as FluentTable).rows,
      mutableChildren: (node) => (node as FluentTable).rows,
    ),
    FluentNodeDefinition<FNode>(
      type: 'row',
      nodeClass: FluentRow,
      decode: _decodeRow,
      create: (_) => FluentRow(),
      buildWidget: (_, _, _, _) => const SizedBox.shrink(),
      children: (node) => (node as FluentRow).getChildren(),
      mutableChildren: (node) => (node as FluentRow).getChildren(),
    ),
    FluentNodeDefinition<FNode>(
      type: 'cell',
      nodeClass: FluentCell,
      decode: _decodeCell,
      create: (_) => FluentCell(),
      buildWidget: (node, document, _, _) => FluentCellWidget(
        key: document.getKeyForNode(node.id),
        node: node as FluentCell,
        document: document,
      ),
      children: (node) => (node as FluentCell).children,
      mutableChildren: (node) => (node as FluentCell).children,
    ),
  ];
}

Root _decodeRoot(Map<String, dynamic> json, FluentPluginRegistry registry) {
  final root = Root(
    nodes: _decodeChildren(json['nodes'], registry),
  );
  root.id = json['id'] as String? ?? root.id;
  root.type = json['type'] as String? ?? 'root';
  return root;
}

Paragraph _decodeParagraph(
  Map<String, dynamic> json,
  FluentPluginRegistry registry,
) {
  final paragraph = Paragraph(
    textAlign: json['textAlign'] as String? ?? 'left',
    indent: (json['indent'] as num?)?.toInt() ?? 0,
    styleName: json['styleName'] as String?,
  );
  paragraph.id = json['id'] as String? ?? paragraph.id;
  paragraph.type = json['type'] as String? ?? 'paragraph';
  paragraph.fragments = _decodeChildren(json['fragments'], registry);
  return paragraph;
}

Link _decodeLink(Map<String, dynamic> json, FluentPluginRegistry registry) {
  final link = Link(url: json['url'] as String? ?? '');
  link.id = json['id'] as String? ?? link.id;
  link.fragments = _decodeChildren(json['fragments'], registry);
  link.textAlign = json['textAlign'] as String? ?? 'left';
  link.indent = (json['indent'] as num?)?.toInt() ?? 0;
  link.styleName = json['styleName'] as String?;
  return link;
}

FluentList _decodeList(
  Map<String, dynamic> json,
  FluentPluginRegistry registry,
) {
  final list = FluentList(listType: json['listType'] as String? ?? 'bullet');
  list.id = json['id'] as String? ?? list.id;
  list.textAlign = json['textAlign'] as String? ?? 'left';
  list.indent = (json['indent'] as num?)?.toInt() ?? 0;
  list.styleName = json['styleName'] as String?;
  list.items = _decodeChildren(json['items'], registry).cast<ListItem>();
  return list;
}

ListItem _decodeListItem(
  Map<String, dynamic> json,
  FluentPluginRegistry registry,
) {
  final item = ListItem(
    bulletType: json['bulletType'] as String? ?? 'bullet',
    indexList: (json['indexList'] as List<dynamic>? ?? const [1])
        .map((value) => (value as num).toInt())
        .toList(),
    children: _decodeChildren(json['children'], registry),
  );
  item.id = json['id'] as String? ?? item.id;
  return item;
}

FluentTable _decodeTable(
  Map<String, dynamic> json,
  FluentPluginRegistry registry,
) {
  final table = FluentTable(
    rows: _decodeChildren(json['rows'], registry).cast<FluentRow>(),
    columnWidths: (json['columnWidths'] as List<dynamic>?)
        ?.map((value) => (value as num).toDouble())
        .toList(),
    tableWidth: (json['tableWidth'] as num?)?.toDouble(),
  );
  table.id = json['id'] as String? ?? table.id;
  return table;
}

FluentRow _decodeRow(
  Map<String, dynamic> json,
  FluentPluginRegistry registry,
) {
  final row = FluentRow(
    cells: _decodeChildren(json['cells'], registry).cast<FluentCell>(),
    rowHeight: (json['rowHeight'] as num?)?.toDouble(),
  );
  row.id = json['id'] as String? ?? row.id;
  return row;
}

FluentCell _decodeCell(
  Map<String, dynamic> json,
  FluentPluginRegistry registry,
) {
  final cell = FluentCell(children: _decodeChildren(json['children'], registry));
  cell.id = json['id'] as String? ?? cell.id;
  cell.colSpan = (json['colSpan'] as num?)?.toInt() ?? 1;
  cell.rowSpan = (json['rowSpan'] as num?)?.toInt() ?? 1;
  return cell;
}

FNode _createTable(Map<String, dynamic> options) {
  final rowCount = (options['rows'] as num?)?.toInt() ?? 2;
  final columnCount = (options['cells'] as num?)?.toInt() ?? 2;
  return FluentTable(
    rows: List.generate(
      rowCount,
      (_) => FluentRow(
        cells: List.generate(columnCount, (_) => FluentCell()),
      ),
    ),
  );
}

List<FNode> _decodeChildren(
  Object? value,
  FluentPluginRegistry registry,
) {
  if (value is! List) return [];
  return value
      .map((item) => registry.decodeNode(item as Map<String, dynamic>))
      .toList();
}

FluentPluginRegistry createDefaultFluentPluginRegistry([
  Iterable<FluentEditorPlugin> plugins = const [],
]) {
  return FluentPluginRegistry([FluentBuiltInPlugin(), ...plugins]);
}
