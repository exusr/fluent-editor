import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/controllers/document_language_controller.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/widgets/node_widget_builder.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/widgets/editor/fluent_toolbar_widget.dart';
import 'package:fluent_editor/widgets/editor/fluent_bubble_toolbar.dart';
import 'package:fluent_editor/widgets/nodes/virtualized_selectable_area.dart';
import 'package:fluent_editor/widgets/editor/fluent_unified_sidebar.dart';
import 'package:fluent_editor/plugins/plugin_api.dart';

/// Toolbar display mode.
enum FluentToolbarMode { fixed, bubble }

class FluentDocumentWidget extends StatefulWidget {
  const FluentDocumentWidget({
    super.key,
    required this.document,
    this.maxWidth = 800.0,
    this.labels,
    this.sidebar,
    this.toolbarMode = FluentToolbarMode.fixed,
    this.bubbleActions = const [],
  });

  final FluentDocument document;
  final double maxWidth;
  final FluentEditorLabels? labels;
  final Widget? sidebar;
  final FluentToolbarMode toolbarMode;

  /// Extra widgets appended to the bubble toolbar when in bubble mode.
  final List<Widget> bubbleActions;

  @override
  State<FluentDocumentWidget> createState() => _FluentDocumentWidgetState();
}

/// Provides layout references (scroll controller + content stack key)
/// so that sidebars can compute positions relative to the shared Stack.
class DocumentLayout extends InheritedWidget {
  final ScrollController scrollController;
  final GlobalKey contentStackKey;

  const DocumentLayout({
    super.key,
    required this.scrollController,
    required this.contentStackKey,
    required super.child,
  });

  static DocumentLayout? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DocumentLayout>();
  }

  @override
  bool updateShouldNotify(DocumentLayout old) =>
      scrollController != old.scrollController ||
      contentStackKey != old.contentStackKey;
}

class _FluentDocumentWidgetState extends State<FluentDocumentWidget> {
  bool _showStatsPanel = false;
  bool _isSidebarCollapsed = false;
  bool _pendingScrollToCursor = false;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _contentStackKey = GlobalKey();

  final Map<int, double> _itemHeights = {};
  double _averageItemHeight = 40.0;
  double _totalMeasuredHeight = 0.0;

  // Cumulative height cache for O(1) offset lookup in _ensureCursorVisibleVirtualized.
  // Invalidated when _itemHeights changes.
  List<double>? _cumulativeHeights;
  int _cumulativeHeightsCount = -1;

  // Cached word/char counts keyed by content version to avoid O(n) tree walk on every rebuild.
  int _cachedWordCount = 0;
  int _cachedCharCount = 0;
  int? _statsContentVersion;

  void _computeStats() {
    final version = widget.document.contentVersion;
    if (_statsContentVersion == version) return;

    int words = 0;
    int chars = 0;
    final root = widget.document.content;

    void visit(FNode node) {
      // Link extends Paragraph implements Fragment — check Link/InlineContainerNode first.
      if (node is Fragment && node is! InlineContainerNode) {
        final text = node.text;
        if (text.isNotEmpty) {
          // Simple word boundary scan — avoids RegExp + List allocation per fragment.
          bool inWord = false;
          for (int i = 0; i < text.length; i++) {
            final isSpace = text.codeUnitAt(i) <= 32;
            if (isSpace) {
              if (inWord) {
                words++;
                inWord = false;
              }
            } else {
              inWord = true;
            }
          }
          if (inWord) words++;
        }
        chars += text.length;
      } else if (node is InlineContainerNode) {
        for (final child in childrenOf(node)) {
          visit(child);
        }
      } else if (node is FluentList) {
        for (final item in node.items) {
          visit(item);
        }
      }
    }

    visit(root);
    _cachedWordCount = words;
    _cachedCharCount = chars;
    _statsContentVersion = version;
  }

  Timer? _blinkTimer;
  static const Duration _blinkInterval = Duration(milliseconds: 530);

  /// Repaints the paragraph that currently owns the caret, if rendered.
  void _repaintCaretParagraph() {
    final doc = widget.document;
    final cursor = doc.cursor;
    final fragId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    if (fragId.isEmpty) return;
    final containerId = doc.findLogicalContainerId(fragId);
    if (containerId == null) return;
    doc.paragraphRegistry.renderFor(containerId)?.markNeedsPaint();
  }

  DateTime? _lastBlinkRestart;

