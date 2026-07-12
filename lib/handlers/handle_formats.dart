import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

bool executeHandleBold(FluentDocument document) =>
    _executeHandleStyle(document, 'bold');

bool executeHandleItalic(FluentDocument document) =>
    _executeHandleStyle(document, 'italic');

bool executeHandleUnderline(FluentDocument document) =>
    _executeHandleStyle(document, 'underline');

bool executeHandleStrikethrough(FluentDocument document) =>
    _executeHandleStyle(document, 'strikethrough');

bool executeHandleSmallCaps(FluentDocument document) =>
    _executeHandleStyle(document, 'smallcaps');

bool executeHandleSuperscript(FluentDocument document) =>
    _executeHandleExclusiveStyle(document, 'superscript', 'subscript');

bool executeHandleSubscript(FluentDocument document) =>
    _executeHandleExclusiveStyle(document, 'subscript', 'superscript');

bool _executeHandleStyle(FluentDocument document, String styleName) {
  final selection = resolveSelectionFromCursor(document);

  if (selection != null) {
    return _applyStyleToSelection(document, selection, styleName);
  }

  if (document.cursor.isCollapsed) {
    final styles = document.pendingStyles;
    if (styles.contains(styleName)) {
      document.pendingStyles = styles.where((s) => s != styleName).toList();
    } else {
      document.pendingStyles = [...styles, styleName];
    }
    document.updateContent();
    return true;
  }

  return false;
}

/// Exclusive version: applies styleName and removes excludeStyle.
/// Used for superscript/subscript which are mutually exclusive.
bool _executeHandleExclusiveStyle(FluentDocument document, String styleName, String excludeStyle) {
  final selection = resolveSelectionFromCursor(document);

  if (selection != null) {
    for (final node in selection.nodes) {
      final leafs = FragmentOperations.collectLeafFragments(node.container as FNode);
      for (final f in leafs) {
        final s = f.styles ?? [];
        if (s.contains(excludeStyle)) {
          f.styles = s.where((x) => x != excludeStyle).toList();
        }
      }
    }
    return _applyStyleToSelection(document, selection, styleName);
  }

  if (document.cursor.isCollapsed) {
    final styles = document.pendingStyles;
    if (styles.contains(styleName)) {
      document.pendingStyles = styles.where((s) => s != styleName).toList();
    } else {
      document.pendingStyles = [...styles.where((s) => s != excludeStyle), styleName];
    }
    document.updateContent();
    return true;
  }

  return false;
}

void _toggleStyle(Fragment f, String styleName) {
  final s = f.styles ?? [];
  if (s.contains(styleName)) {
    f.styles = s.where((x) => x != styleName).toList();
  } else {
    f.styles = [...s, styleName];
  }
}

/// Apply/remove an inline style to fragments affected by the selection.
bool _applyStyleToSelection(FluentDocument document, ResolvedSelection selection, String styleName) {
  final cursor = document.cursor;

  final result = splitAndApplyToLeaves(
    document,
    selection,
    modify: (leaf) => _toggleStyle(leaf, styleName),
  );

  if (result.firstModified != null && result.lastModified != null) {
    cursor.anchorId = result.firstModified!.id;
    cursor.anchorOffset = 0;
    cursor.focusId = result.lastModified!.id;
    cursor.focusOffset = result.lastModified!.text.length;
  }

  document.syncPendingFontWithCursor();
  document.updateContent();

  syncSelectionManager(document);

  return true;
}

/// Synchronizes SelectionManager with the current cursor state.
void syncSelectionManager(FluentDocument document) {
  final cursor = document.cursor;

  if (cursor.isCollapsed) {
    document.selectionManager.collapse();
    return;
  }

  final anchorNodeId = document.findLogicalContainerId(cursor.anchorId);
  final focusNodeId  = document.findLogicalContainerId(cursor.focusId);

  if (anchorNodeId == null || focusNodeId == null) {
    document.selectionManager.clear();
    return;
  }

  document.selectionManager.startSelection(
    anchorNodeId,
    cursor.anchorId,
    cursor.anchorOffset,
  );
  document.selectionManager.updateFocus(
    focusNodeId,
    cursor.focusId,
    cursor.focusOffset,
  );
}