import 'package:flutter/foundation.dart';

/// Represents a point in the selection (node, fragment, offset)
class SelectionPoint {
  final String nodeId;      // ID of the paragraph/list/etc
  final String fragmentId;  // ID of the fragment
  final int offset;         // Offset in the fragment
  
  const SelectionPoint({
    required this.nodeId,
    required this.fragmentId,
    required this.offset,
  });
}

/// Global selection state in the document
class SelectionState {
  final SelectionPoint? anchor;
  final SelectionPoint? focus;
  
  const SelectionState({this.anchor, this.focus});
  
  bool get isCollapsed => 
    anchor == null || 
    focus == null || 
    (anchor!.nodeId == focus!.nodeId && 
     anchor!.fragmentId == focus!.fragmentId && 
     anchor!.offset == focus!.offset);
  
  bool get hasSelection => anchor != null && focus != null && !isCollapsed;
  
  /// Returns true if a node is selected (partially or fully).
  /// [positionIndex] maps nodeId → document-order position (0..n-1). When
  /// provided it is used instead of the broken lexicographic UUID comparison.
  bool isNodeSelected(String nodeId, {Map<String, int>? positionIndex}) {
    if (!hasSelection) return false;
    
    final base = _isAnchorBeforeFocus(positionIndex) ? anchor! : focus!;
    final extent = _isAnchorBeforeFocus(positionIndex) ? focus! : anchor!;
    
    final nodeIsBase = base.nodeId == nodeId;
    final nodeIsExtent = extent.nodeId == nodeId;
    final nodeBetween = _isNodeBetween(nodeId, base.nodeId, extent.nodeId, positionIndex);
    
    return nodeIsBase || nodeIsExtent || nodeBetween;
  }
  
  /// For a given node, returns the selection limits in terms of fragment/offset
  /// Returns: (startFragmentId, startOffset, endFragmentId, endOffset) or null if not selected
  ({String startFrag, int startOff, String endFrag, int endOff})? getSelectionRangeForNode(
    String nodeId, {
    Map<String, int>? positionIndex,
  }) {
    if (!hasSelection) return null;
    if (!isNodeSelected(nodeId, positionIndex: positionIndex)) return null;
    
    final base = _isAnchorBeforeFocus(positionIndex) ? anchor! : focus!;
    final extent = _isAnchorBeforeFocus(positionIndex) ? focus! : anchor!;
    
    final nodeIsBase = base.nodeId == nodeId;
    final nodeIsExtent = extent.nodeId == nodeId;
    
    if (nodeIsBase && nodeIsExtent) {
      // Selection entirely within this node
      return (
        startFrag: base.fragmentId,
        startOff: base.offset,
        endFrag: extent.fragmentId,
        endOff: extent.offset,
      );
    } else if (nodeIsBase) {
      // Selection starts here and continues in other nodes
      // Select from base to the end of the node
      return (
        startFrag: base.fragmentId,
        startOff: base.offset,
        endFrag: '',  // "" = end of node
        endOff: -1,
      );
    } else if (nodeIsExtent) {
      // Selection ends here, started in other nodes
      // Select from the beginning of the node to extent
      return (
        startFrag: '',  // "" = start of node
        startOff: 0,
        endFrag: extent.fragmentId,
        endOff: extent.offset,
      );
    } else {
      // Node completely selected (in the middle)
      return (
        startFrag: '',  // start
        startOff: 0,
        endFrag: '',    // end
        endOff: -1,
      );
    }
  }
  
  /// Determines whether anchor comes before focus in document order.
  /// Uses [positionIndex] (nodeId → linear position) when available,
  /// otherwise falls back to the legacy (and often wrong) UUID comparison.
  bool _isAnchorBeforeFocus([Map<String, int>? positionIndex]) {
    if (anchor == null || focus == null) return true;

    final aPos = positionIndex?[anchor!.nodeId];
    final fPos = positionIndex?[focus!.nodeId];
    if (aPos != null && fPos != null) {
      if (aPos != fPos) return aPos < fPos;
    } else {
      final nodeCompare = anchor!.nodeId.compareTo(focus!.nodeId);
      if (nodeCompare != 0) return nodeCompare < 0;
    }

    final fragCompare = anchor!.fragmentId.compareTo(focus!.fragmentId);
    if (fragCompare != 0) return fragCompare < 0;

    return anchor!.offset <= focus!.offset;
  }

