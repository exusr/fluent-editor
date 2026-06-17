// paragraph_registry.dart
//
// Global registry of active RenderFluentParagraph.
// Each render object auto-registers in attach() and removes itself in detach().
// The registry is owned by FluentDocument, which is already accessible
// anywhere in the widget tree without InheritedWidget.

import 'package:flutter/rendering.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/renderers/render_paragraph.dart';

/// Registry of active RenderFluentParagraph in the tree.
/// Key = containerId (the id of the InlineContainerNode: Paragraph, ListItem, FluentCell).
class ParagraphRegistry {
  final Map<String, RenderFluentParagraph> _renders = {};

  /// HR render boxes keyed by node id, so vertical navigation can resolve
  /// their y-coordinate even though they are not RenderFluentParagraph.
  final Map<String, RenderBox> _hrRenders = {};

  /// Container IDs whose paragraphs are currently inside the viewport
  /// (or within the ListView cache). Updated by the virtualized builder.
  final Set<String> _visibleContainerIds = <String>{};

  /// Current caret blink phase. The render that owns the caret paints it only
  /// when this is true. Toggled by the editor's blink timer and forced to
  /// true on cursor movement so the caret restarts visible.
  bool caretVisible = true;

  /// Direct (non-copying) lookup of the render registered for [containerId].
  RenderFluentParagraph? renderFor(String containerId) => _renders[containerId];

  /// Mark a container as visible (called from the virtualized item builder).
  void markVisible(String containerId) => _visibleContainerIds.add(containerId);

  /// Mark a container as no longer visible (called on item disposal / recycle).
  void markInvisible(String containerId) => _visibleContainerIds.remove(containerId);

  /// Iterates only the renders whose containers are currently in view.
  /// Used by selection sync to avoid an O(n) scan over every paragraph in the
  /// document, reducing the per-frame cost to O(visible) on key-hold.
  Iterable<MapEntry<String, RenderFluentParagraph>> get visibleRenders sync* {
    for (final id in _visibleContainerIds) {
      final render = _renders[id];
      if (render != null) yield MapEntry(id, render);
    }
  }

  // ─── Lifecycle called by RenderObject ─────────────────────────

  void register(String containerId, RenderFluentParagraph render) {
    _renders[containerId] = render;
  }

  /// Removes [render] from the registry ONLY if it is actually the one
  /// currently registered for [containerId]. This prevents that, during
  /// reparenting of a node with the same id (e.g. outdent of a ListItem
  /// that reuses the Paragraph), the late detach of the old render deletes
  /// the entry of the new render already registered, making the node unresolvable.
  void unregister(String containerId, RenderFluentParagraph render) {
    if (identical(_renders[containerId], render)) {
      _renders.remove(containerId);
    }
  }

  // ─── HR lifecycle ─────────────────────────────────────────

  void registerHR(String nodeId, RenderBox render) {
    _hrRenders[nodeId] = render;
  }

  void unregisterHR(String nodeId, RenderBox render) {
    if (identical(_hrRenders[nodeId], render)) {
      _hrRenders.remove(nodeId);
    }
  }

  // ─── Public resolver ───────────────────────────────────────────

  /// Returns the global x coordinate (in logical pixels) of the caret
  /// for the given [stop]. Iterates the renders until one recognizes the fragmentId.
  ///
  /// Returns 0.0 if no render knows the fragment (e.g.: layout not
  /// yet happened — in that case preferredX will remain -1.0 and will be
  /// recalculated at the next vertical movement).
  ///
  /// OPTIMISATION: visible renders are checked first because during
  /// arrow-key navigation the target fragment is almost always inside
  /// the current or a neighbouring visible paragraph.
  double resolveCaretX(CaretStop stop) {
    // 1. Check visible paragraph renders first (O(visible), usually ~20)
    for (final id in _visibleContainerIds) {
      final render = _renders[id];
      if (render != null) {
        final x = render.getCaretX(stop.fragmentId, stop.offset);
        if (x != null) return x;
      }
    }
    // 2. HR renders — HR stops use the node id as fragmentId.
    // Return the center X so vertical navigation lands in the middle.
    final hrRender = _hrRenders[stop.fragmentId];
    if (hrRender != null && hrRender.attached && hrRender.hasSize) {
      final box = hrRender.localToGlobal(Offset.zero);
      return box.dx + hrRender.size.width / 2;
    }
    // 3. Fall back to all paragraph renders (rare, e.g. after scroll)
    for (final render in _renders.values) {
      final x = render.getCaretX(stop.fragmentId, stop.offset);
      if (x != null) return x;
    }
    return 0.0;
  }

  double resolveCaretY(CaretStop stop) {
    // 1. Paragraph renders (visible first)
    for (final id in _visibleContainerIds) {
      final render = _renders[id];
      if (render != null) {
        final y = render.getCaretY(stop.fragmentId, stop.offset);
        if (y != null) return y;
      }
    }
    // 2. HR renders — HR stops use the node id as fragmentId
    final hrRender = _hrRenders[stop.fragmentId];
    if (hrRender != null && hrRender.attached && hrRender.hasSize) {
      return hrRender.localToGlobal(Offset.zero).dy;
    }
    // 3. All paragraph renders fallback
    for (final render in _renders.values) {
      final y = render.getCaretY(stop.fragmentId, stop.offset);
      if (y != null) return y;
    }
    return 0.0;
  }

  /// Returns the global screen [Rect] of the caret for [fragmentId]/[offset].
  /// Returns null if the fragment's render object is not currently in the tree.
  Rect? resolveCaretScreenRect(String fragmentId, int offset) {
    for (final id in _visibleContainerIds) {
      final render = _renders[id];
      if (render != null) {
        final rect = render.getCaretScreenRect(fragmentId, offset);
        if (rect != null) return rect;
      }
    }
    for (final render in _renders.values) {
      final rect = render.getCaretScreenRect(fragmentId, offset);
      if (rect != null) return rect;
    }
    return null;
  }

  /// Finds the rendered paragraph whose global bounds vertically contain
  /// [globalY]; if none contains it, returns the vertically nearest one.
  ///
  /// Iterates only the currently rendered paragraphs (bounded by the viewport
  /// + ListView cache), so it is O(visible) — used by drag selection to do
  /// precise hit testing without an O(n) scan over the whole document.
  ({String id, RenderFluentParagraph render})? paragraphAtGlobalY(double globalY) {
    RenderFluentParagraph? best;
    String? bestId;
    double bestDist = double.infinity;

    for (final entry in _renders.entries) {
      final render = entry.value;
      if (!render.attached || !render.hasSize) continue;
      final top = render.localToGlobal(Offset.zero).dy;
      final bottom = top + render.size.height;

      final double dist;
      if (globalY >= top && globalY <= bottom) {
        dist = 0.0;
      } else if (globalY < top) {
        dist = top - globalY;
      } else {
        dist = globalY - bottom;
      }

      if (dist < bestDist) {
        bestDist = dist;
        best = render;
        bestId = entry.key;
        if (dist == 0.0) break; // exact vertical hit, cannot do better
      }
    }

    if (best == null || bestId == null) return null;
    return (id: bestId, render: best);
  }

  /// Diagnostic: number of currently registered renders.
  int get registeredCount => _renders.length;

  /// Public read-only access to the registered render objects.
  /// Key = containerId, Value = the active RenderFluentParagraph.
  Map<String, RenderFluentParagraph> get renders => Map.unmodifiable(_renders);
}
