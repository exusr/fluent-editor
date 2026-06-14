import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

/// Applies highlight color to fragments affected by the selection
/// or stores the pending color for collapsed cursor.
/// Pass [null] or empty string to remove the highlight.
bool executeHandleHighlightColor(FluentDocument document, String? color) {
  final root = document.content;
  final cursor = document.cursor;

  final selection = resolveSelection(
    root,
    cursor.anchorId,
    cursor.anchorOffset,
    cursor.focusId,
    cursor.focusOffset,
    cachedStops: document.caretStops,
    cachedLines: document.logicalLines,
  );

  if (selection != null) {
    return _applyColorToSelection(document, selection, color);
  }

  return _applyColorAtCursor(document, color);
}

// ───────────────────────────────────────────────────────────────────
// Helpers
// ───────────────────────────────────────────────────────────────────

bool _applyColorToSelection(
  FluentDocument document,
  ResolvedSelection selection,
  String? color,
) {
  final root = document.content;
  final cursor = document.cursor;

  for (final node in selection.nodes) {
    final container = node.container;
    final startParent = findParent(root, node.startFragment);
    final endParent = findParent(root, node.endFragment);

    late Fragment actualStartFrag;
    late Fragment actualEndFrag;

    if (node.startFragment.id == node.endFragment.id) {
      final frag = node.startFragment;
      if (node.startOffset > 0 && node.endOffset < frag.text.length) {
        final before = frag.text.substring(0, node.startOffset);
        final mid = frag.text.substring(node.startOffset, node.endOffset);
        final after = frag.text.substring(node.endOffset);
        frag.text = before;
        final midFrag = FragmentOperations.cloneFragment(frag, text: mid);
        if (startParent != null) insertAfter(startParent, frag, midFrag);
        if (after.isNotEmpty && startParent != null) {
          final afterFrag = FragmentOperations.cloneFragment(frag, text: after);
          insertAfter(startParent, midFrag, afterFrag);
        }
        actualStartFrag = midFrag;
        actualEndFrag = midFrag;
      } else if (node.startOffset > 0) {
        final before = frag.text.substring(0, node.startOffset);
        final after = frag.text.substring(node.startOffset);
        frag.text = before;
        final newFrag = FragmentOperations.cloneFragment(frag, text: after);
        if (startParent != null) insertAfter(startParent, frag, newFrag);
        actualStartFrag = newFrag;
        actualEndFrag = newFrag;
      } else if (node.endOffset < frag.text.length) {
        final selected = frag.text.substring(0, node.endOffset);
        final after = frag.text.substring(node.endOffset);
        frag.text = selected;
        final afterFrag = FragmentOperations.cloneFragment(frag, text: after);
        if (startParent != null) insertAfter(startParent, frag, afterFrag);
        actualStartFrag = frag;
        actualEndFrag = frag;
      } else {
        actualStartFrag = frag;
        actualEndFrag = frag;
      }
    } else {
      final first = node.startFragment;
      if (node.startOffset > 0 && node.startOffset < first.text.length) {
        final before = first.text.substring(0, node.startOffset);
        final after = first.text.substring(node.startOffset);
        first.text = before;
        final newFrag = FragmentOperations.cloneFragment(first, text: after);
        if (startParent != null) insertAfter(startParent, first, newFrag);
        actualStartFrag = newFrag;
      } else {
        actualStartFrag = first;
      }

      final last = node.endFragment;
      if (node.endOffset > 0 && node.endOffset < last.text.length) {
        final selected = last.text.substring(0, node.endOffset);
        final after = last.text.substring(node.endOffset);
        last.text = selected;
        final afterFrag = FragmentOperations.cloneFragment(last, text: after);
        if (endParent != null) insertAfter(endParent, last, afterFrag);
        actualEndFrag = last;
      } else {
        actualEndFrag = last;
      }
    }

    final leaves = FragmentOperations.collectLeafFragments(container as FNode);
    bool inRange = false;
    Fragment? lastModified;
    for (final leaf in leaves) {
      if (leaf.id == actualStartFrag.id) inRange = true;
      if (inRange && leaf is! FluentImage) {
        leaf.highlightColor = color;
        lastModified = leaf;
      }
      if (leaf.id == actualEndFrag.id) inRange = false;
    }

    if (lastModified != null) {
      cursor.moveTo(lastModified.id, lastModified.text.length);
    }
  }

  document.pendingHighlightColor = color;
  document.updateContent();
  return true;
}

bool _applyColorAtCursor(FluentDocument document, String? color) {
  document.pendingHighlightColor = color;
  document.updateContent();
  return true;
}
