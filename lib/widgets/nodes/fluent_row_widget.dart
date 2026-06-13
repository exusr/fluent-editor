import 'dart:math' as math;

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/renderers/render_fluent_node.dart';
import 'package:fluent_editor/utils/editor_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class FluentRowWidget extends StatefulWidget {
  const FluentRowWidget({
    super.key,
    required this.node,
    required this.document,
  });

  final FluentRow node;
  final FluentDocument document;

  @override
  State<FluentRowWidget> createState() => _FluentRowWidgetState();
}

class _FluentRowWidgetState extends State<FluentRowWidget> {
  @override
  Widget build(BuildContext context) {
    return FluentRowWidgetRenderer(node: widget.node, document: widget.document);
  }
}

class FluentRowWidgetRenderer extends MultiChildRenderObjectWidget {
  final FluentRow node;

  FluentRowWidgetRenderer({
    super.key,
    required this.node,
    required FluentDocument document,
  }) : super(
          children: node.cells
              .map((cell) => _CellWrapper(cell: cell, child: buildFNodeWidget(cell, document)))
              .toList(),
        );

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderFluentRow(
      node: node,
      borderColor: Theme.of(context).colorScheme.outline,
    );
  }

  @override
  void updateRenderObject(BuildContext context, covariant RenderFluentRow renderObject) {
    renderObject.node = node;
    renderObject.borderColor = Theme.of(context).colorScheme.outline;
  }
}

// Wrapper to pass colSpan to the render object
class _CellWrapper extends SingleChildRenderObjectWidget {
  final FluentCell cell;
  
  const _CellWrapper({required this.cell, required super.child});
  
  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCellWrapper(colSpan: cell.colSpan);
  }
  
  @override
  void updateRenderObject(BuildContext context, _RenderCellWrapper renderObject) {
    renderObject.colSpan = cell.colSpan;
  }
}

class _RenderCellWrapper extends RenderProxyBox {
  int colSpan;
  
  _RenderCellWrapper({required this.colSpan});
}

class FluentRowParentData extends ContainerBoxParentData<RenderBox> {
  double width = 0.0;
  int colSpan = 1;
}

class RenderFluentRow extends RenderFluentNode
    with
        ContainerRenderObjectMixin<RenderBox, FluentRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, FluentRowParentData> {
  static const double minCellWidth = 20.0;
  static const double minCellHeight = 20.0;

  Color _borderColor = const Color(0xFFE0E0E0);
  Color get borderColor => _borderColor;
  set borderColor(Color value) {
    if (_borderColor != value) {
      _borderColor = value;
      markNeedsPaint();
    }
  }

  RenderFluentRow({required FluentRow node, Color? borderColor}) : super(node: node) {
    if (borderColor != null) {
      _borderColor = borderColor;
    }
  }

  @override
  FluentRow get node => super.node as FluentRow;

  @override
  set node(covariant FluentRow value) {
    if (super.node != value) {
      super.node = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! FluentRowParentData) {
      child.parentData = FluentRowParentData();
    }
  }

  @override
  void performLayout() {
    final int cellCount = childCount;
    if (cellCount == 0) {
      size = constraints.constrain(const Size(0, 0));
      return;
    }

    // Calculate uniform width for each cell (minimum 20px)
    final double availableWidth = constraints.maxWidth;
    final double cellWidth = math.max(availableWidth / cellCount, minCellWidth);

    double maxHeight = 0;
    double x = 0;
    RenderBox? child = firstChild;

    while (child != null) {
      final parentData = child.parentData as FluentRowParentData;
      
      // Get the colSpan from wrapper or default 1
      int colSpan = 1;
      if (child is _RenderCellWrapper) {
        colSpan = child.colSpan;
        parentData.colSpan = colSpan;
      }
      
      // Calculate width based on colSpan
      final double spanWidth = cellWidth * colSpan;
      
      // Layout the cell with extended width and minimum height
      child.layout(
        BoxConstraints(
          minWidth: spanWidth,
          maxWidth: spanWidth,
          minHeight: minCellHeight,
        ),
        parentUsesSize: true,
      );

      parentData.offset = Offset(x, 0);
      parentData.width = spanWidth;
      x += spanWidth;
      maxHeight = math.max(maxHeight, child.size.height);
      child = parentData.nextSibling;
    }

    // Minimum height of the row: 20px
    size = constraints.constrain(Size(availableWidth, math.max(maxHeight, minCellHeight)));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Draw vertical borders between cells
    final linePaint = Paint()
      ..color = _borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    RenderBox? child = firstChild;
    while (child != null) {
      final parentData = child.parentData as FluentRowParentData;
      final childRect = (offset + parentData.offset) & child.size;
      // Vertical line to the right of each cell
      context.canvas.drawLine(
        Offset(childRect.right, childRect.top),
        Offset(childRect.right, childRect.bottom),
        linePaint,
      );
      child = parentData.nextSibling;
    }
    
    // Draw the children (cells)
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
