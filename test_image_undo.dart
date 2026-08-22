import 'package:flutter/widgets.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/plugins/plugin_api.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  final image = FluentImage('http://example.com/image.png');
  image.width = 100;
  image.height = 200;
  
  final json = image.toJson();
  print('Image JSON: \${jsonEncode(json)}');
  
  final converter = FNodeJsonConverter();
  try {
    final restored = converter.fromJson(json);
    print('Restored successfully! Type: \${restored.runtimeType}');
  } catch (e) {
    print('Failed to restore: \$e');
  }
}
