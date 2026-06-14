// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('Virtualization test app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TestApp());

    // Verify that the app title is displayed
    expect(find.text('FluentEditor Virtualization Test'), findsOneWidget);
    
    // Verify that the toggle button is present
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    
    // Verify that the initial mode is "Small Document Test"
    expect(find.text('Small Document Test'), findsOneWidget);
    
    // Verify that the status indicator is present
    expect(find.textContaining('Normal mode with'), findsOneWidget);
  });
}
