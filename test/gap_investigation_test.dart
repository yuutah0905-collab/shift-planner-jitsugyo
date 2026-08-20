import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_planner/models/day_entry.dart';
import 'package:shift_planner/models/employee.dart';
import 'package:shift_planner/models/shift_submission.dart';
import 'package:shift_planner/screens/monthly_shift_matrix_screen.dart';

void main() {
  testWidgets('inspect header name cell geometry at PC-like 1024x554', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 554));

    final days = List.generate(31, (i) {
      final day = i + 1;
      return DayEntry(
        date: '2025-10-${day.toString().padLeft(2, '0')}',
        dayOfWeek: '',
        isHoliday: false,
        hours: '4.25',
        code: 'J',
      );
    });
    final submission = ShiftSubmission(
      name: 'テスト1',
      department: '出庫',
      targetMonth: '2025-10',
      monthMemo: '',
      days: days,
      totalHours: 32.5,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MonthlyShiftMatrixScreen(
          submissions: [submission],
          targetMonth: '2025-10',
          availableDepartments: const ['出庫'],
          initialDepartment: '出庫',
          employees: [Employee(name: 'テスト1', department: '出庫', pin: '1234')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Find the '氏名' text and get its containing Container's rect by
    // walking up to the nearest ancestor Container render object.
    final nameTextFinder = find.text('氏名');
    final nameTextEl = nameTextFinder.evaluate().first;

    // Find nearest ancestor RenderBox that is the header Container's box
    // decoration painter - walk up render tree.
    RenderObject? ro = nameTextEl.renderObject;
    // ignore: avoid_print
    print('--- ancestor chain from 氏名 Text render object ---');
    var depth = 0;
    ro?.visitChildren((c) {}); // no-op just to ensure it's RenderBox capable
    // Walk manually via Element ancestors instead (more reliable than
    // RenderObject.parent casting).
    nameTextEl.visitAncestorElements((ancestor) {
      final w = ancestor.widget;
      if (ancestor.renderObject is RenderBox) {
        final box = ancestor.renderObject as RenderBox;
        // ignore: avoid_print
        print(
          '[$depth] ${w.runtimeType} size=${box.size} globalOffset=${box.localToGlobal(Offset.zero)}',
        );
      } else {
        // ignore: avoid_print
        print('[$depth] ${w.runtimeType} (no RenderBox)');
      }
      depth++;
      return depth < 15;
    });
  });
}
