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
  
  /// Returns true if a node is selected (partially or fully)
  bool isNodeSelected(String nodeId) {
    if (!hasSelection) return false;
    
    // Determine the order (base is before, extent is after)
    final base = _isAnchorBeforeFocus() ? anchor! : focus!;
    final extent = _isAnchorBeforeFocus() ? focus! : anchor!;
    
    // The node is selected if:
    // - is between base and extent, OR
    // - is the base node (with selection continuing), OR  
    // - is the extent node (with selection starting before)
    
    // For simplicity, assume nodes are ordered in the document
    // and use only the ID for comparison (assuming lexicographic order = document order)
    // In reality we should use the position in the document
    
    final nodeIsBase = base.nodeId == nodeId;
    final nodeIsExtent = extent.nodeId == nodeId;
    final nodeBetween = _isNodeBetween(nodeId, base.nodeId, extent.nodeId);
    
    return nodeIsBase || nodeIsExtent || nodeBetween;
  }
  
  /// For a given node, returns the selection limits in terms of fragment/offset
  /// Returns: (startFragmentId, startOffset, endFragmentId, endOffset) or null if not selected
  ({String startFrag, int startOff, String endFrag, int endOff})? getSelectionRangeForNode(String nodeId) {
    if (!hasSelection) return null;
    if (!isNodeSelected(nodeId)) return null;
    
    final base = _isAnchorBeforeFocus() ? anchor! : focus!;
    final extent = _isAnchorBeforeFocus() ? focus! : anchor!;
    
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
  
  bool _isAnchorBeforeFocus() {
    if (anchor == null || focus == null) return true;
    // Simple comparison for ID - in production use position in the document
    final nodeCompare = anchor!.nodeId.compareTo(focus!.nodeId);
    if (nodeCompare != 0) return nodeCompare < 0;
    
    final fragCompare = anchor!.fragmentId.compareTo(focus!.fragmentId);
    if (fragCompare != 0) return fragCompare < 0;
    
    return anchor!.offset <= focus!.offset;
  }
  
  bool _isNodeBetween(String nodeId, String startNodeId, String endNodeId) {
    // Simple lexicographic comparison - in production use index in the document
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
    if (!_suppressNotifications) notifyListeners();
  }

  /// Collapses the selection (removes the highlight)
  void collapse() {
    if (_state.anchor != null) {
      _state = SelectionState(
        anchor: _state.anchor,
        focus: _state.anchor,
      );
      if (!_suppressNotifications) notifyListeners();
    }
  }

  /// Clears the selection
  void clear() {
    _state = const SelectionState();
    if (!_suppressNotifications) notifyListeners();
  }
  
  /// Returns the selection range for a given node
  ({String startFrag, int startOff, String endFrag, int endOff})? getRangeForNode(String nodeId) {
    return _state.getSelectionRangeForNode(nodeId);
  }
  
  /// True if the node is selected (partially or fully)
  bool isNodeSelected(String nodeId) {
    return _state.isNodeSelected(nodeId);
  }
}
