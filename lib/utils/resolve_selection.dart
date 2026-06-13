// resolve_selection.dart
//
// Utility that resolves the active selection into a structured object with
// references to the involved nodes.
//
// MAIN FUNCTION:
//   resolveSelection(root, anchorFragmentId, anchorOffset,
//                         focusFragmentId,  focusOffset)
//     → ResolvedSelection?   (null = collapsed cursor or position not found)
//
// DATA MODEL:
//   ResolvedSelection
//   ├── anchor: SelectionEndpoint   (reference to fragment + offset)
//   ├── focus:  SelectionEndpoint
//   ├── base:   SelectionEndpoint   (the lesser in document order)
//   ├── extent: SelectionEndpoint   (the greater)
//   └── nodes:  List<SelectedNode>  (all traversed nodes, in order)
//
//   SelectedNode
//   ├── container:        InlineContainerNode  (Paragraph / ListItem / FluentCell)
//   ├── startFragment:    Fragment             (first selected fragment in node)
//   ├── startOffset:      int                  (local offset in startFragment)
//   ├── endFragment:      Fragment             (last selected fragment)
//   ├── endOffset:        int                  (local offset in endFragment)
//   └── isFullySelected:  bool                 (entire node selected)

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/node_operations.dart';

// ─── Modelli ─────────────────────────────────────────────────────────

/// An endpoint of the selection with direct reference to the Fragment.
class SelectionEndpoint {
  /// The leaf Fragment where this selection endpoint falls.
  final Fragment fragment;

  /// Local offset inside [fragment].
  final int offset;

  /// The LogicalLine container (Paragraph / ListItem / FluentCell).
  final InlineContainerNode container;

  const SelectionEndpoint({
    required this.fragment,
    required this.offset,
    required this.container,
  });

  @override
  String toString() =>
      'SelectionEndpoint(${fragment.id}:$offset in ${(container as FNode).id})';
}

/// A node partially or completely traversed by the selection.
class SelectedNode {
  /// The logical container (Paragraph / ListItem / FluentCell).
  final InlineContainerNode container;

  /// First selected fragment in this node.
  /// If the node is completely selected, it coincides with the first fragment.
  final Fragment startFragment;

  /// Local offset in [startFragment] where the selection starts.
  /// 0 if the node is completely selected or if the selection starts before.
  final int startOffset;

  /// Last selected fragment in this node.
  final Fragment endFragment;

  /// Local offset in [endFragment] where the selection reaches.
  /// text.length if the node is completely selected or the selection continues.
  final int endOffset;

  /// True if the entire node is included in the selection
  /// (neither startOffset nor endOffset are partial).
  final bool isFullySelected;

  const SelectedNode({
    required this.container,
    required this.startFragment,
    required this.startOffset,
    required this.endFragment,
    required this.endOffset,
    required this.isFullySelected,
  });

  @override
  String toString() {
    final id = (container as FNode).id;
    return 'SelectedNode($id: ${startFragment.id}:$startOffset → '
        '${endFragment.id}:$endOffset, full=$isFullySelected)';
  }
}

/// The active selection with all references resolved.
class ResolvedSelection {
  /// Fixed endpoint (where the selection started).
  final SelectionEndpoint anchor;

  /// Mobile endpoint (where the cursor is now).
  final SelectionEndpoint focus;

  /// The endpoint that comes first in the document (anchor or focus).
  final SelectionEndpoint base;

  /// The endpoint that comes after in the document (anchor or focus).
  final SelectionEndpoint extent;

  /// All nodes traversed by the selection, in document order.
  /// The first and last can be partially selected.
  /// Intermediate ones are always completely selected.
  final List<SelectedNode> nodes;

  /// True if the selection traverses more than one LogicalLine.
  bool get isMultiNode => nodes.length > 1;

  /// True if anchor and focus are on the same container.
  bool get isSingleNode => nodes.length == 1;

  const ResolvedSelection({
    required this.anchor,
    required this.focus,
    required this.base,
    required this.extent,
    required this.nodes,
  });

  @override
  String toString() =>
      'ResolvedSelection(${nodes.length} node/s, '
      'base=${base.fragment.id}:${base.offset}, '
      'extent=${extent.fragment.id}:${extent.offset})';
}

// ─── Funzione principale ──────────────────────────────────────────────

