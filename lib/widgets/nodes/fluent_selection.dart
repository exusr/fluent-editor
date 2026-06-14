import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/renderers/render_paragraph.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// FluentSelectableArea with precise selection management
/// at character level, even on multi-line and multi-node text.
class FluentSelectableArea extends StatefulWidget {
  const FluentSelectableArea({super.key, required this.document, required this.children});

  final FluentDocument document;
  final List<Widget> children;

  @override
  State<FluentSelectableArea> createState() => _FluentSelectableAreaState();
}

class _FluentSelectableAreaState extends State<FluentSelectableArea> {
  // Active selection state
  bool _isSelecting = false;
  
  // Exact position of the PointerDownEvent (captured before the slop of the PanGestureRecognizer)
  Offset? _pointerDownPosition;

  /// Captures the exact position of the PointerDownEvent
  /// BEFORE the gesture recognizer applies the slop
  void _onPointerDown(PointerDownEvent event) {
    _pointerDownPosition = event.position;
  }

  /// Returns true on native mobile (Android/iOS) or on web.
  bool _isMobilePlatform() {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS;
  }
  
  void onPanStart(DragStartDetails details) {
    // Request focus on the hidden TextField first so the virtual keyboard
    // opens on mobile (native and web). The editorFocusNode is a descendant
    // in the same FocusScope, so shortcut events still reach it via
    // Flutter's key-event bubbling.
    if (_isMobilePlatform()) {
      widget.document.requestMobileKeyboardFocus();
    }

    // Always request editor focus so onKeyEvent fires for shortcuts.
    widget.document.requestEditorFocus();

    // CRITICAL: Use the PointerDown position if available,
    // because details.globalPosition arrives AFTER the slop of the gesture
    // recognizer and could be on a different line than the initial click.
    final startPosition = _pointerDownPosition ?? details.globalPosition;

    final result = _findFragmentAtPosition(startPosition);

    if (result != null) {
      _isSelecting = true;

      widget.document.selectionManager.startSelection(
        result.nodeId,
        result.fragmentId,
        result.localOffset,
      );
      widget.document.cursor.moveTo(result.fragmentId, result.localOffset);
    }
  }
  
  void onPanUpdate(DragUpdateDetails details) {
    if (!_isSelecting) return;

    final result = _findFragmentAtPosition(details.globalPosition);

    if (result != null) {
      widget.document.selectionManager.updateFocus(
        result.nodeId,
        result.fragmentId,
        result.localOffset,
      );
      widget.document.cursor.focusTo(result.fragmentId, result.localOffset);
    }
  }
  
  void onPanEnd(DragEndDetails details) {
    _isSelecting = false;
    _pointerDownPosition = null;
    // Re-request mobile keyboard focus after drag selection ends
    if (_isMobilePlatform()) {
      widget.document.requestMobileKeyboardFocus();
    }
  }
  
  void onPanCancel() {
    _isSelecting = false;
    _pointerDownPosition = null;
  }

  /// Finds the fragment and local offset at a global position
  _FragmentHitResult? _findFragmentAtPosition(Offset globalPosition) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    
    final rootLocalPosition = renderBox.globalToLocal(globalPosition);
    
    // 1. Try RenderFluentParagraph (text, paragraphs, links...)
    final paragraph = _findParagraphAtPosition(renderBox, rootLocalPosition);
    if (paragraph != null) {
      final paragraphLocalPosition = paragraph.globalToLocal(globalPosition);
      final result = paragraph.getFragmentAtPosition(paragraphLocalPosition);
      if (result != null) {
        final nodeId = (paragraph.container as dynamic).id as String;
        return _FragmentHitResult(
          nodeId: nodeId,
          fragmentId: result.fragmentId,
          localOffset: result.localOffset,
        );
      }
    }

