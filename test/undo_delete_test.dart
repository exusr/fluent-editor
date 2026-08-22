import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/undo_redo/undo_redo_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('undo after deleting section', () {
    final doc = FluentDocument();
    doc.content.nodes.clear();
    
    final p1 = Paragraph(text: 'Section 1');
    final p2 = Paragraph(text: 'Section 2');
    final p3 = Paragraph(text: 'Section 3');
    doc.content.nodes.addAll([p1, p2, p3]);
    doc.invalidateNodeIndex();
    
    print('Initial: ${doc.content.nodes.map((e) => (e as Paragraph).text).join(', ')}');
    
    doc.saveState(description: 'Delete', forceNewAction: false);
    
    doc.cursor.anchorId = p2.fragments.first.id;
    doc.cursor.anchorOffset = 0;
    doc.cursor.focusId = p2.fragments.first.id;
    doc.cursor.focusOffset = p2.text.length;
    doc.selectionManager.startSelection(p2.id, doc.cursor.anchorId, doc.cursor.anchorOffset);
    doc.selectionManager.updateFocus(p2.id, doc.cursor.focusId, doc.cursor.focusOffset);
    
    executeHandleReplaceSelection('', doc);
    
    print('After deletion: ${doc.content.nodes.map((e) => (e as Paragraph).text).join(', ')}');
    print('Undo stack: ${doc.undoRedoManager.undoStackSize}');
    
    doc.undo();
    
    print('After undo: ${doc.content.nodes.map((e) => (e as Paragraph).text).join(', ')}');
    expect(doc.content.nodes.length, 3);
  });

  test('undo after 5-node section deletion with intermediate nodes', () {
    final doc = FluentDocument();
    doc.content.nodes.clear();
    
    final p1 = Paragraph(text: 'Section 1');
    final p2 = Paragraph(text: 'Section 2');
    final p3 = Paragraph(text: 'Section 3'); // INTERMEDIATE NODE
    final p4 = Paragraph(text: 'Section 4');
    final p5 = Paragraph(text: 'Section 5');
    doc.content.nodes.addAll([p1, p2, p3, p4, p5]);
    doc.invalidateNodeIndex();
    
    print('Initial 5 nodes: ${doc.content.nodes.map((e) => (e as Paragraph).text).join(', ')}');
    
    // FIRST DELETION (p2 to p4)
    doc.saveState(description: 'Delete 1', forceNewAction: false);
    
    doc.cursor.anchorId = p2.fragments.first.id;
    doc.cursor.anchorOffset = 0;
    doc.cursor.focusId = p4.fragments.first.id;
    doc.cursor.focusOffset = p4.text.length;
    doc.selectionManager.startSelection(p2.id, doc.cursor.anchorId, doc.cursor.anchorOffset);
    doc.selectionManager.updateFocus(p4.id, doc.cursor.focusId, doc.cursor.focusOffset);
    
    executeHandleReplaceSelection('', doc);
    
    print('1st deletion nodes (${doc.content.nodes.length}): ${doc.content.nodes.map((e) => (e as Paragraph).text).join(', ')}');
    expect(doc.content.nodes.length, 3);

    // FIRST UNDO
    doc.undo();
    print('1st undo nodes (${doc.content.nodes.length}): ${doc.content.nodes.map((e) => (e as Paragraph).text).join(', ')}');
    expect(doc.content.nodes.length, 5);

    // SECOND DELETION (p2 to p4)
    final rP2 = doc.content.nodes[1] as Paragraph;
    final rP4 = doc.content.nodes[3] as Paragraph;
    
    doc.saveState(description: 'Delete 2', forceNewAction: true);
    
    doc.cursor.anchorId = rP2.fragments.first.id;
    doc.cursor.anchorOffset = 0;
    doc.cursor.focusId = rP4.fragments.first.id;
    doc.cursor.focusOffset = rP4.text.length;
    doc.selectionManager.startSelection(rP2.id, doc.cursor.anchorId, doc.cursor.anchorOffset);
    doc.selectionManager.updateFocus(rP4.id, doc.cursor.focusId, doc.cursor.focusOffset);
    
    executeHandleReplaceSelection('', doc);
    
    print('2nd deletion nodes (${doc.content.nodes.length}): ${doc.content.nodes.map((e) => (e as Paragraph).text).join(', ')}');
    expect(doc.content.nodes.length, 3);
  });

  test('undo after deleting list items twice', () {
    final doc = FluentDocument();
    doc.content.nodes.clear();

    final item1 = ListItem(bulletType: 'bullet', indexList: const [1], children: [Paragraph(text: 'Item 1')]);
    final item2 = ListItem(bulletType: 'bullet', indexList: const [2], children: [Paragraph(text: 'Item 2')]);
    final item3 = ListItem(bulletType: 'bullet', indexList: const [3], children: [Paragraph(text: 'Item 3')]);
    final list = FluentList(listType: 'bullet')..items = [item1, item2, item3];
    doc.content.nodes.add(list);
    doc.invalidateNodeIndex();

    expect(list.items.length, 3);

    // 1st deletion (select item 1 to item 3, deleting item 2 intermediate)
    doc.saveState(description: 'Delete Item', forceNewAction: true);
    doc.cursor.anchorId = item1.fragments.first.id;
    doc.cursor.anchorOffset = 0;
    doc.cursor.focusId = item3.fragments.first.id;
    doc.cursor.focusOffset = item3.text.length;
    doc.selectionManager.startSelection(item1.id, doc.cursor.anchorId, doc.cursor.anchorOffset);
    doc.selectionManager.updateFocus(item3.id, doc.cursor.focusId, doc.cursor.focusOffset);

    executeHandleReplaceSelection('', doc);
    final listAfter1st = doc.content.nodes.first as FluentList;
    print('After 1st list deletion items (${listAfter1st.items.length}): ${listAfter1st.items.map((e) => (e.children.first as Paragraph).text).join(' | ')}');
    expect(listAfter1st.items.length, 2);

    // 1st undo
    doc.undo();
    final listAfterUndo = doc.content.nodes.first as FluentList;
    print('After 1st list undo items: ${listAfterUndo.items.length}');
    expect(listAfterUndo.items.length, 3);

    // 2nd deletion (select item 1 to item 3 again)
    final rItem1 = listAfterUndo.items[0];
    final rItem3 = listAfterUndo.items[2];
    doc.saveState(description: 'Delete Item 2', forceNewAction: true);
    doc.cursor.anchorId = rItem1.fragments.first.id;
    doc.cursor.anchorOffset = 0;
    doc.cursor.focusId = rItem3.fragments.first.id;
    doc.cursor.focusOffset = rItem3.text.length;
    doc.selectionManager.startSelection(rItem1.id, doc.cursor.anchorId, doc.cursor.anchorOffset);
    doc.selectionManager.updateFocus(rItem3.id, doc.cursor.focusId, doc.cursor.focusOffset);

    executeHandleReplaceSelection('', doc);
    final listAfter2nd = doc.content.nodes.first as FluentList;
    print('After 2nd list deletion items (${listAfter2nd.items.length}): ${listAfter2nd.items.map((e) => (e.children.first as Paragraph).text).join(' | ')}');
    expect(listAfter2nd.items.length, 2);
  });
}
