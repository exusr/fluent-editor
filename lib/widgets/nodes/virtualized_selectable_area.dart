import 'dart:io' show Platform;
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/renderers/render_paragraph.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Virtualized version of FluentSelectableArea that works with ListView.builder
/// Uses calculated positions instead of RenderBox hit testing for performance
class VirtualizedSelectableArea extends StatefulWidget {
  const VirtualizedSelectableArea({
    super.key,
    required this.document,
    required this.itemCount,
    required this.itemBuilder,
    this.scrollController,
    this.onHeightsChanged,
  });

  final FluentDocument document;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final ScrollController? scrollController;
  final ValueChanged<Map<int, double>>? onHeightsChanged;

  @override
  State<VirtualizedSelectableArea> createState() => _VirtualizedSelectableAreaState();
}

class _VirtualizedSelectableAreaState extends State<VirtualizedSelectableArea> {
  bool _isSelecting = false;
  Offset? _pointerDownPosition;
  final ScrollController _internalScrollController = ScrollController();

  ScrollController get _scrollController =>
      widget.scrollController ?? _internalScrollController;

  // ─── Mobile-web gesture detection ─────────────────────────
  /// Tracks the gesture state for distinguishing tap / scroll / drag.
  bool _isDragging = false;
  bool _isScrolling = false;
  Timer? _tapTimer;
  Timer? _longPressTimer;
  
  /// Threshold for drag (selection) vs scroll detection
  static const _kDragThreshold = 10.0;
  /// Timeout for tap detection
  static const _kTapTimeout = Duration(milliseconds: 250);
  /// Timeout for long-press detection (scroll mode on web-mobile)
  static const _kLongPressTimeout = Duration(milliseconds: 400);

  // Performance optimizations for large documents
  final Map<int, double> _itemHeights = {};
  double _averageItemHeight = 40.0;
  // Running sum of measured heights, kept in sync incrementally so the
  // average is computed in O(1) instead of O(n) on every measurement.
  double _heightSum = 0.0;

  // Cumulative height cache for O(log n) lookups
  final List<double> _cumulativeHeights = [];
  bool _cumulativeHeightsDirty = true;

  // Selection optimization: throttle updates and cache results
  _FragmentHitResult? _lastSelectionResult;
  Offset? _lastSelectionPosition;
  Timer? _selectionUpdateTimer;

  @override
  void dispose() {
    _selectionUpdateTimer?.cancel();
    _tapTimer?.cancel();
    if (widget.scrollController == null) {
      _internalScrollController.dispose();
    }
    super.dispose();
  }

  /// Returns true on native mobile (Android/iOS) or on web.
  bool _isMobilePlatform() {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS;
  }

  // ─── Raw pointer handlers (work on mobile-web where GestureDetector
  //     is starved by the browser's native scroll). ─────────────────

  void _onPointerDown(PointerDownEvent event) {
    // Ignore pointer events while resizing images
    if (widget.document.isResizingImage) return;

    // Commit any active IME composition before processing pointer events
    // so that selection/cursor movement cannot occur while preedit text
    // is still uncommitted.
    if (widget.document.imeHandler.isComposing) {
      widget.document.imeHandler.commitIfComposing();
    }

    _pointerDownPosition = event.position;
    _isDragging = false;
    _isSelecting = false;
    _isScrolling = false;

    // Cancel any pending timers
    _tapTimer?.cancel();
    _longPressTimer?.cancel();
    
    // Start tap timer for keyboard activation
    _tapTimer = Timer(_kTapTimeout, () {
      // Timer expired while finger is still down → possible long-press
    });
    
    // On mobile (native and web), start long-press timer for scroll mode.
    // If user holds without moving much, we enter scroll mode (close keyboard).
    if (_isMobilePlatform()) {
      _longPressTimer = Timer(_kLongPressTimeout, () {
        if (!_isDragging && _pointerDownPosition != null) {
          // Long press without drag → enter scroll mode
          _isScrolling = true;
          // Close keyboard to allow smooth scrolling
          _dismissKeyboard();
        }
      });
    }
  }
  
