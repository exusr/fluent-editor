import 'package:flutter/widgets.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/undo_redo/undo_redo_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Create document
  final doc = FluentDocument();
  doc.content.nodes.clear();
  
  // 2. Add some paragraphs
  final p1 = Paragraph(text: 'Section 1');
  final p2 = Paragraph(text: 'Section 2');
  final p3 = Paragraph(text: 'Section 3');
  doc.content.nodes.addAll([p1, p2, p3]);
  doc.invalidateNodeIndex();
  
  print('Initial nodes: ${doc.content.nodes.map((e) => (e as Paragraph).text).join(', ')}');
  
  // 3. Delete section 2 (e.g. by selecting it and replacing with empty)
  doc.saveState(description: 'Delete', forceNewAction: false);
  
  // Select p2
  doc.cursor.anchorId = p2.fragments.first.id;
  doc.cursor.anchorOffset = 0;
  doc.cursor.focusId = p2.fragments.first.id;
  doc.cursor.focusOffset = p2.text.length;
  doc.selectionManager.startSelection(p2.id, doc.cursor.anchorId, doc.cursor.anchorOffset);
  doc.selectionManager.updateFocus(p2.id, doc.cursor.focusId, doc.cursor.focusOffset);
  
  // Delete selection
  executeHandleReplaceSelection('', doc);
  
  print('Nodes after deletion: ${doc.content.nodes.map((e) => (e as Paragraph).text).join(', ')}');
  print('Undo stack size: ${doc.undoRedoManager.undoStackSize}');
  
  // 4. Undo
  doc.undo();
  
  print('Nodes after undo: ${doc.content.nodes.map((e) => (e as Paragraph).text).join(', ')}');
}
