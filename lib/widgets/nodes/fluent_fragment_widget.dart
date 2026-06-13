import 'package:flutter/material.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/renderers/render_fragment.dart';

class FluentFragmentWidget extends LeafRenderObjectWidget {
  const FluentFragmentWidget({
    super.key, 
    required this.node, 
    required this.anchorOffset, 
    required this.focusOffset,
    this.style,
    this.cursorColor,
    this.selectionColor,
  });

  final Fragment node;
  final int anchorOffset;
  final int focusOffset;
  final TextStyle? style;
  final Color? cursorColor;
  final Color? selectionColor;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderFluentFragment(
      node: node,
      anchorOffset: anchorOffset,
      focusOffset: focusOffset,
      textDirection: Directionality.of(context),
      style: style,
      cursorColor: cursorColor ?? Theme.of(context).colorScheme.primary,
      selectionColor: selectionColor ?? Theme.of(context).colorScheme.primary.withAlpha(100),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderFluentFragment renderObject) {
    renderObject
      ..id = node.id
      ..text = node.text
      ..textDirection = Directionality.of(context)
      ..style = style
      ..cursorColor = cursorColor ?? Theme.of(context).colorScheme.primary
      ..selectionColor = selectionColor ?? Theme.of(context).colorScheme.primary.withAlpha(100);
  }
}