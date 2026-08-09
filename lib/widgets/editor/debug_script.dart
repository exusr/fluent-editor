import 'package:fluent_editor/fluent_document.dart';
void debugNode(FluentDocument doc, String id) {
  final node = doc.nodeById(id);
  print("Found node: \${node?.runtimeType}");
}
