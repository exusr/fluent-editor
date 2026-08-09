import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('undo/redo with table — typing in a cell', () {
    final doc = FluentDocument();
    final table = FluentTable(
      rows: [
        FluentRow(
          cells: [
            FluentCell(children: [Paragraph(text: '')]),
          ],
        ),
      ],
    );
    doc.content.nodes.clear();
    doc.content.nodes.add(table);
    doc.invalidateNodeIndex();
    final para = table.rows.first.cells.first.children.first as Paragraph;
    final frag = para.fragments.first as Fragment;
    doc.cursor.moveTo(frag.id, 0);

    // Type a character
    doc.saveState(description: 'Type character: a');
    frag.text = 'a';
    doc.cursor.focusOffset = 1;
    doc.cursor.anchorOffset = 1;
    doc.updateContent();

    expect(doc.canUndo, isTrue);

    // Undo
    final result = doc.undo();
    expect(result, isTrue);

    // The table should still be there with empty cell
    expect(doc.content.nodes.length, 1);
    expect(doc.content.nodes.first, isA<FluentTable>());
    final restoredTable = doc.content.nodes.first as FluentTable;
    expect(restoredTable.rows.length, 1);
    expect(restoredTable.rows.first.cells.length, 1);
    final restoredPara = restoredTable.rows.first.cells.first.children.first as Paragraph;
    expect(restoredPara.text, '');
  });

  test('undo/redo with table — adding a row', () {
    final doc = FluentDocument();
    final table = FluentTable(
      rows: [
        FluentRow(
          cells: [
            FluentCell(children: [Paragraph(text: 'row1')]),
          ],
        ),
      ],
    );
    doc.content.nodes.clear();
    doc.content.nodes.add(table);
    doc.invalidateNodeIndex();

    // Add a second row
    doc.saveState(description: 'Add row');
    table.rows.add(FluentRow(
      cells: [
        FluentCell(children: [Paragraph(text: 'row2')]),
      ],
    ));
    doc.updateContent();

    expect(doc.content.nodes.first, isA<FluentTable>());
    expect((doc.content.nodes.first as FluentTable).rows.length, 2);

    // Undo — should restore 1-row table
    expect(doc.canUndo, isTrue);
    doc.undo();

    expect(doc.content.nodes.first, isA<FluentTable>());
    final restored = doc.content.nodes.first as FluentTable;
    expect(restored.rows.length, 1);
    expect((restored.rows.first.cells.first.children.first as Paragraph).text, 'row1');
  });
}
