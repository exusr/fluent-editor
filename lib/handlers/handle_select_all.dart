import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_formats.dart';

bool handleSelectAll(FluentDocument document) {
  final root = document.content;
  final cursor = document.cursor;
  
  if (root.nodes.isEmpty) return false;
  
  final stops = document.caretStops;
  if (stops.isEmpty) return false;

  final firstStop = stops.first;
  final lastStop = stops.last;

  cursor.moveTo(firstStop.fragmentId, firstStop.offset);
  cursor.focusTo(lastStop.fragmentId, lastStop.offset);

  syncSelectionManager(document);

  document.cursorOnlyUpdate();
  return true;
}