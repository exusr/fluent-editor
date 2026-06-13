
import 'package:fluent_editor/core/constants.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/cursor_utils.dart';

class FNodeRange {
  final FNode node;
  final FNode? parent;

  FNodeRange({required this.node, this.parent});
}

class FragmentRange {
  final FNode fragment;
  final FNode parent;
  final int offset;
  final int focus;

  FragmentRange({
    required this.fragment,
    required this.parent,
    required this.offset,
    required this.focus,
  });
}

class CursorOffset {
  String id;
  int offset;

  CursorOffset({required this.id, required this.offset});

  //convert local cursor coords to global position managing boundaries chars
  void _foundForward(FluentDocument document) {
    for (final topLevelNode in document.content.nodes) {
      final flat = flattenFragmentsSimple(topLevelNode);
      var skipped = false;
      for (final (fragment, startOffset, _) in flat) {
        if (skipped && fragment.text.contains(Whitespaces.zws)) {
          id = topLevelNode.id;
          offset = startOffset + (fragment.text.indexOf(Whitespaces.zws) + 1);
          return;
        }
        if (fragment.id == id) {
          if (fragment.text.length >= offset) {
            if (fragment.text[(offset-1).clamp(0, fragment.text.length)] == Whitespaces.zws) {
              skipped = true;
              continue;
            }
          }
          id = topLevelNode.id;
          offset = startOffset + offset;
          return;
        }
      }
    }
  }

  //convert local cursor coords to global position managing boundaries chars
  void _foundBackward(FluentDocument document) {
    for (final topLevelNode in document.content.nodes) {
      final flat = flattenFragmentsSimple(topLevelNode);
      (Fragment, int)? lastStep;
      for (final (fragment, startOffset, _) in flat) {
        if (fragment.id == id) {
          if (fragment.text[(offset).clamp(0, fragment.text.length - 1)] == Whitespaces.zws && lastStep != null) {
            id = topLevelNode.id;
            final lastMarkerIndex = lastStep.$1.text.lastIndexOf(Whitespaces.zws);
            if (lastMarkerIndex != -1) {
              offset = lastStep.$2 + lastMarkerIndex;
              return;
            }
          }
          id = topLevelNode.id;
          offset = startOffset + offset;
          return;
        }
        if (fragment.text.contains(Whitespaces.zws)) {
          lastStep = (fragment, startOffset);
        }
      }
    }
  }

  void localToGlobal(FluentDocument document, {bool forward = true}) {
    if (document.content.nodes.any((e) => e.id == id)) return;
    if (forward) { _foundForward(document); return; }
    _foundBackward(document);
  }
}
