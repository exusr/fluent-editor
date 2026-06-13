// paragraph_registry.dart
//
// Global registry of active RenderFluentParagraph.
// Each render object auto-registers in attach() and removes itself in detach().
// The registry is owned by FluentDocument, which is already accessible
// anywhere in the widget tree without InheritedWidget.

import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/renderers/render_paragraph.dart';

/// Registry of active RenderFluentParagraph in the tree.
/// Key = containerId (the id of the InlineContainerNode: Paragraph, ListItem, FluentCell).
class ParagraphRegistry {
  final Map<String, RenderFluentParagraph> _renders = {};

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

  // ─── Public resolver ───────────────────────────────────────────

  /// Returns the global x coordinate (in logical pixels) of the caret
  /// for the given [stop]. Iterates the renders until one recognizes the fragmentId.
  ///
  /// Returns 0.0 if no render knows the fragment (e.g.: layout not
  /// yet happened — in that case preferredX will remain -1.0 and will be
  /// recalculated at the next vertical movement).
  double resolveCaretX(CaretStop stop) {
    for (final render in _renders.values) {
      final x = render.getCaretX(stop.fragmentId, stop.offset);
      if (x != null) return x;
    }
    return 0.0;
  }

  double resolveCaretY(CaretStop stop) {
    for (final render in _renders.values) {
      final y = render.getCaretY(stop.fragmentId, stop.offset);
      if (y != null) return y;
    }
    return 0.0;
  }

  /// Diagnostic: number of currently registered renders.
  int get registeredCount => _renders.length;

  /// Public read-only access to the registered render objects.
  /// Key = containerId, Value = the active RenderFluentParagraph.
  Map<String, RenderFluentParagraph> get renders => Map.unmodifiable(_renders);
}
