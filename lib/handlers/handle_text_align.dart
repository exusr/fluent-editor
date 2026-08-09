import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';

/// Applies text alignment to Paragraphs in the selection
/// or to the Paragraph under the cursor.
bool executeHandleTextAlign(FluentDocument document, String align) {
  final cursor = document.cursor;

  final selection = resolveSelectionFromCursor(document);

  if (selection != null) {
    for (final node in selection.nodes) {
      _applyToParagraphs(document, node.container as FNode, align);
    }
    document.pendingTextAlign = align;
    document.updateContent();
    return true;
  }

  final container = document.findLogicalContainerCached(cursor.anchorId);
  if (container != null) {
    _applyToParagraphs(document, container as FNode, align);
    document.pendingTextAlign = align;
    document.updateContent();
    return true;
  }

  return false;
}

void _applyToParagraphs(FluentDocument document, FNode node, String align) {
  if (node is Paragraph) {
    if (document.registry.dispatchParagraphMutation(document, node, (p) {
      p.textAlign = align;
    })) {
      return;
    }
    node.textAlign = align;
  } else if (node is FluentImage) {
    node.textAlign = align;
  } else if (node is InlineContainerNode) {
    for (final child in (node as InlineContainerNode).getChildren()) {
      _applyToParagraphs(document, child, align);
    }
  }
}