  /// (Re)starts the blink cycle with the caret visible. Called on init and on
  /// every cursor/document change so the caret restarts solid after movement.
  /// Debounced: during key-hold events arrive at 30-60 Hz; restarting the
  /// timer that often is wasteful. We only restart if >200 ms elapsed.
  void _restartBlink() {
    final now = DateTime.now();
    if (_lastBlinkRestart != null &&
        now.difference(_lastBlinkRestart!).inMilliseconds < 200) {
      _blinkTimer?.cancel();
      widget.document.paragraphRegistry.caretVisible = true;
      _repaintCaretParagraph();
      // Schedule blink restart after inactivity; cancelled if another keypress arrives first.
      _blinkTimer = Timer(_blinkInterval, _startBlinking);
      return;
    }
    _lastBlinkRestart = now;
    _startBlinking();
  }

  void _startBlinking() {
    _blinkTimer?.cancel();
    widget.document.paragraphRegistry.caretVisible = true;
    _repaintCaretParagraph();
    _blinkTimer = Timer.periodic(_blinkInterval, (_) {
      final registry = widget.document.paragraphRegistry;
      registry.caretVisible = !registry.caretVisible;
      _repaintCaretParagraph();
    });
  }

   Widget _buildVirtualizedContent(bool hasActiveSidebar) {
    return Focus(
      focusNode: widget.document.editorFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (widget.document.editorFocusNode.hasFocus &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.tab) {
          final isShift = HardwareKeyboard.instance.isShiftPressed;
          final handled = widget.document.registry.plugins.any(
            (p) => p.onTab(widget.document, isShiftPressed: isShift),
          );
          if (handled) return KeyEventResult.handled;
        }

        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final keyboard = HardwareKeyboard.instance;
        if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
            _shortcutKeys.contains(event.logicalKey) &&
            (keyboard.isControlPressed || keyboard.isMetaPressed)) {
          return KeyEventResult.ignored;
        }

        if (widget.document.imeHandler.isComposing) {
          final isCtrl = HardwareKeyboard.instance.isControlPressed;
          final isMeta = HardwareKeyboard.instance.isMetaPressed;
          if (isCtrl || isMeta) {
            return KeyEventResult.ignored;
          }

          // On Android/iOS, backspace and delete during IME composing must be
          // left to the IME delta pipeline.  Previously this guard checked
          // `!isComposing` (always false here) so it was dead code, causing
          // the key event to reach executeHandleBackspace which operated on
          // the already-stripped fragment text instead of the composing text.
          if (widget.document.imeHandler.shouldUseBufferSync &&
              widget.document.imeHandler.isConnectionActive &&
              (event.logicalKey == LogicalKeyboardKey.backspace ||
                  event.logicalKey == LogicalKeyboardKey.delete)) {
            return KeyEventResult.ignored;
          }

          widget.document.manageEvent(event);
          return KeyEventResult.handled;
        }

        widget.document.manageEvent(event);
        return KeyEventResult.handled;
      },
      child: Padding(
        padding: const EdgeInsets.all(24.0).copyWith(
          right:
              24.0 + (!hasActiveSidebar || _isSidebarCollapsed ? 0 : 300),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: VirtualizedSelectableArea(
              document: widget.document,
              scrollController: _scrollController,
              itemCount: widget.document.content.nodes.length,
              onHeightsChanged: (index, height) {
                final oldHeight = _itemHeights[index];
                if (oldHeight != null) {
                  _totalMeasuredHeight -= oldHeight;
                }
                _itemHeights[index] = height;
                _totalMeasuredHeight += height;
                _cumulativeHeights = null;
                if (_itemHeights.isNotEmpty) {
                  _averageItemHeight =
                      _totalMeasuredHeight / _itemHeights.length;
                }
              },
              itemBuilder: (context, index) {
                final node = widget.document.content.nodes[index];
                return buildFNodeWidget(node, widget.document);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Resolves the current caret screen rect and forwards it to the IME so
  /// macOS can position the candidate window next to the cursor.
  /// Uses two nested postFrameCallbacks: the first waits for the current frame
  /// to complete (setState/layout), the second waits for the following paint so
  /// the render object coordinates are guaranteed to be up-to-date.
  void _updateImeCaretRect() {
    final cursor = widget.document.cursor;
    final fragId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    if (fragId.isEmpty) return;
    final offset = cursor.focusId.isNotEmpty
        ? cursor.focusOffset
        : cursor.anchorOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final rect = widget.document.paragraphRegistry.resolveCaretScreenRect(
          fragId,
          offset,
        );
        if (rect != null && (rect.width > 0 || rect.height > 0)) {
          final view = View.of(context);
          final viewH = view.physicalSize.height / view.devicePixelRatio;
          widget.document.imeHandler.setViewHeight(viewH);
          widget.document.imeHandler.updateCaretRect(rect);
        }
      });
    });
  }

