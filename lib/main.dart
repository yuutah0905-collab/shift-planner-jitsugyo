import 'package:flutter/material.dart';
import 'package:shift_planner/models/day_entry.dart';
import 'package:shift_planner/models/employee.dart';
import 'package:shift_planner/models/shift_submission.dart';
import 'package:shift_planner/screens/monthly_shift_matrix_screen.dart';

void main() {
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    final days = List.generate(31, (i) {
      final day = i + 1;
      final date = '2025-10-${day.toString().padLeft(2, '0')}';
      String code = '';
      String hours = '';
      if (day == 1) {
        code = 'J';
        hours = '4.25';
      }
      if (day == 2) {
        code = 'J';
        hours = '4.25';
      }
      if (day == 7) {
        code = '有';
        hours = '4.25';
      }
      if (day == 8) {
        code = 'J';
        hours = '4.25';
      }
      if (day == 9) {
        code = 'J';
        hours = '4.25';
      }
      if (day == 12) {
        code = 'K';
        hours = '4.50';
      }
      if (day == 16) {
        code = 'J';
        hours = '4.25';
      }
      if (day == 22) {
        code = 'I';
        hours = '4.00';
      }
      if (day == 27) {
        code = 'D';
        hours = '2.75';
      }
      return DayEntry(
        date: date,
        dayOfWeek: '',
        isHoliday: false,
        hours: hours,
        code: code,
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

    return MaterialApp(
      home: MonthlyShiftMatrixScreen(
        submissions: [submission],
        targetMonth: '2025-10',
        availableDepartments: const ['出庫', '入庫', '小分け', '梱包', 'その他'],
        initialDepartment: '出庫',
        employees: [Employee(name: 'テスト1', department: '出庫', pin: '1234')],
      ),
    );
  }
}
