// render_paragraph.dart
// Single TextPainter for the entire paragraph
// with tracking of fragment positions for ID ↔ offset conversion

import 'dart:ui' show Picture, PictureRecorder;

import 'package:fluent_editor/core/paragraph_registry.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/renderers/render_fluent_node.dart';
import 'package:fluent_editor/spell_check/spell_annotation.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/utils/color_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// ParentData for RenderBox children (images inside links) of the paragraph.
class FluentInlineParentData extends ContainerBoxParentData<RenderBox> {}

/// Collects FluentImage in visitation order (both direct and
/// those inside Link). Must produce the same order used by
/// `_buildTextSpanAndTrackPositions`, so the placeholder index aligns
/// the child RenderBox.
List<FluentImage> collectInlineImages(InlineContainerNode container) {
  final result = <FluentImage>[];
  void visit(FNode node) {
    if (node is FluentImage) {
      result.add(node);
      return;
    }
    if (node is Link) {
      for (final child in node.getChildren()) {
        if (child is FluentImage) result.add(child);
      }
      return;
    }
    if (node is FluentList) return;
    if (node is InlineContainerNode) {
      for (final child in (node as InlineContainerNode).getChildren()) {
        visit(child);
      }
    }
  }
  for (final child in container.getChildren()) {
    visit(child);
  }
  return result;
}

/// Tracks the position of a fragment in the global text of the paragraph.
class _FragmentPosition {
  final String id;
  final int start;
  final int end;
  final bool isImage;

  int get textLength => end - start;

  _FragmentPosition({required this.id, required this.start, required this.end, this.isImage = false});

  bool contains(int offset) => offset >= start && offset < end;
  int toLocal(int globalOffset) => globalOffset - start;
  int toGlobal(int localOffset) => start + localOffset;
}

/// Tracks a superscript/subscript fragment to be painted with vertical offset.
class _ScriptSpanInfo {
  final int globalStart;
  final int globalEnd;
  final String text;
  final TextStyle style;
  final bool isSuperscript;

  _ScriptSpanInfo({
    required this.globalStart,
    required this.globalEnd,
    required this.text,
    required this.style,
    required this.isSuperscript,
  });
}

/// RenderFluentParagraph with single TextPainter for all text.
/// Supports WidgetSpan children (e.g. images inside Link): RenderBox children
/// are laid out, positioned at placeholder offsets calculated by
/// TextPainter and painted as part of the paragraph.
class RenderFluentParagraph extends RenderFluentNode
    with
        ContainerRenderObjectMixin<RenderBox, FluentInlineParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, FluentInlineParentData> {

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! FluentInlineParentData) {
      child.parentData = FluentInlineParentData();
    }
  }

  final TextPainter _painter = TextPainter(
    textDirection: TextDirection.ltr,
    textWidthBasis: TextWidthBasis.parent,
  );

  final List<_FragmentPosition> _fragmentPositions = [];
  final List<PlaceholderDimensions> _placeholderDimensions = [];
  final List<_ScriptSpanInfo> _scriptSpans = [];

  String _anchorFragmentId = '';
  int _anchorLocalOffset = -1;
  String? _focusFragmentId;
  int? _focusLocalOffset;

  String? _selAnchorFragmentId;
  int? _selAnchorLocalOffset;
  String? _selFocusFragmentId;
  int? _selFocusLocalOffset;

  // ─── IME preedit state ──────────────────────────────────────────
  /// Preedit text rendered with a blue dashed underline during composition.
  String _imePreeditText = '';
  String get imePreeditText => _imePreeditText;
  set imePreeditText(String value) {
    if (_imePreeditText != value) {
      _imePreeditText = value;
      markNeedsLayout();
    }
  }

  /// The composing range within the preedit text.
  TextRange _imeComposingRange = TextRange.empty;
  TextRange get imeComposingRange => _imeComposingRange;
  set imeComposingRange(TextRange value) {
    if (_imeComposingRange != value) {
      _imeComposingRange = value;
      markNeedsPaint();
    }
  }

  /// Fragment id where the preedit starts.
  String _imePreeditFragmentId = '';
  String get imePreeditFragmentId => _imePreeditFragmentId;
  set imePreeditFragmentId(String value) {
    if (_imePreeditFragmentId != value) {
      _imePreeditFragmentId = value;
      markNeedsLayout();
    }
  }

  /// Local offset where the preedit starts.
  int _imePreeditLocalOffset = 0;
  int get imePreeditLocalOffset => _imePreeditLocalOffset;
  set imePreeditLocalOffset(int value) {
    if (_imePreeditLocalOffset != value) {
      _imePreeditLocalOffset = value;
      markNeedsLayout();
    }
  }

  InlineContainerNode _container;

  /// Registry in which this render automatically registers.
