import 'package:fluent_editor/factories.dart';
void main() {
  final list = FluentList(listType: 'bullet');
  final item = ListItem(bulletType: 'bullet', indexList: [], children: []);
  item.id = 'target';
  list.items.add(item);
  final root = Root(nodes: [list]);
  
  FNode? nodeById(String id) {
    if (id.isEmpty) return null;
    FNode? search(FNode root) {
      if (root.id == id) return root;
      if (root is InlineContainerNode) {
        for (final child in root.getChildren()) {
          final found = search(child);
          if (found != null) return found;
        }
      } else if (root is FluentList) {
        for (final child in root.items) {
          final found = search(child);
          if (found != null) return found;
        }
      }
      return null;
    }
    return search(root);
  }
  
  print(nodeById('target') != null ? 'FOUND' : 'NOT FOUND');
}
