import 'package:fluent_editor/core/types.dart';
import 'package:fluent_editor/cursor.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/event_handler.dart';
import 'package:fluent_editor/renderers/render_fluent_node.dart';
import 'package:fluent_editor/renderers/render_fragment.dart';
import 'package:fluent_editor/renderers/render_paragraph.dart';
import 'package:fluent_editor/utils/tree_utils.dart';
import 'package:fluent_editor/widgets/nodes/fluent_paragraph_widget.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

RenderFluentNode? _findTopLevelRenderNodeRecursive(RenderFluentLeaf start) {
  RenderObject? current = start;
  RenderFluentNode? lastNode;
  while (current != null) {
    if (current is RenderFluentNode) {
      lastNode = current;
    }
    current = current.parent;
  }
  return lastNode;
}

int _computeGlobalOffset(FNode container, FNode fragmentNode, int localOffset) {
  final flat = flattenFragmentsSimple(container);
  for (final (f, start, _) in flat) {
    if (f.id == fragmentNode.id) {
      return start + localOffset;
    }
  }
  return localOffset;
}

List<(Fragment, int, int)> flattenFragmentsSimple(FNode node) {
  final result = <(Fragment, int, int)>[];
  _flattenSimple(node, 0, result);
  return result;
}

int _flattenSimple(FNode node, int currentOffset, List<(Fragment, int, int)> result) {
  if (node is InlineContainerNode) {
    for (final child in (node as InlineContainerNode).getChildren()) {
      currentOffset = _flattenSimple(child, currentOffset, result);
    }
    return currentOffset;
  }
  if (node is Fragment) {
    final len = node.text.length;
    result.add((node, currentOffset, currentOffset + len));
    return currentOffset + len;
  }
  return currentOffset;
}

CursorOffset? resolvePositionGestureDetails(PositionedGestureDetails details, BuildContext context, Widget widget) {
  final renderBox = context.findRenderObject() as RenderBox;
  final result = BoxHitTestResult();
  final localPosition = renderBox.globalToLocal(details.globalPosition);
  renderBox.hitTest(result, position: localPosition);
  
  //Search for RenderFluentParagraph first
  RenderFluentParagraph? foundParagraph;
  for (final entry in result.path) {
    if (entry.target is RenderFluentParagraph) {
      foundParagraph = entry.target as RenderFluentParagraph;
      final fragmentResult = foundParagraph.getFragmentAtPosition(localPosition);
      if (fragmentResult != null) {
        return CursorOffset(
          id: fragmentResult.fragmentId,
          offset: fragmentResult.localOffset,
        );
      }
    }
  }
  
  // Fallback: old method with RenderFluentFragment
  for (final entry in result.path) {
    if (entry.target is RenderFluentFragment) {
      if ((entry.target as RenderFluentFragment).node is! InlineContainerNode) {
        return detectOffsetOnRenderFluentFragment(entry.target as RenderFluentFragment, renderBox, localPosition, context, widget);
      }
    }
  }
  return null;
}

CursorOffset? detectOffsetOnRenderFluentFragment(RenderFluentFragment fragment, RenderBox renderBox, Offset localPosition, BuildContext context, Widget widget) {
    final fragmentBox = fragment;
    final localInFragment = fragmentBox.globalToLocal(
      renderBox.localToGlobal(localPosition),
    );
    final localOffset = fragment.getOffsetForPosition(localInFragment);
    // Walk up the render tree to find the top-level RenderFluentNode
    final topLevel = _findTopLevelRenderNodeRecursive(fragment);
    if (topLevel != null) {
      final globalOffset = _computeGlobalOffset(topLevel.node, fragment.node, localOffset);
      return CursorOffset(
        id: topLevel.id,
        offset: globalOffset,
      );
    }
    // Fallback: use widget's node (may be Link-relative for nested structures)
    return CursorOffset(
      id: (widget as FluentParagraphWidget).node.id,
      offset: absoluteOffset(fragment, localOffset, widget),
    );
}