  bool _isNodeBetween(
    String nodeId,
    String startNodeId,
    String endNodeId, [
    Map<String, int>? positionIndex,
  ]) {
    final nPos = positionIndex?[nodeId];
    final sPos = positionIndex?[startNodeId];
    final ePos = positionIndex?[endNodeId];
    if (nPos != null && sPos != null && ePos != null) {
      return nPos > sPos && nPos < ePos;
    }
    return nodeId.compareTo(startNodeId) > 0 && nodeId.compareTo(endNodeId) < 0;
  }
}

/// Manages the global selection in the document
class SelectionManager extends ChangeNotifier {
  SelectionState _state = const SelectionState();

  SelectionState get state => _state;

  bool get hasSelection => _state.hasSelection;
  bool get isCollapsed => _state.isCollapsed;

  bool _suppressNotifications = false;

  /// Cache for getRangeForNode to avoid recomputing the same range across
  /// visible paragraphs during a single selection sync pass.
  final Map<String, ({String startFrag, int startOff, String endFrag, int endOff})?> _rangeCache = {};

  /// Executes [fn] with notifications suppressed, then notifies once.
  void batchUpdate(void Function() fn) {
    _suppressNotifications = true;
    fn();
    _suppressNotifications = false;
    notifyListeners();
  }

  /// Starts a selection (tap or start of drag)
  void startSelection(String nodeId, String fragmentId, int offset) {
    final point = SelectionPoint(
      nodeId: nodeId,
      fragmentId: fragmentId,
      offset: offset,
    );
    _state = SelectionState(anchor: point, focus: point);
    _rangeCache.clear();
    if (!_suppressNotifications) notifyListeners();
  }

  /// Updates the focus during drag
  void updateFocus(String nodeId, String fragmentId, int offset) {
    if (_state.anchor == null) return;

    _state = SelectionState(
      anchor: _state.anchor,
      focus: SelectionPoint(
        nodeId: nodeId,
        fragmentId: fragmentId,
        offset: offset,
      ),
    );
    _rangeCache.clear();
    if (!_suppressNotifications) notifyListeners();
  }

  /// Collapses the selection (removes the highlight)
  void collapse() {
    if (_state.anchor != null) {
      _state = SelectionState(
        anchor: _state.anchor,
        focus: _state.anchor,
      );
      _rangeCache.clear();
      if (!_suppressNotifications) notifyListeners();
    }
  }

  /// Clears the selection
  void clear() {
    _state = const SelectionState();
    _rangeCache.clear();
    if (!_suppressNotifications) notifyListeners();
  }
  
  /// Document-order position index (nodeId → 0..n-1) injected by the
  /// owning FluentDocument. When set, selection comparisons use real document
  /// order instead of the broken lexicographic UUID comparison.
  Map<String, int>? _positionIndex;
  void setPositionIndex(Map<String, int> index) => _positionIndex = index;

  /// Returns the selection range for a given node.
  /// Uses an internal cache so repeated lookups during a single sync pass
  /// (e.g. one per visible paragraph) are O(1) instead of O(visible).
  ({String startFrag, int startOff, String endFrag, int endOff})? getRangeForNode(String nodeId) {
    if (_rangeCache.containsKey(nodeId)) return _rangeCache[nodeId];
    final range = _state.getSelectionRangeForNode(nodeId, positionIndex: _positionIndex);
    _rangeCache[nodeId] = range;
    return range;
  }

  /// True if the node is selected (partially or fully)
  bool isNodeSelected(String nodeId) {
    return _state.isNodeSelected(nodeId, positionIndex: _positionIndex);
  }
}
