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
  
  void onPanStart(DragStartDetails details) {
    widget.document.requestEditorFocus();

    // Request focus on hidden TextField for mobile platforms to show virtual keyboard
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      widget.document.requestMobileKeyboardFocus();
    }

    // CRITICAL: Use the PointerDown position if available,
    // because details.globalPosition arrives AFTER the slop of the gesture recognizer
    // and could be on a different line than the initial click
    final startPosition = _pointerDownPosition ?? details.globalPosition;

    // Find the fragment at the initial position (the click position, not the slop)
    final result = _findFragmentAtPosition(startPosition);

    if (result != null) {
      _isSelecting = true;

      // Start the selection
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

    // Find the fragment at the new position
    final result = _findFragmentAtPosition(details.globalPosition);

    if (result != null) {
      // Update the selection focus
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
  }
  
  void onPanCancel() {
    _isSelecting = false;
    _pointerDownPosition = null;
  }

  /// Finds the fragment and local offset at a global position
  _FragmentHitResult? _findFragmentAtPosition(Offset globalPosition) {
    // Get the RenderBox of the Scrollable or main container
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

    // 2. Fallback: FluentImage block-level (direct children of Root/ListItem/
    //    FluentCell). The hit test doesn't find a RenderFluentParagraph because
    //    these widgets don't have a paragraph as render object.
    return _findBlockImageAtPosition(globalPosition);
  }

  /// Searches among FluentImage and HorizontalRule in the document for the one that contains
  /// [globalPosition] (matches via the GlobalKey registered in FluentDocument).
  /// Returns offset 0 (left) or 1 (right) based on the tap side.
  _FragmentHitResult? _findBlockImageAtPosition(Offset globalPosition) {
    _FragmentHitResult? hit;
    walkTree(widget.document.content, (node, _) {
      if (hit != null) return false; // stop
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
            return false; // stop walk
          }
        }
      }
      return true;
    });
    return hit;
  }
  
  /// Finds the RenderFluentParagraph at a local position.
  /// If the hit test fails (e.g. beyond the last line), searches for the paragraph
  /// closest vertically for a fluid selection.
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
    // This handles the case where we are beyond the last line of the document
    RenderFluentParagraph? nearestParagraph;
    double minVerticalDistance = double.infinity;

    // Iterate over all render paragraphs registered in the document
    for (final paragraph in _collectAllParagraphs(root)) {
      final paragraphBox = paragraph as RenderBox;
      final paragraphRect = paragraphBox.localToGlobal(Offset.zero) & paragraphBox.size;
      final rootLocalRect = root.globalToLocal(paragraphRect.topLeft) & paragraphBox.size;

      // Calculate vertical distance (consider above and below)
      double verticalDistance;
      if (localPosition.dy < rootLocalRect.top) {
        // Above the paragraph
        verticalDistance = rootLocalRect.top - localPosition.dy;
      } else if (localPosition.dy > rootLocalRect.bottom) {
        // Below the paragraph
        verticalDistance = localPosition.dy - rootLocalRect.bottom;
      } else {
        // Inside the paragraph vertically (but not found by hit test)
        verticalDistance = 0;
      }

      // Also consider horizontal distance if we are very far
      double horizontalDistance = 0;
      if (localPosition.dx < rootLocalRect.left) {
        horizontalDistance = rootLocalRect.left - localPosition.dx;
      } else if (localPosition.dx > rootLocalRect.right) {
        horizontalDistance = localPosition.dx - rootLocalRect.right;
      }

      // Total distance (priority to vertical)
      final totalDistance = verticalDistance + horizontalDistance * 0.5;

      if (totalDistance < minVerticalDistance) {
        minVerticalDistance = totalDistance;
        nearestParagraph = paragraph;
      }
    }

    return nearestParagraph;
  }

  /// Collects all RenderFluentParagraph in the tree
  List<RenderFluentParagraph> _collectAllParagraphs(RenderBox root) {
    final paragraphs = <RenderFluentParagraph>[];

    // Visit the entire tree to find RenderFluentParagraph
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
    // Listener intercepts PointerDownEvent BEFORE the gesture recognizer
    // This is essential to capture the exact position of the click
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

/// Risultato di un hit test su un fragment
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