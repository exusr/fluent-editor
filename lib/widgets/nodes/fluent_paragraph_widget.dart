import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:fluent_editor/core/paragraph_registry.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/renderers/render_paragraph.dart';
import 'package:fluent_editor/comments/comment_provider.dart';
import 'package:fluent_editor/spell_check/spell_annotation.dart';
import 'package:fluent_editor/spell_check/spell_check_provider.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/widgets/editor/fluent_link_dialog.dart';
import 'package:fluent_editor/widgets/editor/fluent_context_menu.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Paragraph with single TextPainter.
/// The widget is simple: manages only tap and passes cursor offsets to the render object.
class FluentParagraphWidget extends StatefulWidget {
  const FluentParagraphWidget({
    super.key,
    required this.node,
    required this.document,
    this.applyParagraphSpacing = true,
    this.shrinkWrap = false,
  });

  final FNode node;
  final FluentDocument document;
  final bool applyParagraphSpacing;
  final bool shrinkWrap;

  @override
  FluentParagraphWidgetState createState() => FluentParagraphWidgetState();
}

class FluentParagraphWidgetState<T extends FluentParagraphWidget> extends State<T> {
  final GlobalKey _renderWidgetKey = GlobalKey();
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;
  StreamSubscription<String>? _spellSubscription;
  StreamSubscription<void>? _commentSubscription;
  bool _isSecondaryTap = false;
  ({String startFrag, int startOff, String endFrag, int endOff})? _savedSelection;

  SpellCheckProvider? get _spell => widget.document.spellCheckProvider;
  CommentProvider? get _comment => widget.document.commentProvider;

