// Basic smoke test for Shift Planner app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shift_planner/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ShiftPlannerApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