  /// Dismisses the virtual keyboard on mobile platforms
  void _dismissKeyboard() {
    if (_isMobilePlatform()) {
      // Remove focus from any text field to close keyboard
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    // Ignore pointer events while resizing images
    if (widget.document.isResizingImage) return;
    
    final downPos = _pointerDownPosition;
    if (downPos == null) return;

    final distance = (event.position - downPos).distance;

    if (!_isDragging && !_isScrolling && distance > _kDragThreshold) {
      // Finger moved past threshold before long-press timeout
      // Cancel long-press timer as this is either drag or scroll
      _longPressTimer?.cancel();
      
      // On mobile with vertical movement, prefer scroll over selection
      // when the movement is predominantly vertical
      final dx = (event.position.dx - downPos.dx).abs();
      final dy = (event.position.dy - downPos.dy).abs();
      
      if (_isMobilePlatform() && dy > dx * 1.5) {
        // Predominantly vertical movement on mobile → scroll mode
        _isScrolling = true;
        _dismissKeyboard();
        return; // Don't block scroll, let ListView handle it
      }
      
      // Diagonal or horizontal movement → drag selection
      _isDragging = true;
      _tapTimer?.cancel();
      setState(() {});
      _startSelectionAt(downPos);
    }

    if (_isDragging && _isSelecting) {
      _scheduleSelectionUpdate(event.position);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    // Ignore pointer events while resizing images (but still clean up)
    if (widget.document.isResizingImage) {
      _tapTimer?.cancel();
      _longPressTimer?.cancel();
      _isDragging = false;
      _isScrolling = false;
      _isSelecting = false;
      _pointerDownPosition = null;
      return;
    }
    
    _tapTimer?.cancel();
    _longPressTimer?.cancel();

    if (!_isDragging && !_isScrolling) {
      // It was a tap (finger never moved past the threshold).
      _handleTapAt(event.position);
    }

    final wasDragging = _isDragging;
    final wasScrolling = _isScrolling;

    // Clean-up shared state.
    _isDragging = false;
    _isScrolling = false;
    _isSelecting = false;
    _pointerDownPosition = null;
    _selectionUpdateTimer?.cancel();
    _lastSelectionResult = null;
    _lastSelectionPosition = null;

    if (wasDragging) {
      setState(() {});
      // Sync the IME buffer with the new selection so the platform IME
      // knows about the selected range. Without this, the buffer remains
      // stale from the previous typing session and IME suggestions produce
      // incorrect text (e.g., inserting content from the old paragraph).
      widget.document.cursorOnlyUpdate();
      // Open keyboard after drag selection on mobile.
      if (_isMobilePlatform()) {
        widget.document.requestMobileKeyboardFocus(context);
      }
    } else if (wasScrolling) {
      // After scroll, don't automatically reopen keyboard
      // User can tap to edit when ready
      setState(() {});
    }
  }
  
  /// Prevents browser's default context menu on web
  void _onPointerCancel(PointerCancelEvent event) {
    _tapTimer?.cancel();
    _longPressTimer?.cancel();
    _isDragging = false;
    _isScrolling = false;
    _pointerDownPosition = null;
  }

  // ─── Selection helpers (used by both raw-pointer and gesture paths) ─

  void _handleTapAt(Offset position) {
    widget.document.requestEditorFocus();
    final result = _findFragmentAtPosition(position);
    if (result != null) {
      widget.document.selectionManager.clear();
      widget.document.cursor.moveTo(result.fragmentId, result.localOffset);
      widget.document.cursorOnlyUpdate();
      if (_isMobilePlatform()) {
        widget.document.requestMobileKeyboardFocus(context);
      }
    }
  }

  void _startSelectionAt(Offset position) {
    widget.document.requestEditorFocus();
    final result = _findFragmentAtPosition(position);
    if (result != null) {
      _isSelecting = true;
      widget.document.selectionManager.startSelection(
        result.nodeId,
        result.fragmentId,
        result.localOffset,
      );
      widget.document.cursor.moveTo(result.fragmentId, result.localOffset);
    }
  }

  void _scheduleSelectionUpdate(Offset position) {
    _selectionUpdateTimer?.cancel();

    if (_lastSelectionPosition != null) {
      final distance = (position - _lastSelectionPosition!).distance;
      if (distance < 5.0) return;
    }

    _selectionUpdateTimer = Timer(const Duration(milliseconds: 16), () {
      _performSelectionUpdate(position);
    });
  }

  void _performSelectionUpdate(Offset position) {
    final result = _findFragmentAtPosition(position);
    if (result != null) {
      if (_lastSelectionResult == null ||
          _lastSelectionResult!.nodeId != result.nodeId ||
          _lastSelectionResult!.fragmentId != result.fragmentId ||
          _lastSelectionResult!.localOffset != result.localOffset) {
        _lastSelectionResult = result;
        _lastSelectionPosition = position;

        widget.document.selectionManager.updateFocus(
          result.nodeId,
          result.fragmentId,
          result.localOffset,
        );
        widget.document.cursor.focusTo(result.fragmentId, result.localOffset);
      }
    }
  }

  /// Finds the fragment at a position using optimized coordinates
  _FragmentHitResult? _findFragmentAtPosition(Offset globalPosition) {
    // FAST PRECISE PATH: the pointer is almost always over a currently
    // rendered paragraph. Hit-test directly against the (few) rendered
    // paragraphs via the registry — O(visible) and precise — bypassing the
    // O(n) cumulative-height estimate entirely. This is the hot path during
    // drag selection on huge documents.
    final hit = widget.document.paragraphRegistry
        .paragraphAtGlobalY(globalPosition.dy);
    if (hit != null) {
      final box = hit.render;
      final res = box.getFragmentAtPosition(box.globalToLocal(globalPosition));
      if (res != null) {
        return _FragmentHitResult(
          nodeId: hit.id,
          fragmentId: res.fragmentId,
          localOffset: res.localOffset,
        );
      }
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    final localPosition = renderBox.globalToLocal(globalPosition);
    
    // Use optimized binary search for item index estimation
    final estimatedItemIndex = _estimateItemIndex(localPosition.dy);
    if (estimatedItemIndex < 0 || estimatedItemIndex >= widget.itemCount) {
      return null;
    }

    // PRECISE PATH (preferred): if the estimated item is currently rendered,
    // use its RenderBox for exact fragment/offset hit testing. We also probe
    // the immediate neighbours because the height estimate can be off by one.
    for (final index in _candidateIndices(estimatedItemIndex)) {
      final precise = _preciseHitTest(index, globalPosition);
      if (precise != null) return precise;
    }

    // FALLBACK: the target item is not rendered (off-screen). Use the
    // coordinate-based heuristic so the selection still anchors somewhere
    // reasonable until the item scrolls into view.
    return _calculateVirtualizedHitResult(estimatedItemIndex, localPosition);
  }

  /// Returns the estimated index plus its direct neighbours, clamped to the
  /// valid range, to compensate for small height-estimation errors.
  Iterable<int> _candidateIndices(int estimated) sync* {
    for (final delta in const [0, 1, -1]) {
      final i = estimated + delta;
      if (i >= 0 && i < widget.itemCount) yield i;
    }
  }

  /// Exact hit test against a rendered item's RenderBox. Returns null when the
  /// item is not rendered or the point falls outside its bounds.
  _FragmentHitResult? _preciseHitTest(int index, Offset globalPosition) {
    final node = widget.document.content.nodes[index];
    final keyCtx = widget.document.getKeyForNode(node.id).currentContext;
    final box = keyCtx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;

    final nodeLocalPosition = box.globalToLocal(globalPosition);

    // Precise text hit testing for paragraphs/links.
    if (box is RenderFluentParagraph) {
      final result = box.getFragmentAtPosition(nodeLocalPosition);
      if (result != null) {
        return _FragmentHitResult(
          nodeId: node.id,
          fragmentId: result.fragmentId,
          localOffset: result.localOffset,
        );
      }
    }

    // Non-text node: only accept the hit if the point is inside its bounds.
    if (nodeLocalPosition.dx >= 0 &&
        nodeLocalPosition.dx <= box.size.width &&
        nodeLocalPosition.dy >= 0 &&
        nodeLocalPosition.dy <= box.size.height) {
      final offset = nodeLocalPosition.dx < box.size.width / 2 ? 0 : 1;
      return _FragmentHitResult(
        nodeId: node.id,
        fragmentId: node.id,
        localOffset: offset,
      );
    }

    return null;
  }

  /// Estimates which item index corresponds to a Y position
  /// Optimized with binary search for O(log n) performance
  int _estimateItemIndex(double yPosition) {
    if (yPosition < 0) return 0;
    
    _updateCumulativeHeightsIfNeeded();
    
    // Binary search in cumulative heights for O(log n) performance
    int left = 0;
    int right = _cumulativeHeights.length - 1;
    
    while (left < right) {
      final mid = (left + right + 1) ~/ 2;
      if (_cumulativeHeights[mid] <= yPosition) {
        left = mid;
      } else {
        right = mid - 1;
      }
    }
    
    return left.clamp(0, widget.itemCount - 1);
  }

  /// Updates cumulative heights cache when needed
  void _updateCumulativeHeightsIfNeeded() {
    if (!_cumulativeHeightsDirty) return;
    
    _cumulativeHeights.clear();
    double cumulative = 0.0;
    
    for (int i = 0; i < widget.itemCount; i++) {
      final height = _itemHeights[i] ?? _averageItemHeight;
      cumulative += height;
      _cumulativeHeights.add(cumulative);
    }
    
    _cumulativeHeightsDirty = false;
  }

  /// Updates the cached height for an item when it's rendered.
  /// Keeps the running sum/average in O(1) and skips no-op updates so the
  /// cumulative cache is not needlessly invalidated during scrolling.
  void _updateItemHeight(int index, double height) {
    if (height <= 0) return;
    final existing = _itemHeights[index];
    // Ignore sub-pixel changes: avoids invalidating caches on every frame.
    if (existing != null && (existing - height).abs() < 0.5) return;
    if (existing != null) _heightSum -= existing;
    _itemHeights[index] = height;
    _heightSum += height;
    _averageItemHeight = _heightSum / _itemHeights.length;
    _cumulativeHeightsDirty = true;
    widget.onHeightsChanged?.call(Map.unmodifiable(_itemHeights));
  }

  /// Fallback method for virtualized nodes without RenderBox
  _FragmentHitResult? _calculateVirtualizedHitResult(int itemIndex, Offset localPosition) {
    if (itemIndex < 0 || itemIndex >= widget.itemCount) return null;
    
    final node = widget.document.content.nodes[itemIndex];
    
    // For paragraphs, try to find a valid fragment
    if (node is Paragraph && node.fragments.isNotEmpty) {
      final fragment = node.fragments.first;
      // Calculate offset based on horizontal position
      final offset = localPosition.dx > 100 ? 1 : 0; // Simple heuristic
      return _FragmentHitResult(
        nodeId: node.id,
        fragmentId: fragment.id,
        localOffset: offset,
      );
    }
    
    // For other node types, use the node itself as fragment
    return _FragmentHitResult(
      nodeId: node.id,
      fragmentId: node.id,
      localOffset: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    // When image resize is active, disable text selection cursor and scroll
    final isResizeActive = widget.document.isResizingImage;
    
    return MouseRegion(
      cursor: isResizeActive ? SystemMouseCursors.basic : SystemMouseCursors.text,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: ListView.builder(
          controller: _scrollController,
          physics: (isResizeActive || _isDragging) 
              ? const NeverScrollableScrollPhysics() 
              : null,
          itemCount: widget.itemCount,
          itemBuilder: (context, index) {
            // Wrap each item to measure its actual height (only fires when
            // the size actually changes, see MeasureSize).
            return _VisibilityTracker(
              document: widget.document,
              index: index,
              child: MeasureSize(
                onChange: (size) => _updateItemHeight(index, size.height),
                child: widget.itemBuilder(context, index),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Tracks whether a virtualized item is currently inside the viewport (or
/// within the ListView cache) and reports its container id to the paragraph
/// registry.  ListView.builder mounts/unmounts this widget exactly when the
/// item enters/leaves the viewport, so the registry always knows which
/// paragraphs are visible without an expensive scroll-computation pass.
class _VisibilityTracker extends StatefulWidget {
  const _VisibilityTracker({
    required this.document,
    required this.index,
    required this.child,
  });

  final FluentDocument document;
  final int index;
  final Widget child;

  @override
  State<_VisibilityTracker> createState() => _VisibilityTrackerState();
}

class _VisibilityTrackerState extends State<_VisibilityTracker> {
  late String? _containerId;

  @override
  void initState() {
    super.initState();
    _containerId = _computeContainerId();
    if (_containerId != null) {
      widget.document.paragraphRegistry.markVisible(_containerId!);
    }
  }

  @override
  void dispose() {
    if (_containerId != null) {
      widget.document.paragraphRegistry.markInvisible(_containerId!);
    }
    super.dispose();
  }

  /// Computes the logical container id (Paragraph/ListItem/Cell) for the
  /// top-level node at [index].  For non-text nodes there is no paragraph
  /// render to track.
  String? _computeContainerId() {
    if (widget.index < 0 ||
        widget.index >= widget.document.content.nodes.length) {
      return null;
    }
    final node = widget.document.content.nodes[widget.index];
    if (node is InlineContainerNode) return node.id;
    // Tables and lists have nested containers; we do not track them at
    // the top-level because their paragraphs register themselves.
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Widget that reports its child's size, but only when it actually changes.
/// Implemented as a RenderObject (RenderProxyBox) so measurement happens
/// during layout instead of scheduling a post-frame callback on every frame,
/// which was a major bottleneck while scrolling large documents.
class MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChange;

  const MeasureSize({
    super.key,
    required this.onChange,
    required Widget child,
  }) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _MeasureSizeRenderObject(onChange);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _MeasureSizeRenderObject).onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    if (_oldSize != newSize) {
      _oldSize = newSize;
      // Defer the callback: mutating state during layout is not allowed.
      WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize));
    }
  }
}

class _FragmentHitResult {
  final String nodeId;
  final String fragmentId;
  final int localOffset;
  
  _FragmentHitResult({
    required this.nodeId,
    required this.fragmentId,
    required this.localOffset,
  });
}
