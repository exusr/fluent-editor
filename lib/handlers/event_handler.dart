import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/handle_arrow_key.dart';
import 'package:fluent_editor/handlers/handle_backspace.dart';
import 'package:fluent_editor/handlers/handle_delete.dart';
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
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'handle_insert_character.dart';
import 'handle_replace_selection.dart';

class EventHandler {
  bool isCtrlPressed = false;
  bool isShiftPressed = false;
  bool isMetaPressed = false;

  late FluentDocument document;

  void onTapDown(TapDownDetails details, BuildContext context, Widget widget) {
    final localOffset = resolvePositionGestureDetails(details, context, widget);
    if (localOffset != null) {
      document.cursor.moveTo(localOffset.id, localOffset.offset);
      document.selectionManager.collapse();
      document.syncPendingFontWithCursor();
      document.cursorOnlyUpdate();
    }
  }

  void onTapDownWithPosition(
    Offset localPosition,
    RenderBox renderBox,
    Widget widget,
  ) {
    final paragraph = renderBox as RenderFluentParagraph;
    final fragmentResult = paragraph.getFragmentAtPosition(localPosition);
    if (fragmentResult != null) {
      document.cursor.moveTo(fragmentResult.fragmentId, fragmentResult.localOffset);
      document.selectionManager.collapse();
      document.syncPendingFontWithCursor();
      document.cursorOnlyUpdate();
    }
  }

  void onDoubleTapWithPosition(
    Offset localPosition,
    RenderBox renderBox,
    Widget widget,
  ) {
    final paragraph = renderBox as RenderFluentParagraph;
    final fragmentResult = paragraph.getFragmentAtPosition(localPosition);
    if (fragmentResult != null) {
      final node = document.nodeById(fragmentResult.fragmentId);
      if (node is Fragment) {
        final text = node.text;
        final offset = fragmentResult.localOffset;

        int start = offset;
        int end = offset;

        while (start > 0 && _isWordChar(text[start - 1])) {
          start--;
        }

        while (end < text.length && _isWordChar(text[end])) {
          end++;
        }

        document.cursor.moveTo(node.id, start);
        document.cursor.focusTo(node.id, end);

        syncSelectionManager(document);

        document.cursorOnlyUpdate();
      }
    }
  }

  void onTripleTapWithPosition(
    Offset localPosition,
    RenderBox renderBox,
    Widget widget,
  ) {
    final paragraph = renderBox as RenderFluentParagraph;
    final bounds = paragraph.getLineBoundsAtOffset(localPosition);
    if (bounds == null) return;

    document.cursor.moveTo(bounds.startFrag, bounds.startOff);
    document.cursor.focusTo(bounds.endFrag, bounds.endOff);

    syncSelectionManager(document);
    document.syncPendingFontWithCursor();
    document.cursorOnlyUpdate();
  }

  /// Pre-compiled RegExp for word-character detection.
  /// Creating a new RegExp for every character in the double-tap loop
  /// was a severe bottleneck (1000+ allocations per long paragraph).
  static final _wordCharRe = RegExp(r'[\w]');

  bool _isWordChar(String char) {
    return _wordCharRe.hasMatch(char);
  }

  void updateModifiers(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    isShiftPressed = keyboard.isShiftPressed;
    if (!kIsWeb && (Platform.isMacOS || Platform.isIOS)) {
      isMetaPressed = keyboard.isControlPressed;
      isCtrlPressed = keyboard.isMetaPressed;
    } else {
      isMetaPressed = keyboard.isMetaPressed;
      isCtrlPressed = keyboard.isControlPressed;
    }
  }

  void handleInsertNode(String nodeType, [Map<String, dynamic>? options]) {
    final opts = options ?? <String, dynamic>{
      'rows': 2,
      'cells': 2,
      'url': 'https://google.com',
      'src': 'https://picsum.photos/200/300',
    };

    if (document.registry.dispatchInsertNode(document, nodeType, opts)) return;

    document.saveState(description: 'Insert $nodeType', forceNewAction: true);
    handleInsertNodeExceution(nodeType, document, opts);
  }

  bool handle(dynamic event, FluentDocument document) {
    if (event is! KeyEvent) return false;
    this.document = document;
    updateModifiers(event);
    if (document.registry.dispatchKeyEvent(event, document)) return true;
    if (handleBackspaceKey(event)) return true;
    if (handleDeleteKey(event)) return true;
    if (handleMetaActions(event)) return true;
    if (handleEnterKey(event)) return true;
    if (handleTabKey(event)) return true;
    if (handleArrowKeys(event)) return true;
    if (handleHomeKey(event)) return true;
    if (handleEndKey(event)) return true;
    if (handlePageUpKey(event)) return true;
    if (handlePageDownKey(event)) return true;
    return handleCharacterInput(event);
  }

