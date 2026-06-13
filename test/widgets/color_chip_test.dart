import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/widgets/shared/color_picker_widgets.dart';

void main() {
  group('ColorChip widget', () {
    testWidgets('renders with color', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColorChip(color: Colors.red, label: 'Red', isSelected: false, onTap: () {}),
          ),
        ),
      );
      expect(find.byType(ColorChip), findsOneWidget);
    });

    testWidgets('renders without color', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColorChip(color: null, label: 'None', isSelected: true, onTap: () {}),
          ),
        ),
      );
      expect(find.byType(ColorChip), findsOneWidget);
    });
  });
}
