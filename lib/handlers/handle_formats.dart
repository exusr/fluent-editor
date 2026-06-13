import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';
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

// ───────────────────────────────────────────────────────────────────
// Core
// ───────────────────────────────────────────────────────────────────

bool _executeHandleStyle(FluentDocument document, String styleName) {
  final root = document.content;
  final cursor = document.cursor;

  final selection = resolveSelection(
    root,
    cursor.anchorId,
    cursor.anchorOffset,
    cursor.focusId,
    cursor.focusOffset,
  );

  if (selection != null) {
    return _applyStyleToSelection(document, selection, styleName);
  }

  // Collapsed cursor: toggle pending style
  if (cursor.isCollapsed) {
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
  final root = document.content;
  final cursor = document.cursor;

  final selection = resolveSelection(
    root,
    cursor.anchorId,
    cursor.anchorOffset,
    cursor.focusId,
    cursor.focusOffset,
  );

  if (selection != null) {
    // Remove the opposite style from all leaf fragments in the container
    // before the split, so new fragments won't inherit it.
    for (final node in selection.nodes) {
      final leafs = FragmentOperations.collectLeafFragments(node.container as FNode);
      for (final f in leafs) {
        final s = f.styles ?? [];
        if (s.contains(excludeStyle)) {
          f.styles = s.where((x) => x != excludeStyle).toList();
        }
        // If the fragment already has styleName, remove it so the toggle will re-add it
        // (this avoids the toggle removing it when we want to switch)
      }
    }
    // Now apply/remove the requested style (standard toggle)
    return _applyStyleToSelection(document, selection, styleName);
  }

  // Collapsed cursor: toggle pending style
  if (cursor.isCollapsed) {
    final styles = document.pendingStyles;
    if (styles.contains(styleName)) {
      document.pendingStyles = styles.where((s) => s != styleName).toList();
    } else {
      // Remove the opposite style and add the new one
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
  final root = document.content;
  final cursor = document.cursor;

  for (final node in selection.nodes) {
    final container = node.container;

    // ── 1st pass: split at edges in the actual parent ───────────
    final startParent = findParent(root, node.startFragment);
    final endParent   = findParent(root, node.endFragment);

    // References to selected fragments (change after splits)
    late Fragment actualStartFrag;
    late Fragment actualEndFrag;

    // Single fragment
    if (node.startFragment.id == node.endFragment.id) {
      final frag = node.startFragment;
      if (node.startOffset > 0 && node.endOffset < frag.text.length) {
        // Split in three: [before][mid][after]
        final before = frag.text.substring(0, node.startOffset);
        final mid    = frag.text.substring(node.startOffset, node.endOffset);
        final after  = frag.text.substring(node.endOffset);
        frag.text = before;
        final midFrag = FragmentOperations.cloneFragment(frag, text: mid);
        if (startParent != null) insertAfter(startParent, frag, midFrag);
        if (after.isNotEmpty && startParent != null) {
          final afterFrag = FragmentOperations.cloneFragment(frag, text: after);
          insertAfter(startParent, midFrag, afterFrag);
        }
        actualStartFrag = midFrag;
        actualEndFrag   = midFrag;
      } else if (node.startOffset > 0) {
        // Split at start: [before][selected]
        final before = frag.text.substring(0, node.startOffset);
        final after  = frag.text.substring(node.startOffset);
        frag.text = before;
        final newFrag = FragmentOperations.cloneFragment(frag, text: after);
        if (startParent != null) insertAfter(startParent, frag, newFrag);
        actualStartFrag = newFrag;
        actualEndFrag   = newFrag;
      } else if (node.endOffset < frag.text.length) {
        // Split at end: [selected][after]
        final selected = frag.text.substring(0, node.endOffset);
        final after    = frag.text.substring(node.endOffset);
        frag.text = selected;
        final afterFrag = FragmentOperations.cloneFragment(frag, text: after);
        if (startParent != null) insertAfter(startParent, frag, afterFrag);
        actualStartFrag = frag;
        actualEndFrag   = frag;
      } else {
        // Entire fragment is selected, no split
        actualStartFrag = frag;
        actualEndFrag   = frag;
      }
    } else {
      // First fragment: split at start
      final first = node.startFragment;
      if (node.startOffset > 0 && node.startOffset < first.text.length) {
        final before = first.text.substring(0, node.startOffset);
        final after  = first.text.substring(node.startOffset);
        first.text = before;
        final newFrag = FragmentOperations.cloneFragment(first, text: after);
        if (startParent != null) insertAfter(startParent, first, newFrag);
        actualStartFrag = newFrag;
      } else {
        actualStartFrag = first;
      }

      // Last fragment: split at end
      final last = node.endFragment;
      if (node.endOffset > 0 && node.endOffset < last.text.length) {
        final selected = last.text.substring(0, node.endOffset);
        final after    = last.text.substring(node.endOffset);
        last.text = selected;
        final afterFrag = FragmentOperations.cloneFragment(last, text: after);
        if (endParent != null) insertAfter(endParent, last, afterFrag);
        actualEndFrag = last;
      } else {
        actualEndFrag = last;
      }
    }

    // ── 2nd pass: toggle style on leaf fragments in range ────
    final leaves = FragmentOperations.collectLeafFragments(container as FNode);
    bool inRange = false;
    Fragment? firstToggled;
    Fragment? lastToggled;
    for (final leaf in leaves) {
      if (leaf.id == actualStartFrag.id) inRange = true;
      if (inRange && leaf is! FluentImage) {
        _toggleStyle(leaf, styleName);
        firstToggled ??= leaf;
        lastToggled = leaf;
      }
      if (leaf.id == actualEndFrag.id) inRange = false;
    }

    // Preserve selection: anchor at start, focus at end
    if (firstToggled != null && lastToggled != null) {
      cursor.anchorId = firstToggled.id;
      cursor.anchorOffset = 0;
      cursor.focusId = lastToggled.id;
      cursor.focusOffset = lastToggled.text.length;
    }
  }

  document.syncPendingFontWithCursor();
  document.updateContent();

  // Keep SelectionManager in sync after cursor is repositioned
  _syncSelectionManager(document);

  return true;
}

/// Synchronizes SelectionManager with the current cursor state.
void _syncSelectionManager(FluentDocument document) {
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