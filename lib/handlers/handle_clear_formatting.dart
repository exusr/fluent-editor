import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

/// Removes all formatting from the selected text.
/// Keeps only plain text.
bool executeHandleClearFormatting(FluentDocument document) {
  document.saveState(description: 'Clear formatting', forceNewAction: true);

  final cursor = document.cursor;

  final selection = resolveSelectionFromCursor(document);

  if (selection != null) {
    return _clearFormattingFromSelection(document, selection);
  }

  if (cursor.isCollapsed) {
    document.pendingStyles = [];
    document.pendingFontFamily = 'DejaVu Sans';
    document.pendingFontSize = 14.0;
    document.pendingColor = null;
    document.pendingHighlightColor = null;
    document.pendingStyle = ParagraphStyle.normal;

    final container = document.findLogicalContainerCached(cursor.anchorId);
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

    if (container is Paragraph) {
      final paragraphId = container.id;
      if (!processedParagraphs.contains(paragraphId)) {
        container.styleName = 'normal';
        processedParagraphs.add(paragraphId);
      }
    }

    final leaves = FragmentOperations.collectLeafFragments(container as FNode);
    bool inRange = false;
    Fragment? lastCleared;

    for (final leaf in leaves) {
      if (leaf.id == node.startFragment.id) inRange = true;

      if (inRange && leaf is! FluentImage) {
        if (leaf.styles?.contains('suggestion_deletion') != true) {
          leaf.styles = [];
          leaf.fontFamily = 'DejaVu Sans';
          leaf.fontSize = 14.0;
          leaf.color = null;
          leaf.highlightColor = null;
          lastCleared = leaf;
        }
      }

      if (leaf.id == node.endFragment.id) inRange = false;
    }

    if (lastCleared != null) {
      cursor.moveTo(lastCleared.id, lastCleared.text.length);
    }
  }

  document.pendingStyle = ParagraphStyle.normal;

  document.syncPendingFontWithCursor();
  document.updateContent();
  return true;
}