int absoluteOffset(RenderFluentFragment targetRender, int localOffset, Widget widget) {
  int absolute = 0;
  
  for (final child in ((widget as FluentParagraphWidget).node as InlineContainerNode).getChildren()) {
    final result = _walkNode(child, targetRender, localOffset, absolute);
    if (result.$1) return result.$2; // found
    absolute = result.$2;
  }
  
  return absolute;
}

//walk into nodes until we find the target render fragment
(bool, int) _walkNode(FNode node, RenderFluentFragment targetRender, int localOffset, int currentOffset) {
  // Link extends Paragraph AND implements Fragment, check Link first!
  if (node is InlineContainerNode) {
    int offset = currentOffset;
    for (final child in (node as InlineContainerNode).fragments) {
      final result = _walkNode(child, targetRender, localOffset, offset);
      if (result.$1) return result;
      offset = result.$2;
    }
    return (false, offset);
  }
  if (node is Fragment) {
    if (node.id == targetRender.id) {
      return (true, currentOffset + localOffset);
    }
    return (false, currentOffset + node.text.length);
  }
  return (false, currentOffset);
}

Fragment? getFirstFragmentRecursive(InlineContainerNode node) {
  var children = node.getChildren();
  children = children.where((child) => child is InlineContainerNode || (child is Fragment && child.text.isNotEmpty)).toList();
  if (children.isEmpty) return null;
  final firstChild = children.first;
  if (firstChild is InlineContainerNode) {
    return getFirstFragmentRecursive(firstChild as InlineContainerNode);
  }
  return firstChild as Fragment;
}

Fragment? getLastFragmentRecursive(InlineContainerNode node) {
  var children = node.getChildren();
  children = children.where((child) => child is InlineContainerNode || (child is Fragment && child.text.isNotEmpty)).toList();
  if (children.isEmpty) return null;
  final lastChildren = children.last;
  if (lastChildren is InlineContainerNode) {
    return getLastFragmentRecursive(lastChildren as InlineContainerNode);
  }
  return lastChildren as Fragment;
}

FragmentRange? getFragmentAtCursor(EventHandler eventHandler) {
  final cursor = eventHandler.document.cursor;
  final targetId = cursor.anchorId;
  final node = eventHandler.document.nodeById(targetId);
  if (node == null) {
    return null;
  }
  // Flatten all fragments in the container with their global offsets.
  // Use the document cache to avoid rebuilding on repeated calls.
  final flat = eventHandler.document.flattenContainer(node);
  for (int i = 0; i < flat.length; i++) {
    final (fragment, startOffset, endOffset) = flat[i];
    // Check if the cursor offset falls within this fragment
    if (cursor.anchorOffset >= startOffset && cursor.anchorOffset <= endOffset) {
      // Find the direct parent of this fragment (Link or Paragraph)
      final parent = findDirectParent(node, fragment);
      final localOffset = cursor.anchorOffset - startOffset;
      return FragmentRange(
        fragment: fragment,
        parent: parent?.node ?? node,
        offset: localOffset,
        focus: localOffset,
      );
    }
  }
  return null;
}

int findCurrentFragmentIndex(InlineContainerNode parent, Cursor cursor) {
  final flat = flattenFragmentsSimple(parent as FNode);
  var currentIndex = -1;
  for (int i = 0; i < flat.length; i++) {
    final (fragment, startOffset, endOffset) = flat[i];
    if (cursor.anchorOffset >= startOffset && cursor.anchorOffset <= endOffset) {
      currentIndex = i;
      break;
    }
  }
  return currentIndex;
}

//region cursor finds
FNode? getNodeAtCursor(EventHandler eventHandler) {
  final targetId = eventHandler.document.cursor.anchorId;
  return eventHandler.document.nodeById(targetId);
}

