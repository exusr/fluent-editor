import 'package:flutter/widgets.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Create a list item with a nested list
  final p1 = Paragraph(text: 'Item A');
  final p2 = Paragraph(text: 'Item B');
  final nestedList = FluentList(listType: 'bullet')..items = [
    ListItem(bulletType: 'bullet', indexList: [0, 0], children: [Paragraph(text: 'Nested 1')]),
    ListItem(bulletType: 'bullet', indexList: [0, 1], children: [Paragraph(text: 'Nested 2')])
  ];
  
  final listItem = ListItem(
    bulletType: 'bullet',
    indexList: [0],
    children: [p1, nestedList, p2]
  );
  
  print('Original children count: ${listItem.children.length}');
  print('Original children types: ${listItem.children.map((c) => c.runtimeType).join(', ')}');
  
  final json = listItem.toJson();
  print('\nJSON: ${jsonEncode(json)}');
  
  final restored = ListItem.fromJson(json);
  print('\nRestored children count: ${restored.children.length}');
  print('Restored children types: ${restored.children.map((c) => c.runtimeType).join(', ')}');
  
  if (restored.children.length > 0 && restored.children[0] is Paragraph) {
    final p = restored.children[0] as Paragraph;
    print('Restored first child text: ${p.text}');
  }
}