/// Received from parent widget via the document.
  final ParagraphRegistry registry;

  InlineContainerNode get container => _container;
  set container(InlineContainerNode value) {
    if ((_container as FNode).id != (value as FNode).id) {
      registry.unregister((_container as FNode).id, this);
      _container = value;
      node = value as FNode;
      registry.register((_container as FNode).id, this);
    } else {
      _container = value;
      node = value as FNode;
    }
    markNeedsLayout();
  }

  double _lineHeight = 1.15;
  double get lineHeight => _lineHeight;
  set lineHeight(double value) {
    if (_lineHeight != value) {
      _lineHeight = value;
      markNeedsLayout();
    }
  }

  TextAlign _textAlign = TextAlign.left;
  TextAlign get textAlign => _textAlign;
  set textAlign(TextAlign value) {
    if (_textAlign != value) {
      _textAlign = value;
      markNeedsLayout();
    }
  }

  /// Width passed to layout(maxWidth) used to calculate the alignment
  /// offset (useful when the parent widget restricts the width).
  double _layoutMaxWidth = 0;

  /// If true, the paragraph shrinks to the content width.
  /// Useful for aligning the paragraph with the marker in list items.
  bool _shrinkWrap = false;
  bool get shrinkWrap => _shrinkWrap;
  set shrinkWrap(bool value) {
    if (_shrinkWrap != value) {
      _shrinkWrap = value;
      markNeedsLayout();
    }
  }

  /// Paragraph style for fallback of fragment properties.
  ParagraphStyle? _paragraphStyle;
  ParagraphStyle? get paragraphStyle => _paragraphStyle;
  set paragraphStyle(ParagraphStyle? value) {
    if (_paragraphStyle != value) {
      _paragraphStyle = value;
      markNeedsLayout();
    }
  }

  Color _defaultTextColor = const Color(0xFF000000);
  Color get defaultTextColor => _defaultTextColor;
  set defaultTextColor(Color value) {
    if (_defaultTextColor != value) {
      _defaultTextColor = value;
      markNeedsLayout();
    }
  }

  Color _cursorColor = const Color(0xFF2196F3);
  Color get cursorColor => _cursorColor;
  set cursorColor(Color value) {
    if (_cursorColor != value) {
      _cursorColor = value;
      markNeedsPaint();
    }
  }

  Color _selectionColor = const Color(0xFF64B5F6);
  Color get selectionColor => _selectionColor;
  set selectionColor(Color value) {
    if (_selectionColor != value) {
      _selectionColor = value;
      markNeedsPaint();
    }
  }

  List<SpellAnnotation> _spellAnnotations = const [];
  List<SpellAnnotation> get spellAnnotations => _spellAnnotations;
  set spellAnnotations(List<SpellAnnotation> value) {
    if (!listEquals(_spellAnnotations, value)) {
      _spellAnnotations = value;
      _cachedSpellBoxes = null;
      markNeedsPaint();
    }
  }

  List<Map<String, dynamic>> _commentAnnotations = const [];
  List<Map<String, dynamic>> get commentAnnotations => _commentAnnotations;
  set commentAnnotations(List<Map<String, dynamic>> value) {
    if (!listEquals(_commentAnnotations, value)) {
      _commentAnnotations = value;
      _cachedCommentBoxes = null;
      markNeedsPaint();
    }
  }

  String? _selectedCommentId;
  String? get selectedCommentId => _selectedCommentId;
  set selectedCommentId(String? value) {
    if (_selectedCommentId != value) {
      _selectedCommentId = value;
      markNeedsPaint();
    }
  }

  Color _linkColor = const Color(0xFF2196F3);
  Color get linkColor => _linkColor;
  set linkColor(Color value) {
    if (_linkColor != value) {
      _linkColor = value;
      markNeedsLayout();
    }
  }

  Color _imeCompositionColor = const Color(0xFF2196F3);
  Color get imeCompositionColor => _imeCompositionColor;
  set imeCompositionColor(Color value) {
    if (_imeCompositionColor != value) {
      _imeCompositionColor = value;
      markNeedsPaint();
    }
  }

  // ─── Paint caches ───────────────────────────────────────────────
  // Cached structures to avoid recomputing expensive TextPainter
  // queries on every paint (e.g. cursor blink, selection highlight).

  List<LineMetrics>? _cachedLineMetrics;
  bool _lineMetricsDirty = true;

  ({String? aFrag, int? aOff, String? fFrag, int? fOff})? _lastSelectionKey;
  List<TextBox>? _cachedSelectionBoxes;

  List<List<TextBox>>? _cachedSpellBoxes;

  List<List<TextBox>>? _cachedCommentBoxes;

  /// Cached Picture of the pure text layer. Invalidated on layout changes;
  /// the overlay layer (selection, caret, spell) is painted on top every frame.
  Picture? _cachedTextPicture;

  RenderFluentParagraph({
    required InlineContainerNode container,
    required this.registry,
    double lineHeight = 1.15,
    TextAlign textAlign = TextAlign.left,
    bool shrinkWrap = false,
    ParagraphStyle? paragraphStyle,
    Color defaultTextColor = const Color(0xFF000000),
    Color cursorColor = const Color(0xFF2196F3),
    Color selectionColor = const Color(0xFF64B5F6),
    Color linkColor = const Color(0xFF2196F3),
    Color imeCompositionColor = const Color(0xFF2196F3),
  }) : _lineHeight = lineHeight,
       _textAlign = textAlign,
       _container = container,
       _shrinkWrap = shrinkWrap,
       _paragraphStyle = paragraphStyle,
       _defaultTextColor = defaultTextColor,
       _cursorColor = cursorColor,
       _selectionColor = selectionColor,
       _linkColor = linkColor,
       _imeCompositionColor = imeCompositionColor,
       super(node: container as FNode);

  // ─── System fonts changed (web CanvasKit fallback loading) ────────
  // CanvasKit loads browser fallback fonts asynchronously. When a CJK
  // character is first shaped, the font may not be ready yet, producing
  // tofu glyphs. Once the font loads, PaintingBinding fires the systemFonts
  // notification. We register/unregister in attach/detach so only live
  // render objects get notified.
  void _handleSystemFontsChanged() {
    _painter.markNeedsLayout();
    _cachedTextPicture?.dispose();
    _cachedTextPicture = null;
    markNeedsLayout();
  }

  // ─── Lifecycle: automatic registration ──────────────────────────

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    registry.register((_container as FNode).id, this);
    PaintingBinding.instance.systemFonts.addListener(_handleSystemFontsChanged);
  }

  @override
  void detach() {
    registry.unregister((_container as FNode).id, this);
    PaintingBinding.instance.systemFonts.removeListener(_handleSystemFontsChanged);
    super.detach();
  }

  // ─── Helper for properties with fallback from style ────────────────

  /// Returns the effective font family for a fragment,
  /// using the paragraph style as fallback.
  String _getEffectiveFontFamily(Fragment fragment) {
    // Always use the fragment's font family to respect user's font changes
    // The paragraph style should only be used as a fallback, not as an override
    if (fragment.fontFamily.isNotEmpty) {
      return fragment.fontFamily;
    }
    // Fallback to paragraph style if fragment has no font
    if (_paragraphStyle?.fontFamily != null) {
      return _paragraphStyle!.fontFamily!;
    }
    return 'Arial';
  }

  /// Returns the effective font size for a fragment,
  /// using the paragraph style as fallback.
  double _getEffectiveFontSize(Fragment fragment) {
    // If the style is applied and the fragment has the default size,
    // use the style size
    if (_paragraphStyle?.fontSize != null &&
        fragment.fontSize == 14.0) {
      return _paragraphStyle!.fontSize!;
    }
    return fragment.fontSize;
  }

  /// Returns the effective inline styles for a fragment,
  /// using the paragraph style as base.
  List<String> _getEffectiveStyles(Fragment fragment) {
    // If the style has defined styles and the fragment is empty,
    // use the style styles
    if (_paragraphStyle?.styles != null &&
        (fragment.styles == null || fragment.styles!.isEmpty)) {
      return _paragraphStyle!.styles!;
    }
    return fragment.styles ?? [];
  }

  // ─── Public API for the resolver ─────────────────────────────────

  /// Offset X that shifts the text for alignment (center/right).
  /// When shrinkWrap is true, alignment is managed by the parent.
  double get _alignmentXOffset {
    if (_shrinkWrap) return 0.0;
    return switch (_textAlign) {
      TextAlign.center => (_layoutMaxWidth - _painter.width) / 2,
      TextAlign.right => _layoutMaxWidth - _painter.width,
      _ => 0.0,
    };
  }

  /// Returns the global x coordinate (logical pixels) of the caret for
  /// [fragmentId] at [localOffset]. Returns null if the fragment does not
  /// belong to this paragraph (used by ParagraphRegistry to iterate).
  double? getCaretX(String fragmentId, int localOffset) {
    final globalOffset = _localToGlobal(fragmentId, localOffset);
    if (globalOffset == null) return null;

    // Use the character box for precise X (left/right of the real box).
    // More accurate than getOffsetForCaret which can round or be wrong
    // near fragment borders or WidgetSpan.
    TextBox? charBox;
    final textLength = _painter.text?.toPlainText().length ?? 0;
    if (globalOffset > 0 && globalOffset <= textLength) {
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: globalOffset - 1, extentOffset: globalOffset),
      );
      if (boxes.isNotEmpty) charBox = boxes.first;
    } else if (globalOffset == 0 && textLength > 0) {
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: 1),
      );
      if (boxes.isNotEmpty) charBox = boxes.first;
    }

    final xAlign = _alignmentXOffset;
    if (charBox != null) {
      final x = globalOffset == 0 ? charBox.left : charBox.right;
      return localToGlobal(Offset(x + xAlign, 0)).dx;
    }

    // Fallback
    final caretOffset = _painter.getOffsetForCaret(
      TextPosition(offset: globalOffset),
      Rect.zero,
    );
    return localToGlobal(Offset(caretOffset.dx + xAlign, caretOffset.dy)).dx;
  }

  double? getCaretY(String fragmentId, int localOffset) {
    final globalOffset = _localToGlobal(fragmentId, localOffset);
    if (globalOffset == null) return null;

    // 1. Find the character box at the caret to identify the line.
    TextBox? charBox;
    final textLength = _painter.text?.toPlainText().length ?? 0;
    if (globalOffset > 0 && globalOffset <= textLength) {
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: globalOffset - 1, extentOffset: globalOffset),
      );
      if (boxes.isNotEmpty) charBox = boxes.first;
    } else if (globalOffset == 0 && textLength > 0) {
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: 1),
      );
      if (boxes.isNotEmpty) charBox = boxes.first;
    }

    if (charBox != null) {
      // 2. The baseline of the line is identical for ALL characters on the same
      // visual line, regardless of font size. Find it with
      // computeLineMetrics looking for the line whose baseline falls within
      // the vertical range of the character box.
      if (_lineMetricsDirty || _cachedLineMetrics == null) {
        _cachedLineMetrics = _painter.computeLineMetrics();
        _lineMetricsDirty = false;
      }
      final lineMetrics = _cachedLineMetrics!;
      for (final lm in lineMetrics) {
        if (lm.baseline >= charBox.top && lm.baseline <= charBox.bottom) {
          return localToGlobal(Offset(0, lm.baseline)).dy;
        }
      }
      // If not found (fallback), use the center of the box
      return localToGlobal(Offset(0, (charBox.top + charBox.bottom) / 2)).dy;
    }

    // Fallback for empty document
    final caretOffset = _painter.getOffsetForCaret(
      TextPosition(offset: globalOffset),
      Rect.zero,
    );
    return localToGlobal(caretOffset).dy;
  }


  /// Returns a [Rect] in global screen coordinates representing the caret line
  /// at [fragmentId]/[localOffset]. Used to position the IME candidate window
  /// on macOS (via [TextInputConnection.setCaretRect]).
  /// Returns null if the fragment is not in this paragraph.
  Rect? getCaretScreenRect(String fragmentId, int localOffset) {
    final globalOffset = _localToGlobal(fragmentId, localOffset);
    if (globalOffset == null) return null;
    return _screenRectForPainterOffset(globalOffset);
  }

  /// Returns the caret [Rect] (global screen coords) for a caret sitting
  /// [caretOffsetInPreedit] characters into the active IME preedit. The
  /// preedit is injected into [_painter] but not into [_fragmentPositions],
  /// so the painter offset is the preedit-start global offset plus the
  /// in-preedit caret offset. Lets the candidate window follow the caret.
  Rect? getImePreeditCaretScreenRect(int caretOffsetInPreedit) {
    if (_imePreeditFragmentId.isEmpty) return null;
    final base = _localToGlobal(_imePreeditFragmentId, _imePreeditLocalOffset);
    if (base == null) return null;
    return _screenRectForPainterOffset(base + caretOffsetInPreedit);
  }

  /// Shared: caret line [Rect] in global screen coords for a painter offset.
  Rect? _screenRectForPainterOffset(int globalOffset) {
    TextBox? charBox;
    final textLength = _painter.text?.toPlainText().length ?? 0;
    if (globalOffset > 0 && globalOffset <= textLength) {
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: globalOffset - 1, extentOffset: globalOffset),
      );
      if (boxes.isNotEmpty) charBox = boxes.first;
    } else if (globalOffset == 0 && textLength > 0) {
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: 1),
      );
      if (boxes.isNotEmpty) charBox = boxes.first;
    }

    if (charBox != null) {
      if (_lineMetricsDirty || _cachedLineMetrics == null) {
        _cachedLineMetrics = _painter.computeLineMetrics();
        _lineMetricsDirty = false;
      }
      for (final lm in _cachedLineMetrics!) {
        if (lm.baseline >= charBox.top && lm.baseline <= charBox.bottom) {
          final topLocal = lm.baseline - lm.ascent;
          final topGlobal = localToGlobal(Offset(charBox.left + _alignmentXOffset, topLocal));
          final x = globalOffset == 0 ? charBox.left : charBox.right;
          return Rect.fromLTWH(
            localToGlobal(Offset(x + _alignmentXOffset, 0)).dx,
            topGlobal.dy,
            1.0,
            lm.ascent + lm.descent,
          );
        }
      }
      // Fallback: use charBox bounds
      final tl = localToGlobal(Offset(charBox.left + _alignmentXOffset, charBox.top));
      return Rect.fromLTWH(tl.dx, tl.dy, 1.0, charBox.bottom - charBox.top);
    }

    // Empty paragraph fallback
    final caretOffset = _painter.getOffsetForCaret(
      TextPosition(offset: globalOffset), Rect.zero);
    final globalPt = localToGlobal(Offset(caretOffset.dx + _alignmentXOffset, caretOffset.dy));
    final lineH = _painter.preferredLineHeight;
    return Rect.fromLTWH(globalPt.dx, globalPt.dy, 1.0, lineH);
  }

  /// Returns true if this paragraph contains the given fragment.
  bool containsFragment(String fragmentId) =>
      _fragmentPositions.any((p) => p.id == fragmentId);

  // ─── Layout ───────────────────────────────────────────────────────

  @override
  void performLayout() {
    _fragmentPositions.clear();
    _placeholderDimensions.clear();
    _scriptSpans.clear();

    // 1. Pre-layout of children (inline images): need real sizes
    //    to set PlaceholderDimensions of TextPainter.
    final childSizes = <Size>[];
    var child = firstChild;
    var placeholderIdx = 0;
    while (child != null) {
      child.layout(
        BoxConstraints.loose(Size(constraints.maxWidth, double.infinity)),
        parentUsesSize: true,
      );
      
      // Apply stretch logic to inline images
      var childSize = child.size;
      final inlineImages = collectInlineImages(_container);
      if (placeholderIdx < inlineImages.length) {
        final image = inlineImages[placeholderIdx];
        final originalWidth = image.width ?? 300.0;
        final availableWidth = constraints.maxWidth;
        
        // Apply stretch logic
        if (originalWidth > availableWidth && availableWidth > 0 && availableWidth != double.infinity) {
          final aspectRatio = (image.height ?? 300.0) / originalWidth;
          childSize = Size(availableWidth, availableWidth * aspectRatio);
        }
      }
      
      childSizes.add(childSize);
      child = (child.parentData as FluentInlineParentData).nextSibling;
      placeholderIdx++;
    }

    // 2. Build the TextSpan and populate _placeholderDimensions using the
    //    size of children (index 1:1 with visitation order).
    final textSpan = _buildTextSpanAndTrackPositions(_container, childSizes);

    _painter.textAlign = textAlign;
    _painter.text = textSpan;
    if (_placeholderDimensions.isNotEmpty) {
      _painter.setPlaceholderDimensions(_placeholderDimensions);
    }
    _painter.layout(maxWidth: constraints.maxWidth);
    _layoutMaxWidth = constraints.maxWidth;

    // Any layout change invalidates line-metrics and box caches.
    _lineMetricsDirty = true;
    _cachedSelectionBoxes = null;
    _cachedSpellBoxes = null;
    _cachedCommentBoxes = null;
    _cachedTextPicture?.dispose();
    _cachedTextPicture = null;

    // 3. Position children at offsets calculated by TextPainter.
    final placeholderBoxes = _painter.inlinePlaceholderBoxes ?? const [];
    child = firstChild;
    var i = 0;
    while (child != null && i < placeholderBoxes.length) {
      final box = placeholderBoxes[i];
      final parentData = child.parentData as FluentInlineParentData;
      parentData.offset = Offset(box.left, box.top);
      child = parentData.nextSibling;
      i++;
    }

    final width = _shrinkWrap ? _painter.width : constraints.maxWidth;
    size = constraints.constrain(Size(width, _painter.height));
  }

  /// Builds a TextSpan for the IME preedit text, styled with a blue dashed
  /// underline. Inherits font properties from [baseStyle].
  TextSpan _buildImePreeditSpan(TextStyle? baseStyle) {
    final base = baseStyle ?? const TextStyle();
    return TextSpan(
      text: _imePreeditText,
      style: base.copyWith(
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dashed,
        decorationColor: _imeCompositionColor,
        decorationThickness: 1.5,
      ),
    );
  }

  /// Emits text spans for a fragment, injecting the IME preedit at the
  /// correct local offset if this fragment is the preedit anchor.
  void _emitFragmentSpans(
    List<InlineSpan> spans,
    String text,
    TextStyle style,
    String fragmentId,
    int fragmentLocalOffset,
    GestureRecognizer? recognizer,
  ) {
    final preeditHere = _imePreeditText.isNotEmpty &&
        _imePreeditFragmentId == fragmentId &&
        fragmentLocalOffset >= 0 &&
        fragmentLocalOffset <= text.length;
    if (!preeditHere) {
      spans.add(TextSpan(text: text, style: style, recognizer: recognizer));
      return;
    }
    final before = text.substring(0, fragmentLocalOffset);
    final after = text.substring(fragmentLocalOffset);
    if (before.isNotEmpty) {
      spans.add(TextSpan(text: before, style: style, recognizer: recognizer));
    }
    spans.add(_buildImePreeditSpan(style));
    if (after.isNotEmpty) {
      spans.add(TextSpan(text: after, style: style, recognizer: recognizer));
    }
  }

  TextSpan _buildTextSpanAndTrackPositions(
    InlineContainerNode container,
    List<Size> childSizes,
  ) {
    final spans = <InlineSpan>[];
    var currentOffset = 0;
    var placeholderIdx = 0;

    void processNode(FNode node, TextStyle? style) {
      switch (node) {
        case FluentList _:
          // Sublists: rendered separately, do not contribute to text
          break;

        case Link link:
          final linkStyle = TextStyle(
            color: _linkColor,
            decoration: TextDecoration.underline,
            decorationColor: _linkColor,
          );
          // Check if link contains images - if so, don't add gesture recognizer to allow image gestures
          final hasImages = link.getChildren().any((child) => child is FluentImage);
          
          // ignore: avoid_print
          void onLinkTap() => print('Link tapped: ${link.url}');
          final recognizer = hasImages ? null : (TapGestureRecognizer()..onTap = onLinkTap);

          for (final child in link.getChildren()) {
            if (child is FluentImage) {
              // Image inside a Link: WidgetSpan placeholder that occupies 1
              // char (the ZWS) to align with the caret stops rail. The real
              // drawing happens via the RenderBox children of the paragraph.
              final start = currentOffset;
              final end = currentOffset + child.text.length; // ZWS = 1
              _fragmentPositions.add(
                _FragmentPosition(id: child.id, start: start, end: end, isImage: true),
              );
              final childSize = placeholderIdx < childSizes.length
                  ? childSizes[placeholderIdx]
                  : const Size(1, 1);
              _placeholderDimensions.add(PlaceholderDimensions(
                size: childSize,
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
              ));
              spans.add(WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: SizedBox(width: childSize.width, height: childSize.height),
              ));
              placeholderIdx++;
              currentOffset = end;
            } else if (child is Fragment) {
              final text = child.renderText;
              final start = currentOffset;
              final end = currentOffset + text.length;
              _fragmentPositions.add(
                _FragmentPosition(id: child.id, start: start, end: end),
              );
              var effectiveStyle = linkStyle;
              final childStyles = child.styles;
              if (childStyles != null && childStyles.isNotEmpty) {
                if (childStyles.contains('bold')) {
                  effectiveStyle = effectiveStyle.copyWith(fontWeight: FontWeight.bold);
                }
                if (childStyles.contains('italic')) {
                  effectiveStyle = effectiveStyle.copyWith(fontStyle: FontStyle.italic);
                }
                if (childStyles.contains('underline')) {
                  effectiveStyle = effectiveStyle.copyWith(
                    decoration: TextDecoration.combine([
                      effectiveStyle.decoration ?? TextDecoration.none,
                      TextDecoration.underline,
                    ]),
                  );
                }
                if (childStyles.contains('strikethrough')) {
                  effectiveStyle = effectiveStyle.copyWith(
                    decoration: TextDecoration.combine([
                      effectiveStyle.decoration ?? TextDecoration.none,
                      TextDecoration.lineThrough,
                    ]),
                  );
                }
                if (childStyles.contains('smallcaps')) {
                  effectiveStyle = effectiveStyle.copyWith(
                    fontFeatures: [...(effectiveStyle.fontFeatures ?? []), const FontFeature.enable('smcp')],
                  );
                }
              }
              effectiveStyle = effectiveStyle.copyWith(
                fontFamily: _getEffectiveFontFamily(child),
                fontSize: _getEffectiveFontSize(child),
                color: ColorUtils.parseColor(child.color) ?? effectiveStyle.color,
                backgroundColor: ColorUtils.parseColor(child.highlightColor),
              );
              
              // Handle superscript/subscript: insert transparent text for space, paint with offset later
              if (childStyles != null && (childStyles.contains('superscript') || childStyles.contains('subscript'))) {
                final fontSize = effectiveStyle.fontSize ?? 14;
                final isSuperscript = childStyles.contains('superscript');
                // Ensure the style has a color (inherit from defaultTextColor if child.color is null)
                final scriptColor = effectiveStyle.color ?? defaultTextColor;
                final adjustedStyle = effectiveStyle.copyWith(
                  fontSize: fontSize * 0.65,
                  color: scriptColor,
                );
                // Insert transparent text so it occupies the right space
                final transparentStyle = adjustedStyle.copyWith(color: const Color(0x00000000));
                spans.add(
                  TextSpan(text: text, style: transparentStyle, recognizer: recognizer),
                );
                // Track for custom paint
                _scriptSpans.add(_ScriptSpanInfo(
                  globalStart: start,
                  globalEnd: end,
                  text: text,
                  style: adjustedStyle,
                  isSuperscript: isSuperscript,
                ));
              } else {
                _emitFragmentSpans(
                  spans, text, effectiveStyle, child.id,
                  child.id == _imePreeditFragmentId ? _imePreeditLocalOffset : 0,
                  recognizer,
                );
              }
              currentOffset = end;
            }
          }
          break;

        case FluentImage image:
          final start = currentOffset;
          final end = currentOffset + image.text.length; // ZWS = 1
          _fragmentPositions.add(
            _FragmentPosition(id: image.id, start: start, end: end, isImage: true),
          );
          final childSize = placeholderIdx < childSizes.length
              ? childSizes[placeholderIdx]
              : const Size(1, 1);
          _placeholderDimensions.add(PlaceholderDimensions(
            size: childSize,
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
          ));
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: SizedBox(width: childSize.width, height: childSize.height),
          ));
          placeholderIdx++;
          currentOffset = end;
          break;

        case InlineContainerNode container:
          for (final child in container.getChildren()) {
            processNode(child, style);
          }
          break;

        case Fragment fragment:
          final text = fragment.renderText;
          final start = currentOffset;
          final end = currentOffset + text.length;
          _fragmentPositions.add(
            _FragmentPosition(id: fragment.id, start: start, end: end),
          );
          TextStyle? effectiveStyle = style;
          final styles = _getEffectiveStyles(fragment);
          if (styles.isNotEmpty) {
            effectiveStyle = effectiveStyle ?? const TextStyle();
            if (styles.contains('bold')) {
              effectiveStyle = effectiveStyle.copyWith(fontWeight: FontWeight.bold);
            }
            if (styles.contains('italic')) {
              effectiveStyle = effectiveStyle.copyWith(fontStyle: FontStyle.italic);
            }
            if (styles.contains('underline')) {
              effectiveStyle = effectiveStyle.copyWith(decoration: TextDecoration.underline);
            }
            if (styles.contains('strikethrough')) {
              effectiveStyle = effectiveStyle.copyWith(
                decoration: TextDecoration.combine([
                  effectiveStyle.decoration ?? TextDecoration.none,
                  TextDecoration.lineThrough,
                ]),
              );
            }
            if (styles.contains('smallcaps')) {
              effectiveStyle = effectiveStyle.copyWith(
                fontFeatures: [...(effectiveStyle.fontFeatures ?? []), const FontFeature.enable('smcp')],
              );
            }
          }
          final fontFamily = _getEffectiveFontFamily(fragment);
          // Use fontFamily directly - fonts are bundled locally in assets/google_fonts/
          effectiveStyle = (effectiveStyle ?? const TextStyle()).copyWith(
            fontFamily: fontFamily,
            fontSize: _getEffectiveFontSize(fragment),
            color: ColorUtils.parseColor(fragment.color),
            backgroundColor: ColorUtils.parseColor(fragment.highlightColor),
          );

          // If underline or strikethrough is present but no explicit decoration color
          // is set, make the decoration inherit the text color.
          if (effectiveStyle.decoration != null &&
              effectiveStyle.decoration != TextDecoration.none &&
              effectiveStyle.decorationColor == null) {
            effectiveStyle = effectiveStyle.copyWith(
              decorationColor: effectiveStyle.color,
            );
          }

          // Handle superscript/subscript: insert transparent text for space, paint with offset later
          if (styles.contains('superscript') || styles.contains('subscript')) {
            final fontSize = effectiveStyle.fontSize ?? 14;
            final isSuperscript = styles.contains('superscript');
            final adjustedStyle = effectiveStyle.copyWith(fontSize: fontSize * 0.65);
            // Insert transparent text so it occupies the right space
            final transparentStyle = adjustedStyle.copyWith(color: const Color(0x00000000));
            spans.add(TextSpan(text: text, style: transparentStyle));
            // Track for custom paint
            _scriptSpans.add(_ScriptSpanInfo(
              globalStart: start,
              globalEnd: end,
              text: text,
              style: adjustedStyle,
              isSuperscript: isSuperscript,
            ));
          } else {
            _emitFragmentSpans(
              spans, text, effectiveStyle, fragment.id,
              fragment.id == _imePreeditFragmentId ? _imePreeditLocalOffset : 0,
              null,
            );
          }
          currentOffset = end;
          break;

        default:
          break;
      }
    }

    for (final child in container.getChildren()) {
      processNode(child, null);
    }

    return TextSpan(
      children: spans,
      style: TextStyle(height: lineHeight, color: _defaultTextColor),
    );
  }

  // ─── Local ↔ global conversions ─────────────────────────────────

  int? _localToGlobal(String fragmentId, int localOffset) {
    for (final pos in _fragmentPositions) {
      if (pos.id == fragmentId) {
        final global = pos.toGlobal(localOffset);
        if (global >= pos.start && global <= pos.end) return global;
        return null;
      }
    }
    return null;
  }

  ({String fragmentId, int localOffset})? _globalToLocal(int globalOffset) {
    for (final pos in _fragmentPositions) {
      if (pos.contains(globalOffset)) {
        return (fragmentId: pos.id, localOffset: pos.toLocal(globalOffset));
      }
    }

    // If the offset is beyond the last fragment, return the end of the last
    if (_fragmentPositions.isNotEmpty) {
      final lastPos = _fragmentPositions.last;
      final totalLength = _getTotalTextLength();
      if (globalOffset >= totalLength) {
        return (fragmentId: lastPos.id, localOffset: lastPos.textLength);
      }
    }

    return null;
  }

  /// Converts a local (fragment, offset) pair to a global offset within
  /// the paragraph text. Returns null if the fragment is not found.
  int? resolveGlobalOffset(String fragmentId, int localOffset) {
    return _localToGlobal(fragmentId, localOffset);
  }

  /// Returns the text boxes for a global offset range.
  /// Used by the comment plugin to determine the visual position of a comment.
  List<TextBox> getBoxesForGlobalRange(int start, int end) {
    return _painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
  }

  // ─── Hit testing (tap/click) ──────────────────────────────────────

  ({String fragmentId, int localOffset})? getFragmentAtPosition(
    Offset position,
  ) {
    // The TextPainter works in coordinates relative to the text (x=0).
    // Subtract the alignment offset to map the local position
    // of the render object to TextPainter coordinates.
    final adjustedPosition = position - Offset(_alignmentXOffset, 0);

    // FAST PATH: TextPainter.getPositionForOffset does a binary search
    // internally (O(log n)) and returns the closest text position. This
    // replaces the O(n) character-by-character loop that called
    // getBoxesForSelection once per character — a major bottleneck during
    // drag selection on long paragraphs (1000+ characters).
    final textPosition = _painter.getPositionForOffset(adjustedPosition);
    final result = _globalToLocal(textPosition.offset);
    if (result != null) return result;

    // FALLBACK: if getPositionForOffset returns an offset that does not
    // map to any fragment (should be rare), use line metrics to find the
    // nearest character on the target line.
    if (_lineMetricsDirty || _cachedLineMetrics == null) {
      _cachedLineMetrics = _painter.computeLineMetrics();
      _lineMetricsDirty = false;
    }
    final lineMetrics = _cachedLineMetrics!;
    if (lineMetrics.isEmpty) return null;

    int targetLine = lineMetrics.length - 1;
    for (int i = 0; i < lineMetrics.length; i++) {
      final line = lineMetrics[i];
      final lineTop = line.baseline - line.ascent;
      final lineBottom = line.baseline + line.descent;
      if (adjustedPosition.dy >= lineTop && adjustedPosition.dy <= lineBottom) {
        targetLine = i;
        break;
      }
      if (i == 0 && adjustedPosition.dy < lineTop) {
        targetLine = 0;
        break;
      }
    }

    final targetLineMetric = lineMetrics[targetLine];
    final targetLineY = targetLineMetric.baseline - targetLineMetric.ascent;
    final targetLineBottom =
        targetLineMetric.baseline + targetLineMetric.descent;

    String? bestFragmentId;
    int bestLocalOffset = 0;
    double bestXDistance = double.infinity;

    for (final fragment in _fragmentPositions) {
      for (int offset = 0; offset < fragment.textLength; offset++) {
        final globalOffset = fragment.start + offset;

        final boxes = _painter.getBoxesForSelection(
          TextSelection(
            baseOffset: globalOffset,
            extentOffset: globalOffset + 1,
          ),
        );
        if (boxes.isEmpty) continue;

        final box = boxes.first.toRect();
        final boxCenterY = (box.top + box.bottom) / 2;
        if (boxCenterY < targetLineY || boxCenterY > targetLineBottom) {
          continue;
        }

        if (box.contains(adjustedPosition)) {
          final isRightHalf = adjustedPosition.dx > (box.left + box.right) / 2;
          return (
            fragmentId: fragment.id,
            localOffset: isRightHalf ? offset + 1 : offset,
          );
        }

        final leftDistance = (adjustedPosition.dx - box.left).abs();
        final rightDistance = (adjustedPosition.dx - box.right).abs();

        if (leftDistance < bestXDistance) {
          bestXDistance = leftDistance;
          bestFragmentId = fragment.id;
          bestLocalOffset = offset;
        }
        if (rightDistance < bestXDistance) {
          bestXDistance = rightDistance;
          bestFragmentId = fragment.id;
          bestLocalOffset = offset + 1;
        }
      }
    }

    if (bestFragmentId != null) {
      return (fragmentId: bestFragmentId, localOffset: bestLocalOffset);
    }

    return null;
  }

  /// Returns the fragment-local start/end bounds of the text line that
  /// contains [offset] (in paragraph-local coordinates).
  /// Used by triple-tap to select an entire logical line in O(log n)
  /// without rebuilding the whole document tree.
  ({String startFrag, int startOff, String endFrag, int endOff})?
      getLineBoundsAtOffset(Offset offset) {
    final adjustedOffset = offset - Offset(_alignmentXOffset, 0);
    final textPosition = _painter.getPositionForOffset(adjustedOffset);
    final lineBoundary = _painter.getLineBoundary(textPosition);

    final startLocal = _globalToLocal(lineBoundary.start);
    if (startLocal == null) return null;
    final endLocal = _globalToLocal(lineBoundary.end);
    if (endLocal == null) return null;

    return (
      startFrag: startLocal.fragmentId,
      startOff: startLocal.localOffset,
      endFrag: endLocal.fragmentId,
      endOff: endLocal.localOffset,
    );
  }

  // ─── Cursor / Selection setters ───────────────────────────────────

  void setCursorOffsets(
    String anchorFragmentId,
    int anchorLocal,
    String? focusFragmentId,
    int? focusLocal,
  ) {
    _anchorFragmentId = anchorFragmentId;
    _anchorLocalOffset = anchorLocal;
    _focusFragmentId = focusFragmentId;
    _focusLocalOffset = focusLocal;
    markNeedsPaint();
  }

  void setSelectionRange(
    String? anchorFragmentId,
    int? anchorLocalOffset,
    String? focusFragmentId,
    int? focusLocalOffset,
  ) {
    // Skip repaint when the range is identical — crucial during key-hold
    // where _syncSelectionManager touches every visible paragraph but
    // only a few actually changed.
    if (_selAnchorFragmentId == anchorFragmentId &&
        _selAnchorLocalOffset == anchorLocalOffset &&
        _selFocusFragmentId == focusFragmentId &&
        _selFocusLocalOffset == focusLocalOffset) {
      return;
    }
    _selAnchorFragmentId = anchorFragmentId;
    _selAnchorLocalOffset = anchorLocalOffset;
    _selFocusFragmentId = focusFragmentId;
    _selFocusLocalOffset = focusLocalOffset;
    _cachedSelectionBoxes = null; // invalidate paint cache
    markNeedsPaint();
  }

  // ─── Paint ────────────────────────────────────────────────────────

  @override
  void paint(PaintingContext context, Offset offset) {
    final xOffset = _shrinkWrap
        ? 0.0
        : switch (_textAlign) {
            TextAlign.center => (_layoutMaxWidth - _painter.width) / 2,
            TextAlign.right => _layoutMaxWidth - _painter.width,
            _ => 0.0,
          };
    final alignedOffset = offset + Offset(xOffset, 0);

    // Build the static text Picture on first paint after layout.
    _cachedTextPicture ??= _buildTextPicture(alignedOffset);

    // 1. Selection "under" the text (classic look)
    _paintSelection(context.canvas, alignedOffset);
    // 1.5 Comment highlights (under the text)
    _paintCommentHighlights(context.canvas, alignedOffset);
    // 2. Text (cached Picture — avoids re-executing Skia text rasterisation)
    context.canvas.drawPicture(_cachedTextPicture!);
    // 3. Inline images (RenderBox children) above placeholders
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData as FluentInlineParentData;
      context.paintChild(child, alignedOffset + parentData.offset);
      child = parentData.nextSibling;
    }
    // 4. Selection overlay above images
    _paintSelectionOverlayOnImages(context.canvas, alignedOffset);
    // 5. Spell check wavy underline
    _paintSpellErrors(context.canvas, alignedOffset);
    // 6. Cursor on top of everything
    _paintCursor(context.canvas, alignedOffset);
  }

  /// Records the pure text + script spans into a [Picture] so they are
  /// rasterised once per layout instead of on every paint frame.
  Picture _buildTextPicture(Offset offset) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    _painter.paint(canvas, offset);
    _paintScriptSpans(canvas, offset);
    return recorder.endRecording();
  }

  /// Paints red wavy underlines for each spell annotation.
  /// Amplitude 2 px, wavelength 4 px, 1.5 px below the baseline.
  void _paintSpellErrors(Canvas canvas, Offset offset) {
    if (_spellAnnotations.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFFE53935)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    _cachedSpellBoxes ??= _spellAnnotations.map((ann) {
      return _painter.getBoxesForSelection(
        TextSelection(baseOffset: ann.startOffset, extentOffset: ann.endOffset),
      );
    }).toList();

    for (int i = 0; i < _spellAnnotations.length; i++) {
      final boxes = _cachedSpellBoxes![i];
      for (final box in boxes) {
        final rect = box.toRect().translate(offset.dx, offset.dy);
        final baselineY = rect.bottom + 1.5;
        final path = Path();
        const amplitude = 2.0;
        const wavelength = 4.0;
        var x = rect.left;
        path.moveTo(x, baselineY);
        while (x < rect.right) {
          x += wavelength / 2;
          final y = ((x ~/ wavelength) % 2 == 0) ? baselineY - amplitude : baselineY + amplitude;
          path.lineTo(x.clamp(rect.left, rect.right), y);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  /// Paints yellow/orange semi-transparent rectangles under commented text.
  void _paintCommentHighlights(Canvas canvas, Offset offset) {
    if (_commentAnnotations.isEmpty) return;

    _cachedCommentBoxes ??= _commentAnnotations.map((c) {
      final start = c['startOffset'] as int? ?? 0;
      final end = c['endOffset'] as int? ?? 0;
      if (start >= end) return const <TextBox>[];
      return _painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
    }).toList();

    for (int i = 0; i < _commentAnnotations.length; i++) {
      final c = _commentAnnotations[i];
      if (c['resolved'] == true) continue;
      final boxes = _cachedCommentBoxes![i];
      if (boxes.isEmpty) continue;

      final isSelected = _selectedCommentId != null && c['id'] == _selectedCommentId;
      final baseColor = isSelected ? Colors.orange : Colors.yellow;
      final paint = Paint()
        ..color = baseColor.withAlpha((0.35 * 255).round())
        ..style = PaintingStyle.fill;

      for (final box in boxes) {
        final rect = box.toRect().translate(offset.dx, offset.dy);
        canvas.drawRect(rect.inflate(1), paint);
      }
    }
  }

  /// Paints superscript/subscript fragments with vertical offset.
  void _paintScriptSpans(Canvas canvas, Offset offset) {
    for (final info in _scriptSpans) {
      // Find the position of the first character of the span in TextPainter
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: info.globalStart, extentOffset: info.globalEnd),
      );
      if (boxes.isEmpty) continue;

      final box = boxes.first;
      final fontSize = info.style.fontSize ?? 14;
      // Superscript: shift up; Subscript: shift down
      final yShift = info.isSuperscript ? -(fontSize * 0.45) : (fontSize * 0.25);
      
      // Ensure the style has a color
      final scriptColor = info.style.color ?? defaultTextColor;
      final scriptStyle = info.style.copyWith(color: scriptColor);
      
      final tp = TextPainter(
        text: TextSpan(text: info.text, style: scriptStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      
      tp.paint(canvas, Offset(box.left + offset.dx, box.top + offset.dy + yShift));
      tp.dispose();
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  int? _fragmentOffsetToGlobal(String fragmentId, int localOffset) {
    for (final pos in _fragmentPositions) {
      if (pos.id == fragmentId) {
        final effectiveOffset =
            (localOffset < 0 || localOffset > pos.textLength)
            ? pos.textLength
            : localOffset;
        final global = pos.start + effectiveOffset;
        if (global >= pos.start && global <= pos.end) return global;
      }
    }
    return null;
  }

  void _paintSelection(Canvas canvas, Offset offset) {
    if (_selAnchorFragmentId == null ||
        _selAnchorLocalOffset == null ||
        _selFocusFragmentId == null ||
        _selFocusLocalOffset == null) {
      return;
    }

    int? baseGlobal = _selAnchorFragmentId!.isEmpty
        ? 0
        : _fragmentOffsetToGlobal(
            _selAnchorFragmentId!,
            _selAnchorLocalOffset!,
          );

    int? extentGlobal =
        (_selFocusFragmentId!.isEmpty || _selFocusLocalOffset == -1)
        ? _getTotalTextLength()
        : _fragmentOffsetToGlobal(_selFocusFragmentId!, _selFocusLocalOffset!);

    if (baseGlobal == null || extentGlobal == null) {
      return;
    }

    final start = baseGlobal < extentGlobal ? baseGlobal : extentGlobal;
    final end = baseGlobal < extentGlobal ? extentGlobal : baseGlobal;

    final key = (aFrag: _selAnchorFragmentId, aOff: _selAnchorLocalOffset,
                 fFrag: _selFocusFragmentId, fOff: _selFocusLocalOffset);
    if (_cachedSelectionBoxes == null || _lastSelectionKey != key) {
      _lastSelectionKey = key;
      _cachedSelectionBoxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
    }

    final selectionPaint = Paint()..color = selectionColor;
    for (final box in _cachedSelectionBoxes!) {
      canvas.drawRect(
        box.toRect().translate(offset.dx, offset.dy),
        selectionPaint,
      );
    }
  }

  /// Semi-transparent blue overlay above inline images that fall within
  /// the current selection. Necessary because the paint of children overwrites
  /// the base highlight drawn by `_paintSelection`.
  void _paintSelectionOverlayOnImages(Canvas canvas, Offset offset) {
    if (_selAnchorFragmentId == null ||
        _selAnchorLocalOffset == null ||
        _selFocusFragmentId == null ||
        _selFocusLocalOffset == null) {
      return;
    }

    int? baseGlobal = _selAnchorFragmentId!.isEmpty
        ? 0
        : _fragmentOffsetToGlobal(_selAnchorFragmentId!, _selAnchorLocalOffset!);
    int? extentGlobal =
        (_selFocusFragmentId!.isEmpty || _selFocusLocalOffset == -1)
            ? _getTotalTextLength()
            : _fragmentOffsetToGlobal(_selFocusFragmentId!, _selFocusLocalOffset!);
    if (baseGlobal == null || extentGlobal == null) return;

    final start = baseGlobal < extentGlobal ? baseGlobal : extentGlobal;
    final end = baseGlobal < extentGlobal ? extentGlobal : baseGlobal;

    final placeholderBoxes = _painter.inlinePlaceholderBoxes ?? const [];
    final inlineImages = collectInlineImages(_container);

    // The order of placeholderBoxes matches that of inlineImages.
    final overlayPaint = Paint()
      ..color = selectionColor.withValues(alpha: 0.4);
    for (var i = 0; i < placeholderBoxes.length && i < inlineImages.length; i++) {
      // Find the global position of the image
      final imgId = inlineImages[i].id;
      _FragmentPosition? pos;
      for (final p in _fragmentPositions) {
        if (p.id == imgId) { pos = p; break; }
      }
      if (pos == null) continue;
      // If the placeholder is entirely inside the selection
      if (pos.start >= start && pos.end <= end) {
        canvas.drawRect(
          placeholderBoxes[i].toRect().translate(offset.dx, offset.dy),
          overlayPaint,
        );
      }
    }
  }

  int _getTotalTextLength() {
    var length = 0;
    for (final pos in _fragmentPositions) {
      length += pos.end - pos.start;
    }
    return length;
  }

  void _paintCursor(Canvas canvas, Offset offset) {
    String fragmentId;
    int localOffset;
    int? focusGlobal;
    if (_focusFragmentId != null && _focusLocalOffset != null) {
      fragmentId = _focusFragmentId!;
      localOffset = _focusLocalOffset!;
      focusGlobal = _localToGlobal(fragmentId, localOffset);
    } else {
      fragmentId = _anchorFragmentId;
      localOffset = _anchorLocalOffset;
      focusGlobal = _localToGlobal(fragmentId, localOffset);
    }

    if (focusGlobal == null || focusGlobal < 0) return;

    // Blink: the editor's periodic timer toggles registry.caretVisible and
    // resets it to true on movement. Skip painting while in the hidden phase.
    if (!registry.caretVisible) return;

    // If the cursor is on an inline image, draw vertical lines at the borders
    // of the placeholder instead of the thin text line.
    _FragmentPosition? fragPos;
    for (final p in _fragmentPositions) {
      if (p.id == fragmentId) {
        fragPos = p;
        break;
      }
    }
    if (fragPos != null && fragPos.isImage) {
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: fragPos.start, extentOffset: fragPos.end),
      );
      if (boxes.isNotEmpty) {
        final box = boxes.first.toRect();
        final cursorX = localOffset == 0 ? box.left : box.right;
        final cursorPaint = Paint()
          ..color = cursorColor
          ..strokeWidth = 3.0;
        canvas.drawLine(
          Offset(offset.dx + cursorX, offset.dy + box.top),
          Offset(offset.dx + cursorX, offset.dy + box.bottom),
          cursorPaint,
        );
        return;
      }
    }

    // Use the character box to correctly position the cursor
    // both in height and vertically, adapting to the real font size.
    TextBox? charBox;
    final textLength = _painter.text?.toPlainText().length ?? 0;
    if (focusGlobal > 0 && focusGlobal <= textLength) {
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: focusGlobal - 1, extentOffset: focusGlobal),
      );
      if (boxes.isNotEmpty) charBox = boxes.first;
    } else if (focusGlobal == 0 && textLength > 0) {
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: 1),
      );
      if (boxes.isNotEmpty) charBox = boxes.first;
    }

    final cursorPaint = Paint()
      ..color = cursorColor
      ..strokeWidth = 2.0;

    if (charBox != null) {
      final cursorX = focusGlobal == 0 ? charBox.left : charBox.right;
      canvas.drawLine(
        Offset(offset.dx + cursorX, offset.dy + charBox.top),
        Offset(offset.dx + cursorX, offset.dy + charBox.bottom),
        cursorPaint,
      );
      return;
    }

    // Fallback for empty document
    final cursorOffset = _painter.getOffsetForCaret(
      TextPosition(offset: focusGlobal),
      Rect.zero,
    );
    final cursorHeight = _painter.preferredLineHeight;
    canvas.drawLine(
      Offset(offset.dx + cursorOffset.dx, offset.dy + cursorOffset.dy),
      Offset(
        offset.dx + cursorOffset.dx,
        offset.dy + cursorOffset.dy + cursorHeight,
      ),
      cursorPaint,
    );
  }

  @override
  bool hitTestSelf(Offset position) => true;
}
