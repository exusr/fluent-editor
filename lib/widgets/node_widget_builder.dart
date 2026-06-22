import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
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

Widget buildFNodeWidget(FNode node, FluentDocument document,
    {int anchorOffset = -1, int focusOffset = -1}) {
  return switch (node) {
    HorizontalRule() => FluentHrWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    FluentImage() => FluentImageWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    FluentCell() => FluentCellWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    FluentTable() => FluentTableWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    FluentList() => FluentListWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    ListItem() => FluentListItemWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    Link() => FluentLinkWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    Paragraph() => FluentParagraphWidget(
        key: document.getKeyForNode(node.id), node: node, document: document),
    Fragment() => FluentFragmentWidget(
        key: document.getKeyForNode(node.id),
        node: node,
        anchorOffset: anchorOffset,
        focusOffset: focusOffset),
    _ => throw Exception('Node type not supported: ${node.runtimeType}'),
  };
}
