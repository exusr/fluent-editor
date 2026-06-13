// render_f_text_node.dart — leaf that knows how to draw itself
import 'package:fluent_editor/factories.dart';
import 'package:flutter/material.dart';
import 'package:fluent_editor/renderers/render_fluent_node.dart';

/// Leaf render object: has no children, draws only text.
class RenderFluentFragment extends RenderFluentLeaf {
  RenderFluentFragment({ 
    required super.node, 
    required int anchorOffset, 
    required int focusOffset, 
    required TextDirection textDirection,
    TextStyle? style,
    Color? cursorColor,
    Color? selectionColor,
  }) : 
        _painter = TextPainter(
          text: TextSpan(
            text: (node as Fragment).text,
            style: style,
          ),
          textDirection: textDirection,
          textAlign: TextAlign.left,
        ),
        _anchorOffset = anchorOffset,
        _focusOffset = focusOffset,
        _cursorColor = cursorColor ?? const Color(0xFF2196F3),
        _selectionColor = selectionColor ?? const Color(0xFF64B5F6);

  final TextPainter _painter;
  final int _anchorOffset;
  final int _focusOffset;
  Color _cursorColor;
  Color _selectionColor;

  Color get cursorColor => _cursorColor;
  set cursorColor(Color value) {
    if (_cursorColor != value) {
      _cursorColor = value;
      markNeedsPaint();
    }
  }

  Color get selectionColor => _selectionColor;
  set selectionColor(Color value) {
    if (_selectionColor != value) {
      _selectionColor = value;
      markNeedsPaint();
    }
  }

  String get text => (_painter.text as TextSpan).text ?? '';
  set text(String v) {
    if (text == v) return;
    _painter.text = TextSpan(text: v, style: style);
    markNeedsLayout();
  }

  TextStyle? get style => (_painter.text as TextSpan).style;
  set style(TextStyle? v) {
    if (style == v) return;
    _painter.text = TextSpan(text: text, style: v);
    markNeedsLayout();
  }

  TextDirection get textDirection => _painter.textDirection!;
  set textDirection(TextDirection v) {
    if (_painter.textDirection == v) return;
    _painter.textDirection = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    _painter.layout(
      minWidth: constraints.minWidth,
      maxWidth: constraints.maxWidth,
    );
    size = constraints.constrain(Size(_painter.width, _painter.height));
  }

  /// Returns true if the text was wrapped on multiple lines
  bool get isWrapped {
    // If the height is significantly greater than the height of one line, it is wrapped
    return size.height > _painter.preferredLineHeight * 1.5;
  }

  /// Calculates the minimum width needed to contain all text on one line
  double get naturalWidth {
    _painter.layout(minWidth: 0, maxWidth: double.infinity);
    final width = _painter.width;
    // Restore the previous layout
    _painter.layout(minWidth: constraints.minWidth, maxWidth: constraints.maxWidth);
    return width;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _painter.paint(context.canvas, offset);
    if (_anchorOffset == _focusOffset && _focusOffset != -1) {
      _paintCursor(context.canvas, offset);
    }
    if (_anchorOffset != -1 && _focusOffset != -1) {
      _paintSelection(context.canvas, offset);
    }
  }

  int getOffsetForPosition(Offset localPosition) {
    final textPosition = _painter.getPositionForOffset(localPosition);
    return textPosition.offset;
  }

  void _paintCursor(Canvas canvas, Offset offset) {
    // Calculate the pixel position of the caret via TextPainter
    final caretOffset = _painter.getOffsetForCaret(
      TextPosition(offset: _anchorOffset.clamp(0, text.length)),
      Rect.zero,
    );

    final cursorRect = Rect.fromLTWH(
      offset.dx + caretOffset.dx,
      offset.dy + caretOffset.dy,
      2,
      _painter.preferredLineHeight,
    );

    canvas.drawRect(cursorRect, Paint()..color = _cursorColor);
  }

  void _paintSelection(Canvas canvas, Offset offset) {
    // Calculate the pixel position of the caret via TextPainter
    final startOffset = _painter.getOffsetForCaret(
      TextPosition(offset: _anchorOffset.clamp(0, text.length)),
      Rect.zero,
    );
    final endOffset = _painter.getOffsetForCaret(
      TextPosition(offset: _focusOffset.clamp(0, text.length)),
      Rect.zero,
    );

    final selectionRect = Rect.fromLTWH(
      offset.dx + startOffset.dx,
      offset.dy + startOffset.dy,
      endOffset.dx - startOffset.dx,
      _painter.preferredLineHeight,
    );

    canvas.drawRect(selectionRect, Paint()..color = _selectionColor.withValues(alpha: 0.3));
  }

  @override
  bool hitTestSelf(Offset position) => true;
}