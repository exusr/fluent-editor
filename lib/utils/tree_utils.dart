import 'package:fluent_editor/core/constants.dart';
import 'package:fluent_editor/core/types.dart';
import 'package:fluent_editor/factories.dart';

FNodeRange? findDirectParent(FNode root, FNode target) {
  if (root is InlineContainerNode) {
    for (final child in (root as InlineContainerNode).getChildren()) {
      if (child.id == target.id) return FNodeRange(node: root, parent: null);
      if (child is InlineContainerNode) {
        final found = findDirectParent(child, target);
        if (found != null) {
          return FNodeRange(
            node: found.node,
            parent: found.parent ?? root,
          );
        }
      }
    }
  }
  return null;
}


/// Counts characters excluding zero-width space (ZWS) without
/// allocating a new string via replaceAll. Called inside tight
/// loops (e.g. getNextFragmentRecursive), so every allocation matters.
int _countWithoutZws(String text) {
  int count = 0;
  for (int i = 0; i < text.length; i++) {
    if (text[i] != Whitespaces.zws) count++;
  }
  return count;
}

// Return node length (sum of all fragments length)
int nodeLength(FNode node) {
  if (node is InlineContainerNode) {
    return _countWithoutZws((node as InlineContainerNode).text);
  }
  if (node is Fragment) return _countWithoutZws(node.text);
  return 0;
}


Fragment? getNextFragmentRecursive(int currentAcc, int targetAcc,  FNode node) {
  for (final c in (node as InlineContainerNode).getChildren().where((node) => nodeLength(node) > 0)) {
    if (nodeLength(c) + currentAcc < targetAcc) {
      currentAcc += nodeLength(c);
      continue;
    }
    if (nodeLength(c) + currentAcc > targetAcc) {
      if (c is InlineContainerNode) {
        return getNextFragmentRecursive(currentAcc, targetAcc, c);
      } else if (c is Fragment) {
        return c;
      }
    }
  }
  return null;
}

InlineContainerNode? findNodeAfterRecursive(FNode container, FNode targetNode) {
  final range = findDirectParent(container, targetNode);
  if (range == null) {
    return null; // No parent, no next node
  }
  final parentNode = range.node;
  if (parentNode is InlineContainerNode) {
    final siblings = (parentNode as InlineContainerNode).getChildren();
    for (int i = 0; i < siblings.length; i++) {
      if (siblings[i].id == targetNode.id) { // Found current node in parent's children
        if (i < siblings.length - 1) { // Current node is not the last child, return next sibling
          final nextSibling = siblings[i + 1];
          if (nextSibling is InlineContainerNode) {
            return nextSibling as InlineContainerNode;
          }
        } else { // Current node is the last child, recurse up the tree
          return findNodeAfterRecursive(container, parentNode);
        }
      }
    }
  }
  return null;
}


InlineContainerNode? findNodeBeforeRecursive(FNode container, FNode targetNode) {
  if (container is InlineContainerNode) {
    final children = (container as InlineContainerNode).getChildren();
    for (int i = 0; i < children.length; i++) {
      if (children[i].id == targetNode.id) { // Found target, return previous if exists
        if (i > 0 && children[i - 1] is InlineContainerNode) {
          return children[i - 1] as InlineContainerNode;
        }
        return null;
      }
      // Search recursively in children
      final result = findNodeBeforeRecursive(children[i], targetNode);
      if (result != null) {
        return result;
      }
    }
  }
  return null;
}