  bool handleCharacterInput(KeyEvent event) {
    if (document.imeHandler.isConnectionActive) {
      // Let the OS send a TextEditingDelta. Manual insertion kills the OS IME composing session.
      return false;
    }
    
    if (event.character != null && event.character!.isNotEmpty) {
      if (document.imeHandler.isComposing) {
        return false;
      }
      final character = event.character!;
      final isSpace = character == ' ' || character == '\n' || character == '\r';

      document.saveState(
        description: 'Type',
        forceNewAction: isSpace,
      );

      if (document.cursor.isCollapsed) {
        executeHandleInsertCharacter(character, document);
      } else {
        executeHandleReplaceSelection(character, document);
      }
      return true;
    }
    return false;
  }

  bool handleEnterKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (document.imeHandler.isComposing) {
        return false;
      }
      if (document.imeHandler.state.justCommittedComposition) {
        document.imeHandler.state.justCommittedComposition = false;
        return false;
      }
      if (document.registry.dispatchEnter(document)) return true;
      document.saveState(description: 'Enter', forceNewAction: true);
      executeHandleEnter(document);
      return true;
    }
    return false;
  }

  bool handleBackspaceKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (document.imeHandler.isComposing) {
        return false;
      }
      document.saveState(description: 'Delete', forceNewAction: false);
      final isApple = !kIsWeb && (Platform.isMacOS || Platform.isIOS);
      final lineStart = isApple && isCtrlPressed;
      final wordDelete = isApple ? isMetaPressed : isCtrlPressed;
      executeHandleBackspace(document, ctrl: wordDelete, lineStart: lineStart);
      return true;
    }
    return false;
  }

  bool handleDeleteKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      document.saveState(description: 'Delete', forceNewAction: false);
      executeHandleDelete(document, ctrl: isCtrlPressed);
      return true;
    }
    return false;
  }

  bool handleHomeKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.home) {
      final cursor = document.cursor;
      final current = CaretStop(cursor.anchorId, cursor.anchorOffset);
      final result = moveToLineStart(
        document.content, current,
        lines: document.logicalLines,
      );

      if (result.position != null) {
        if (isShiftPressed) {
          cursor.focusTo(result.position!.fragmentId, result.position!.offset);
          syncSelectionManager(document);
        } else {
          cursor.moveTo(result.position!.fragmentId, result.position!.offset);
          document.selectionManager.collapse();
        }
        document.syncPendingFontWithCursor();
        document.cursorOnlyUpdate();
      }
      return true;
    }
    return false;
  }

  bool handleEndKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.end) {
      final cursor = document.cursor;
      final current = CaretStop(cursor.anchorId, cursor.anchorOffset);
      final result = moveToLineEnd(
        document.content, current,
        lines: document.logicalLines,
      );

      if (result.position != null) {
        if (isShiftPressed) {
          cursor.focusTo(result.position!.fragmentId, result.position!.offset);
          syncSelectionManager(document);
        } else {
          cursor.moveTo(result.position!.fragmentId, result.position!.offset);
          document.selectionManager.collapse();
        }
        document.syncPendingFontWithCursor();
        document.cursorOnlyUpdate();
      }
      return true;
    }
    return false;
  }

  bool handlePageUpKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      final cursor = document.cursor;
      final current = CaretStop(cursor.anchorId, cursor.anchorOffset);
      final registry = document.paragraphRegistry;

      final result = movePageUp(
        document.content,
        current,
        cursor.preferredX,
        (stop) => registry.resolveCaretX(stop),
        (stop) => registry.resolveCaretY(stop),
        lines: document.logicalLines,
      );

      if (result.position != null) {
        if (isShiftPressed) {
          cursor.focusTo(result.position!.fragmentId, result.position!.offset);
          syncSelectionManager(document);
        } else {
          cursor.moveTo(result.position!.fragmentId, result.position!.offset);
          document.selectionManager.collapse();
        }
        cursor.preferredX = result.preferredX;
        document.syncPendingFontWithCursor();
        document.cursorOnlyUpdate();
      }
      return true;
    }
    return false;
  }

  bool handlePageDownKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      final cursor = document.cursor;
      final current = CaretStop(cursor.anchorId, cursor.anchorOffset);
      final registry = document.paragraphRegistry;

      final result = movePageDown(
        document.content,
        current,
        cursor.preferredX,
        (stop) => registry.resolveCaretX(stop),
        (stop) => registry.resolveCaretY(stop),
        lines: document.logicalLines,
      );

      if (result.position != null) {
        if (isShiftPressed) {
          cursor.focusTo(result.position!.fragmentId, result.position!.offset);
          syncSelectionManager(document);
        } else {
          cursor.moveTo(result.position!.fragmentId, result.position!.offset);
          document.selectionManager.collapse();
        }
        cursor.preferredX = result.preferredX;
        document.syncPendingFontWithCursor();
        document.cursorOnlyUpdate();
      }
      return true;
    }
    return false;
  }

  bool handleArrowKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (document.imeHandler.isComposing) {
        return false;
      }
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
      if (document.imeHandler.isComposing) {
        return false;
      }
      if (document.registry.dispatchTab(document, isShiftPressed: isShiftPressed)) return true;
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
      document.saveState(description: 'Paste', forceNewAction: true);
      if (isShiftPressed) {
        executeHandlePastePlain(document);
      } else {
        executeHandlePaste(document);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.keyX) {
      document.saveState(description: 'Cut', forceNewAction: true);
      executeHandleCut(document);
      return true;
    }
    if (key == LogicalKeyboardKey.keyZ) {
      if (isShiftPressed) {
        document.redo();
        return true;
      } else {
        document.undo();
        return true;
      }
    }
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
    if (document.registry.isFormattingDisabled(document)) return false;
    executeHandleBold(document);
    return true;
  }

  bool handleItalic() {
    if (document.registry.isFormattingDisabled(document)) return false;
    executeHandleItalic(document);
    return true;
  }

  bool handleUnderline() {
    if (document.registry.isFormattingDisabled(document)) return false;
    executeHandleUnderline(document);
    return true;
  }

  bool handleStrikethrough() {
    if (document.registry.isFormattingDisabled(document)) return false;
    document.saveState(description: 'Strikethrough', forceNewAction: true);
    executeHandleStrikethrough(document);
    return true;
  }

  bool handleSmallCaps() {
    if (document.registry.isFormattingDisabled(document)) return false;
    document.saveState(description: 'Small caps', forceNewAction: true);
    executeHandleSmallCaps(document);
    return true;
  }

  bool handleSuperscript() {
    if (document.registry.isFormattingDisabled(document)) return false;
    document.saveState(description: 'Superscript', forceNewAction: true);
    executeHandleSuperscript(document);
    return true;
  }

  bool handleSubscript() {
    if (document.registry.isFormattingDisabled(document)) return false;
    document.saveState(description: 'Subscript', forceNewAction: true);
    executeHandleSubscript(document);
    return true;
  }

  bool handleFontFamily(String fontFamily) {
    if (document.registry.isFormattingDisabled(document)) return false;
    document.saveState(description: 'Change font to $fontFamily');
    executeHandleFontFamily(document, fontFamily);
    return true;
  }

  bool handleFontSize(double fontSize) {
    if (document.registry.isFormattingDisabled(document)) return false;
    document.saveState(description: 'Change font size', forceNewAction: true);
    executeHandleFontSize(document, fontSize);
    return true;
  }

  bool handleParagraphSpacing({
    double? lineHeight,
    double? spacingBefore,
    double? spacingAfter,
  }) {
    if (document.registry.isFormattingDisabled(document)) return false;
    document.saveState(description: 'Change paragraph spacing', forceNewAction: true);
    executeHandleParagraphSpacing(document,
        lineHeight: lineHeight,
        spacingBefore: spacingBefore,
        spacingAfter: spacingAfter);
    return true;
  }

  bool handleTextColor(String? color) {
    if (document.registry.isFormattingDisabled(document)) return false;
    document.saveState(description: 'Change text color', forceNewAction: true);
    executeHandleTextColor(document, color);
    return true;
  }

  bool handleHighlightColor(String? color) {
    if (document.registry.isFormattingDisabled(document)) return false;
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
    if (document.registry.isFormattingDisabled(document)) return false;
    executeHandleClearFormatting(document);
    return true;
  }

  /// Applies a paragraph style to the current paragraph or selection.
  bool handleParagraphStyle(ParagraphStyle style) {
    if (document.registry.isFormattingDisabled(document)) return false;
    document.saveState(description: 'Apply paragraph style', forceNewAction: true);
    executeHandleParagraphStyle(document, style);
    return true;
  }
}