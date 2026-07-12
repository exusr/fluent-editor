import 'dart:convert';
import 'dart:developer' as developer;

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_insert_character.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';
import 'package:flutter/services.dart';
import 'package:nanoid/nanoid.dart';

class _ClipboardPayload {
  final String plainText;
  /// Cloned and truncated nodes ready for paste, serialized as JSON
  final List<Map<String, dynamic>> nodes;

  _ClipboardPayload({required this.plainText, required this.nodes});

  Map<String, dynamic> toJson() => {
    'plainText': plainText,
    'nodes': nodes,
  };

  factory _ClipboardPayload.fromJson(Map<String, dynamic> json) =>
      _ClipboardPayload(
        plainText: json['plainText'] as String? ?? '',
        nodes: (json['nodes'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>(),
      );
}

Future<void> executeHandleCopy(FluentDocument document) async {
  final cursor = document.cursor;
  if (cursor.isCollapsed) return;

  final sel = resolveSelectionFromCursor(document);

  if (sel == null) return;

  final clonedNodes = <Map<String, dynamic>>[];
  final plainTextBuffer = StringBuffer();

  final topLevelNodes = _groupByTopLevel(document.content, sel);

  for (final tlEntry in topLevelNodes) {
    final clone = _cloneTopLevel(tlEntry, sel, plainTextBuffer);
    if (clone != null) {
      clonedNodes.add(clone.toJson());
    } else {
    }
    plainTextBuffer.write('\n');
  }

  final plainText = plainTextBuffer.toString().trimRight();

  final payload = _ClipboardPayload(
    plainText: plainText,
    nodes: clonedNodes,
  );

  await Clipboard.setData(ClipboardData(text: plainText));
  document.clipboardPayload = jsonEncode(payload.toJson());
}

Future<void> executeHandleCut(FluentDocument document) async {
  final cursor = document.cursor;
  if (cursor.isCollapsed) return;

  await executeHandleCopy(document);

  executeHandleReplaceSelection('', document);
  
  document.updateContent();
}

Future<void> executeHandlePaste(FluentDocument document) async {
  final internalPayload = document.clipboardPayload;
  if (internalPayload != null) {
    try {
      final payload = _ClipboardPayload.fromJson(
        jsonDecode(internalPayload) as Map<String, dynamic>,
      );
      if (payload.nodes.isNotEmpty) {
        _pasteNodes(payload.nodes, document);
        return;
      }
    } catch (e) {
    }
  }

  final data = await Clipboard.getData(Clipboard.kTextPlain);
  if (data?.text != null && data!.text!.isNotEmpty) {
    _pastePlainText(data.text!, document);
  }
}

Future<void> executeHandlePastePlain(FluentDocument document) async {
  final internalPayload = document.clipboardPayload;
  if (internalPayload != null) {
    try {
      final payload = _ClipboardPayload.fromJson(
        jsonDecode(internalPayload) as Map<String, dynamic>,
      );
      _pastePlainText(payload.plainText, document);
      return;
    } catch (_) {}
  }

  final data = await Clipboard.getData(Clipboard.kTextPlain);
  if (data?.text != null && data!.text!.isNotEmpty) {
    _pastePlainText(data.text!, document);
  }
}

void _pasteNodes(List<Map<String, dynamic>> nodesJson, FluentDocument document) {
  if (!document.cursor.isCollapsed) {
    executeHandleReplaceSelection('', document);
  }

  final root = document.content;
  final cursor = document.cursor;

  final curContainer = findLogicalContainer(root, cursor.anchorId);
  final curTopLevel = _findTopLevelParent(root, cursor.anchorId);
  if (curTopLevel == null) {
    return;
  }

  final converter = const FNodeJsonConverter();
  FNode lastInserted = curTopLevel;
  Fragment? lastFragment;

  for (int i = 0; i < nodesJson.length; i++) {
    final nodeJson = nodesJson[i];
    FNode newNode;
    try {
      newNode = converter.fromJson(nodeJson);
      _reassignIds(newNode);
    } catch (e) {
      continue;
    }

    if (newNode is Link) {
      final wrapper = Paragraph();
      wrapper.fragments.clear();
      wrapper.fragments.add(newNode);
      newNode = wrapper;
    }

    final curContainerIsMergeTarget = curContainer is Paragraph &&
        curContainer is! Link &&
        curContainer is! FluentList;

    final canMerge = i == 0 &&
        newNode is Paragraph &&
        newNode is! Link &&
        newNode is! FluentList &&
        curContainerIsMergeTarget;

    if (canMerge) {
      lastFragment = _mergeFragmentsIntoParagraph(
        newNode,
        curContainer,
        cursor,
      );
    } else {
      insertAfter(root, lastInserted, newNode);
      lastInserted = newNode;
      lastFragment = FragmentOperations.collectLeafFragments(newNode).lastOrNull;
    }
  }

  if (lastFragment != null) {
    document.cursor.moveTo(lastFragment.id, lastFragment.text.length);
  } else {
    _moveCursorToEndOf(lastInserted, document);
  }

  document.selectionManager.collapse();
  document.syncPendingFontWithCursor();
  document.updateContent();

  mergeConsecutiveLists(root);
}

/// Merges the fragments of the source node into the destination paragraph at
/// the cursor position. Returns the last inserted fragment (for the caret).
Fragment? _mergeFragmentsIntoParagraph(
  Paragraph src,
  Paragraph dest,
  dynamic cursor,
) {
  final flat = _flattenFragmentsOf(dest);
  Fragment? splitFrag;
  int splitOffset = 0;
  for (final frag in flat) {
    if (frag.id == cursor.anchorId) {
      splitFrag = frag;
      splitOffset = (cursor.anchorOffset as int).clamp(0, frag.text.length);
      break;
    }
  }
  if (splitFrag == null && flat.isNotEmpty) {
    splitFrag = flat.last;
    splitOffset = splitFrag.text.length;
  }
  if (splitFrag == null) return null;

  final leftText = FragmentOperations.safeSubstring(splitFrag.text, 0, splitOffset);
  final rightText = FragmentOperations.safeSubstring(splitFrag.text, splitOffset);
  splitFrag.text = leftText;

  final destNode = dest as FNode;
  FNode anchor = splitFrag;
  Fragment? lastInserted = splitFrag;

  final srcChildren = src.fragments; // List<FNode>: Fragment, Link, FluentImage, HorizontalRule
  for (final child in srcChildren) {
    insertAfter(destNode, anchor, child);
    anchor = child;
    if (child is Link) {
      final leaves = _flattenLeaves(child.fragments);
      lastInserted = leaves.lastOrNull ?? lastInserted;
    } else if (child is HorizontalRule) {
      lastInserted = child;
    } else if (child is FluentImage) {
      lastInserted = child;
    } else if (child is Fragment) {
      lastInserted = child;
    }
  }

  if (rightText.isNotEmpty) {
    final rightFrag = Fragment(
      rightText,
      styles: splitFrag.styles != null ? List.from(splitFrag.styles!) : null,
      fontFamily: splitFrag.fontFamily,
      fontSize: splitFrag.fontSize,
      color: splitFrag.color,
      highlightColor: splitFrag.highlightColor,
    );
    insertAfter(destNode, anchor, rightFrag);
  }

  if (leftText.isEmpty && dest.fragments.length > 1) {
    dest.fragments.removeWhere((f) => f.id == splitFrag!.id);
  }

  return lastInserted;
}

void _pastePlainText(String text, FluentDocument document) {
  if (text.isEmpty) return;

  if (!document.cursor.isCollapsed) {
    executeHandleReplaceSelection('', document);
  }

  final lines = text.split('\n');
  for (int i = 0; i < lines.length; i++) {
    if (i > 0) {
      _insertParagraphBreak(document);
    }
    if (lines[i].isNotEmpty) {
      executeHandleInsertText(lines[i], document);
    }
  }

  document.selectionManager.collapse();
  document.syncPendingFontWithCursor();
  document.updateContent();
}

void _insertParagraphBreak(FluentDocument document) {
  final cursor = document.cursor;
  final root = document.content;
  final container = findLogicalContainer(root, cursor.anchorId);
  if (container is! InlineContainerNode) return;

  final newParagraph = Paragraph(
    textAlign: (container is Paragraph) ? container.textAlign : 'left',
    indent: (container is Paragraph) ? container.indent : 0,
  );
  final firstFrag = newParagraph.fragments.first as Fragment;
  FragmentOperations.applyPendingStyles(document, firstFrag);

  final topLevel = _findTopLevelParent(root, cursor.anchorId);
  if (topLevel != null) {
    insertAfter(root, topLevel, newParagraph);
  }
  document.cursor.moveTo(firstFrag.id, 0);
}

/// Groups SelectedNodes by their top-level container
/// (direct Paragraph, FluentList, FluentTable, FluentImage).
List<_TopLevelEntry> _groupByTopLevel(Root root, ResolvedSelection sel) {
  final result = <_TopLevelEntry>[];
  final seen = <String>{};

  for (final selectedNode in sel.nodes) {
    final containerNode = selectedNode.container as FNode;
    final containerId = containerNode.id;
    final topLevel = _findTopLevelParent(root, containerId);
    if (topLevel == null) continue;
    final tlId = topLevel.id;

    if (seen.contains(tlId)) {
      result.last.selectedNodes.add(selectedNode);
    } else {
      seen.add(tlId);
      result.add(_TopLevelEntry(topLevel: topLevel, selectedNodes: [selectedNode]));
    }
  }

  for (final node in root.nodes) {
    if (node is FluentImage) {
      final nodeId = node.id;
      if (_isImageInSelection(root, node, sel)) {
        if (!seen.contains(nodeId)) {
          seen.add(nodeId);
          result.add(_TopLevelEntry(topLevel: node, selectedNodes: []));
        }
      }
    }
  }

  return result;
}

bool _isImageInSelection(Root root, FluentImage image, ResolvedSelection sel) {
  for (final sn in sel.nodes) {
    if (sn.startFragment.id == image.id || sn.endFragment.id == image.id) {
      return true;
    }
  }
  return false;
}

/// Clones a top-level node with only the selected contents
FNode? _cloneTopLevel(
  _TopLevelEntry entry,
  ResolvedSelection sel,
  StringBuffer plainText,
) {
  final node = entry.topLevel;

  if (node is HorizontalRule) {
    return HorizontalRule();
  }

  if (node is FluentImage) {
    return _cloneImage(node, plainText);
  }

  if (node is FluentList) {
    return _cloneList(node, entry.selectedNodes, sel, plainText);
  }

  if (node is FluentTable) {
    return _cloneTable(node, entry.selectedNodes, sel, plainText);
  }

  if (node is Link && entry.selectedNodes.isNotEmpty) {
    return _cloneLink(node, entry.selectedNodes.first, plainText);
  }

  if (node is Paragraph &&
      node is! FluentList &&
      node is! Link &&
      entry.selectedNodes.isNotEmpty) {
    return _cloneParagraph(node, entry.selectedNodes.first, plainText);
  }

  return null;
}

FluentImage _cloneImage(FluentImage src, StringBuffer plainText) {
  final clone = FluentImage(src.src);
  clone.textAlign = src.textAlign;
  return clone;
}

/// Clones a Link preserving URL and its inline fragments/images.
Link _cloneLink(
  Link src,
  SelectedNode selectedNode,
  StringBuffer plainText,
) {
  final clone = Link(url: src.url, text: src.url);
  clone.fragments.clear();
  clone.fragments.addAll(
    _cloneInlineChildren(src.fragments, selectedNode, plainText),
  );
  if (clone.fragments.isEmpty) clone.fragments.add(Fragment(''));
  return clone;
}

Paragraph _cloneParagraph(
  Paragraph src,
  SelectedNode selectedNode,
  StringBuffer plainText,
) {
  final clone = Paragraph(
    textAlign: src.textAlign,
    indent: src.indent,
    styleName: src.styleName,
  );
  clone.fragments.clear();
  clone.fragments.addAll(
    _cloneInlineChildren(src.fragments, selectedNode, plainText),
  );
  if (clone.fragments.isEmpty) clone.fragments.add(Fragment(''));
  return clone;
}

/// Flattens the inline nodes of a container (Paragraph/Link) preserving
/// also FluentImage as a leaf (unlike _flattenFragmentsOf which skips them
/// because they are InlineContainerNode without children).
List<Fragment> _flattenLeaves(List<FNode> children) {
  final result = <Fragment>[];
  for (final child in children) {
    if (child is Link) {
      result.addAll(_flattenLeaves(child.fragments));
    } else if (child is HorizontalRule) {
      result.add(child); // atomic, treated as a leaf
    } else if (child is FluentImage) {
      result.add(child); // atomic, treated as a leaf
    } else if (child is Fragment) {
      result.add(child);
    }
  }
  return result;
}

/// Clones the inline fragments of a container (Paragraph or Link),
/// preserving FluentImage and nested Links, respecting selection bounds.
/// [inRangeIds] is optional: if provided, it's used directly without recalculation
/// (used for recursive calls on inner Links).
List<FNode> _cloneInlineChildren(
  List<FNode> children,
  SelectedNode selectedNode,
  StringBuffer plainText, {
  Set<String>? inRangeIds,
}) {
  final startId = selectedNode.startFragment.id;
  final endId   = selectedNode.endFragment.id;

  final Set<String> rangeIds;
  if (inRangeIds != null) {
    rangeIds = inRangeIds;
  } else {
    final flat = _flattenLeaves(children);
    rangeIds = {};
    bool inRange = false;
    for (final f in flat) {
      if (f.id == startId) inRange = true;
      if (inRange) rangeIds.add(f.id);
      if (f.id == endId) break;
    }
  }

  final result = <FNode>[];

  for (final child in children) {
    if (child is Link) {
      final linkLeaves = _flattenLeaves(child.fragments);
      final anyInRange = linkLeaves.any((f) => rangeIds.contains(f.id));
      if (!anyInRange) continue;
      final linkRangeIds = linkLeaves
          .where((f) => rangeIds.contains(f.id))
          .map((f) => f.id)
          .toSet();
      final linkClone = Link(url: child.url, text: child.url);
      linkClone.fragments.clear();
      linkClone.fragments.addAll(
        _cloneInlineChildren(
          child.fragments,
          selectedNode,
          plainText,
          inRangeIds: linkRangeIds,
        ),
      );
      if (linkClone.fragments.isEmpty) linkClone.fragments.add(Fragment(''));
      result.add(linkClone);
      continue;
    }

    if (child is HorizontalRule) {
      if (!rangeIds.contains(child.id)) continue;
      result.add(HorizontalRule());
      continue;
    }

    if (child is FluentImage) {
      if (!rangeIds.contains(child.id)) continue;
      result.add(_cloneImage(child, plainText));
      continue;
    }

    if (child is Fragment) {
      if (!rangeIds.contains(child.id)) continue;
      final startOff = child.id == startId ? selectedNode.startOffset : 0;
      final endOff   = child.id == endId
          ? selectedNode.endOffset
          : child.text.length;
      final text = FragmentOperations.safeSubstring(child.text, startOff, endOff);
      if (text.isNotEmpty) {
        plainText.write(text);
        result.add(_cloneFragment(child, text));
      }
    }
  }

  return result;
}

FNode? _cloneList(
  FluentList src,
  List<SelectedNode> selectedNodes,
  ResolvedSelection sel,
  StringBuffer plainText,
) {
  final clone = FluentList(listType: src.listType);
  bool first = true;

  for (final item in src.items) {
    final clonedItem = _cloneListItem(item, selectedNodes, sel, plainText, !first);
    if (clonedItem != null) {
      if (clonedItem is ListItem) {
        clone.items.add(clonedItem);
        first = false;
      } else if (clonedItem is Paragraph) {
        return clonedItem;
      }
    }
  }

  return clone.items.isEmpty ? null : clone;
}

/// Recursively clones a ListItem including sublists if selected.
/// Returns either a ListItem (for full list structure) or a Paragraph
/// (for partial text selection within a single ListItem).
FNode? _cloneListItem(
  ListItem item,
  List<SelectedNode> selectedNodes,
  ResolvedSelection sel,
  StringBuffer plainText,
  bool prefixNewline,
) {
  final clonedChildren = <FNode>[];
  bool hasContent = false;
  bool addedNewline = false;
  bool hasSublist = false;
  Paragraph? singleClonedParagraph;
  bool isPartialSelection = false;

  for (final child in item.children) {
    if (child is FluentList) {
      final clonedSub = _cloneList(child, selectedNodes, sel, plainText);
      if (clonedSub != null) {
        clonedChildren.add(clonedSub);
        hasContent = true;
        hasSublist = true;
      }
      continue;
    }

    if (child is Paragraph && child is! Link) {
      bool paragraphMatchesSn(SelectedNode sn, Paragraph par) {
        final containerId = (sn.container as FNode).id;
        if (containerId == par.id) return true;
        final parFragIds = _flattenFragmentsOf(par).map((f) => f.id).toSet();
        return parFragIds.contains(sn.startFragment.id) ||
               parFragIds.contains(sn.endFragment.id);
      }

      final isSelected = selectedNodes.any((sn) => paragraphMatchesSn(sn, child));
      if (!isSelected) continue;

      final rawSn = selectedNodes.firstWhere((sn) => paragraphMatchesSn(sn, child));

      isPartialSelection = !rawSn.isFullySelected;

      final parFragIds = _flattenFragmentsOf(child).map((f) => f.id).toSet();
      final effectiveSn = (rawSn.container as FNode).id == child.id
          ? rawSn
          : SelectedNode(
              container: child,
              startFragment: parFragIds.contains(rawSn.startFragment.id)
                  ? rawSn.startFragment
                  : _flattenFragmentsOf(child).first,
              startOffset: parFragIds.contains(rawSn.startFragment.id)
                  ? rawSn.startOffset
                  : 0,
              endFragment: parFragIds.contains(rawSn.endFragment.id)
                  ? rawSn.endFragment
                  : _flattenFragmentsOf(child).last,
              endOffset: parFragIds.contains(rawSn.endFragment.id)
                  ? rawSn.endOffset
                  : (_flattenFragmentsOf(child).lastOrNull?.text.length ?? 0),
              isFullySelected: rawSn.isFullySelected,
            );

      if (prefixNewline && !addedNewline) {
        plainText.write('\n');
        addedNewline = true;
      }
      final clonedPar = _cloneParagraph(child, effectiveSn, plainText);
      clonedChildren.add(clonedPar);
      singleClonedParagraph = clonedPar;
      hasContent = true;
      continue;
    }

  }

  if (!hasContent) return null;

  if (isPartialSelection && !hasSublist && clonedChildren.length == 1 && singleClonedParagraph != null) {
    return singleClonedParagraph;
  }

  return ListItem(
    bulletType: item.bulletType,
    indexList: List.from(item.indexList),
    children: clonedChildren,
  );
}

FluentTable? _cloneTable(
  FluentTable src,
  List<SelectedNode> selectedNodes,
  ResolvedSelection sel,
  StringBuffer plainText,
) {
  final selectedCellIds = selectedNodes
      .map((sn) => (sn.container as FNode).id)
      .toSet();
  developer.log('[COPY] _cloneTable selectedCellIds=$selectedCellIds src.rows=${src.rows.length}', name: 'clipboard');

  final cloneRows = <FluentRow>[];
  bool firstRow = true;

  for (final row in src.rows) {
    final cloneCells = <FluentCell>[];
    bool rowHasSelection = false;

    for (final cell in row.cells) {
      final cellSelected = selectedCellIds.contains(cell.id);
      if (!cellSelected) continue;

      rowHasSelection = true;
      if (!firstRow) plainText.write('\t');

      final cloneCell = FluentCell()
        ..colSpan = cell.colSpan
        ..rowSpan = cell.rowSpan;
      cloneCell.children.clear();
      bool firstCellContent = true;

      for (final child in cell.children) {
        if (child is Link) {
          if (!firstCellContent) plainText.write('\n');
          firstCellContent = false;
          final linkAsP = Paragraph();
          linkAsP.fragments.addAll(_flattenFragmentsOf(child).map((f) => _cloneFragment(f, f.text)));
          cloneCell.children.add(linkAsP);
        } else if (child is Paragraph) {
          if (!firstCellContent) plainText.write('\n');
          firstCellContent = false;
          final flat = _flattenFragmentsOf(child);
          final snForChild = SelectedNode(
            container: child,
            startFragment: flat.firstOrNull ?? Fragment(''),
            startOffset: 0,
            endFragment: flat.lastOrNull ?? Fragment(''),
            endOffset: flat.lastOrNull?.text.length ?? 0,
            isFullySelected: true,
          );
          cloneCell.children.add(_cloneParagraph(child, snForChild, plainText));
        } else if (child is FluentImage) {
          cloneCell.children.add(_cloneImage(child, plainText));
        }
      }

      if (cloneCell.children.isEmpty) {
        cloneCell.children.add(Paragraph());
      }
      cloneCells.add(cloneCell);
    }

    if (rowHasSelection) {
      if (!firstRow) plainText.write('\n');
      firstRow = false;
      final cloneRow = FluentRow(cells: cloneCells);
      cloneRows.add(cloneRow);
    }
  }

  return cloneRows.isEmpty ? null : FluentTable(rows: cloneRows);
}

Fragment _cloneFragment(Fragment src, String text) {
  return Fragment(
    text,
    styles: src.styles != null ? List.from(src.styles!) : null,
    fontFamily: src.fontFamily,
    fontSize: src.fontSize,
    color: src.color,
    highlightColor: src.highlightColor,
  );
}

/// Flattens only the leaf Fragments of an inline container
List<Fragment> _flattenFragmentsOf(InlineContainerNode node) {
  final result = <Fragment>[];
  for (final child in node.getChildren()) {
    if (child is Link) {
      result.addAll(_flattenFragmentsOf(child as InlineContainerNode));
    } else if (child is InlineContainerNode) {
      result.addAll(_flattenFragmentsOf(child as InlineContainerNode));
    } else if (child is Fragment) {
      result.add(child);
    }
  }
  return result;
}

/// Finds the top-level node (direct child of Root) that contains the fragment
FNode? _findTopLevelParent(Root root, String fragmentId) {
  for (final node in root.nodes) {
    if (_containsId(node, fragmentId)) return node;
  }
  return null;
}

bool _containsId(FNode node, String id) {
  if (node.id == id) return true;
  for (final child in childrenOf(node)) {
    if (_containsId(child, id)) return true;
  }
  return false;
}

/// Reassigns new IDs to all nodes in the subtree to avoid conflicts
void _reassignIds(FNode node) {
  node.id = nanoid();
  for (final child in childrenOf(node)) {
    _reassignIds(child);
  }
}

void _moveCursorToEndOf(FNode node, FluentDocument document) {
  final frags = FragmentOperations.collectLeafFragments(node);
  if (frags.isNotEmpty) {
    final last = frags.last;
    document.cursor.moveTo(last.id, last.text.length);
  }
}

class _TopLevelEntry {
  final FNode topLevel;
  final List<SelectedNode> selectedNodes;
  _TopLevelEntry({required this.topLevel, required this.selectedNodes});
}