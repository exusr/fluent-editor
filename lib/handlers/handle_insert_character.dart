import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/cursor_utils.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';

/// Inserts text by iterating through grapheme clusters instead of UTF-16 code units.
/// This ensures emoji and other multi-code-unit characters are inserted as single units.
void executeHandleInsertText(String text, FluentDocument document) {
  if (text.isEmpty) return;
  
  int i = 0;
  while (i < text.length) {
    int charCode = text.codeUnitAt(i);
    
    if (charCode >= 0xD800 && charCode <= 0xDBFF && i + 1 < text.length) {
      int nextCharCode = text.codeUnitAt(i + 1);
      if (nextCharCode >= 0xDC00 && nextCharCode <= 0xDFFF) {
        final emoji = text.substring(i, i + 2);
        executeHandleInsertCharacter(emoji, document);
        i += 2;
        continue;
      }
    }
    
    executeHandleInsertCharacter(text[i], document);
    i++;
  }
}

void executeHandleInsertCharacter(String character, FluentDocument document) {
  if (document.registry.dispatchInsertCharacter(character, document)) return;

  final node = getNodeAtCursor(document.eventHandler);
  bool inserted = false;
  bool needsForward = true;

  if (node is Root) {
    final newParagraph = Paragraph(
      text: character,
      textAlign: document.pendingTextAlign,
      indent: document.pendingIndent,
      styleName: document.pendingStyle.name,
    );
    final style = document.pendingStyle;
    final firstFrag = newParagraph.fragments.first as Fragment;
    firstFrag.fontFamily = style.fontFamily ?? document.pendingFontFamily;
    firstFrag.fontSize = style.fontSize ?? document.pendingFontSize;
    firstFrag.styles = List.from(style.styles ?? document.pendingStyles);
    firstFrag.color = style.color ?? document.pendingColor;
    firstFrag.highlightColor = style.highlightColor ?? document.pendingHighlightColor;
    node.nodes.add(newParagraph);
    document.cursor.moveTo(firstFrag.id, character.length);
    inserted = true;
    needsForward = false;
  }

  if (node is HorizontalRule) {
    final parent = findParentCached(document, node);
    if (parent != null) {
      final newFrag = FragmentOperations.createFragmentWithPendingStyles(document, character);
      final offset = document.cursor.anchorOffset;
      final wrapper = Paragraph(
        textAlign: document.pendingTextAlign,
        indent: document.pendingIndent,
        styleName: document.pendingStyle.name,
      )..fragments.add(newFrag);
      final style = document.pendingStyle;
      newFrag.fontFamily = style.fontFamily ?? document.pendingFontFamily;
      newFrag.fontSize = style.fontSize ?? document.pendingFontSize;
      newFrag.styles = List.from(style.styles ?? document.pendingStyles);
      if (offset == 0) {
        insertBefore(parent, node, wrapper);
      } else {
        insertAfter(parent, node, wrapper);
      }
      document.cursor.moveTo(newFrag.id, character.length);
      document.updateContent();
      return;
    }
  }

  if (node is FluentImage) {
    final parent = findParentCached(document, node);
    if (parent != null) {
      final newFrag = FragmentOperations.createFragmentWithPendingStyles(document, character);
      final offset = document.cursor.anchorOffset;
      final isInlineContext = parent is Paragraph &&
          parent is! FluentList && parent is! FluentTable && parent is! FluentRow;
      if (isInlineContext) {
        if (offset == 0) {
          insertBefore(parent, node, newFrag);
          document.updateContent();
          return;
        } else {
          insertAfter(parent, node, newFrag);
        }
      } else {
        final wrapper = Paragraph(
          textAlign: document.pendingTextAlign,
          indent: document.pendingIndent,
          styleName: document.pendingStyle.name,
        )..fragments.add(newFrag);
        final style = document.pendingStyle;
        newFrag.fontFamily = style.fontFamily ?? document.pendingFontFamily;
        newFrag.fontSize = style.fontSize ?? document.pendingFontSize;
        newFrag.styles = List.from(style.styles ?? document.pendingStyles);
        if (offset == 0) {
          insertBefore(parent, node, wrapper);
        } else {
          insertAfter(parent, node, wrapper);
        }
      }
      document.cursor.moveTo(newFrag.id, character.length);
      inserted = true;
      needsForward = false; // cursor already positioned correctly
    }
  }

  if (node is InlineContainerNode && node is! FluentImage) {
    final result = getFragmentAtCursor(document.eventHandler);
    if (result != null) {
      final frag = result.fragment as Fragment;
      final offset = result.offset;
      if (_shouldApplyPendingFont(document, frag)) {
        _insertWithPendingFont(document, character, frag, offset);
        return;
      }
      inserted = FragmentOperations.insertTextInFragment(frag, offset, character);
    }
  } else if (node is Fragment && node is! FluentImage && node is! HorizontalRule) {
    final frag = node;
    final offset = document.cursor.anchorOffset;
    if (_shouldApplyPendingFont(document, frag)) {
      _insertWithPendingFont(document, character, frag, offset);
      return;
    }
    inserted = FragmentOperations.insertTextInFragment(frag, offset, character);
  }

  if (inserted) {
    if (needsForward) {
      final advanceAmount = character.length;
      document.cursor.focusOffset += advanceAmount;
      document.cursor.anchorOffset += advanceAmount;
    }
    document.updateContent();

    final fragId = document.cursor.anchorId;
    final frag = document.nodeById(fragId);
    final parent = frag != null ? findParentCached(document, frag) : null;
    if (parent is Paragraph) {
      final globalOffset = document.getGlobalOffsetInParagraph(
        parent.id,
        fragId,
        document.cursor.anchorOffset - character.length,
      );
      if (globalOffset != null) {
        document.notifyTextMutation(parent.id, globalOffset, character.length);
      }
    }
  }
}

