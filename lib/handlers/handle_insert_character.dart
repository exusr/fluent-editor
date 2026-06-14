import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/cursor_utils.dart';
import 'package:fluent_editor/utils/editor_utils.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';

void executeHandleInsertCharacter(String character, FluentDocument document) {
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
    // Apply style properties to fragments
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

  // HorizontalRule: behaves like block-level FluentImage. The character
  // is inserted in a Paragraph before or after the HR.
  if (node is HorizontalRule) {
    final parent = findParent(document.content, node);
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

  // Image: insert a new fragment before or after the image.
  // If the image is inline (parent Paragraph/Link), insert a naked Fragment.
  // If it's block-level (parent Root/ListItem/FluentCell/etc.), wrap the
  // fragment in a Paragraph otherwise it won't be renderable.
  if (node is FluentImage) {
    final parent = findParent(document.content, node);
    if (parent != null) {
      final newFrag = FragmentOperations.createFragmentWithPendingStyles(document, character);
      final offset = document.cursor.anchorOffset;
      // Inline context: Paragraph or Link accept naked fragments
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
        // Block context: wrap in Paragraph
        final wrapper = Paragraph(
          textAlign: document.pendingTextAlign,
          indent: document.pendingIndent,
          styleName: document.pendingStyle.name,
        )..fragments.add(newFrag);
        // Apply style properties to the fragment
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
      inserted = insertCharacterInFragment(
        character,
        frag,
        offset,
      );
    }
  }

  if (node is Fragment && node is! FluentImage && node is! HorizontalRule) {
    final frag = node;
    final offset = document.cursor.anchorOffset;
    if (_shouldApplyPendingFont(document, frag)) {
      _insertWithPendingFont(document, character, frag, offset);
      return;
    }
    inserted = insertCharacterInFragment(
      character,
      frag,
      offset,
    );
  }

  if (inserted) {
    if (needsForward) document.cursor.forward();
    document.updateContent();

    // Notify comment system of the text mutation.
    final fragId = document.cursor.anchorId;
    final frag = document.nodeById(fragId);
    final parent = frag != null ? findParent(document.content, frag) : null;
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
  final sortedA = List<String>.from(a)..sort();
  final sortedB = List<String>.from(b)..sort();
  for (var i = 0; i < sortedA.length; i++) {
    if (sortedA[i] != sortedB[i]) return false;
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
  final parent = findParent(document.content, frag);
  if (parent == null) return;

  if (offset == 0) {
    // Insert the new character BEFORE the current fragment
    final newFrag = FragmentOperations.createFragmentWithPendingStyles(document, character);
    insertBefore(parent, frag, newFrag);
    document.cursor.moveTo(newFrag.id, character.length);
    document.updateContent();
    return;
  }

  if (offset == frag.text.length) {
    // Insert the new character AFTER the current fragment
    final newFrag = FragmentOperations.createFragmentWithPendingStyles(document, character);
    insertAfter(parent, frag, newFrag);
    document.cursor.moveTo(newFrag.id, character.length);
    document.updateContent();
    return;
  }

  // Offset in middle: split into before/after, insert character in middle
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