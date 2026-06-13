import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/arrow_key_repeater.dart';
import 'package:fluent_editor/handlers/handle_arrow_key.dart';
import 'package:fluent_editor/handlers/handle_backspace.dart';
import 'package:fluent_editor/handlers/handle_font_family.dart';
import 'package:fluent_editor/handlers/handle_font_size.dart';
import 'package:fluent_editor/handlers/handle_formats.dart';
import 'package:fluent_editor/handlers/handle_paragraph_spacing.dart';
import 'package:fluent_editor/handlers/handle_enter.dart';
import 'package:fluent_editor/handlers/handle_text_color.dart';
import 'package:fluent_editor/handlers/handle_highlight_color.dart';
import 'package:fluent_editor/handlers/handle_insert_node.dart';
import 'package:fluent_editor/handlers/handle_text_align.dart';
import 'package:fluent_editor/handlers/handle_select_all.dart';
import 'package:fluent_editor/handlers/handle_tab.dart';
import 'package:fluent_editor/handlers/handle_clear_formatting.dart';
import 'package:fluent_editor/handlers/handle_clipboard.dart';
import 'package:fluent_editor/handlers/handle_paragraph_style.dart';
import 'package:fluent_editor/renderers/render_paragraph.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/utils/cursor_utils.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/widgets/editor/fluent_link_dialog.dart';
import 'package:fluent_editor/widgets/dialogs/image_insert_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'handle_insert_character.dart';
import 'handle_replace_selection.dart';

class EventHandler {
  bool isCtrlPressed = false;
  bool isShiftPressed = false;
  bool isMetaPressed = false;

  late FluentDocument document;

  // ─── Manual repeat handling for arrow keys (Linux workaround) ─────
  //
  // See arrow_key_repeater.dart for details. On non-Linux platforms
  // this is inert and native KeyRepeatEvent is handled normally.

  late final ArrowKeyRepeater _arrowRepeater = ArrowKeyRepeater(
    (event) => handleKeyDown(event, document),
  );

  // Move cursor to tap position (simple tap, collapse selection)
  void onTapDown(TapDownDetails details, BuildContext context, Widget widget) {
    final localOffset = resolvePositionGestureDetails(details, context, widget);
    if (localOffset != null) {
      document.cursor.moveTo(localOffset.id, localOffset.offset);
      // Collapse global selection
      document.selectionManager.collapse();
      document.syncPendingFontWithCursor();
      document.updateContent();
    }
  }

  // Version with pre-calculated position (uses coordinates relative to RenderBox)
  void onTapDownWithPosition(
    Offset localPosition,
    RenderBox renderBox,
    Widget widget,
  ) {
    final paragraph = renderBox as RenderFluentParagraph;
    final fragmentResult = paragraph.getFragmentAtPosition(localPosition);
    if (fragmentResult != null) {
      document.cursor.moveTo(fragmentResult.fragmentId, fragmentResult.localOffset);
      // Collapse global selection
      document.selectionManager.collapse();
      document.syncPendingFontWithCursor();
      document.updateContent();
    }
  }

  // Double-tap to select word
  void onDoubleTapWithPosition(
    Offset localPosition,
    RenderBox renderBox,
    Widget widget,
  ) {
    final paragraph = renderBox as RenderFluentParagraph;
    final fragmentResult = paragraph.getFragmentAtPosition(localPosition);
    if (fragmentResult != null) {
      final root = document.content;
      final node = findById(root, fragmentResult.fragmentId);
      if (node is Fragment) {
        final text = node.text;
        final offset = fragmentResult.localOffset;

        // Find word boundaries
        int start = offset;
        int end = offset;

        // Find start of word
        while (start > 0 && _isWordChar(text[start - 1])) {
          start--;
        }

        // Find end of word
        while (end < text.length && _isWordChar(text[end])) {
          end++;
        }

        // Set selection to the word
        document.cursor.moveTo(node.id, start);
        document.cursor.focusTo(node.id, end);

        // Sync SelectionManager to show visual selection
        _syncSelectionManager(document);

        document.updateContent();
      }
    }
  }

  bool _isWordChar(String char) {
    // Word characters: letters, numbers, underscore, and some common punctuation
    return RegExp(r'[\w]').hasMatch(char);
  }

