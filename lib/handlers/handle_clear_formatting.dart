import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

/// Removes all formatting from the selected text.
/// Keeps only plain text.
bool executeHandleClearFormatting(FluentDocument document) {
  document.saveState(description: 'Clear formatting', forceNewAction: true);

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
    return _clearFormattingFromSelection(document, selection);
  }

  // Collapsed cursor: reset pending styles and style
  if (cursor.isCollapsed) {
    document.pendingStyles = [];
    document.pendingFontFamily = 'Arial';
    document.pendingFontSize = 14.0;
    document.pendingColor = null;
    document.pendingHighlightColor = null;
    document.pendingStyle = ParagraphStyle.normal;

    // Also reset the current paragraph style to "normal"
    final container = findLogicalContainer(root, cursor.anchorId);
    if (container is Paragraph) {
      container.styleName = 'normal';
    }

    document.updateContent();
    return true;
  }

  return false;
}

/// Removes formatting from all fragments in the selection.
/// Also resets paragraph styles to "normal".
bool _clearFormattingFromSelection(FluentDocument document, ResolvedSelection selection) {
  final cursor = document.cursor;
  final processedParagraphs = <String>{}; // Track processed paragraphs

  for (final node in selection.nodes) {
    final container = node.container;

    // Reset paragraph style to "normal" (once per paragraph)
    if (container is Paragraph) {
      final paragraphId = container.id;
      if (!processedParagraphs.contains(paragraphId)) {
        container.styleName = 'normal';
        processedParagraphs.add(paragraphId);
      }
    }

    // Collect all leaf fragments in the range
    final leaves = FragmentOperations.collectLeafFragments(container as FNode);
    bool inRange = false;
    Fragment? lastCleared;

    for (final leaf in leaves) {
      if (leaf.id == node.startFragment.id) inRange = true;

      if (inRange && leaf is! FluentImage) {
        // Remove all formatting
        leaf.styles = [];
        leaf.fontFamily = 'Arial';
        leaf.fontSize = 14.0;
        leaf.color = null;
        leaf.highlightColor = null;
        lastCleared = leaf;
      }

      if (leaf.id == node.endFragment.id) inRange = false;
    }

    if (lastCleared != null) {
      cursor.moveTo(lastCleared.id, lastCleared.text.length);
    }
  }

  // Also reset the pending style
  document.pendingStyle = ParagraphStyle.normal;

  document.syncPendingFontWithCursor();
  document.updateContent();
  return true;
}