    // 2. Fallback: FluentImage block-level
    return _findBlockImageAtPosition(globalPosition);
  }

  /// Searches among FluentImage and HorizontalRule in the document for the one
  /// that contains [globalPosition].
  _FragmentHitResult? _findBlockImageAtPosition(Offset globalPosition) {
    _FragmentHitResult? hit;
    walkTree(widget.document.content, (node, _) {
      if (hit != null) return false;
      if (node is FluentImage || node is HorizontalRule) {
        final keyCtx = widget.document.getKeyForNode(node.id).currentContext;
        final box = keyCtx?.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final local = box.globalToLocal(globalPosition);
          if (local.dx >= 0 &&
              local.dx <= box.size.width &&
              local.dy >= 0 &&
              local.dy <= box.size.height) {
            final offset = local.dx < box.size.width / 2 ? 0 : 1;
            hit = _FragmentHitResult(
              nodeId: node.id,
              fragmentId: node.id,
              localOffset: offset,
            );
            return false;
          }
        }
      }
      return true;
    });
    return hit;
  }
  
  /// Finds the RenderFluentParagraph at a local position.
  RenderFluentParagraph? _findParagraphAtPosition(RenderBox root, Offset localPosition) {
    // 1. Try exact hit test
    final result = BoxHitTestResult();
    root.hitTest(result, position: localPosition);

    for (final entry in result.path) {
      if (entry.target is RenderFluentParagraph) {
        return entry.target as RenderFluentParagraph;
      }
    }

    // 2. Fallback: find the nearest paragraph vertically
    RenderFluentParagraph? nearestParagraph;
    double minVerticalDistance = double.infinity;

    for (final paragraph in _collectAllParagraphs(root)) {
      final paragraphBox = paragraph as RenderBox;
      final paragraphRect = paragraphBox.localToGlobal(Offset.zero) & paragraphBox.size;
      final rootLocalRect = root.globalToLocal(paragraphRect.topLeft) & paragraphBox.size;

      double verticalDistance;
      if (localPosition.dy < rootLocalRect.top) {
        verticalDistance = rootLocalRect.top - localPosition.dy;
      } else if (localPosition.dy > rootLocalRect.bottom) {
        verticalDistance = localPosition.dy - rootLocalRect.bottom;
      } else {
        verticalDistance = 0;
      }

      double horizontalDistance = 0;
      if (localPosition.dx < rootLocalRect.left) {
        horizontalDistance = rootLocalRect.left - localPosition.dx;
      } else if (localPosition.dx > rootLocalRect.right) {
        horizontalDistance = localPosition.dx - rootLocalRect.right;
      }

      final totalDistance = verticalDistance + horizontalDistance * 0.5;

      if (totalDistance < minVerticalDistance) {
        minVerticalDistance = totalDistance;
        nearestParagraph = paragraph;
      }
    }

    return nearestParagraph;
  }

  /// Collects all RenderFluentParagraph in the render tree
  List<RenderFluentParagraph> _collectAllParagraphs(RenderBox root) {
    final paragraphs = <RenderFluentParagraph>[];

    void visit(RenderObject node) {
      if (node is RenderFluentParagraph) {
        paragraphs.add(node);
      }
      node.visitChildren(visit);
    }

    visit(root);
    return paragraphs;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      child: RawGestureDetector(
        gestures: {
          PanGestureRecognizer: GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
            () => PanGestureRecognizer(),
            (PanGestureRecognizer instance) {
              instance
                ..onStart = onPanStart
                ..onUpdate = onPanUpdate
                ..onEnd = onPanEnd
                ..onCancel = onPanCancel;
            },
          ),
        },
        behavior: HitTestBehavior.translucent,
        child: MouseRegion(
          cursor: SystemMouseCursors.text,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        ),
      ),
    );
  }
}

/// Result of a hit test on a fragment
class _FragmentHitResult {
  final String nodeId;
  final String fragmentId;
  final int localOffset;
  
  _FragmentHitResult({
    required this.nodeId,
    required this.fragmentId,
    required this.localOffset,
  });
}