import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_planner/models/day_entry.dart';
import 'package:shift_planner/services/shift_matrix_pdf_service.dart';

void main() {
  test('long remarks + many rows still fits on one page', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final rows = List.generate(15, (i) => ShiftMatrixPdfRow(
      name: 'スタッフ$i',
      entriesByDate: {
        '2026-10-01': DayEntry(date: '2026-10-01', dayOfWeek: '木', isHoliday: false, code: 'A', hours: '4.25'),
      },
      totalHours: 4.25,
      filledDaysCount: 1,
    ));
    final remarks = List.generate(8, (i) => '${i + 1}行目：これは長めのテスト備考文章です。休みの調整や時間変更などの連絡事項をここに手打ちで入力します。').join('\n');

    final bytes = await ShiftMatrixPdfService.exportAndShareForTest(
      year: 2026,
      month: 10,
      daysInMonth: 31,
      department: 'テスト部署',
      rows: rows,
      remarks: remarks,
    );
    File('/tmp/test_remarks_long.pdf').writeAsBytesSync(bytes);
    print('PDF bytes length: ${bytes.length}');
  });
}
