import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/controllers/document_language_controller.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/widgets/node_widget_builder.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/widgets/editor/fluent_toolbar_widget.dart';
import 'package:fluent_editor/widgets/nodes/virtualized_selectable_area.dart';

class FluentDocumentWidget extends StatefulWidget {
  const FluentDocumentWidget({
    super.key,
    required this.document,
    this.maxWidth = 800.0,
    this.labels,
    this.sidebar,
  });

  final FluentDocument document;
  final double maxWidth;
  final FluentEditorLabels? labels;
  final Widget? sidebar;

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

  final Map<String, int> _nodeIndexCache = {};
  bool _nodeIndexCacheDirty = true;

  final Map<int, double> _itemHeights = {};
  double _averageItemHeight = 40.0;

  // Cached word/char counts keyed by content version to avoid O(n) tree walk on every rebuild.
  int _cachedWordCount = 0;
  int _cachedCharCount = 0;
  int? _statsContentVersion;

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
      widget.document.paragraphRegistry.caretVisible = true;
      _repaintCaretParagraph();
      return;
    }
    _lastBlinkRestart = now;
    _blinkTimer?.cancel();
    widget.document.paragraphRegistry.caretVisible = true;
    _repaintCaretParagraph();
    _blinkTimer = Timer.periodic(_blinkInterval, (_) {
      final registry = widget.document.paragraphRegistry;
      registry.caretVisible = !registry.caretVisible;
      _repaintCaretParagraph();
    });
  }

  Widget _buildVirtualizedContent() {
    return Focus(
      focusNode: widget.document.editorFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (widget.document.imeHandler.isComposing) {
          final isCtrl = HardwareKeyboard.instance.isControlPressed;
          final isMeta = HardwareKeyboard.instance.isMetaPressed;
          if (isCtrl || isMeta) {
            widget.document.manageEvent(event);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        final _shouldRouteToIME = kIsWeb || (
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);
        if (_shouldRouteToIME && widget.document.imeHandler.isConnectionActive) {
          final _isCtrl = HardwareKeyboard.instance.isControlPressed;
          final _isMeta = HardwareKeyboard.instance.isMetaPressed;
          if (!_isCtrl && !_isMeta) {
            final _ch = event.character;
            final _isPrintable = _ch != null &&
                _ch.isNotEmpty &&
                _ch.runes.every((r) => r >= 32 && r != 127);
            if (_isPrintable) return KeyEventResult.ignored;
          }
        }

        final _isIOSOrAndroid = !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);
        if (_isIOSOrAndroid &&
            widget.document.imeHandler.shouldUseBufferSync &&
            widget.document.cursor.isCollapsed &&
            !widget.document.imeHandler.isComposing &&
            (event.logicalKey == LogicalKeyboardKey.backspace ||
             event.logicalKey == LogicalKeyboardKey.delete)) {
          return KeyEventResult.ignored;
        }

        widget.document.manageEvent(event);
        return KeyEventResult.handled;
      },
      child: Padding(
        padding: const EdgeInsets.all(24.0).copyWith(
          right: 24.0 + (widget.sidebar == null || _isSidebarCollapsed ? 0 : 280),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: VirtualizedSelectableArea(
              document: widget.document,
              scrollController: _scrollController,
              itemCount: widget.document.content.nodes.length,
              onHeightsChanged: (heights) {
                _itemHeights.clear();
                _itemHeights.addAll(heights);
                if (heights.isNotEmpty) {
                  final sum = heights.values.reduce((a, b) => a + b);
                  _averageItemHeight = sum / heights.length;
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
    final offset = cursor.focusId.isNotEmpty ? cursor.focusOffset : cursor.anchorOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final rect = widget.document.paragraphRegistry.resolveCaretScreenRect(fragId, offset);
        if (rect != null && (rect.width > 0 || rect.height > 0)) {
          final view = View.of(context);
          final viewH = view.physicalSize.height / view.devicePixelRatio;
          widget.document.imeHandler.setViewHeight(viewH);
          widget.document.imeHandler.updateCaretRect(rect);
        }
      });
    });
  }

  void _onDocumentChanged() {
    _updateImeCaretRect();
    widget.document.imeHandler.syncImeBufferToFragment();

    if (widget.document.cursorOnlyChange) {
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
    _nodeIndexCacheDirty = true;
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
    widget.document.saveState(description: 'Initial state', forceNewAction: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.document.imeHandler.showKeyboard(context);
    });
    _initDocumentLanguage();
    DocumentLanguageController.instance.currentLanguage
        .addListener(_onLanguageChanged);
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
  bool _onHardwareKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final doc = widget.document;
    final keyboard = HardwareKeyboard.instance;
    final isCtrl = keyboard.isControlPressed;
    final isMeta = keyboard.isMetaPressed;
    final key = event.logicalKey;

    final navKeys = {
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

    final shortcutKeys = {
      LogicalKeyboardKey.keyZ,
    };
    if (doc.editorFocusNode.hasFocus && !shortcutKeys.contains(key)) {
      return false;
    }

    if (doc.imeHandler.isComposing) {
      if (isCtrl || isMeta) {
        doc.manageEvent(event);
        return true;
      }
      return false; // Let IME consume everything else (incl. arrows)
    }

    final _isVirtualKeyboard = !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);
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

    if (navKeys.contains(key)) {
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

      double nodeStart = 0.0;
      for (int i = 0; i < cursorNodeIndex; i++) {
        nodeStart += _itemHeights[i] ?? _averageItemHeight;
      }
      final nodeHeight = _itemHeights[cursorNodeIndex] ?? _averageItemHeight;
      final nodeEnd = nodeStart + nodeHeight;

      final position = _scrollController.position;
      const margin = 80.0;
      final viewportStart = position.pixels;
      final viewportEnd   = viewportStart + position.viewportDimension;

      if (nodeStart >= viewportStart + margin &&
          nodeEnd   <= viewportEnd   - margin) {
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

  /// Optimized node index lookup with caching
  int _findNodeIndexCached(String fragmentId) {
    _updateNodeIndexCacheIfNeeded();
    
    final directIndex = _nodeIndexCache[fragmentId];
    if (directIndex != null) return directIndex;
    
    for (int i = 0; i < widget.document.content.nodes.length; i++) {
      final node = widget.document.content.nodes[i];
      if (_nodeContainsFragment(node, fragmentId)) {
        return i;
      }
    }
    
    return -1;
  }

  /// Updates node index cache when document changes
  void _updateNodeIndexCacheIfNeeded() {
    if (!_nodeIndexCacheDirty) return;
    
    _nodeIndexCache.clear();
    for (int i = 0; i < widget.document.content.nodes.length; i++) {
      final node = widget.document.content.nodes[i];
      _nodeIndexCache[node.id] = i;
      
      if (node is Paragraph) {
        for (final fragment in node.fragments) {
          _nodeIndexCache[fragment.id] = i;
        }
      } else if (node is FluentList) {
        for (final item in node.items) {
          for (final child in item.children) {
            if (child is Paragraph) {
              _nodeIndexCache[child.id] = i;
              for (final fragment in child.fragments) {
                _nodeIndexCache[fragment.id] = i;
              }
            }
          }
        }
      } else if (node is FluentTable) {
        for (final row in node.rows) {
          for (final cell in row.cells) {
            for (final child in cell.children) {
              if (child is Paragraph) {
                _nodeIndexCache[child.id] = i;
                for (final fragment in child.fragments) {
                  _nodeIndexCache[fragment.id] = i;
                }
              }
            }
          }
        }
      }
    }
    
    _nodeIndexCacheDirty = false;
  }

  bool _nodeContainsFragment(FNode node, String fragmentId) {
    if (node.id == fragmentId) return true;
    
    if (node is Paragraph) {
      return node.fragments.any((frag) => frag.id == fragmentId);
    }
    
    return false;
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
    DocumentLanguageController.instance.currentLanguage
        .removeListener(_onLanguageChanged);
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          FluentToolbar(document: widget.document, labels: widget.labels),
          Expanded(
            child: Stack(
              children: [
                Stack(
                  children: [
                    _buildVirtualizedContent(),
                    if (widget.sidebar != null && !_isSidebarCollapsed)
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        width: 280,
                        child: DocumentLayout(
                          scrollController: _scrollController,
                          contentStackKey: _contentStackKey,
                          child: widget.sidebar!,
                        ),
                      ),
                  ],
                ),
                if (_showStatsPanel)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${widget.labels?.wordCount ?? "Words"}: ${_countWords()}'),
                          const SizedBox(width: 16),
                          Text('Chars: ${_countChars()}'),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: _showStatsPanel ? 80 : 16,
                  right: 16,
                  child: IconButton(
                    icon: Icon(_showStatsPanel ? Icons.close : Icons.info_outline),
                    onPressed: () {
                      setState(() {
                        _showStatsPanel = !_showStatsPanel;
                      });
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                if (widget.sidebar != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(20),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: IconButton(
                        icon: Icon(
                          _isSidebarCollapsed
                              ? Icons.chevron_left
                              : Icons.chevron_right,
                        ),
                        tooltip: _isSidebarCollapsed
                            ? (widget.labels?.showCommentsLabel ?? 'Show comments')
                            : (widget.labels?.hideCommentsLabel ?? 'Hide comments'),
                        onPressed: () {
                          setState(() {
                            _isSidebarCollapsed = !_isSidebarCollapsed;
                          });
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _countWords() {
    final version = widget.document.contentVersion;
    if (_statsContentVersion == version) return _cachedWordCount;

    int count = 0;
    final root = widget.document.content;
    
    void visit(FNode node) {
      if (node is Fragment) {
        final text = node.text;
        if (text.isNotEmpty) {
          final words = text.split(RegExp(r'\s+'));
          count += words.where((w) => w.isNotEmpty).length;
        }
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
    _cachedWordCount = count;
    _statsContentVersion = version;
    return count;
  }

  int _countChars() {
    final version = widget.document.contentVersion;
    if (_statsContentVersion == version) return _cachedCharCount;

    int count = 0;
    final root = widget.document.content;

    void visit(FNode node) {
      if (node is Fragment) {
        count += node.text.length;
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
    _cachedCharCount = count;
    _statsContentVersion = version;
    return count;
  }
}