  /// Synchronizes SelectionManager with the current cursor state.
  /// Called after every movement, with or without shift.
  void _syncSelectionManager(FluentDocument document) {
    final cursor = document.cursor;

    if (cursor.isCollapsed) {
      // No selection: collapse
      document.selectionManager.collapse();
      return;
    }

    final anchorNodeId = document.findLogicalContainerId(cursor.anchorId);
    final focusNodeId  = document.findLogicalContainerId(cursor.focusId);

    if (anchorNodeId == null || focusNodeId == null) {
      document.selectionManager.collapse();
      return;
    }

    // Start selection with anchor
    document.selectionManager.startSelection(
      anchorNodeId,
      cursor.anchorId,
      cursor.anchorOffset,
    );

    // Update focus
    document.selectionManager.updateFocus(
      focusNodeId,
      cursor.focusId,
      cursor.focusOffset,
    );
  }

  void updateModifiers(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    isShiftPressed = keyboard.isShiftPressed;
    isMetaPressed = keyboard.isMetaPressed;
    isCtrlPressed = keyboard.isControlPressed;
  }

  void handleInsertNode(String nodeType, [Map<String, dynamic>? options]) {
    options ??= <String, dynamic>{
      'rows': 2,
      'cells': 2,
      'url': 'https://google.com',
      'src': 'https://picsum.photos/200/300',
    };

    // Save state before node insertion
    document.saveState(description: 'Insert $nodeType', forceNewAction: true);
    handleInsertNodeExceution(nodeType, document, options);
  }

