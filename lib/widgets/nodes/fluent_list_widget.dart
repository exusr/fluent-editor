import 'dart:math' as math;
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/renderers/render_fluent_node.dart';
import 'package:fluent_editor/utils/editor_utils.dart';
import 'package:fluent_editor/widgets/nodes/fluent_paragraph_widget.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class FluentListWidget extends FluentParagraphWidget{
  const FluentListWidget({super.key, required super.node, required super.document});

  @override
  FluentList get node => super.node as FluentList;

  @override
  FluentParagraphWidgetState<FluentListWidget> createState() => _FluentListWidgetState();
}

class _FluentListWidgetState extends FluentParagraphWidgetState<FluentListWidget> {
  @override
  Widget build(BuildContext context) {
    return FluentListWidgetRender(node: widget.node, document: widget.document);
  }
}

class FluentListWidgetRender extends MultiChildRenderObjectWidget {
  final FluentList node;
  
  FluentListWidgetRender({
    super.key,
    required this.node,
    required FluentDocument document,
  }) : super(children: _createChildren(node, document));

  static List<Widget> _createChildren(FluentList node, FluentDocument document) {
    return node.getChildren().map((item) => buildFNodeWidget(item, document)).toList();
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderFluentList(node: node);
  }

  @override
  void updateRenderObject(BuildContext context, covariant RenderFluentList renderObject) {
    renderObject.node = node;
  }
}

class FluentListParentData extends ContainerBoxParentData<RenderBox> {}

class RenderFluentList extends RenderFluentNode
    with ContainerRenderObjectMixin<RenderBox, FluentListParentData>,
         RenderBoxContainerDefaultsMixin<RenderBox, FluentListParentData> {
  
  RenderFluentList({required FluentList node}) : super(node: node);

  @override
  FluentList get node => super.node as FluentList;
  
  @override
  set node(covariant FluentList value) {
    if (super.node != value) {
      super.node = value;
      markNeedsLayout();
    }
  }
  
  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! FluentListParentData) {
      child.parentData = FluentListParentData();
    }
  }
  
  @override
  void performLayout() {
    double y = 0;
    double maxWidth = 0;
    RenderBox? child = firstChild;
    
    while (child != null) {
      child.layout(BoxConstraints(maxWidth: constraints.maxWidth), parentUsesSize: true);
      final parentData = child.parentData as FluentListParentData;
      parentData.offset = Offset(0, y);
      y += child.size.height;
      maxWidth = math.max(maxWidth, child.size.width);
      child = parentData.nextSibling;
    }
    
    size = constraints.constrain(Size(maxWidth, y));
  }
  
  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }
  
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