bool _shouldApplyPendingFont(FluentDocument document, Fragment frag) {
  return frag.fontFamily != document.pendingFontFamily ||
         frag.fontSize != document.pendingFontSize ||
         frag.color != document.pendingColor ||
         frag.highlightColor != document.pendingHighlightColor ||
         !_stylesEqual(frag.styles ?? [], document.pendingStyles);
}

bool _stylesEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  // Styles lists are typically 0-3 items; linear contains is cheaper
  // than allocating + sorting two lists on every keystroke.
  for (final s in a) {
    if (!b.contains(s)) return false;
  }
  return true;
}

/// Splits the fragment at cursor and inserts the character in a new
/// fragment with the pending font. The existing text after the cursor
/// keeps the original font.
void _insertWithPendingFont(
  FluentDocument document,
  String character,
  Fragment frag,
  int offset,
) {
  final parent = findParentCached(document, frag);
  if (parent == null) return;

  if (offset == 0) {
    final newFrag = FragmentOperations.createFragmentWithPendingStyles(document, character);
    insertBefore(parent, frag, newFrag);
    document.cursor.moveTo(newFrag.id, character.length);
    document.updateContent();
    return;
  }

  if (offset == frag.text.length) {
    final newFrag = FragmentOperations.createFragmentWithPendingStyles(document, character);
    insertAfter(parent, frag, newFrag);
    document.cursor.moveTo(newFrag.id, character.length);
    document.updateContent();
    return;
  }

  final before = frag.text.substring(0, offset);
  final after = frag.text.substring(offset);
  frag.text = before;

  final newFrag = FragmentOperations.createFragmentWithPendingStyles(document, character);

  insertAfter(parent, frag, newFrag);

  if (after.isNotEmpty) {
    final afterFrag = FragmentOperations.cloneFragment(frag, text: after);
    insertAfter(parent, newFrag, afterFrag);
  }

  document.cursor.moveTo(newFrag.id, character.length);
  document.updateContent();
}