  int _lastTopLevelNodeCount = -1;

  void _onDocumentChanged() {
    _updateImeCaretRect();
    widget.document.imeHandler.syncImeBufferToFragment();

    if (widget.document.cursorOnlyChange) {
      _restartBlink();
      if (!_pendingScrollToCursor) {
        _pendingScrollToCursor = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pendingScrollToCursor = false;
          _ensureCursorVisible();
        });
      }
      return;
    }

    setState(() {});

    _restartBlink();
    if (!_pendingScrollToCursor) {
      _pendingScrollToCursor = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingScrollToCursor = false;
        _ensureCursorVisible();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onDocumentChanged);
    widget.document.imeHandler.attachInput(widget.document);
    widget.document.editorFocusNode.addListener(_onEditorFocusChanged);
    HardwareKeyboard.instance.addHandler(_onHardwareKeyEvent);
    if (widget.document.content.nodes.isNotEmpty) {
      widget.document.cursor.document = widget.document;
      widget.document.eventHandler.document = widget.document;
      final firstNode = widget.document.content.nodes[0];
      if (firstNode is Paragraph && firstNode.fragments.isNotEmpty) {
        final firstFrag = firstNode.fragments.first;
        if (firstFrag is Fragment) {
          widget.document.cursor.moveTo(firstFrag.id, 0);
        } else {
          widget.document.cursor.moveTo(firstNode.id, 0);
        }
      } else {
        widget.document.cursor.moveTo(firstNode.id, 0);
      }
    }
    widget.document.saveState(
      description: 'Initial state',
      forceNewAction: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.document.imeHandler.showKeyboard(context);
    });
    _initDocumentLanguage();
    DocumentLanguageController.instance.currentLanguage.addListener(
      _onLanguageChanged,
    );
    _restartBlink();
  }

  void _initDocumentLanguage() async {
    await DocumentLanguageController.instance.initialize();
    widget.document.documentLanguage =
        DocumentLanguageController.instance.current.code;
  }

  void _onLanguageChanged() {
    final newLang = DocumentLanguageController.instance.current.code;
    if (widget.document.documentLanguage != newLang) {
      widget.document.documentLanguage = newLang;
    }
  }

  void _onEditorFocusChanged() {
    if (widget.document.editorFocusNode.hasFocus) {
      widget.document.imeHandler.showKeyboard(context);
    } else {
      widget.document.imeHandler.commitIfComposing();
    }
  }

  /// Global HardwareKeyboard handler active on all platforms.
  /// Intercepts shortcuts and navigation keys so they reach the EventHandler
  /// even when the platform text input owns focus.
  ///
  /// During an active IME composition all non-navigation keys are suppressed
  /// so the system IME receives them instead of the raw key pipeline.
  static final _navKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
  };

  static final _shortcutKeys = {LogicalKeyboardKey.keyZ};

  bool _onHardwareKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final doc = widget.document;
    final keyboard = HardwareKeyboard.instance;
    final isCtrl = keyboard.isControlPressed;
    final isMeta = keyboard.isMetaPressed;
    final key = event.logicalKey;

    // When the editor doesn't have focus (e.g. a dialog is open), let all
    // key events pass through to the framework so other widgets get input.
    if (!doc.editorFocusNode.hasFocus) return false;

    if (!_shortcutKeys.contains(key)) {
      return false;
    }

    if (doc.imeHandler.isComposing) {
      if (isCtrl || isMeta) {
        doc.manageEvent(event);
        return true;
      }
      return false; // Let IME consume everything else (incl. arrows)
    }

    final _isVirtualKeyboard =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    if (_isVirtualKeyboard &&
        doc.imeHandler.shouldUseBufferSync &&
        doc.cursor.isCollapsed &&
        !doc.imeHandler.isComposing &&
        (key == LogicalKeyboardKey.backspace ||
            key == LogicalKeyboardKey.delete)) {
      return false;
    }

    if (isCtrl || isMeta) {
      doc.manageEvent(event);
      return true;
    }

    if (_navKeys.contains(key)) {
      doc.manageEvent(event);
      return true;
    }

    if (doc.imeHandler.isConnectionActive) return false;
    doc.manageEvent(event);
    return true;
  }

  void _ensureCursorVisible() {
    _ensureCursorVisibleVirtualized();
  }

  void _ensureCursorVisibleVirtualized() {
    final cursor = widget.document.cursor;
    if (cursor.anchorId.isEmpty) return;

    final cursorNodeIndex = _findNodeIndexCached(cursor.anchorId);
    if (cursorNodeIndex == -1) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final nodeCount = widget.document.content.nodes.length;
      // Build cumulative heights cache if stale.
      if (_cumulativeHeights == null || _cumulativeHeightsCount != nodeCount) {
        _cumulativeHeightsCount = nodeCount;
        final cum = List<double>.filled(nodeCount, 0.0);
        double acc = 0.0;
        for (int i = 0; i < nodeCount; i++) {
          acc += _itemHeights[i] ?? _averageItemHeight;
          cum[i] = acc;
        }
        _cumulativeHeights = cum;
      }
      final cum = _cumulativeHeights!;
      final nodeStart = cursorNodeIndex == 0 ? 0.0 : cum[cursorNodeIndex - 1];
      final nodeHeight = _itemHeights[cursorNodeIndex] ?? _averageItemHeight;
      final nodeEnd = nodeStart + nodeHeight;

      final position = _scrollController.position;
      const margin = 80.0;
      final viewportStart = position.pixels;
      final viewportEnd = viewportStart + position.viewportDimension;

      if (nodeStart >= viewportStart + margin &&
          nodeEnd <= viewportEnd - margin) {
        return;
      }

      double scrollTarget;
      if (nodeEnd > viewportEnd - margin) {
        scrollTarget = nodeEnd + margin - position.viewportDimension;
      } else {
        scrollTarget = nodeStart - margin;
      }

      final clampedOffset = scrollTarget.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      position.jumpTo(clampedOffset.toDouble());
    });
  }

  int _findNodeIndexCached(String fragmentId) {
    return widget.document.topLevelIndexOf(fragmentId);
  }

  @override
  void didUpdateWidget(FluentDocumentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onDocumentChanged);
      widget.document.addListener(_onDocumentChanged);
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    widget.document.removeListener(_onDocumentChanged);
    widget.document.editorFocusNode.removeListener(_onEditorFocusChanged);
    DocumentLanguageController.instance.currentLanguage.removeListener(
      _onLanguageChanged,
    );
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);
    super.dispose();
  }

  List<Widget> _buildPluginUiContributions(FluentPluginUiLocation location) {
    final doc = widget.document;
    return doc.registry
        .uiAt(location)
        .where((c) => c.visible?.call(doc) ?? true)
        .map((c) => Builder(builder: (ctx) => c.builder(ctx, doc)))
        .toList();
  }

  Widget? _resolveSidebar(BuildContext context) {
    if (widget.sidebar != null) return widget.sidebar;
    if (!widget.document.registry.hasSidebarPlugins) return null;
    final items = widget.document.registry.buildSidebarItems(context, widget.document);
    return FluentUnifiedSidebar(
      document: widget.document,
      items: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeSidebar = _resolveSidebar(context);

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          if (widget.toolbarMode == FluentToolbarMode.fixed)
            FluentToolbar(document: widget.document, labels: widget.labels),
          Expanded(
            child: Stack(
              key: _contentStackKey,
              children: [
                Stack(
                  children: [
                    _buildVirtualizedContent(activeSidebar != null),
                    if (activeSidebar != null && !_isSidebarCollapsed)
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        width: 300,
                        child: DocumentLayout(
                          scrollController: _scrollController,
                          contentStackKey: _contentStackKey,
                          child: activeSidebar,
                        ),
                      ),
                  ],
                ),
                if (_showStatsPanel)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${widget.labels?.wordCount ?? "Words"}: ${_countWords()}',
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '${widget.labels?.characterCount ?? "Characters"}: ${_countChars()}',
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: _showStatsPanel ? 80 : 16,
                  right: 16,
                  child: IconButton(
                    icon: Icon(
                      _showStatsPanel ? Icons.close : Icons.info_outline,
                    ),
                    onPressed: () {
                      setState(() {
                        _showStatsPanel = !_showStatsPanel;
                      });
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                if (activeSidebar != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: Icon(
                        _isSidebarCollapsed
                            ? Icons.chevron_left
                            : Icons.chevron_right,
                      ),
                      tooltip: _isSidebarCollapsed
                          ? (widget.labels?.showCommentsLabel ??
                                'Show comments')
                          : (widget.labels?.hideCommentsLabel ??
                                'Hide comments'),
                      onPressed: () {
                        setState(() {
                          _isSidebarCollapsed = !_isSidebarCollapsed;
                        });
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                if (widget.toolbarMode == FluentToolbarMode.bubble)
                  FluentBubbleToolbar(
                    document: widget.document,
                    labels: widget.labels,
                    stackKey: _contentStackKey,
                    scrollController: _scrollController,
                    bubbleActions: widget.bubbleActions,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _countWords() {
    _computeStats();
    return _cachedWordCount;
  }

  int _countChars() {
    _computeStats();
    return _cachedCharCount;
  }
}
