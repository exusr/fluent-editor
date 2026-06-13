import 'package:fluent_editor/factories.dart';
import 'package:flutter/widgets.dart';

class RenderFluentLeaf extends RenderBox {
  String id;
  FNode node;

  RenderFluentLeaf({required this.node}) : id = node.id;

  @override
  void performLayout() {
    throw UnimplementedError();
  }
  
  @override
  void paint(PaintingContext context, Offset offset) {
    throw UnimplementedError();
  }
}

class RenderFluentNode extends RenderFluentLeaf {
  List<Widget> children = [];

  RenderFluentNode({required super.node});
  
  @override
  void performLayout() {
    throw UnimplementedError();
  }
  
  @override
  void paint(PaintingContext context, Offset offset) {
    throw UnimplementedError();
  }
}