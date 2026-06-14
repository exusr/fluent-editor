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
  // Save state for undo/redo
  document.saveState(description: 'Change paragraph style to ${style.name}');

  final root = document.content;
  final cursor = document.cursor;

  // If there's a selection, apply it to all paragraphs in the selection
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
    // Collapsed cursor: apply to the current paragraph
    final container = findLogicalContainer(root, cursor.anchorId);
    if (container is Paragraph) {
      _applyStyleToParagraph(container, style);
    } else {
      // If we're not in a paragraph, only set the pending style
      document.pendingStyle = style;
      document.updateContent();
      return true;
    }
  }

  // Update the pending style
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
  // Save only the style reference
  paragraph.styleName = style.name;

  // Apply style properties only if there are no explicit overrides
  // within the paragraph (like textAlign, indent)
  if (style.textAlign != null) {
    paragraph.textAlign = style.textAlign!;
  }
  if (style.indent != null) {
    paragraph.indent = style.indent!;
  }

  // NOTE: We don't modify fragment properties (font, size, styles)
  // because those are explicit user customizations.
  // The style works as a "fallback" when creating new fragments.
}
