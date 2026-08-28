import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_planner/models/day_entry.dart';
import 'package:shift_planner/services/shift_matrix_pdf_service.dart';

void main() {
  test('4-line remarks pdf generation does not throw and produces bytes', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final rows = [
      ShiftMatrixPdfRow(
        name: 'てすと',
        entriesByDate: {
          '2026-10-01': DayEntry(date: '2026-10-01', dayOfWeek: '木', isHoliday: false, code: 'A', hours: '4.25'),
        },
        totalHours: 4.25,
        filledDaysCount: 1,
      ),
    ];
    final remarks = '1行目：山田さん 10/3 休み対応についての備考です。\n'
        '2行目：佐藤さん 10/7 時間変更 【9:00〜15:30】に変更してください。\n'
        '3行目：鈴木さん 10/12 有給申請あり、確認してください。\n'
        '4行目：これは4行目のテスト文章です。この行が見えるかどうか確認します。';

    final bytes = await ShiftMatrixPdfService.exportAndShareForTest(
      year: 2026,
      month: 10,
      daysInMonth: 31,
      department: 'テスト部署',
      rows: rows,
      remarks: remarks,
    );
    File('/tmp/test_remarks_4lines.pdf').writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('PDF bytes length: ${bytes.length}');
    expect(bytes.length, greaterThan(1000));
  });
}