/// Resolves the selection defined by (anchorFragmentId, anchorOffset) →
/// (focusFragmentId, focusOffset) in the [root] tree.
///
/// Returns null if:
/// - anchor == focus (collapsed selection)
/// - one of the fragments is not found in the tree
/// - positions are not on the stop rail
///
/// Usage example:
/// ```dart
/// final sel = resolveSelection(
///   document.content,
///   cursor.anchorId, cursor.anchorOffset,
///   cursor.focusId,  cursor.focusOffset,
/// );
/// if (sel != null) {
///   for (final node in sel.nodes) {
///     print(node);
///   }
/// }
/// ```
ResolvedSelection? resolveSelection(
  Root root,
  String anchorFragmentId,
  int anchorOffset,
  String focusFragmentId,
  int focusOffset,
) {
  // Collapsed selection: nothing to resolve
  if (anchorFragmentId == focusFragmentId && anchorOffset == focusOffset) {
    return null;
  }

  // Build the stop rail to determine the order in the document
  final stops = buildAllStops(root);
  final lines = buildAllLogicalLines(root);

  final anchorIdx = findStopIndex(stops, anchorFragmentId, anchorOffset);
  final focusIdx  = findStopIndex(stops, focusFragmentId,  focusOffset);

  if (anchorIdx < 0 || focusIdx < 0) return null;

  // Normalize: base = first in document, extent = after
  final baseIsAnchor = anchorIdx <= focusIdx;
  final baseIdx   = baseIsAnchor ? anchorIdx : focusIdx;
  final extentIdx = baseIsAnchor ? focusIdx  : anchorIdx;

  // Resolve the Fragments (HorizontalRule extends Fragment so it works directly)
  final anchorFragResolved = findById(root, anchorFragmentId);
  final focusFragResolved  = findById(root, focusFragmentId);
  if (anchorFragResolved is! Fragment || focusFragResolved is! Fragment) return null;

  // Resolve the containers of the two endpoints
  final anchorContainer = findLogicalContainer(root, anchorFragmentId);
  final focusContainer  = findLogicalContainer(root, focusFragmentId);
  if (anchorContainer == null || focusContainer == null) return null;

  final anchorEndpoint = SelectionEndpoint(
    fragment:  anchorFragResolved,
    offset:    anchorOffset,
    container: anchorContainer,
  );
  final focusEndpoint = SelectionEndpoint(
    fragment:  focusFragResolved,
    offset:    focusOffset,
    container: focusContainer,
  );

  final baseEndpoint   = baseIsAnchor ? anchorEndpoint : focusEndpoint;
  final extentEndpoint = baseIsAnchor ? focusEndpoint  : anchorEndpoint;

  // Find the LogicalLines involved
  // A line is involved if it contains at least one stop in the range [baseIdx, extentIdx]
  final selectedNodes = <SelectedNode>[];

  for (final line in lines) {
    // Check if the line has stop in the range
    bool hasStopInRange = false;
    for (final stop in line.stops) {
      final i = findStopIndex(stops, stop.fragmentId, stop.offset);
      if (i >= baseIdx && i <= extentIdx) {
        hasStopInRange = true;
        break;
      }
    }
    if (!hasStopInRange) continue;

    // Determine startFragment/startOffset for this line
    final Fragment startFrag;
    final int startOff;

    final lineContainerId = (line.node as FNode).id;
    final isBaseLine   = lineContainerId == (baseEndpoint.container as FNode).id;
    final isExtentLine = lineContainerId == (extentEndpoint.container as FNode).id;

    if (isBaseLine) {
      startFrag = baseEndpoint.fragment;
      startOff  = baseEndpoint.offset;
    } else {
      // Line completely selected from the start: take the first fragment
      final firstStop = line.stops.first;
      final firstNode = findById(root, firstStop.fragmentId);
      if (firstNode is! Fragment) continue;
      final frag = firstNode;
      startFrag = frag;
      startOff  = 0;
    }

    // Determine endFragment/endOffset for this line
    final Fragment endFrag;
    final int endOff;

    if (isExtentLine) {
      endFrag = extentEndpoint.fragment;
      endOff  = extentEndpoint.offset;
    } else {
      // Line completely selected until the end: take the last fragment
      final lastStop = line.stops.last;
      final lastNode = findById(root, lastStop.fragmentId);
      if (lastNode is! Fragment) continue;
      final frag = lastNode;
      endFrag = frag;
      endOff  = frag.text.length;
    }

    final isFullySelected = !isBaseLine && !isExtentLine;

    selectedNodes.add(SelectedNode(
      container:       line.node,
      startFragment:   startFrag,
      startOffset:     startOff,
      endFragment:     endFrag,
      endOffset:       endOff,
      isFullySelected: isFullySelected,
    ));
  }

  if (selectedNodes.isEmpty) return null;

  return ResolvedSelection(
    anchor: anchorEndpoint,
    focus:  focusEndpoint,
    base:   baseEndpoint,
    extent: extentEndpoint,
    nodes:  selectedNodes,
  );
}