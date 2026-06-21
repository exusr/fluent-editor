import 'dart:async';
    
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart' show Fragment;
import 'package:fluent_editor/handlers/handle_insert_character.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/handlers/handle_enter.dart';
import 'package:fluent_editor/handlers/handle_backspace.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'composition_detector_stub.dart'
    if (dart.library.html) 'composition_detector_web.dart';

/// Singleton IME handler that implements [TextInputClient] for Flutter's
/// system text input channel. Preedit text is kept isolated from the document
/// model and only committed when the composition genuinely ends.
class FluentTextInputHandler with DeltaTextInputClient {
  static final FluentTextInputHandler _instance = FluentTextInputHandler._internal();
  factory FluentTextInputHandler() => _instance;
  FluentTextInputHandler._internal();

  TextInputConnection? _connection;
  FluentDocument? _document;

  bool get _shouldSyncBuffer =>
      kIsWeb || (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.macOS ||
                  defaultTargetPlatform == TargetPlatform.windows ||
                  defaultTargetPlatform == TargetPlatform.linux);

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get shouldUseBufferSync => _shouldSyncBuffer;

  String _preeditText = '';
  String get preeditText => _preeditText;

  String _preeditFragmentId = '';
  int _preeditLocalOffset = 0;
  String _preeditContainerId = '';

  int _preeditCaretOffset = 0;

  bool _isComposing = false;
  bool get isComposing => _isComposing;

  String get preeditFragmentId => _preeditFragmentId;
  int get preeditLocalOffset => _preeditLocalOffset;

  TextRange _composingRange = TextRange.empty;
  TextRange get composingRange => _composingRange;

  bool _updatingSelf = false;
  bool _justHandledEnter = false;
  String _lastSyncedFragmentId = '';
  String _lastSyncedText = '';
  String _prevSelectionKey = '';

  bool get isConnectionActive => _connection != null && _connection!.attached;

  Rect? _lastCaretRect;
  double? _lastViewHeight;

  Timer? _connectionRetryTimer;
  int _connectionRetryCount = 0;
  static const int _maxConnectionRetries = 5;
  static const List<Duration> _windowsRetryDelays = [
    Duration(milliseconds: 50),
    Duration(milliseconds: 100),
    Duration(milliseconds: 200),
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
  ];

  bool _structuralChangeInProgress = false;
  Timer? _structuralChangeTimer;
  static const Duration _structuralChangeGracePeriod =
      Duration(milliseconds: 300);

  void setViewHeight(double viewHeight) {
    _lastViewHeight = viewHeight;
    if (_connection == null || !_connection!.attached) return;
    if (kIsWeb) return;
    _connection!.setEditableSizeAndTransform(
      const Size(9999, 9999),
      Matrix4.identity(),
    );
  }

  void _updateWebImePosition() {
    if (_connection == null || !_connection!.attached) return;
    if (_document == null) return;
    final doc = _document!;

    final fragId = doc.cursor.focusId.isNotEmpty
        ? doc.cursor.focusId
        : doc.cursor.anchorId;
    if (fragId.isEmpty) return;

    final containerId = doc.findLogicalContainerId(fragId);
    if (containerId == null) return;

    final render = doc.paragraphRegistry.renderFor(containerId);
    if (render == null || !render.attached || !render.hasSize) return;

    String fontFamily = 'DejaVu Sans';
    double fontSize = 14.0;
    FontWeight fontWeight = FontWeight.normal;
    final fragNode = doc.nodeById(fragId);
    if (fragNode is Fragment) {
      fontFamily = fragNode.fontFamily;
      fontSize = fragNode.fontSize;
      fontWeight = fragNode.isBold ? FontWeight.bold : FontWeight.normal;
    }

    final fragmentStartRect = render.getCaretScreenRect(fragId, 0);

    final Matrix4 transform;
    if (fragmentStartRect != null) {
      final renderBoxOrigin = render.localToGlobal(Offset.zero);
      final fragOffsetX = fragmentStartRect.left - renderBoxOrigin.dx;
      final fragOffsetY = fragmentStartRect.top - renderBoxOrigin.dy;
      transform = render.getTransformTo(null)
          .multiplied(Matrix4.translationValues(fragOffsetX, fragOffsetY, 0));
    } else {
      transform = render.getTransformTo(null);
    }

    _connection!.setEditableSizeAndTransform(render.size, transform);

    final browserFontFamily = _webFontFallback(fontFamily);
    _connection!.setStyle(
      fontFamily: browserFontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );
  }

  String _webFontFallback(String fontFamily) {
    const webFontFamilies = {
      'Crimson Text', 'Fira Sans', 'Lato', 'Poppins', 'Titillium Web',
      'DejaVu Sans', 'DejaVu Sans Mono', 'DejaVu Serif',
    };
    if (webFontFamilies.contains(fontFamily)) {
      return '$fontFamily, sans-serif';
    }
    return switch (fontFamily) {
      _ => '$fontFamily, sans-serif',
    };
  }

  void updateCaretRect(Rect rect) {
    _lastCaretRect = rect;
    if (_connection == null || !_connection!.attached) return;
    if (kIsWeb) {
      _updateWebImePosition();
      return;
    }
    _connection!.setCaretRect(rect);
    _connection!.setComposingRect(rect);
  }

  void attachInput(FluentDocument document) {
    _document = document;
    _lastSyncedFragmentId = '';
    _lastSyncedText = '';
    _prevSelectionKey = '';
    CompositionDetector.initialize();
  }

  void detachInput() {
    commitIfComposing();
    _connectionRetryTimer?.cancel();
    _connectionRetryTimer = null;
    _connectionRetryCount = 0;
    _structuralChangeTimer?.cancel();
    _structuralChangeTimer = null;
    _structuralChangeInProgress = false;
    _connection?.close();
    _connection = null;
    _document = null;
    _resetComposition();
    _lastSyncedFragmentId = '';
    _lastSyncedText = '';
    _prevSelectionKey = '';
  }

  void showKeyboard(BuildContext context) {
    final int viewId = View.of(context).viewId;
    if (_connection == null || !_connection!.attached) {
      _attachConnection(viewId: viewId);
    }
    _connection?.show();
    if (kIsWeb) {
      _updateWebImePosition();
      return;
    }
    final h = _lastViewHeight;
    if (h != null) setViewHeight(h);
    final rect = _lastCaretRect;
    if (rect != null) {
      _connection?.setCaretRect(rect);
      _connection?.setComposingRect(rect);
    }
  }

  void hideKeyboard() {
    commitIfComposing();
    _connection?.close();
  }

