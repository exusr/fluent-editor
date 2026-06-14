import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

/// Applies text alignment to Paragraphs in the selection
/// or to the Paragraph under the cursor.
bool executeHandleTextAlign(FluentDocument document, String align) {
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
    for (final node in selection.nodes) {
      _applyToParagraphs(node.container as FNode, align);
    }
    document.pendingTextAlign = align;
    document.updateContent();
    return true;
  }

  // Collapsed cursor: apply to the current Paragraph and update pending.
  final container = findLogicalContainer(root, cursor.anchorId);
  if (container != null) {
    _applyToParagraphs(container as FNode, align);
    document.pendingTextAlign = align;
    document.updateContent();
    return true;
  }

  return false;
}

void _applyToParagraphs(FNode node, String align) {
  if (node is Paragraph) {
    node.textAlign = align;
  } else if (node is FluentImage) {
    node.textAlign = align;
  } else if (node is InlineContainerNode) {
    for (final child in (node as InlineContainerNode).getChildren()) {
      _applyToParagraphs(child, align);
    }
  }
}
