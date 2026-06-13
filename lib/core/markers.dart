import 'package:fluent_editor/core/constants.dart';
import 'package:fluent_editor/factories.dart';

//apply markers to list
void applyListMarkers(List<ListItem> items, {bool nested = false}) {
  for (final item in items) {
    for (final frag in item.fragments.whereType<Fragment>()) {
      frag.text = frag.text.replaceAll(Whitespaces.zws, '');
    }
  }

  for (int i = 0; i < items.length; i++) {
    final frags = items[i].fragments.whereType<Fragment>().toList();
    if (frags.isEmpty) continue;

    if (nested) {
      frags.first.text = '${Whitespaces.zws}${frags.first.text}';
      frags.last.text = '${frags.last.text}${Whitespaces.zws}';
    } else if (items.length > 1) {
      if (i > 0) {
        frags.first.text = '${Whitespaces.zws}${frags.first.text}';
      }
      if (i < items.length - 1) {
        frags.last.text = '${frags.last.text}${Whitespaces.zws}';
      }
    }
  }

  for (final item in items) {
    for (final child in item.getChildren()) {
      if (child is FluentList) {
        applyListMarkers(child.items, nested: true);
      } else if (child is InlineContainerNode) {
        _applyListMarkersInNode(child as InlineContainerNode);
      }
    }
  }
}

//apply markers to table
void applyTableMarkers(List<FluentRow> rows) {
  // remove all existing markers
  for (final row in rows) { 
    for (final cell in row.cells) {
      for (final frag in cell.fragments.whereType<Fragment>()) {
        frag.text = frag.text.replaceAll(Whitespaces.zws, '');
      }
    }
  }

  final allCells = rows.expand((r) => r.cells).toList();
  if (allCells.length <= 1) return;

  for (int i = 0; i < allCells.length; i++) {
    final frags = allCells[i].fragments.whereType<Fragment>().toList();
    if (frags.isEmpty) continue;

    if (i == 0) {
      frags.last.text = '${frags.last.text}${Whitespaces.zws}';
    } else if (i == allCells.length - 1) {
      frags.first.text = '${Whitespaces.zws}${frags.first.text}';
    } else {
      frags.first.text = '${Whitespaces.zws}${frags.first.text}';
      frags.last.text = '${frags.last.text}${Whitespaces.zws}';
    }
  }
}

void _applyListMarkersInNode(InlineContainerNode node) {
  for (final child in node.getChildren()) {
    if (child is FluentList) {
      applyListMarkers(child.items, nested: true);
    } else if (child is InlineContainerNode) {
      _applyListMarkersInNode(child as InlineContainerNode);
    }
  }
}