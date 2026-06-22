import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

/// Applies a paragraph style to the current paragraph or selection.
/// The style works as a "base" - explicit fragment customizations
/// always take precedence.
bool executeHandleParagraphStyle(
  FluentDocument document,
  ParagraphStyle style,
) {
  document.saveState(description: 'Change paragraph style to ${style.name}');

  final root = document.content;
  final cursor = document.cursor;

  if (!cursor.isCollapsed) {
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
        final container = node.container;
        if (container is Paragraph) {
          _applyStyleToParagraph(container, style);
        }
      }
    }
  } else {
    final container = findLogicalContainer(root, cursor.anchorId);
    if (container is Paragraph) {
      _applyStyleToParagraph(container, style);
    } else {
      document.pendingStyle = style;
      document.updateContent();
      return true;
    }
  }

  document.pendingStyle = style;
  document.syncPendingFontWithCursor();
  document.updateContent();
  return true;
}

/// Applies a style to a specific paragraph.
/// Only the style reference is saved; fragment properties
/// are NOT overwritten, so explicit customizations persist.
void _applyStyleToParagraph(
  Paragraph paragraph,
  ParagraphStyle style,
) {
  paragraph.styleName = style.name;

  if (style.textAlign != null) {
    paragraph.textAlign = style.textAlign!;
  }
  if (style.indent != null) {
    paragraph.indent = style.indent!;
  }

}
