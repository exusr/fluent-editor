import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:flutter/widgets.dart';

Widget buildFNodeWidget(FNode node, FluentDocument document,
    {int anchorOffset = -1, int focusOffset = -1}) {
  final definition = document.registry.nodeFor(node);
  if (definition != null) {
    return definition.buildWidget(node, document, anchorOffset, focusOffset);
  }
  throw Exception('Node type not supported: ${node.runtimeType}');
}