  bool _attachConnection({required int viewId}) {
    if (_document == null) return false;
    try {
      _connection = TextInput.attach(
        this,
        TextInputConfiguration(
          inputType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          inputAction: TextInputAction.newline,
          enableDeltaModel: true,
          viewId: viewId,
        ),
      );
      if (_connection == null || !_connection!.attached) return false;
      _connection!.setEditingState(const TextEditingValue());
      _connection!.show();
      if (_shouldSyncBuffer) {
        syncImeBufferToFragment();
      }
      _connectionRetryCount = 0;
      _connectionRetryTimer?.cancel();
      _connectionRetryTimer = null;
      return true;
    } on PlatformException catch (e) {
      if (defaultTargetPlatform == TargetPlatform.windows &&
          e.message?.contains('view ID is null') == true &&
          _connectionRetryCount < _maxConnectionRetries) {
        final delay = _windowsRetryDelays[_connectionRetryCount.clamp(0, _windowsRetryDelays.length - 1)];
        _connectionRetryCount++;
        _connectionRetryTimer?.cancel();
        _connectionRetryTimer = Timer(delay, () {
          _connectionRetryTimer = null;
          _attachConnection(viewId: viewId);
        });
        return false;
      }
      _connection = null;
      return false;
    }
  }

  // ─── TextInputClient implementation ─────────────────────────────

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue? get currentTextEditingValue {
    if (_isComposing) {
      if (_shouldSyncBuffer) {
        final fragText = _getCurrentFragmentText() ?? '';
        final start = _preeditLocalOffset.clamp(0, fragText.length);
        final text = fragText.substring(0, start) + _preeditText + fragText.substring(start);
        final composingStart = start;
        final composingEnd = start + _preeditText.length;
        return TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(
            offset: composingStart + _preeditCaretOffset.clamp(0, _preeditText.length),
          ),
          composing: TextRange(start: composingStart, end: composingEnd),
        );
      }
      return TextEditingValue(
        text: _preeditText,
        selection: TextSelection.collapsed(offset: _preeditText.length),
        composing: _composingRange,
      );
    }
    if (_shouldSyncBuffer) {
      final text = _getCurrentFragmentText();
      if (text != null) {
        final doc = _document!;
        final cursor = doc.cursor;
        final isSingleFragSelection =
            !cursor.isCollapsed && cursor.anchorId == cursor.focusId;
        final offset = _getCursorOffsetInFragment().clamp(0, text.length);
        if (_isIOS &&
            cursor.isCollapsed &&
            offset == 0 &&
            !text.startsWith(_emptyFragmentPlaceholder)) {
          return TextEditingValue(
            text: '$_emptyFragmentPlaceholder$text',
            selection: const TextSelection.collapsed(offset: 1),
            composing: TextRange.empty,
          );
        }
        if (isSingleFragSelection) {
          return TextEditingValue(
            text: text,
            selection: TextSelection(
              baseOffset: cursor.anchorOffset.clamp(0, text.length),
              extentOffset: cursor.focusOffset.clamp(0, text.length),
            ),
            composing: TextRange.empty,
          );
        }
        if (!cursor.isCollapsed) {
          return TextEditingValue(
            text: text,
            selection: TextSelection(
              baseOffset: 0,
              extentOffset: text.length,
            ),
            composing: TextRange.empty,
          );
        }
        return TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: offset),
          composing: TextRange.empty,
        );
      }
    }
    return const TextEditingValue();
  }

  bool _isDeltaRangeValid(TextEditingDelta delta, String text) {
    final textLength = text.length;
    bool isRangeSafe(int start, int end) {
      if (start < 0 || end > textLength || start > end) return false;
      if (start > 0 && start < textLength) {
        final prev = text.codeUnitAt(start - 1);
        final curr = text.codeUnitAt(start);
        if (prev >= 0xD800 && prev <= 0xDBFF &&
            curr >= 0xDC00 && curr <= 0xDFFF) return false;
      }
      if (end > 0 && end < textLength) {
        final prev = text.codeUnitAt(end - 1);
        final curr = text.codeUnitAt(end);
        if (prev >= 0xD800 && prev <= 0xDBFF &&
            curr >= 0xDC00 && curr <= 0xDFFF) return false;
      }
      return true;
    }
    if (delta is TextEditingDeltaDeletion) {
      return isRangeSafe(delta.deletedRange.start, delta.deletedRange.end);
    }
    if (delta is TextEditingDeltaReplacement) {
      return isRangeSafe(delta.replacedRange.start, delta.replacedRange.end);
    }
    if (delta is TextEditingDeltaInsertion) {
      final offset = delta.insertionOffset;
      if (offset < 0 || offset > textLength) return false;
      if (offset > 0 && offset < textLength) {
        final prev = text.codeUnitAt(offset - 1);
        final curr = text.codeUnitAt(offset);
        if (prev >= 0xD800 && prev <= 0xDBFF &&
            curr >= 0xDC00 && curr <= 0xDFFF) return false;
      }
      return true;
    }
    return true;
  }

  TextEditingValue _safeApplyDelta(TextEditingDelta delta, TextEditingValue value) {
    final String newText;
    if (delta is TextEditingDeltaInsertion) {
      newText = value.text.replaceRange(
          delta.insertionOffset, delta.insertionOffset, delta.textInserted);
    } else if (delta is TextEditingDeltaDeletion) {
      newText = value.text.replaceRange(
          delta.deletedRange.start, delta.deletedRange.end, '');
    } else if (delta is TextEditingDeltaReplacement) {
      newText = value.text.replaceRange(
          delta.replacedRange.start, delta.replacedRange.end, delta.replacementText);
    } else {
      return TextEditingValue(
        text: delta.oldText,
        selection: delta.selection,
        composing: delta.composing,
      );
    }
    final len = newText.length;
    return TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: delta.selection.baseOffset.clamp(0, len),
        extentOffset: delta.selection.extentOffset.clamp(0, len),
      ),
      composing: delta.composing.isValid
          ? TextRange(
              start: delta.composing.start.clamp(0, len),
              end: delta.composing.end.clamp(0, len),
            )
          : TextRange.empty,
    );
  }

  TextEditingValue _applyDeltasSafely(
    TextEditingValue initialValue,
    List<TextEditingDelta> deltas,
  ) {
    var value = initialValue;
    for (final delta in deltas) {
      if (value.text != delta.oldText) {
        value = TextEditingValue(
          text: delta.oldText,
          selection: delta.selection,
          composing: delta.composing,
        );
      }
      if (!_isDeltaRangeValid(delta, value.text)) {
        debugPrint('FluentTextInputHandler: skipping malformed delta '
            '(range exceeds oldText length ${value.text.length}): $delta');
        value = TextEditingValue(
          text: delta.oldText,
          selection: delta.selection,
          composing: delta.composing,
        );
        continue;
      }
      value = _safeApplyDelta(delta, value);
    }
    return value;
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    if (_updatingSelf) return;
    if (_structuralChangeInProgress) return;
    if (_document == null) return;
    if (deltas.any((d) => d.composing.isValid)) {
      final value = _applyDeltasSafely(
        currentTextEditingValue ?? const TextEditingValue(),
        deltas,
      );
      final cleanText = _sanitizeUtf16(value.text);
      final cleanValue = TextEditingValue(
        text: cleanText,
        selection: value.selection,
        composing: value.composing,
      );
      updateEditingValue(cleanValue);
      return;
    }

    final isAutocorrectReplacement = !_isComposing &&
        deltas.any((d) =>
            d is TextEditingDeltaReplacement && d.replacementText.isNotEmpty);

    if (kIsWeb &&
        CompositionDetector.isComposing &&
        !isAutocorrectReplacement &&
        deltas.any((d) => d is! TextEditingDeltaNonTextUpdate)) {
      final value = _applyDeltasSafely(
        currentTextEditingValue ?? const TextEditingValue(),
        deltas,
      );
      final cleanText = _sanitizeUtf16(value.text);

      int composingStart, composingEnd;
      if (_isComposing) {
        final fragText = _getCurrentFragmentText() ?? '';
        final preeditOffset = _preeditLocalOffset.clamp(0, fragText.length);
        final suffixLen = fragText.length - preeditOffset;
        composingStart = preeditOffset;
        composingEnd =
            (cleanText.length - suffixLen).clamp(composingStart, cleanText.length);
      } else {
        final fragText = _getCurrentFragmentText() ?? '';
        final oldCursorOffset =
            _getCursorOffsetInFragment().clamp(0, fragText.length);
        composingStart = oldCursorOffset;
        composingEnd = value.selection.isValid
            ? value.selection.extentOffset.clamp(composingStart, cleanText.length)
            : cleanText.length;
      }

      final cleanValue = TextEditingValue(
        text: cleanText,
        selection: value.selection,
        composing: TextRange(start: composingStart, end: composingEnd),
      );
      updateEditingValue(cleanValue);
      return;
    }

    if (!_isComposing) {
      if (_shouldSyncBuffer) {
        final _isMacOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

        if (_isIOS && cursorIsAtFragmentStart) {
          final deletedPlaceholder = deltas.any((d) {
            if (d is TextEditingDeltaDeletion) {
              return d.oldText.startsWith(_emptyFragmentPlaceholder) &&
                  d.deletedRange.start == 0 &&
                  d.deletedRange.end == _emptyFragmentPlaceholder.length;
            }
            if (d is TextEditingDeltaReplacement) {
              return d.oldText.startsWith(_emptyFragmentPlaceholder) &&
                  d.replacementText.isEmpty &&
                  d.replacedRange.start == 0 &&
                  d.replacedRange.end == _emptyFragmentPlaceholder.length;
            }
            return false;
          });
          if (deletedPlaceholder) {
            _document!.saveState(description: 'Backspace', forceNewAction: false);
            executeHandleBackspace(_document!);
            syncImeBufferToFragment();
            return;
          }
        }

        if (_isIOS && cursorIsAtFragmentStart && deltas.isNotEmpty) {
          final isZeroContentDeleteAttempt = deltas.every((d) {
            if (d is TextEditingDeltaNonTextUpdate) return true;
            if (d is TextEditingDeltaDeletion) {
              return d.deletedRange.start == d.deletedRange.end;
            }
            if (d is TextEditingDeltaReplacement) {
              return d.replacementText.isEmpty &&
                  d.replacedRange.start == d.replacedRange.end;
            }
            return false;
          });
          if (isZeroContentDeleteAttempt) {
            _document!.saveState(description: 'Backspace', forceNewAction: false);
            executeHandleBackspace(_document!);
            syncImeBufferToFragment();
            return;
          }
        }

        // ── FIX: Autocorrect replacement on buffer-sync platforms ──────────
        // On web+Android (and iOS) the autocorrect/suggestion system sends a
        // single TextEditingDeltaReplacement with non-empty replacementText
        // (e.g. "italic" -> "italico"). The delta's oldText may not match our
        // current buffer if the buffer was de-synced during typing (the
        // browser's internal state drifts). Applying the delta blindly via
        // _applyDeltasSafely in that case produces a wrong intermediate text,
        // and _replaceFragmentText then writes corrupt content (e.g. "italco"
        // instead of "italico").
        //
        // Fix: intercept a single autocorrect Replacement delta here, before
        // the generic loop, and compute the new fragment text directly from
        // the real fragment text + the delta's prefix/suffix anchoring.
        // This bypasses the stale-buffer path entirely.
        if (deltas.length == 1 && deltas.first is TextEditingDeltaReplacement) {
          final rd = deltas.first as TextEditingDeltaReplacement;
          if (rd.replacementText.isNotEmpty) {
            final currentFragText = _getCurrentFragmentText() ?? '';
            final oldBufText = rd.oldText;
            final replacedRange = rd.replacedRange;
            if (replacedRange.isValid &&
                replacedRange.start >= 0 &&
                replacedRange.end <= oldBufText.length) {
              final prefix = oldBufText.substring(0, replacedRange.start);
              final suffix = oldBufText.substring(replacedRange.end);
              final replacement = rd.replacementText;
              // Reconstruct the new fragment text anchored to the real
              // fragment content so stale-buffer drift does not corrupt it.
              final String newFragText;
              if (currentFragText.startsWith(prefix) &&
                  currentFragText.endsWith(suffix) &&
                  currentFragText.length >= prefix.length + suffix.length) {
                newFragText = prefix + replacement + suffix;
              } else {
                // Buffer and fragment diverged: use delta's oldText as base.
                newFragText = prefix + replacement + suffix;
              }
              final newCursorOffset = prefix.length + replacement.length;
              _replaceFragmentText(newFragText, cursorOffset: newCursorOffset);
              return;
            }
          }
        }
        // ── END FIX ────────────────────────────────────────────────────────

        TextEditingValue value = currentTextEditingValue ?? const TextEditingValue();
        for (final delta in deltas) {
          if ((delta is TextEditingDeltaInsertion && delta.textInserted.contains('\n')) ||
              (delta is TextEditingDeltaReplacement && delta.replacementText.contains('\n'))) {
            _structuralChangeInProgress = true;
            _structuralChangeTimer?.cancel();
            _document!.saveState(description: 'Enter', forceNewAction: true);
            executeHandleEnter(_document!);
            _justHandledEnter = true;
            _lastSyncedFragmentId = _document!.cursor.focusId.isNotEmpty
                ? _document!.cursor.focusId
                : _document!.cursor.anchorId;
            syncImeBufferToFragment();
            _structuralChangeTimer = Timer(_structuralChangeGracePeriod, () {
              _structuralChangeInProgress = false;
            });
            return;
          }

          if (_isMacOS && (delta is TextEditingDeltaDeletion ||
              (delta is TextEditingDeltaReplacement &&
                  delta.replacementText.isEmpty))) {
            continue;
          }

          if (delta.oldText != value.text &&
              (delta is TextEditingDeltaDeletion ||
               (delta is TextEditingDeltaReplacement &&
                delta.replacementText.isEmpty))) {
            final deletionRange = delta is TextEditingDeltaDeletion
                ? delta.deletedRange
                : (delta as TextEditingDeltaReplacement).replacedRange;
            final deleteStart = deletionRange.start.clamp(0, delta.oldText.length);
            final deleteEnd = deletionRange.end.clamp(0, delta.oldText.length);
            final deletedText = delta.oldText.substring(deleteStart, deleteEnd);
            final graphemeCount = deletedText.characters.length;
            _document!.saveState(description: 'Backspace', forceNewAction: false);
            if (!_document!.cursor.isCollapsed) {
              executeHandleBackspace(_document!);
            } else {
              for (int i = 0; i < graphemeCount; i++) {
                executeHandleBackspace(_document!);
              }
            }
            syncImeBufferToFragment();
            return;
          }

          if (!_isMacOS && (delta is TextEditingDeltaDeletion ||
              (delta is TextEditingDeltaReplacement &&
                  delta.replacementText.isEmpty))) {
            final deletionRange = delta is TextEditingDeltaDeletion
                ? delta.deletedRange
                : (delta as TextEditingDeltaReplacement).replacedRange;
            final deletionLength = deletionRange.end - deletionRange.start;
            if (deletionRange.isValid && deletionLength == 1) {
              final textBefore = value.text;
              final deleteStart = deletionRange.start.clamp(0, textBefore.length);
              var effectiveDeleteStart = deleteStart;
              if (deleteStart > 0 && deleteStart < textBefore.length) {
                final prev = textBefore.codeUnitAt(deleteStart - 1);
                final curr = textBefore.codeUnitAt(deleteStart);
                if (prev >= 0xD800 && prev <= 0xDBFF &&
                    curr >= 0xDC00 && curr <= 0xDFFF) {
                  effectiveDeleteStart = deleteStart - 1;
                }
              }
              if (effectiveDeleteStart < textBefore.length) {
                final graphemeLen = FragmentOperations.getGraphemeLengthAt(textBefore, effectiveDeleteStart);
                if (graphemeLen > 1) {
                  var adjustedSelection = delta.selection;
                  if (effectiveDeleteStart < deleteStart) {
                    final shift = deleteStart - effectiveDeleteStart;
                    adjustedSelection = delta.selection.copyWith(
                      baseOffset: delta.selection.baseOffset >= deleteStart
                          ? delta.selection.baseOffset - shift
                          : delta.selection.baseOffset,
                      extentOffset: delta.selection.extentOffset >= deleteStart
                          ? delta.selection.extentOffset - shift
                          : delta.selection.extentOffset,
                    );
                  }
                  if (delta is TextEditingDeltaDeletion) {
                    final expandedDelta = TextEditingDeltaDeletion(
                      oldText: delta.oldText,
                      deletedRange: TextRange(start: effectiveDeleteStart, end: effectiveDeleteStart + graphemeLen),
                      selection: adjustedSelection,
                      composing: delta.composing,
                    );
                    if (value.text != delta.oldText) {
                      value = TextEditingValue(
                        text: delta.oldText,
                        selection: delta.selection,
                        composing: delta.composing,
                      );
                    }
                    if (_isDeltaRangeValid(expandedDelta, value.text)) {
                      value = _safeApplyDelta(expandedDelta, value);
                    }
                  } else if (delta is TextEditingDeltaReplacement) {
                    final expandedDelta = TextEditingDeltaReplacement(
                      oldText: delta.oldText,
                      replacementText: '',
                      replacedRange: TextRange(start: effectiveDeleteStart, end: effectiveDeleteStart + graphemeLen),
                      selection: adjustedSelection,
                      composing: delta.composing,
                    );
                    if (value.text != delta.oldText) {
                      value = TextEditingValue(
                        text: delta.oldText,
                        selection: delta.selection,
                        composing: delta.composing,
                      );
                    }
                    if (_isDeltaRangeValid(expandedDelta, value.text)) {
                      value = _safeApplyDelta(expandedDelta, value);
                    }
                  }
                  continue;
                }
              }
            }
          }

          if (value.text != delta.oldText) {
            value = TextEditingValue(
              text: delta.oldText,
              selection: delta.selection,
              composing: delta.composing,
            );
          }
          if (_isDeltaRangeValid(delta, value.text)) {
            value = _safeApplyDelta(delta, value);
          } else {
            debugPrint('FluentTextInputHandler: skipping malformed delta '
                '(range exceeds oldText length ${value.text.length}): $delta');
            value = TextEditingValue(
              text: delta.oldText,
              selection: delta.selection,
              composing: delta.composing,
            );
          }
        }
        int? cursorOffset;
        if (value.selection.isValid) {
          final selOffset = value.selection.extentOffset;
          final textLen = value.text.length;
          if (selOffset > 0 && selOffset < textLen) {
            final prev = value.text.codeUnitAt(selOffset - 1);
            final curr = value.text.codeUnitAt(selOffset);
            if (prev >= 0xD800 && prev <= 0xDBFF && curr >= 0xDC00 && curr <= 0xDFFF) {
              cursorOffset = textLen;
            } else {
              cursorOffset = selOffset;
            }
          } else {
            cursorOffset = selOffset;
          }
        }
        updateEditingValue(value, cursorOffset: cursorOffset);
        return;
      }

      // ─── Android & Desktop: buffer NOT synced, process deltas directly ──
      final hasComposing = deltas.any((d) => d.composing.isValid);
      if (hasComposing) {
        final value = _applyDeltasSafely(
          currentTextEditingValue ?? const TextEditingValue(),
          deltas,
        );
        updateEditingValue(value);
        return;
      }

      final doc = _document!;
      for (final delta in deltas) {
        if (delta is TextEditingDeltaDeletion ||
            (delta is TextEditingDeltaReplacement &&
                delta.replacementText.isEmpty)) {
          doc.saveState(description: 'Delete', forceNewAction: false);
          if (!doc.cursor.isCollapsed) {
            executeHandleBackspace(doc);
            _resetPlatformBuffer();
            return;
          }
          final deletionRange = delta is TextEditingDeltaDeletion
              ? delta.deletedRange
              : (delta as TextEditingDeltaReplacement).replacedRange;
          if (deletionRange.isValid && deletionRange.start < deletionRange.end) {
            final oldText = delta.oldText;
            final deleteStart = deletionRange.start.clamp(0, oldText.length);
            final deleteEnd = deletionRange.end.clamp(0, oldText.length);
            final deletedText = oldText.substring(deleteStart, deleteEnd);
            final graphemeCount = deletedText.characters.length;
            for (int i = 0; i < graphemeCount; i++) {
              executeHandleBackspace(doc);
            }
          } else if (deletionRange.isValid && deletionRange.start == deletionRange.end) {
            executeHandleBackspace(doc);
          }
        } else if (delta is TextEditingDeltaNonTextUpdate) {
          // No action needed.
        } else if (delta is TextEditingDeltaInsertion) {
          doc.saveState(description: 'Insert text', forceNewAction: false);
          _insertTextOrReplaceSelection(delta.textInserted, doc);
        } else if (delta is TextEditingDeltaReplacement) {
          if (_shouldSyncBuffer) {
            final value = _applyDeltasSafely(
              currentTextEditingValue ?? const TextEditingValue(),
              deltas,
            );
            updateEditingValue(value);
            return;
          }
          doc.saveState(description: 'Replace text', forceNewAction: false);
          final replacedRange = delta.replacedRange;
          final replacementText = delta.replacementText;
          final oldText = delta.oldText;
          if (replacedRange.isValid && replacedRange.start != replacedRange.end) {
            final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
            final currentOffset = doc.cursor.focusOffset;
            final typedGraphemeCount = oldText.characters.length;
            final bufferStartInDoc = currentOffset - typedGraphemeCount;
            final beforeReplace = oldText.substring(0, replacedRange.start.clamp(0, oldText.length));
            final replaceStartGraphemes = beforeReplace.characters.length;
            final upToReplaceEnd = oldText.substring(0, replacedRange.end.clamp(0, oldText.length));
            final replaceEndGraphemes = upToReplaceEnd.characters.length;
            final docStart = bufferStartInDoc + replaceStartGraphemes;
            final docEnd = bufferStartInDoc + replaceEndGraphemes;
            doc.cursor.batchUpdate(() {
              doc.cursor.anchorId = fragId;
              doc.cursor.anchorOffset = docStart;
              doc.cursor.focusId = fragId;
              doc.cursor.focusOffset = docEnd;
            });
            executeHandleReplaceSelection(replacementText, doc);
          } else {
            _insertTextOrReplaceSelection(replacementText, doc);
          }
          _resetPlatformBuffer();
        }
      }
      if (!_shouldSyncBuffer) {
        final currentFragText = _getCurrentFragmentText();
        if (currentFragText != null && currentFragText.isEmpty) {
          _resetPlatformBuffer();
        }
      }
      doc.updateContent();
      return;
    }

    // Composition active: reconstruct the final TextEditingValue by
    // applying deltas sequentially against our preedit buffer.
    final value = _applyDeltasSafely(
      currentTextEditingValue ?? const TextEditingValue(),
      deltas,
    );
    updateEditingValue(value);
  }

  @override
  void updateEditingValue(TextEditingValue value, {int? cursorOffset}) {
    if (_updatingSelf) return;
    if (_structuralChangeInProgress) return;
    if (_document == null) return;
    final doc = _document!;
    final cursor = doc.cursor;

    final currentFragId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    if (doc.nodeById(currentFragId) == null) {
      final fallback = moveLeft(
        doc.content,
        CaretStop(cursor.anchorId, cursor.anchorOffset),
        stops: doc.caretStops,
        cachedLines: doc.logicalLines,
      );
      if (fallback.position != null) {
        cursor.moveTo(fallback.position!.fragmentId, fallback.position!.offset);
      } else {
        final right = moveRight(
          doc.content,
          CaretStop(cursor.anchorId, cursor.anchorOffset),
          stops: doc.caretStops,
          cachedLines: doc.logicalLines,
        );
        if (right.position != null) {
          cursor.moveTo(right.position!.fragmentId, right.position!.offset);
        } else if (doc.caretStops.isNotEmpty) {
          final first = doc.caretStops.first;
          cursor.moveTo(first.fragmentId, first.offset);
        }
      }
    }

    if (_shouldSyncBuffer && !_isComposing) {
      final currentText = _getCurrentFragmentText() ?? '';
      final docCursorOffset = _getCursorOffsetInFragment();

      if (_isIOS &&
          docCursorOffset == 0 &&
          value.text.startsWith(_emptyFragmentPlaceholder)) {
        final placeholderLen = _emptyFragmentPlaceholder.length;
        final strippedText = value.text.substring(placeholderLen);
        final strippedBase = (value.selection.baseOffset - placeholderLen).clamp(0, strippedText.length);
        final strippedExtent = (value.selection.extentOffset - placeholderLen).clamp(0, strippedText.length);
        final strippedComposing = value.composing.isValid
            ? TextRange(
                start: (value.composing.start - placeholderLen).clamp(0, strippedText.length),
                end: (value.composing.end - placeholderLen).clamp(0, strippedText.length),
              )
            : value.composing;
        value = TextEditingValue(
          text: strippedText,
          selection: value.selection.copyWith(
            baseOffset: strippedBase,
            extentOffset: strippedExtent,
          ),
          composing: strippedComposing,
        );
      }

      if (value.text == currentText &&
          value.selection.isCollapsed &&
          value.selection.extentOffset == docCursorOffset) {
        if (_isIOS && _shouldSyncBuffer && currentText.isEmpty && docCursorOffset == 0) {
          doc.saveState(description: 'Backspace', forceNewAction: false);
          executeHandleBackspace(doc);
          syncImeBufferToFragment();
        }
        return;
      }

      if (value.composing.isValid) {
        final start = FragmentOperations.adjustIndex(value.text, value.composing.start.clamp(0, value.text.length));
        final end = FragmentOperations.adjustIndex(value.text, value.composing.end.clamp(0, value.text.length));
        final rawPreedit = value.text.substring(start, end);
        final preeditText = _sanitizeUtf16(rawPreedit);

        _isComposing = true;

        int preeditOffset;
        if (!cursor.isCollapsed) {
          final anchorNode = doc.nodeById(cursor.anchorId);
          final focusNode = doc.nodeById(cursor.focusId);
          final anchorValid = anchorNode is Fragment &&
              cursor.anchorOffset <= anchorNode.text.length;
          final focusValid = focusNode is Fragment &&
              cursor.focusOffset <= focusNode.text.length;
          if (anchorValid && focusValid) {
            doc.saveState(description: 'Replace selection', forceNewAction: false);
            executeHandleReplaceSelection('', doc);
          } else {
            if (focusValid) {
              cursor.moveTo(cursor.focusId, cursor.focusOffset);
            } else if (anchorValid) {
              cursor.moveTo(cursor.anchorId, cursor.anchorOffset);
            }
            doc.selectionManager.collapse();
          }
          preeditOffset = cursor.focusId.isNotEmpty
              ? cursor.focusOffset
              : cursor.anchorOffset;
        } else {
          final wholeCleanText = _sanitizeUtf16(value.text);
          final currentFragText = _getCurrentFragmentText() ?? '';
          final textBefore = wholeCleanText.substring(0, start);
          final textAfter = wholeCleanText.substring(end);
          final strippedText = _sanitizeUtf16(textBefore + textAfter);
          if (strippedText != currentFragText) {
            _updatingSelf = true;
            final node = doc.nodeById(cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId);
            if (node is Fragment) {
              node.text = strippedText;
            }
            _updatingSelf = false;
          }
          preeditOffset = start;
        }

        _preeditFragmentId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
        _preeditLocalOffset = preeditOffset;
        _preeditContainerId = doc.findLogicalContainerId(_preeditFragmentId) ?? '';
        cursor.imeComposing = true;
        cursor.imeComposingStart = _preeditLocalOffset;
        doc.selectionManager.clear();
        _preeditText = preeditText;
        _composingRange = TextRange(start: 0, end: preeditText.length);
        _preeditCaretOffset = value.selection.isValid
            ? (value.selection.extentOffset - start).clamp(0, preeditText.length)
            : preeditText.length;
        _invalidatePreeditRender();
        return;
      }

      final oldText = currentText;
      final newText = value.text;

      if (!cursor.isCollapsed) {
        if (newText != oldText) {
          String insertedText;
          if (cursor.anchorId == cursor.focusId) {
            final selStart = cursor.anchorOffset < cursor.focusOffset
                ? cursor.anchorOffset
                : cursor.focusOffset;
            final selEnd = cursor.anchorOffset < cursor.focusOffset
                ? cursor.focusOffset
                : cursor.anchorOffset;
            final clampedStart = selStart.clamp(0, oldText.length);
            final clampedEnd = selEnd.clamp(0, oldText.length);
            final prefixLen = clampedStart;
            final suffixLen = oldText.length - clampedEnd;
            final expectedPrefix = oldText.substring(0, prefixLen);
            final expectedSuffix = oldText.substring(clampedEnd);
            final newTextPrefix = newText.length >= prefixLen
                ? newText.substring(0, prefixLen)
                : newText;
            final newTextSuffix = newText.length >= suffixLen
                ? newText.substring(newText.length - suffixLen)
                : newText;
            if (newText.length >= prefixLen + suffixLen &&
                newTextPrefix == expectedPrefix &&
                newTextSuffix == expectedSuffix) {
              insertedText = newText.substring(prefixLen, newText.length - suffixLen);
            } else {
              insertedText = _computeInsertedText(oldText, newText);
            }
          } else {
            insertedText = newText;
          }
          doc.saveState(description: 'Replace selection', forceNewAction: false);
          if (insertedText.isNotEmpty) {
            _insertTextOrReplaceSelection(insertedText, doc);
          } else {
            executeHandleReplaceSelection('', doc);
          }
          syncImeBufferToFragment();
          doc.updateContent();
          return;
        }
      }

      final lengthDiff = newText.length - oldText.length;
      if (lengthDiff == 1 || lengthDiff == 2) {
        final diffIndex = _findDiffIndex(oldText, newText);
        if (diffIndex >= 0) {
          final oldSuffix = oldText.substring(diffIndex);
          final newSuffix = newText.substring(diffIndex + lengthDiff);
          if (oldSuffix == newSuffix) {
            final insertedText = newText.substring(diffIndex, diffIndex + lengthDiff);
            _moveCursorToFragmentOffset(diffIndex);
            _insertFinalizedText(insertedText);
            return;
          }
        }
      }

      final deleteLengthDiff = oldText.length - newText.length;
      if (deleteLengthDiff == 1 || deleteLengthDiff == 2) {
        final cursorOff = _getCursorOffsetInFragment();
        if (cursorOff == 0) {
          doc.saveState(description: 'Backspace', forceNewAction: false);
          executeHandleBackspace(doc);
          syncImeBufferToFragment();
          return;
        }
        doc.saveState(description: 'Backspace', forceNewAction: false);
        if (deleteLengthDiff == 2) {
          final diffIndex = _findDiffIndex(newText, oldText);
          if (diffIndex >= 0) {
            final deletedText = oldText.substring(diffIndex, diffIndex + 2);
            final graphemeCount = deletedText.characters.length;
            for (int i = 0; i < graphemeCount; i++) {
              executeHandleBackspace(doc);
            }
          } else {
            executeHandleBackspace(doc);
          }
        } else {
          executeHandleBackspace(doc);
        }
        syncImeBufferToFragment();
        return;
      }

      if (newText != oldText) {
        if (newText.isEmpty && oldText.isNotEmpty) {
          final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
          final node = doc.nodeById(fragId);
          if (node is Fragment) {
            final cellParent = findAncestorCell(doc.content, node);
            if (cellParent != null) {
              node.text = '\u200B';
              doc.cursor.moveTo(fragId, 0);
              doc.updateContent();
              syncImeBufferToFragment();
              return;
            }
            doc.saveState(description: 'Backspace', forceNewAction: false);
            node.text = '';
            doc.cursor.moveTo(fragId, 0);
            doc.updateContent();
            executeHandleBackspace(doc);
            syncImeBufferToFragment();
            return;
          }
        }
        if (!cursor.isCollapsed) {
          final insertedText = newText;
          doc.saveState(description: 'Replace selection', forceNewAction: false);
          if (insertedText.isNotEmpty) {
            _insertTextOrReplaceSelection(insertedText, doc);
          } else {
            executeHandleReplaceSelection('', doc);
          }
          syncImeBufferToFragment();
          doc.updateContent();
          return;
        }
        _replaceFragmentText(newText, cursorOffset: cursorOffset);
        return;
      }

      if (newText == oldText && value.selection.isValid && value.selection.isCollapsed) {
        _moveCursorToFragmentOffset(value.selection.extentOffset);
        return;
      }

      return;
    }

    // ─── Active composition handling ────────────────────────────────
    if (_isComposing) {
      if (value.composing.isValid) {
        if (value.text.isEmpty) {
          _cancelPreedit();
          return;
        }
        if (_shouldSyncBuffer) {
          final start = FragmentOperations.adjustIndex(value.text, value.composing.start.clamp(0, value.text.length));
          final end = FragmentOperations.adjustIndex(value.text, value.composing.end.clamp(0, value.text.length));
          final rawPreedit = value.text.substring(start, end);
          final preeditText = _sanitizeUtf16(rawPreedit);
          _preeditText = preeditText;
          _composingRange = TextRange(start: 0, end: preeditText.length);
          _preeditCaretOffset = value.selection.isValid
              ? (value.selection.extentOffset - start).clamp(0, preeditText.length)
              : preeditText.length;
        } else {
          final start = value.composing.start.clamp(0, value.text.length);
          final end = value.composing.end.clamp(0, value.text.length);
          final rawPreedit = value.text.substring(start, end);
          final preeditText = _sanitizeUtf16(rawPreedit);
          _preeditText = preeditText;
          _composingRange = TextRange(start: 0, end: preeditText.length);
          _preeditCaretOffset = value.selection.isValid
              ? (value.selection.extentOffset - start).clamp(0, preeditText.length)
              : preeditText.length;
        }
        _invalidatePreeditRender();
        return;
      }

      if (!_shouldSyncBuffer && value.text == _preeditText) {
        return;
      }

      if (value.text.isEmpty) {
        _cancelPreedit();
        return;
      }

      if (_shouldSyncBuffer) {
        final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
        final node = doc.nodeById(fragId);
        if (node is Fragment) {
          _updatingSelf = true;
          doc.saveState(description: 'Replace text', forceNewAction: false);
          final currentFragText = node.text;
          final insertOffset = _preeditLocalOffset.clamp(0, currentFragText.length);
          final prefix = currentFragText.substring(0, insertOffset);
          final suffix = currentFragText.substring(insertOffset);
          String committedText;
          if (value.text.length >= prefix.length + suffix.length &&
              value.text.startsWith(prefix) &&
              value.text.endsWith(suffix)) {
            committedText = _sanitizeUtf16(
              value.text.substring(prefix.length, value.text.length - suffix.length),
            );
          } else {
            committedText = _sanitizeUtf16(_preeditText);
          }
          node.text = _sanitizeUtf16(prefix + committedText + suffix);
          final _usePlatformSelection = !kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.linux ||
               defaultTargetPlatform == TargetPlatform.windows ||
               defaultTargetPlatform == TargetPlatform.macOS);
          final newCursorOffset = (_usePlatformSelection &&
                  value.selection.isValid &&
                  value.selection.isCollapsed &&
                  value.selection.extentOffset >= prefix.length &&
                  value.selection.extentOffset <= prefix.length + committedText.length)
              ? value.selection.extentOffset
              : insertOffset + committedText.length;
          doc.cursor.moveTo(fragId, _snapCursorOffset(node.text, newCursorOffset));
          _resetComposition();
          doc.cursor.imeComposing = false;
          doc.updateContent();
          _updatingSelf = false;
          syncImeBufferToFragment();
        }
        return;
      }

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final finalizedText = value.text.isNotEmpty ? value.text : _preeditText;
        _commitPreedit(finalizedText);
      } else {
        _commitPreedit(_preeditText);
      }

      _resetPlatformBuffer();
      return;
    }

    // ─── New composition start ────────────────────────────────────
    if (value.text.isEmpty) return;

    if (!value.composing.isValid) {
      if (!_shouldSyncBuffer) {
        final currentFragText = _getCurrentFragmentText() ?? '';
        if (value.text == currentFragText) return;
      }
      _insertFinalizedText(value.text);
      if (_shouldSyncBuffer) {
        syncImeBufferToFragment();
      } else {
        _resetPlatformBuffer();
      }
      return;
    }

    _isComposing = true;

    if (!cursor.isCollapsed) {
      final anchorNode = doc.nodeById(cursor.anchorId);
      final focusNode = doc.nodeById(cursor.focusId);
      final anchorValid = anchorNode is Fragment &&
          cursor.anchorOffset <= anchorNode.text.length;
      final focusValid = focusNode is Fragment &&
          cursor.focusOffset <= focusNode.text.length;
      if (anchorValid && focusValid) {
        doc.saveState(description: 'Replace selection', forceNewAction: false);
        executeHandleReplaceSelection('', doc);
      } else {
        if (focusValid) {
          cursor.moveTo(cursor.focusId, cursor.focusOffset);
        } else if (anchorValid) {
          cursor.moveTo(cursor.anchorId, cursor.anchorOffset);
        }
        doc.selectionManager.collapse();
      }
    }

    _preeditFragmentId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    _preeditLocalOffset = cursor.focusId.isNotEmpty ? cursor.focusOffset : cursor.anchorOffset;
    _preeditContainerId = doc.findLogicalContainerId(_preeditFragmentId) ?? '';
    cursor.imeComposing = true;
    cursor.imeComposingStart = _preeditLocalOffset;
    doc.selectionManager.clear();
    final compStart = value.composing.start.clamp(0, value.text.length);
    final compEnd = value.composing.end.clamp(0, value.text.length);
    final rawPreedit = value.text.substring(compStart, compEnd);
    final preeditText = _sanitizeUtf16(rawPreedit);
    _preeditText = preeditText;
    _composingRange = TextRange(start: 0, end: preeditText.length);
    _preeditCaretOffset = value.selection.isValid
        ? (value.selection.extentOffset - compStart).clamp(0, preeditText.length)
        : preeditText.length;
    _invalidatePreeditRender();
  }

  @override
  void performAction(TextInputAction action) {
    if (_document == null) return;
    switch (action) {
      case TextInputAction.newline:
        if (_justHandledEnter) {
          _justHandledEnter = false;
          break;
        }
        _structuralChangeInProgress = true;
        _structuralChangeTimer?.cancel();
        commitIfComposing();
        _document!.saveState(description: 'Enter', forceNewAction: true);
        executeHandleEnter(_document!);
        _lastSyncedFragmentId = _document!.cursor.focusId.isNotEmpty
            ? _document!.cursor.focusId
            : _document!.cursor.anchorId;
        syncImeBufferToFragment();
        _structuralChangeTimer = Timer(_structuralChangeGracePeriod, () {
          _structuralChangeInProgress = false;
        });
        break;
      case TextInputAction.go:
      case TextInputAction.send:
      case TextInputAction.done:
        commitIfComposing();
        break;
      default:
        break;
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  bool onFocusReceived() => false;

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void connectionClosed() {
    commitIfComposing();
    _connection = null;
  }

  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void performSelector(String selectorName) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void showToolbar() {}

  // ─── Preedit lifecycle ──────────────────────────────────────────

  void commitIfComposing() {
    if (_isComposing && _preeditText.isNotEmpty) {
      _commitPreedit(_preeditText);
    } else if (_isComposing) {
      _cancelPreedit();
    }
  }

  void _insertTextOrReplaceSelection(String text, FluentDocument doc) {
    for (final char in text.characters) {
      if (!doc.cursor.isCollapsed) {
        executeHandleReplaceSelection(char, doc);
      } else {
        executeHandleInsertCharacter(char, doc);
      }
    }
  }

  String _computeInsertedText(String oldText, String newText) {
    if (oldText.isEmpty) return newText;
    if (newText.isEmpty) return '';
    int prefixLen = 0;
    final minLen = oldText.length < newText.length ? oldText.length : newText.length;
    while (prefixLen < minLen && oldText[prefixLen] == newText[prefixLen]) {
      prefixLen++;
    }
    int suffixLen = 0;
    while (suffixLen < oldText.length - prefixLen &&
        suffixLen < newText.length - prefixLen &&
        oldText[oldText.length - 1 - suffixLen] ==
            newText[newText.length - 1 - suffixLen]) {
      suffixLen++;
    }
    return newText.substring(prefixLen, newText.length - suffixLen);
  }

  void _insertFinalizedText(String text) {
    if (_document == null || text.isEmpty) return;
    final doc = _document!;
    doc.saveState(description: 'Insert text', forceNewAction: false);
    _insertTextOrReplaceSelection(text, doc);
    if (_shouldSyncBuffer) {
      syncImeBufferToFragment();
    } else {
      _resetPlatformBuffer();
    }
    doc.updateContent();
  }

  void _commitPreedit(String text) {
    if (_document == null || text.isEmpty) {
      _cancelPreedit();
      return;
    }
    final doc = _document!;
    _updatingSelf = true;
    doc.saveState(description: 'IME commit', forceNewAction: false);
    doc.cursor.imeComposing = false;
    doc.cursor.moveTo(_preeditFragmentId, _preeditLocalOffset);
    _insertTextOrReplaceSelection(text, doc);
    _resetComposition();
    _updatingSelf = false;
    if (_shouldSyncBuffer) {
      syncImeBufferToFragment();
    } else {
      _resetPlatformBuffer();
    }
    doc.updateContent();
  }

  void _cancelPreedit() {
    final doc = _document;
    _resetComposition();
    if (doc != null) {
      doc.cursor.imeComposing = false;
      if (_shouldSyncBuffer) {
        syncImeBufferToFragment();
      } else {
        _resetPlatformBuffer();
      }
      doc.cursorOnlyUpdate();
    }
  }

  void _resetPlatformBuffer() {
    if (_connection == null || !_connection!.attached) return;
    _updatingSelf = true;
    try {
      _connection!.setEditingState(const TextEditingValue());
      _lastSyncedText = '';
    } on PlatformException catch (e) {
      debugPrint('FluentTextInputHandler: _resetPlatformBuffer failed: ${e.message}');
    }
    _updatingSelf = false;
  }

  void _resetComposition() {
    _isComposing = false;
    _preeditText = '';
    _composingRange = TextRange.empty;
    _preeditFragmentId = '';
    _preeditLocalOffset = 0;
    _preeditContainerId = '';
    _preeditCaretOffset = 0;
  }

  /// Handles composing range changes on Android when composition starts/changes.
  void _handleComposingRangeChange(TextRange composing, int cursorOffset) {
    if (!composing.isValid) {
      if (_isComposing) _cancelPreedit();
      return;
    }
    if (!_isComposing) {
      final doc = _document;
      if (doc == null) return;
      final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
      _preeditFragmentId = fragId;
      _preeditLocalOffset = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusOffset : doc.cursor.anchorOffset;
      _preeditContainerId = doc.findLogicalContainerId(_preeditFragmentId) ?? '';
      doc.cursor.imeComposing = true;
      _isComposing = true;
      _preeditText = '';
      _composingRange = TextRange.empty;
    }
    _composingRange = composing;
    _preeditCaretOffset = cursorOffset;
    _invalidatePreeditRender();
  }

  static const String _emptyFragmentPlaceholder = '\u200B';

  String? _getCurrentFragmentText() {
    final doc = _document;
    if (doc == null) return null;
    final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
    final node = doc.nodeById(fragId);
    if (node is Fragment) return node.text;
    return null;
  }

  int _getCursorOffsetInFragment() {
    final doc = _document;
    if (doc == null) return 0;
    return doc.cursor.focusId.isNotEmpty ? doc.cursor.focusOffset : doc.cursor.anchorOffset;
  }

  bool get cursorIsAtFragmentStart => _getCursorOffsetInFragment() == 0;

  int _findDiffIndex(String a, String b) {
    final minLen = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < minLen; i++) {
      if (a[i] != b[i]) return i;
    }
    if (a.length != b.length) return minLen;
    return -1;
  }

  int _snapCursorOffset(String text, int offset) {
    if (text.isEmpty) return offset;
    return FragmentOperations.adjustIndex(text, offset.clamp(0, text.length));
  }

  void _moveCursorToFragmentOffset(int offset) {
    final doc = _document;
    if (doc == null) return;
    final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
    final node = doc.nodeById(fragId);
    final text = node is Fragment ? node.text : '';
    doc.cursor.moveTo(fragId, _snapCursorOffset(text, offset));
  }

  void _replaceFragmentText(String newText, {int? cursorOffset}) {
    final doc = _document;
    if (doc == null) return;
    final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
    final node = doc.nodeById(fragId);
    if (node is! Fragment) return;
    doc.saveState(description: 'Replace text', forceNewAction: false);
    final cleanText = _sanitizeUtf16(newText);
    node.text = cleanText;
    final finalOffset = _snapCursorOffset(cleanText, cursorOffset ?? cleanText.length);
    doc.cursor.moveTo(fragId, finalOffset);
    doc.updateContent();
    syncImeBufferToFragment();
  }

  void syncImeBufferToFragment() {
    if (_connection == null || !_connection!.attached) return;
    if (_isComposing) return;
    final doc = _document;
    if (doc == null) return;
    final currentFragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;

    if (!_shouldSyncBuffer) {
      if (currentFragId != _lastSyncedFragmentId) {
        _resetPlatformBuffer();
      }
      _lastSyncedFragmentId = currentFragId;
      return;
    }

    _lastSyncedFragmentId = currentFragId;
    final text = _getCurrentFragmentText();
    if (text == null) return;
    final cursor = doc.cursor;
    final isSingleFragSelection =
        !cursor.isCollapsed && cursor.anchorId == cursor.focusId;
    final isMultiFragSelection =
        !cursor.isCollapsed && cursor.anchorId != cursor.focusId;
    final offset = _getCursorOffsetInFragment();
    final bool usePlaceholder = _isIOS &&
        cursor.isCollapsed &&
        offset == 0 &&
        !text.startsWith(_emptyFragmentPlaceholder);
    final syncedText = usePlaceholder ? '$_emptyFragmentPlaceholder$text' : text;
    final syncedOffset = usePlaceholder ? 1 : offset.clamp(0, syncedText.length);
    final TextSelection syncedSelection;
    if (isSingleFragSelection && !usePlaceholder) {
      syncedSelection = TextSelection(
        baseOffset: cursor.anchorOffset.clamp(0, syncedText.length),
        extentOffset: cursor.focusOffset.clamp(0, syncedText.length),
      );
    } else if (isMultiFragSelection && !usePlaceholder) {
      syncedSelection = TextSelection(
        baseOffset: 0,
        extentOffset: syncedText.length,
      );
    } else {
      syncedSelection = TextSelection.collapsed(offset: syncedOffset);
    }
    final currentSelectionKey =
        '${cursor.anchorId}:${cursor.anchorOffset}:${cursor.focusId}:${cursor.focusOffset}';
    final bool selectionChanged = currentSelectionKey != _prevSelectionKey;
    _prevSelectionKey = currentSelectionKey;

    _updatingSelf = true;
    try {
      if (kIsWeb && syncedText.length < _lastSyncedText.length) {
        _connection!.setEditingState(const TextEditingValue());
      }
      if (_isIOS && selectionChanged) {
        _connection!.setEditingState(const TextEditingValue());
      }
      _connection!.setEditingState(TextEditingValue(
        text: syncedText,
        selection: syncedSelection,
        composing: TextRange.empty,
      ));
      _lastSyncedText = syncedText;
    } on PlatformException catch (e) {
      debugPrint('FluentTextInputHandler: syncImeBufferToFragment failed: ${e.message}');
    }
    _updatingSelf = false;
    if (kIsWeb) {
      _updateWebImePosition();
    }
  }

  void _invalidatePreeditRender() {
    if (_document == null || _preeditContainerId.isEmpty) return;
    final doc = _document!;
    final render = doc.paragraphRegistry.renderFor(_preeditContainerId);
    if (render != null) {
      render.imePreeditText = _preeditText;
      render.imeComposingRange = _composingRange;
      render.imePreeditFragmentId = _preeditFragmentId;
      render.imePreeditLocalOffset = _preeditLocalOffset;
      render.markNeedsPaint();
      final caretOffset = _preeditCaretOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isComposing) return;
        final rect = render.getImePreeditCaretScreenRect(caretOffset);
        if (rect != null) {
          updateCaretRect(rect);
        }
      });
    }
  }

  String _sanitizeUtf16(String s) {
    if (s.isEmpty) return s;
    final codeUnits = s.codeUnits;
    final cleanUnits = <int>[];
    for (int i = 0; i < codeUnits.length; i++) {
      int unit = codeUnits[i];
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (i + 1 < codeUnits.length && codeUnits[i + 1] >= 0xDC00 && codeUnits[i + 1] <= 0xDFFF) {
          cleanUnits.add(unit);
          cleanUnits.add(codeUnits[i + 1]);
          i++;
        } else {
          cleanUnits.add(0xFFFD);
        }
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        cleanUnits.add(0xFFFD);
      } else {
        cleanUnits.add(unit);
      }
    }
    return String.fromCharCodes(cleanUnits);
  }

  bool isPreeditInContainer(String containerId) {
    return _isComposing && _preeditContainerId == containerId;
  }
}