  void onTapDown(TapDownDetails details) {
    final now = DateTime.now();
    final isDoubleTap = _lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300 &&
        _lastTapPosition != null &&
        (details.globalPosition - _lastTapPosition!).distance < 30;

    _lastTapTime = now;
    _lastTapPosition = details.globalPosition;

    // Get the RenderBox of the RenderFluentParagraph
    final renderObject = _renderWidgetKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      final localPosition = renderObject.globalToLocal(details.globalPosition);
      
      if (isDoubleTap) {
        // Double tap: select the word
        widget.document.eventHandler.onDoubleTapWithPosition(
          localPosition,
          renderObject,
          widget,
        );
      } else {
        // Single tap: move the cursor
        widget.document.eventHandler.onTapDownWithPosition(
          localPosition,
          renderObject,
          widget,
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    widget.document.cursor.addListener(_onStateChange);
    widget.document.selectionManager.addListener(_onStateChange);
    widget.document.addListener(_onDocumentChange);
    _subscribeToSpell();
    _subscribeToComments();
    _triggerSpellCheck();
  }

  void _subscribeToSpell() {
    _spellSubscription?.cancel();
    _spellSubscription = null;
    final provider = _spell;
    if (provider != null) {
      _spellSubscription = provider.annotationsChanged.listen(_onSpellAnnotationsChanged);
    }
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.cursor != widget.document.cursor) {
      oldWidget.document.cursor.removeListener(_onStateChange);
      widget.document.cursor.addListener(_onStateChange);
    }
    if (oldWidget.document.selectionManager != widget.document.selectionManager) {
      oldWidget.document.selectionManager.removeListener(_onStateChange);
      widget.document.selectionManager.addListener(_onStateChange);
    }
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onDocumentChange);
      widget.document.addListener(_onDocumentChange);
      _subscribeToSpell();
      _subscribeToComments();
    }
  }

  void _onStateChange() => setState(() {});

  void _onDocumentChange() {
    _onStateChange();
    _triggerSpellCheck();
  }

  void _triggerSpellCheck() {
    if (widget.node is! Paragraph) return;
    final paragraph = widget.node as Paragraph;
    final plainText = paragraph.fragments
        .whereType<Fragment>()
        .map((f) => f.text)
        .join();
    _spell?.checkParagraph(paragraph.id, plainText);
  }

  void _onSpellAnnotationsChanged(String nodeId) {
    if (nodeId == widget.node.id || nodeId == '__all__') {
      setState(() {});
    }
  }

  TextAlign _parseTextAlign(String value) {
    return switch (value) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.left,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cursor = widget.document.cursor;
    final container = widget.node as InlineContainerNode;
    final nodeId = widget.node.id;

    // Get the paragraph style (if applicable)
    final paragraph = widget.node is Paragraph ? widget.node as Paragraph : null;
    final style = paragraph?.getStyle();

    // Spacing: use the paragraph style as base, with fallback to document
    final styleSpacingBefore = style?.spacingBefore ?? 0.0;
    final styleSpacingAfter = style?.spacingAfter ?? 0.0;
    final spacingBefore = widget.applyParagraphSpacing
        ? (styleSpacingBefore > 0 ? styleSpacingBefore : widget.document.pendingSpacingBefore)
        : 0.0;
    final spacingAfter = widget.applyParagraphSpacing
        ? (styleSpacingAfter > 0 ? styleSpacingAfter : widget.document.pendingSpacingAfter)
        : 0.0;

    // Get the selection range for this node from the document
    final selRange = widget.document.getSelectionRangeForNode(nodeId);

    // Build a widget for each inline FluentImage (e.g. inside Link).
    // The order must match that of `collectInlineImages` used in the
    // RenderObject to align WidgetSpan placeholders.
    final inlineImages = collectInlineImages(container);
    final imageWidgets = inlineImages.map((img) {
      // Use InlineImageWidget for inline images to maintain inline behavior
      return InlineImageWidget(node: img, document: widget.document);
    }).toList();

    final spellAnnotations = _spell?.annotationsForNode(nodeId) ?? const [];
    final commentAnnotations = _comment?.commentsForNode(nodeId) ?? const [];
    final selectedCommentId = _comment?.selectedCommentId;

    // Calculate padding for indentation (24px per level)
    final indentLevel = (widget.node as Paragraph).indent;
    final indentPadding = indentLevel * 24.0;

    return Padding(
      padding: EdgeInsets.only(
        left: indentPadding,
        top: spacingBefore,
        bottom: spacingAfter,
      ),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == 2) { // kSecondaryMouseButton
            _isSecondaryTap = true;
          }
        },
        child: GestureDetector(
          onTapDown: (details) {
            if (_isSecondaryTap) {
              _isSecondaryTap = false;
              return; // Do not move cursor / collapse selection on right-click
            }

            widget.document.requestEditorFocus();

            final now = DateTime.now();
            final isDoubleTap = _lastTapTime != null &&
                now.difference(_lastTapTime!).inMilliseconds < 300 &&
                _lastTapPosition != null &&
                (details.globalPosition - _lastTapPosition!).distance < 30;

            _lastTapTime = now;
            _lastTapPosition = details.globalPosition;

            final renderObject = _renderWidgetKey.currentContext?.findRenderObject();
            if (renderObject is RenderBox) {
              final localPosition = renderObject.globalToLocal(details.globalPosition);

              if (isDoubleTap) {
                _savedSelection = null;
                widget.document.eventHandler.onDoubleTapWithPosition(
                  localPosition, renderObject, widget);
              } else {
                // If this paragraph has an active selection, defer cursor
                // movement to onTap. This way a long-press does not destroy
                // the selection before the context menu is shown.
                final selRange = widget.document.selectionManager.getRangeForNode(widget.node.id);
                final hasSelection = selRange != null &&
                    !widget.document.selectionManager.isCollapsed;
                if (hasSelection) {
                  _savedSelection = selRange;
                  // Do not call onTapDownWithPosition – keep selection intact.
                } else {
                  _savedSelection = null;
                  widget.document.eventHandler.onTapDownWithPosition(
                    localPosition, renderObject, widget);
                }
              }
            }
          },
          onTap: () {
            widget.document.requestEditorFocus();
            // Activate virtual keyboard on mobile (only for confirmed short-taps)
            widget.document.requestMobileKeyboardFocus();
            // Tap completed inside an active selection: now collapse and move cursor.
            if (_savedSelection != null && _lastTapPosition != null && mounted) {
              final renderObject = _renderWidgetKey.currentContext?.findRenderObject();
              if (renderObject is RenderBox) {
                final localPosition = renderObject.globalToLocal(_lastTapPosition!);
                widget.document.eventHandler.onTapDownWithPosition(
                  localPosition, renderObject, widget);
              }
              _savedSelection = null;
            }
          },
          onSecondaryTapUp: (details) {
            _isSecondaryTap = false;
            _onSecondaryTap(details);
          },
          onLongPressStart: (details) {
            _onLongPress(details);
          },
          child: FParagraphRenderWidget(
          key: _renderWidgetKey,
          node: container,
          registry: widget.document.paragraphRegistry,
          lineHeight: style?.lineHeight ?? widget.document.pendingLineHeight,
          textAlign: _parseTextAlign((widget.node as Paragraph).textAlign),
          shrinkWrap: widget.shrinkWrap,
          paragraphStyle: style, // Pass the style for fallbacks
          defaultTextColor: Theme.of(context).colorScheme.onSurface,
          anchorFragmentId: cursor.anchorId,
          anchorLocalOffset: cursor.anchorOffset,
          focusFragmentId: cursor.isCollapsed ? null : cursor.focusId,
          focusLocalOffset: cursor.isCollapsed ? null : cursor.focusOffset,
          // Pass the selection from the document (if present for this node)
          selAnchorFragmentId: selRange?.startFrag,
          selAnchorLocalOffset: selRange?.startOff,
          selFocusFragmentId: selRange?.endFrag,
          selFocusLocalOffset: selRange?.endOff,
          spellAnnotations: spellAnnotations,
          commentAnnotations: commentAnnotations,
          selectedCommentId: selectedCommentId,
          children: imageWidgets,
        ),
      ),
    ),
  );
  }

  void _onSecondaryTap(TapUpDetails details) {
    _showContextMenuAt(details.globalPosition);
  }

  void _onLongPress(LongPressStartDetails details) {
    // On mobile the selection has already been collapsed by onTapDown;
    // pass the snapshot we captured at tap-down time.
    _showContextMenuAt(details.globalPosition, savedSelection: _savedSelection);
    _savedSelection = null;
  }

  void _showContextMenuAt(Offset globalPosition,
      {({String startFrag, int startOff, String endFrag, int endOff})? savedSelection}) {
    final renderObject = _renderWidgetKey.currentContext?.findRenderObject();
    if (renderObject is! RenderFluentParagraph) return;

    final localPosition = renderObject.globalToLocal(globalPosition);
    final fragmentResult = renderObject.getFragmentAtPosition(localPosition);
    if (fragmentResult == null) return;

    final root = widget.document.content;
    final fragment = findById(root, fragmentResult.fragmentId);
    if (fragment == null) return;

    final parent = findParent(root, fragment);
    if (parent is Link) {
      _showLinkContextMenu(globalPosition, parent);
      return;
    }

    _showSpellContextMenu(globalPosition, fragmentResult, savedSelection: savedSelection);
  }

  Future<void> _showSpellContextMenu(
    Offset globalPosition,
    ({String fragmentId, int localOffset}) fragmentResult, {
    ({String startFrag, int startOff, String endFrag, int endOff})? savedSelection,
  }) async {
    final items = <FluentContextMenuItem>[];

    // Spell-check items (only if there is a misspelled word under the cursor)
    final spellProvider = _spell;
    SpellAnnotation? ann;
    if (spellProvider != null) {
      final annotations = spellProvider.annotationsForNode(widget.node.id);
      ann = annotations.firstWhere(
        (a) => a.covers(fragmentResult.fragmentId, fragmentResult.localOffset),
        orElse: () => const SpellAnnotation(nodeId: '', fragmentIndex: 0, startOffset: 0, endOffset: 0, suggestions: [], misspelledWord: ''),
      );

      if (ann.nodeId.isNotEmpty) {
        final suggestions = await spellProvider.requestSuggestions(ann.misspelledWord);
        if (suggestions.isNotEmpty) {
          for (final suggestion in suggestions.take(5)) {
            items.add(FluentContextMenuItem(
              label: suggestion,
              onPressed: () => _applyCorrection(ann!, suggestion),
            ));
          }
          items.add(FluentContextMenuItem(label: '', onPressed: null));
        }
        items.add(FluentContextMenuItem(
          label: 'Aggiungi al dizionario',
          onPressed: () => spellProvider.addToDictionary(ann!.misspelledWord),
        ));
        items.add(FluentContextMenuItem(
          label: 'Ignora',
          onPressed: () => spellProvider.ignoreWord(ann!.misspelledWord),
        ));
        items.add(FluentContextMenuItem(label: '', onPressed: null));
      }
    }

    // Comment item (when there is an active selection in this paragraph)
    final commentProvider = _comment;
    final renderObject = _renderWidgetKey.currentContext?.findRenderObject();
    final selRange = savedSelection ?? widget.document.selectionManager.getRangeForNode(widget.node.id);
    if (commentProvider != null &&
        renderObject is RenderFluentParagraph &&
        selRange != null) {
      // Compute absolute offsets even when selection crosses paragraph
      // boundaries (startFrag / endFrag may be empty).
      int? startGlobal;
      int? endGlobal;

      if (selRange.startFrag.isEmpty) {
        startGlobal = 0;
      } else {
        startGlobal = renderObject.resolveGlobalOffset(selRange.startFrag, selRange.startOff);
      }

      if (selRange.endFrag.isEmpty) {
        endGlobal = _paragraphTotalLength();
      } else {
        endGlobal = renderObject.resolveGlobalOffset(selRange.endFrag, selRange.endOff);
      }

      // Only show if both offsets resolved and selection is not collapsed.
      if (startGlobal != null && endGlobal != null) {
        // Normalize offsets: _isAnchorBeforeFocus() compares fragment IDs
        // lexicographically, but IDs are random nanoids, so start/end can be
        // reversed when the selection spans multiple fragments.
        final start = startGlobal < endGlobal ? startGlobal : endGlobal;
        final end = startGlobal < endGlobal ? endGlobal : startGlobal;
        if (end > start) {
          final labels = widget.document.labels;
          items.add(FluentContextMenuItem(
            icon: Icons.add_comment_outlined,
            label: labels?.addCommentLabel ?? 'Add comment',
            onPressed: () => _showAddCommentDialog(start, end),
          ));
        }
      }
    }

    if (items.isNotEmpty && mounted) {
      showFluentContextMenu(context: context, globalPosition: globalPosition, items: items);
    }
  }

  /// Returns the total text length of the current paragraph,
  /// including text inside Links.
  int _paragraphTotalLength() {
    final container = widget.node as InlineContainerNode;
    var length = 0;
    for (final child in container.getChildren()) {
      length += _nodeTextLength(child);
    }
    return length;
  }

  int _nodeTextLength(FNode node) {
    if (node is Fragment) {
      return node.text.length;
    } else if (node is Link) {
      var len = 0;
      for (final child in node.getChildren()) {
        len += _nodeTextLength(child);
      }
      return len;
    } else if (node is FluentImage) {
      return node.text.length; // ZWS placeholder
    }
    return 0;
  }

  void _showAddCommentDialog(int startOffset, int endOffset) {
    final labels = widget.document.labels;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels?.commentDialogTitle ?? 'Add comment'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(hintText: labels?.commentHint ?? 'Write a comment...'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(labels?.cancel ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                final author = _comment?.currentAuthor ?? labels?.defaultAuthorName ?? 'User';
                final added = _comment?.addComment(widget.node.id, startOffset, endOffset, author, text);
                if (added == false) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Theme.of(context).colorScheme.errorContainer,
                      content: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              labels?.commentOverlapWarning ?? 'Warning: the comment overlaps an existing comment.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
              Navigator.of(ctx).pop();
            },
            child: Text(labels?.confirmButton ?? 'Confirm'),
          ),
        ],
      ),
    );
  }

  void _applyCorrection(SpellAnnotation ann, String correction) {
    final paragraph = widget.node as Paragraph;
    // Flatten all text fragments (including those inside Links) in order.
    final fragments = <Fragment>[];
    for (final child in paragraph.fragments) {
      if (child is Fragment) {
        fragments.add(child);
      } else if (child is Link) {
        for (final linkChild in child.fragments) {
          if (linkChild is Fragment) fragments.add(linkChild);
        }
      }
    }
    // Map the annotation offset to the correct fragment
    int currentOffset = 0;
    for (final frag in fragments) {
      final fragEnd = currentOffset + frag.text.length;
      if (ann.startOffset >= currentOffset && ann.startOffset < fragEnd) {
        final localStart = ann.startOffset - currentOffset;
        final localEnd = ann.endOffset - currentOffset;
        final newText = frag.text.replaceRange(localStart, localEnd, correction);
        frag.text = newText;
        widget.document.updateContent();
        return;
      }
      currentOffset = fragEnd;
    }
  }

  void _showLinkContextMenu(Offset globalPosition, Link link) {
    // Extract the current link text from fragments
    final currentText = link.fragments
        .whereType<Fragment>()
        .map((f) => f.text)
        .join();

    showFluentContextMenu(
      context: context,
      globalPosition: globalPosition,
      items: [
        FluentContextMenuItem(
          icon: Icons.link,
          label: widget.document.labels?.replaceLink ?? 'Replace link',
          onPressed: () async {
            final result = await showFluentLinkDialog(
              context,
              labels: widget.document.labels,
              initialUrl: link.url,
              initialText: currentText,
            );
            if (result != null) {
              link.url = result['url']!;
              // Update the link text if provided
              final text = result['text'];
              if (text != null && text.isNotEmpty && link.fragments.isNotEmpty) {
                final firstFrag = link.fragments.first;
                if (firstFrag is Fragment) {
                  firstFrag.text = text;
                }
              }
              widget.document.updateContent();
            }
          },
        ),
        FluentContextMenuItem(
          icon: Icons.delete,
          label: widget.document.labels?.deleteLink ?? 'Delete',
          onPressed: () {
            widget.document.saveState(description: 'Delete link', forceNewAction: true);
            removeNode(widget.document.content, link);
            widget.document.updateContent();
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    widget.document.cursor.removeListener(_onStateChange);
    widget.document.selectionManager.removeListener(_onStateChange);
    widget.document.removeListener(_onDocumentChange);
    _spellSubscription?.cancel();
    _commentSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToComments() {
    _commentSubscription?.cancel();
    _commentSubscription = null;
    final provider = _comment;
    if (provider != null) {
      _commentSubscription = provider.commentsChanged.listen((_) => _onCommentsChanged());
    }
  }

  void _onCommentsChanged() {
    if (mounted) setState(() {});
  }
}

/// MultiChildRenderObjectWidget that passes cursor/selection offsets to the
/// paragraph and hosts inline widgets (e.g. images inside Link).
class FParagraphRenderWidget extends MultiChildRenderObjectWidget {
  const FParagraphRenderWidget({
    super.key,
    required this.node,
    required this.registry,
    this.lineHeight = 1.15,
    this.textAlign = TextAlign.left,
    this.shrinkWrap = false,
    this.paragraphStyle,
    this.defaultTextColor,
    this.cursorColor,
    this.selectionColor,
    this.linkColor,
    required this.anchorFragmentId,
    required this.anchorLocalOffset,
    this.focusFragmentId,
    this.focusLocalOffset,
    // Selection parameters (optional)
    this.selAnchorFragmentId,
    this.selAnchorLocalOffset,
    this.selFocusFragmentId,
    this.selFocusLocalOffset,
    this.spellAnnotations = const [],
    this.commentAnnotations = const [],
    this.selectedCommentId,
    super.children = const [],
  });

  final InlineContainerNode node;
  final ParagraphRegistry registry;
  final double lineHeight;
  final TextAlign textAlign;
  final bool shrinkWrap;
  final ParagraphStyle? paragraphStyle;
  final Color? defaultTextColor;
  final Color? cursorColor;
  final Color? selectionColor;
  final Color? linkColor;

  final String anchorFragmentId;
  final int anchorLocalOffset;
  final String? focusFragmentId;
  final int? focusLocalOffset;
  // Selection
  final String? selAnchorFragmentId;
  final int? selAnchorLocalOffset;
  final String? selFocusFragmentId;
  final int? selFocusLocalOffset;
  final List<SpellAnnotation> spellAnnotations;
  final List<Map<String, dynamic>> commentAnnotations;
  final String? selectedCommentId;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderFluentParagraph(
        container: node,
        registry: registry,
        lineHeight: lineHeight,
        textAlign: textAlign,
        shrinkWrap: shrinkWrap,
        paragraphStyle: paragraphStyle,
        defaultTextColor: defaultTextColor ?? Theme.of(context).colorScheme.onSurface,
        cursorColor: cursorColor ?? Theme.of(context).colorScheme.primary,
        selectionColor: selectionColor ?? Theme.of(context).colorScheme.primary.withAlpha(100),
        linkColor: linkColor ?? Theme.of(context).colorScheme.primary,
      )
      ..setCursorOffsets(
        anchorFragmentId,
        anchorLocalOffset,
        focusFragmentId,
        focusLocalOffset,
      )
      ..setSelectionRange(
        selAnchorFragmentId,
        selAnchorLocalOffset,
        selFocusFragmentId,
        selFocusLocalOffset,
      )
      ..spellAnnotations = spellAnnotations
      ..commentAnnotations = commentAnnotations
      ..selectedCommentId = selectedCommentId;
  }

  @override
  void updateRenderObject(BuildContext context, RenderFluentParagraph renderObject) {
    renderObject.container = node;
    renderObject.lineHeight = lineHeight;
    renderObject.textAlign = textAlign;
    renderObject.shrinkWrap = shrinkWrap;
    renderObject.paragraphStyle = paragraphStyle;
    renderObject.defaultTextColor = defaultTextColor ?? Theme.of(context).colorScheme.onSurface;
    renderObject.cursorColor = cursorColor ?? Theme.of(context).colorScheme.primary;
    renderObject.selectionColor = selectionColor ?? Theme.of(context).colorScheme.primary.withAlpha(100);
    renderObject.linkColor = linkColor ?? Theme.of(context).colorScheme.primary;
    renderObject.setCursorOffsets(
      anchorFragmentId,
      anchorLocalOffset,
      focusFragmentId,
      focusLocalOffset,
    );
    renderObject.setSelectionRange(
      selAnchorFragmentId,
      selAnchorLocalOffset,
      selFocusFragmentId,
      selFocusLocalOffset,
    );
    renderObject.spellAnnotations = spellAnnotations;
    renderObject.commentAnnotations = commentAnnotations;
    renderObject.selectedCommentId = selectedCommentId;
  }
}

enum _ResizeHandle {
  topLeft, topRight, bottomLeft, bottomRight,
  top, bottom, left, right
}

/// Widget for inline images that maintains inline behavior but enables resize
class InlineImageWidget extends StatefulWidget {
  const InlineImageWidget({
    super.key,
    required this.node,
    required this.document,
  });

  final FluentImage node;
  final FluentDocument document;

  @override
  State<InlineImageWidget> createState() => _InlineImageWidgetState();
}

class _InlineImageWidgetState extends State<InlineImageWidget> {
  static const double _defaultImgWidth = 300;
  static const double _defaultImgHeight = 300;
  static double get _handleSize => kIsWeb || Platform.isAndroid || Platform.isIOS ? 24.0 : 12.0;
  static const double _minSize = 50.0;
  static const double _maxSize = 800.0;

  bool _isDragging = false;
  _ResizeHandle? _activeHandle;
  _ResizeHandle? _hoveredHandle;
  Offset? _dragStartPosition;
  
  // Aspect ratio tracking
  double? _originalAspectRatio;
  bool _aspectRatioConstrained = true;
  static const double _aspectRatioThreshold = 0.1; // 10% deviation threshold

  void _onTapDown(TapDownDetails details) {
    if (_isDragging) return;

    widget.document.requestEditorFocus();

    // Initialize original aspect ratio if not set
    _initializeAspectRatio();
    
    // Position the cursor at offset 0 (before) or 1 (after) based on the tap x.
    final box = context.findRenderObject() as RenderBox?;
    final localX = box != null
        ? box.globalToLocal(details.globalPosition).dx
        : 0.0;
    final imgWidth = widget.node.width ?? _defaultImgWidth;
    final offset = localX < imgWidth / 2 ? 0 : 1;
    widget.document.cursor.moveTo(widget.node.id, offset);
  }

  void _initializeAspectRatio() {
    if (_originalAspectRatio == null) {
      final imgWidth = widget.node.width ?? _defaultImgWidth;
      final imgHeight = widget.node.height ?? _defaultImgHeight;
      _originalAspectRatio = imgWidth / imgHeight;
    }
  }

  bool _isAspectRatioDeviating(double newWidth, double newHeight) {
    if (_originalAspectRatio == null || newHeight <= 0) return false;
    
    final currentAspectRatio = newWidth / newHeight;
    final deviation = (currentAspectRatio - _originalAspectRatio!).abs() / _originalAspectRatio!;
    
    return deviation > _aspectRatioThreshold;
  }

  void _onHoverUpdate(bool hovering, Offset localPosition) {
    if (!hovering) {
      if (_hoveredHandle != null) {
        setState(() => _hoveredHandle = null);
      }
      return;
    }
    
    // Detect which handle is near the cursor
    final imgWidth = widget.node.width ?? _defaultImgWidth;
    final imgHeight = widget.node.height ?? _defaultImgHeight;
    final tolerance = _handleSize;
    
    _ResizeHandle? newHoveredHandle;
    
    // Check corners
    if (localPosition.dx <= tolerance && localPosition.dy <= tolerance) {
      newHoveredHandle = _ResizeHandle.topLeft;
    } else if (localPosition.dx >= imgWidth - tolerance && localPosition.dy <= tolerance) {
      newHoveredHandle = _ResizeHandle.topRight;
    } else if (localPosition.dx <= tolerance && localPosition.dy >= imgHeight - tolerance) {
      newHoveredHandle = _ResizeHandle.bottomLeft;
    } else if (localPosition.dx >= imgWidth - tolerance && localPosition.dy >= imgHeight - tolerance) {
      newHoveredHandle = _ResizeHandle.bottomRight;
    }
    // Check edges
    else if (localPosition.dx <= tolerance) {
      newHoveredHandle = _ResizeHandle.left;
    } else if (localPosition.dx >= imgWidth - tolerance) {
      newHoveredHandle = _ResizeHandle.right;
    } else if (localPosition.dy <= tolerance) {
      newHoveredHandle = _ResizeHandle.top;
    } else if (localPosition.dy >= imgHeight - tolerance) {
      newHoveredHandle = _ResizeHandle.bottom;
    }
    
    if (newHoveredHandle != _hoveredHandle) {
      setState(() => _hoveredHandle = newHoveredHandle);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use the actual rendered size from the node (which may be stretched)
    final imgWidth = widget.node.width ?? _defaultImgWidth;
    final imgHeight = widget.node.height ?? _defaultImgHeight;
    final cursor = widget.document.cursor;
    final cursorOnImage = cursor.isCollapsed && cursor.anchorId == widget.node.id;
    final showHandles = cursorOnImage;

    return MouseRegion(
      onEnter: (_) => _onHoverUpdate(true, Offset.zero),
      onExit: (_) => _onHoverUpdate(false, Offset.zero),
      onHover: (event) => _onHoverUpdate(true, event.localPosition),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _onTapDown,
        onTap: () {
          widget.document.requestEditorFocus();
          // Handle tap to prevent it from reaching the link
          widget.document.cursor.moveTo(widget.node.id, 0);
        },
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: imgWidth,
            height: imgHeight,
            child: Stack(
              children: [
                Positioned.fill(child: _buildImage(widget.node.src)),
                if (showHandles) ..._buildResizeHandles(imgWidth, imgHeight),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(String src) {
    if (src.startsWith('data:')) {
      // Parse data URI: data:[<mediatype>][;base64],<data>
      final commaIndex = src.indexOf(',');
      if (commaIndex != -1) {
        try {
          final bytes = base64Decode(src.substring(commaIndex + 1));
          return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
        } catch (e) {
          return const SizedBox.shrink();
        }
      }
    }
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(src, fit: BoxFit.cover, gaplessPlayback: true);
    }
    return Image.asset(src, fit: BoxFit.cover, gaplessPlayback: true);
  }

  List<Widget> _buildResizeHandles(double imgWidth, double imgHeight) {
    // Show all handles for better visibility and usability
    return [
      // Corner handles
      _buildHandle(0, 0, _ResizeHandle.topLeft, SystemMouseCursors.resizeUpLeft),
      _buildHandle(imgWidth - _handleSize, 0, _ResizeHandle.topRight, SystemMouseCursors.resizeUpRight),
      _buildHandle(0, imgHeight - _handleSize, _ResizeHandle.bottomLeft, SystemMouseCursors.resizeDownLeft),
      _buildHandle(imgWidth - _handleSize, imgHeight - _handleSize, _ResizeHandle.bottomRight, SystemMouseCursors.resizeDownRight),
      // Edge handles
      _buildHandle(imgWidth / 2 - _handleSize / 2, 0, _ResizeHandle.top, SystemMouseCursors.resizeUpDown),
      _buildHandle(imgWidth / 2 - _handleSize / 2, imgHeight - _handleSize, _ResizeHandle.bottom, SystemMouseCursors.resizeUpDown),
      _buildHandle(0, imgHeight / 2 - _handleSize / 2, _ResizeHandle.left, SystemMouseCursors.resizeLeftRight),
      _buildHandle(imgWidth - _handleSize, imgHeight / 2 - _handleSize / 2, _ResizeHandle.right, SystemMouseCursors.resizeLeftRight),
    ];
  }

  Widget _buildHandle(double x, double y, _ResizeHandle handle, MouseCursor cursor) {
    final isActive = _activeHandle == handle;
    return Positioned(
      left: x,
      top: y,
      width: _handleSize,
      height: _handleSize,
      child: GestureDetector(
        onPanStart: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null) {
            setState(() {
              _isDragging = true;
              _activeHandle = handle;
              // Reset aspect ratio constraint for new drag operations
              // This allows users to "re-enable" aspect ratio by starting fresh
              _aspectRatioConstrained = true;
              // Store the handle's initial position relative to the image
              final imgWidth = widget.node.width ?? _defaultImgWidth;
              final imgHeight = widget.node.height ?? _defaultImgHeight;
              _dragStartPosition = _getHandlePosition(handle, imgWidth, imgHeight);
            });
          }
        },
        onPanUpdate: (details) {
          if (_activeHandle == null || _dragStartPosition == null) return;
          
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          
          final currentPos = box.globalToLocal(details.globalPosition);
          final imgWidth = widget.node.width ?? _defaultImgWidth;
          final imgHeight = widget.node.height ?? _defaultImgHeight;
          
          double newWidth = imgWidth;
          double newHeight = imgHeight;

          switch (_activeHandle!) {
            case _ResizeHandle.topLeft:
              newWidth = math.max(currentPos.dx, _minSize);
              newHeight = math.max(currentPos.dy, _minSize);
              break;
            case _ResizeHandle.topRight:
              newWidth = math.max(currentPos.dx, _minSize);
              newHeight = math.max(imgHeight - (currentPos.dy - _dragStartPosition!.dy), _minSize);
              break;
            case _ResizeHandle.bottomLeft:
              newWidth = math.max(currentPos.dx, _minSize);
              newHeight = math.max(currentPos.dy, _minSize);
              break;
            case _ResizeHandle.bottomRight:
              newWidth = math.max(currentPos.dx, _minSize);
              newHeight = math.max(currentPos.dy, _minSize);
              break;
            case _ResizeHandle.left:
              newWidth = math.max(currentPos.dx, _minSize);
              break;
            case _ResizeHandle.right:
              newWidth = math.max(currentPos.dx, _minSize);
              break;
            case _ResizeHandle.top:
              newHeight = math.max(currentPos.dy, _minSize);
              break;
            case _ResizeHandle.bottom:
              newHeight = math.max(currentPos.dy, _minSize);
              break;
          }

          // Apply max size constraints
          newWidth = math.min(newWidth, _maxSize);
          newHeight = math.min(newHeight, _maxSize);

          // Check if aspect ratio is deviating and disable constraint if needed
          if (_aspectRatioConstrained && _isAspectRatioDeviating(newWidth, newHeight)) {
            _aspectRatioConstrained = false;
          }

          // Apply aspect ratio constraint only if still enabled
          if (_aspectRatioConstrained && _originalAspectRatio != null) {
            // For corner handles, maintain aspect ratio
            if (_activeHandle == _ResizeHandle.topLeft || 
                _activeHandle == _ResizeHandle.topRight ||
                _activeHandle == _ResizeHandle.bottomLeft || 
                _activeHandle == _ResizeHandle.bottomRight) {
              
              // Calculate the dimension that changed more
              final widthRatio = newWidth / imgWidth;
              final heightRatio = newHeight / imgHeight;
              
              // Use the ratio that preserves the constraint better
              if (widthRatio > heightRatio) {
                newHeight = newWidth / _originalAspectRatio!;
              } else {
                newWidth = newHeight * _originalAspectRatio!;
              }
            }
            // For edge handles, adjust the other dimension to maintain aspect ratio
            else if (_activeHandle == _ResizeHandle.left || _activeHandle == _ResizeHandle.right) {
              newHeight = newWidth / _originalAspectRatio!;
            } else if (_activeHandle == _ResizeHandle.top || _activeHandle == _ResizeHandle.bottom) {
              newWidth = newHeight * _originalAspectRatio!;
            }
          }

          // Apply minimal threshold for smooth but responsive resize
          const double threshold = 1.0;
          
          final widthDiff = (newWidth - imgWidth).abs();
          final heightDiff = (newHeight - imgHeight).abs();
          
          if (widthDiff >= threshold || heightDiff >= threshold) {
            widget.node.width = newWidth;
            widget.node.height = newHeight;
            setState(() {});
          }
        },
        onPanEnd: (_) {
          setState(() {
            _isDragging = false;
            _activeHandle = null;
            _dragStartPosition = null;
          });
          // Update document only when drag ends
          widget.document.updateContent();
        },
        child: MouseRegion(
          cursor: cursor,
          child: Container(
            decoration: BoxDecoration(
              color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Offset _getHandlePosition(_ResizeHandle handle, double imgWidth, double imgHeight) {
    switch (handle) {
      case _ResizeHandle.topLeft:
        return Offset(0, 0);
      case _ResizeHandle.topRight:
        return Offset(imgWidth - _handleSize, 0);
      case _ResizeHandle.bottomLeft:
        return Offset(0, imgHeight - _handleSize);
      case _ResizeHandle.bottomRight:
        return Offset(imgWidth - _handleSize, imgHeight - _handleSize);
      case _ResizeHandle.top:
        return Offset(imgWidth / 2 - _handleSize / 2, 0);
      case _ResizeHandle.bottom:
        return Offset(imgWidth / 2 - _handleSize / 2, imgHeight - _handleSize);
      case _ResizeHandle.left:
        return Offset(0, imgHeight / 2 - _handleSize / 2);
      case _ResizeHandle.right:
        return Offset(imgWidth - _handleSize, imgHeight / 2 - _handleSize / 2);
    }
  }

  }