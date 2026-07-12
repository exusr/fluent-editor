import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/selection_manager.dart';

void main() {
  group('SelectionState', () {
    test('isCollapsed when anchor equals focus', () {
      const state = SelectionState();
      expect(state.isCollapsed, isTrue);
      expect(state.hasSelection, isFalse);
    });

    test('hasSelection when anchor and focus differ', () {
      const anchor = SelectionPoint(nodeId: 'n1', fragmentId: 'f1', offset: 0);
      const focus = SelectionPoint(nodeId: 'n1', fragmentId: 'f1', offset: 5);
      const state = SelectionState(anchor: anchor, focus: focus);
      expect(state.isCollapsed, isFalse);
      expect(state.hasSelection, isTrue);
    });

    test('isCollapsed when null anchor or focus', () {
      const state1 = SelectionState(anchor: null, focus: null);
      expect(state1.isCollapsed, isTrue);
      const anchor = SelectionPoint(nodeId: 'n1', fragmentId: 'f1', offset: 0);
      const state2 = SelectionState(anchor: anchor, focus: null);
      expect(state2.isCollapsed, isTrue);
    });

    test('isNodeSelected for base and extent nodes', () {
      const anchor = SelectionPoint(nodeId: 'n1', fragmentId: 'f1', offset: 2);
      const focus = SelectionPoint(nodeId: 'n3', fragmentId: 'f3', offset: 4);
      const state = SelectionState(anchor: anchor, focus: focus);
      expect(state.isNodeSelected('n1'), isTrue);
      expect(state.isNodeSelected('n3'), isTrue);
    });

    test('getSelectionRangeForNode within same node', () {
      const anchor = SelectionPoint(nodeId: 'n1', fragmentId: 'f1', offset: 2);
      const focus = SelectionPoint(nodeId: 'n1', fragmentId: 'f1', offset: 5);
      const state = SelectionState(anchor: anchor, focus: focus);
      final range = state.getSelectionRangeForNode('n1');
      expect(range, isNotNull);
      expect(range!.startFrag, 'f1');
      expect(range.startOff, 2);
      expect(range.endFrag, 'f1');
      expect(range.endOff, 5);
    });

    test('getSelectionRangeForNode when node is base', () {
      const anchor = SelectionPoint(nodeId: 'n1', fragmentId: 'f1', offset: 2);
      const focus = SelectionPoint(nodeId: 'n2', fragmentId: 'f2', offset: 4);
      const state = SelectionState(anchor: anchor, focus: focus);
      final range = state.getSelectionRangeForNode('n1');
      expect(range, isNotNull);
      expect(range!.startFrag, 'f1');
      expect(range.startOff, 2);
      expect(range.endFrag, '');
      expect(range.endOff, -1);
    });

    test('getSelectionRangeForNode when node is extent', () {
      const anchor = SelectionPoint(nodeId: 'n1', fragmentId: 'f1', offset: 2);
      const focus = SelectionPoint(nodeId: 'n2', fragmentId: 'f2', offset: 4);
      const state = SelectionState(anchor: anchor, focus: focus);
      final range = state.getSelectionRangeForNode('n2');
      expect(range, isNotNull);
      expect(range!.startFrag, '');
      expect(range.startOff, 0);
      expect(range.endFrag, 'f2');
      expect(range.endOff, 4);
    });

    test('getSelectionRangeForNode for fully selected middle node', () {
      const anchor = SelectionPoint(nodeId: 'n1', fragmentId: 'f1', offset: 2);
      const focus = SelectionPoint(nodeId: 'n3', fragmentId: 'f3', offset: 4);
      const state = SelectionState(anchor: anchor, focus: focus);
      final range = state.getSelectionRangeForNode('n2');
      expect(range, isNotNull);
      expect(range!.startFrag, '');
      expect(range.startOff, 0);
      expect(range.endFrag, '');
      expect(range.endOff, -1);
    });
  });

  group('SelectionManager', () {
    late SelectionManager manager;

    setUp(() {
      manager = SelectionManager();
    });

    test('initial state is empty', () {
      expect(manager.hasSelection, isFalse);
      expect(manager.isCollapsed, isTrue);
    });

    test('startSelection sets anchor and focus', () {
      manager.startSelection('n1', 'f1', 3);
      expect(manager.hasSelection, isFalse); // collapsed, same point
      expect(manager.isCollapsed, isTrue);
      expect(manager.state.anchor!.nodeId, 'n1');
      expect(manager.state.anchor!.fragmentId, 'f1');
      expect(manager.state.anchor!.offset, 3);
    });

    test('updateFocus creates non-collapsed selection', () {
      manager.startSelection('n1', 'f1', 0);
      manager.updateFocus('n1', 'f1', 5);
      expect(manager.hasSelection, isTrue);
      expect(manager.isCollapsed, isFalse);
      expect(manager.state.focus!.offset, 5);
    });

    test('collapse resets focus to anchor', () {
      manager.startSelection('n1', 'f1', 0);
      manager.updateFocus('n1', 'f1', 5);
      manager.collapse();
      expect(manager.isCollapsed, isTrue);
      expect(manager.state.focus!.offset, 0);
    });

    test('clear removes selection', () {
      manager.startSelection('n1', 'f1', 0);
      manager.clear();
      expect(manager.state.anchor, isNull);
      expect(manager.hasSelection, isFalse);
    });

    test('isNodeSelected delegates to state', () {
      manager.startSelection('n1', 'f1', 0);
      manager.updateFocus('n2', 'f2', 5);
      expect(manager.isNodeSelected('n1'), isTrue);
      expect(manager.isNodeSelected('n2'), isTrue);
      expect(manager.isNodeSelected('n3'), isFalse);
    });

    test('getRangeForNode delegates to state', () {
      manager.startSelection('n1', 'f1', 2);
      manager.updateFocus('n1', 'f1', 5);
      final range = manager.getRangeForNode('n1');
      expect(range, isNotNull);
      expect(range!.startFrag, 'f1');
      expect(range.startOff, 2);
    });
  });
}
