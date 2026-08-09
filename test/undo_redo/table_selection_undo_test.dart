import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('undo/redo — multi-node selection spanning a table', () {
    final doc = FluentDocument();
    final para1 = Paragraph(text: 'hello');
    final table = FluentTable(
      rows: [
        FluentRow(
          cells: [
            FluentCell(children: [Paragraph(text: 'cellA')]),
            FluentCell(children: [Paragraph(text: 'cellB')]),
          ],
        ),
      ],
    );
    final para2 = Paragraph(text: 'world');
    doc.content.nodes.clear();
    doc.content.nodes.addAll([para1, table, para2]);
    doc.invalidateNodeIndex();

    // Select from para1's fragment to para2's fragment, then replace with 'X'
    final startFrag = para1.fragments.first as Fragment;
    final endFrag = para2.fragments.first as Fragment;
    doc.cursor.moveTo(startFrag.id, 0);
    doc.cursor.focusTo(endFrag.id, endFrag.text.length);

    doc.saveState(description: 'Replace selection');

    // Simulate replace: clear table cells, merge para1+para2
    (para1.fragments.first as Fragment).text = 'X';
    for (final row in table.rows) {
      for (final cell in row.cells) {
        (cell.children.first as Paragraph).fragments.first as Fragment;
        ((cell.children.first as Paragraph).fragments.first as Fragment).text = '';
      }
    }
    (para2.fragments.first as Fragment).text = '';
    doc.cursor.moveTo(startFrag.id, 1);
    doc.cursor.focusTo(startFrag.id, 1);
    doc.updateContent();

    // After replacement, table cells should be empty
    expect(doc.content.nodes.length, 3);
    expect(doc.content.nodes[1], isA<FluentTable>());

    // Undo should restore original content
    expect(doc.canUndo, isTrue);
    doc.undo();

    expect(doc.content.nodes.length, 3);
    expect(doc.content.nodes[0], isA<Paragraph>());
    expect((doc.content.nodes[0] as Paragraph).text, 'hello');
    expect(doc.content.nodes[1], isA<FluentTable>());
    final restoredTable = doc.content.nodes[1] as FluentTable;
    expect(restoredTable.rows.first.cells.length, 2);
    expect((restoredTable.rows.first.cells[0].children.first as Paragraph).text, 'cellA');
    expect((restoredTable.rows.first.cells[1].children.first as Paragraph).text, 'cellB');
    expect(doc.content.nodes[2], isA<Paragraph>());
    expect((doc.content.nodes[2] as Paragraph).text, 'world');
  });

  test('undo/redo — selection that deletes a paragraph next to a table', () {
    final doc = FluentDocument();
    final para1 = Paragraph(text: 'keep');
    final para2 = Paragraph(text: 'delete');
    final table = FluentTable(
      rows: [
        FluentRow(
          cells: [
            FluentCell(children: [Paragraph(text: 'cellA')]),
          ],
        ),
      ],
    );
    doc.content.nodes.clear();
    doc.content.nodes.addAll([para1, para2, table]);
    doc.invalidateNodeIndex();

    // Select all of para2 and first cell, replace with 'X'
    final startFrag = para2.fragments.first as Fragment;
    final cellPara = table.rows.first.cells.first.children.first as Paragraph;
    final endFrag = cellPara.fragments.first as Fragment;
    doc.cursor.moveTo(startFrag.id, 0);
    doc.cursor.focusTo(endFrag.id, endFrag.text.length);

    doc.saveState(description: 'Replace across para+table');

    // Simulate: para2 gets 'X', cell gets cleared, para2 removed
    (para1.fragments.first as Fragment).text = 'keep';
    (para2.fragments.first as Fragment).text = 'X';
    (endFrag).text = '';
    doc.content.nodes.removeAt(1); // remove para2
    doc.cursor.moveTo(startFrag.id, 1);
    doc.cursor.focusTo(startFrag.id, 1);
    doc.updateContent();

    // After: 2 nodes [para1, table]
    expect(doc.content.nodes.length, 2);

    // Undo should restore 3 nodes
    expect(doc.canUndo, isTrue);
    doc.undo();

    expect(doc.content.nodes.length, 3);
    expect((doc.content.nodes[0] as Paragraph).text, 'keep');
    expect((doc.content.nodes[1] as Paragraph).text, 'delete');
    expect(doc.content.nodes[2], isA<FluentTable>());
    final restoredTable = doc.content.nodes[2] as FluentTable;
    expect((restoredTable.rows.first.cells.first.children.first as Paragraph).text, 'cellA');
  });
}