  void handle(dynamic event, FluentDocument document) {
    if (event is KeyEvent) {
      if (event is KeyDownEvent) {
        updateModifiers(event);
      }
      if (event is KeyUpEvent) {
        updateModifiers(event);
        if (_arrowRepeater.isActive && _arrowRepeater.isArrowKey(event.logicalKey)) {
          _arrowRepeater.stop();
        }
      }
      if (event is KeyRepeatEvent) {
        updateModifiers(event);
        // On Linux, arrow key native autorepeat is ignored: repetition is
        // driven manually by ArrowKeyRepeater instead, to work around
        // missing repaint during OS-level key autorepeat.
        if (_arrowRepeater.isActive && _arrowRepeater.isArrowKey(event.logicalKey)) {
          return;
        }
      }
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        handleKeyDown(event, document);
      }
      if (event is KeyDownEvent &&
          _arrowRepeater.isActive &&
          _arrowRepeater.isArrowKey(event.logicalKey)) {
        this.document = document;
        _arrowRepeater.start(event, fast: isShiftPressed);
      }
    }
  }

  void handleKeyDown(KeyEvent event, FluentDocument document) {
    this.document = document;
    if (handleBackspaceKey(event)) return;
    if (handleMetaActions(event)) return;
    if (handleEnterKey(event)) return;
    if (handleTabKey(event)) return;
    if (handleArrowKeys(event)) return;
    handleCharacterInput(event);
  }

  bool handleCharacterInput(KeyEvent event) {
    if (event.character != null && event.character!.isNotEmpty) {
      final character = event.character!;

      // Save state before modification
      document.saveState(description: 'Type character: $character');

      if (document.cursor.isCollapsed) {
        executeHandleInsertCharacter(character, document);
        return true;
      }
      executeHandleReplaceSelection(character, document);
      return true;
    }
    return false;
  }

  bool handleEnterKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      // Save state before enter
      document.saveState(description: 'Enter', forceNewAction: true);
      executeHandleEnter(document);
      return true;
    }
    return false;
  }

  bool handleBackspaceKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      // Save state before deletion
      document.saveState(description: 'Delete', forceNewAction: true);
      executeHandleBackspace(document, ctrl: isCtrlPressed);
      return true;
    }
    return false;
  }

  bool handleArrowKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      return executeHandleArrowKey(
        event.logicalKey,
        document,
        ctrl: isCtrlPressed,
        shift: isShiftPressed,
      );
    }
    return false;
  }

  bool handleTabKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      document.saveState(description: isShiftPressed ? 'Outdent' : 'Indent', forceNewAction: true);
      return executeHandleTab(document, shift: isShiftPressed);
    }
    return false;
  }

  bool handleMetaActions(KeyEvent event) {
    if (!(isMetaPressed || isCtrlPressed)) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyA) {
      handleSelectAll(document);
      return true;
    }
    if (key == LogicalKeyboardKey.keyC) {
      executeHandleCopy(document);
      return true;
    }
    if (key == LogicalKeyboardKey.keyV) {
      // Save state before paste
      document.saveState(description: 'Paste', forceNewAction: true);
      if (isShiftPressed) {
        executeHandlePastePlain(document);
      } else {
        executeHandlePaste(document);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.keyX) {
      // Save state before cut
      document.saveState(description: 'Cut', forceNewAction: true);
      executeHandleCut(document);
      return true;
    }
    if (key == LogicalKeyboardKey.keyZ) {
      if (isShiftPressed) {
        // Handle redo (Ctrl+Shift+Z)
        document.redo();
        return true;
      } else {
        // Handle undo (Ctrl+Z)
        document.undo();
        return true;
      }
    }
    // Formatting shortcuts
    if (key == LogicalKeyboardKey.keyB) {
      document.saveState(description: 'Bold', forceNewAction: true);
      handleBold();
      return true;
    }
    if (key == LogicalKeyboardKey.keyI) {
      document.saveState(description: 'Italic', forceNewAction: true);
      handleItalic();
      return true;
    }
    if (key == LogicalKeyboardKey.keyU) {
      document.saveState(description: 'Underline', forceNewAction: true);
      handleUnderline();
      return true;
    }
    return false;
  }

  bool handleBold() {
    executeHandleBold(document);
    return true;
  }

  bool handleItalic() {
    executeHandleItalic(document);
    return true;
  }

  bool handleUnderline() {
    executeHandleUnderline(document);
    return true;
  }

  bool handleStrikethrough() {
    document.saveState(description: 'Strikethrough', forceNewAction: true);
    executeHandleStrikethrough(document);
    return true;
  }

  bool handleSmallCaps() {
    document.saveState(description: 'Small caps', forceNewAction: true);
    executeHandleSmallCaps(document);
    return true;
  }

  bool handleSuperscript() {
    document.saveState(description: 'Superscript', forceNewAction: true);
    executeHandleSuperscript(document);
    return true;
  }

  bool handleSubscript() {
    document.saveState(description: 'Subscript', forceNewAction: true);
    executeHandleSubscript(document);
    return true;
  }

  bool handleFontFamily(String fontFamily) {
    document.saveState(description: 'Change font to $fontFamily');
    executeHandleFontFamily(document, fontFamily);
    return true;
  }

  bool handleFontSize(double fontSize) {
    document.saveState(description: 'Change font size', forceNewAction: true);
    executeHandleFontSize(document, fontSize);
    return true;
  }

  bool handleParagraphSpacing({
    double? lineHeight,
    double? spacingBefore,
    double? spacingAfter,
  }) {
    document.saveState(description: 'Change paragraph spacing', forceNewAction: true);
    executeHandleParagraphSpacing(document,
        lineHeight: lineHeight,
        spacingBefore: spacingBefore,
        spacingAfter: spacingAfter);
    return true;
  }

  bool handleTextColor(String? color) {
    document.saveState(description: 'Change text color', forceNewAction: true);
    executeHandleTextColor(document, color);
    return true;
  }

  bool handleHighlightColor(String? color) {
    document.saveState(description: 'Change highlight color', forceNewAction: true);
    executeHandleHighlightColor(document, color);
    return true;
  }

  bool handleTextAlign(String align) {
    document.saveState(description: 'Change text alignment to $align');
    executeHandleTextAlign(document, align);
    return true;
  }

  bool handleTab() {
    document.saveState(description: 'Indent');
    executeHandleTab(document, shift: false);
    return true;
  }

  bool handleShiftTab() {
    document.saveState(description: 'Outdent');
    executeHandleTab(document, shift: true);
    return true;
  }

  bool handleClearFormatting() {
    executeHandleClearFormatting(document);
    return true;
  }

  /// Shows the dialog to insert a link and inserts it if confirmed.
  void handleInsertLink(BuildContext context) async {
    final result = await showFluentLinkDialog(context, labels: document.labels);
    if (result != null) {
      final url = result['url']!;
      final text = result['text']!;
      document.saveState(description: 'Insert link', forceNewAction: true);
      handleInsertNodeExceution(
        'link',
        document,
        {'url': url, 'text': text},
      );
    }
  }

  /// Shows the dialog to insert an image and inserts it if confirmed.
  void handleInsertImage(BuildContext context) async {
    final result = await showImageInsertDialog(context, labels: document.labels);
    if (result != null) {
      final src = result['src']!;
      document.saveState(description: 'Insert image', forceNewAction: true);
      handleInsertNodeExceution(
        'image',
        document,
        {'src': src},
      );
    }
  }

  /// Applies a paragraph style to the current paragraph or selection.
  bool handleParagraphStyle(ParagraphStyle style) {
    document.saveState(description: 'Apply paragraph style', forceNewAction: true);
    executeHandleParagraphStyle(document, style);
    return true;
  }
}