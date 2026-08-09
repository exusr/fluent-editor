import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

bool executeHandleFontFamily(FluentDocument document, String fontFamily) {
  final selection = resolveSelectionFromCursor(document);

  if (selection != null) {
    return _applyFontFamilyToSelection(document, selection, fontFamily);
  }

  return _applyFontFamilyAtCursor(document, fontFamily);
}

/// Applies font family to fragments affected by the selection.
bool _applyFontFamilyToSelection(
  FluentDocument document,
  ResolvedSelection selection,
  String fontFamily,
) {
  final cursor = document.cursor;

  final result = splitAndApplyToLeaves(
    document,
    selection,
    modifyBatch: (leaves) {
      final res = document.registry.dispatchLeavesStyleMutation(
        document,
        leaves,
        (l) => l.fontFamily = fontFamily,
      );
      return res;
    },
    modify: (leaf) {
      final res = document.registry.dispatchStyleMutation(
        document,
        leaf,
        (l) => l.fontFamily = fontFamily,
      );
      if (res != null) return res;

      leaf.fontFamily = fontFamily;
      return leaf;
    },
  );

  if (result.lastModified != null) {
    cursor.moveTo(result.lastModified!.id, result.lastModified!.text.length);
  }

  document.pendingFontFamily = fontFamily;
  document.updateContent();
  // Cursor is collapsed at the end of the affected text: align the visual
  // selection so SelectionManager doesn't keep the stale highlight.
  document.selectionManager.collapse();
  return true;
}

/// Applies font family to collapsed cursor in a persistent way.
/// Stores the font in [document.pendingFontFamily]; subsequently typed
/// text will inherit this font (Word/Google Docs model).
/// Also applies the font to the entire current fragment for immediate visual feedback.
bool _applyFontFamilyAtCursor(FluentDocument document, String fontFamily) {
  final cursor = document.cursor;
  final frag = document.nodeById(cursor.anchorId);

  if (frag is Fragment) {
    final originalAnchorId = cursor.anchorId;
    final originalAnchorOffset = cursor.anchorOffset;

    cursor.moveTo(frag.id, 0);
    cursor.focusTo(frag.id, frag.text.length);

    final selection = resolveSelectionFromCursor(document);

    if (selection != null) {
      _applyFontFamilyToSelection(document, selection, fontFamily);
    }

    cursor.moveTo(originalAnchorId, originalAnchorOffset);
    document.selectionManager.collapse();
  }

  document.pendingFontFamily = fontFamily;
  document.updateContent();
  return true;
}
