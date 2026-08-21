import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/day_entry.dart';
import '../models/shift_code.dart';

/// One row of the monthly shift matrix, in the exact shape needed for PDF
/// rendering. Mirrors `_PersonRow` in monthly_shift_matrix_screen.dart but
/// is a small, public, standalone type so the screen can hand its data
/// across to this service without exposing its private state class.
class ShiftMatrixPdfRow {
  final String name;
  final Map<String, DayEntry> entriesByDate;
  final double totalHours;
  final int filledDaysCount;

  ShiftMatrixPdfRow({
    required this.name,
    required this.entriesByDate,
    required this.totalHours,
    required this.filledDaysCount,
  });
}

/// Renders the on-screen monthly shift matrix (name x date table, with a
/// per-day "合計" footer row) as a single A4-landscape PDF page, matching
/// the "このまま1ページを横で" (as-is, one landscape page) request - the
/// whole month + every staff row always fits on exactly one page, by
/// computing row height / font size to exactly fill the printable area
/// (the same "no fixed cap, always fill available space" approach used to
/// fix the on-screen gap bug), rather than truncating data or letting it
/// overflow onto a second page.
class ShiftMatrixPdfService {
  static const List<String> _dowJp = ['日', '月', '火', '水', '木', '金', '土'];

  // Brand colors, mirrored from AppColors in theme/app_theme.dart (the pdf
  // package uses its own PdfColor type, so these can't be shared directly).
  static final _primaryDeep = PdfColor.fromInt(0xFFC4275F);
  static final _line = PdfColor.fromInt(0xFFD9D5D6);
  static final _weekendBg = PdfColor.fromInt(0xFFF7F5F5);
  static final _holidayBg = PdfColor.fromInt(0xFFF0EEEE);
  static final _paidLeave = PdfColor.fromInt(0xFF3FA9D6);
  static final _surface = PdfColor.fromInt(0xFFFFFFFF);
  static final _background = PdfColor.fromInt(0xFFFAFAFA);

  // Header backgrounds for Sunday / Saturday day-number cells. These MUST
  // be solid, dark enough colors (not near-transparent white) so the white
  // day-number text stays readable even on a monochrome (grayscale)
  // printer, where hue differences disappear and only lightness matters.
  // Previously these cells used a near-transparent white background with
  // white text, which was invisible in both color and monochrome print.
  static final _sundayHeaderBg = PdfColor.fromInt(0xFF9A2D42); // dark red
  static final _saturdayHeaderBg = PdfColor.fromInt(0xFF1F4E79); // dark blue

  /// Opens the platform print/preview sheet (Web: browser print dialog with
  /// a "Save as PDF" destination; Android: native print/share sheet) so the
  /// user gets a visual preview before saving or printing. This is the
  /// primary, recommended entry point.
  static Future<void> previewAndPrint({
    required int year,
    required int month,
    required int daysInMonth,
    required String department,
    required List<ShiftMatrixPdfRow> rows,
  }) async {
    await Printing.layoutPdf(
      name: _fileBaseName(year, month, department),
      onLayout: (format) => _buildPdfBytes(
        year: year,
        month: month,
        daysInMonth: daysInMonth,
        department: department,
        rows: rows,
      ),
    );
  }

  /// Directly shares/downloads the generated PDF bytes without an
  /// intermediate print-preview step (kept as a lower-level building block;
  /// [previewAndPrint] is what the UI calls).
  static Future<void> exportAndShare({
    required int year,
    required int month,
    required int daysInMonth,
    required String department,
    required List<ShiftMatrixPdfRow> rows,
  }) async {
    final bytes = await _buildPdfBytes(
      year: year,
      month: month,
      daysInMonth: daysInMonth,
      department: department,
      rows: rows,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${_fileBaseName(year, month, department)}.pdf',
    );
  }

  // NOTE: This name is passed as the `name:` argument to
  // `Printing.layoutPdf()` / used as the `filename:` for `Printing.sharePdf()`.
  // On Flutter Web, the `printing` package / underlying PDF pipeline can hit
  // a strict ASCII/Latin-1 string encoder somewhere in the save/print path,
  // which throws `ArgumentError: Invalid argument (string): Contains
  // invalid characters.` for any non-ASCII (e.g. Japanese) character. The
  // in-PDF page content (rendered via embedded TTF fonts through pw.Text)
  // is unaffected and can safely contain Japanese - only this identifier
  // string needs to stay ASCII-safe.
  static String _fileBaseName(int year, int month, String department) {
    final monthStr = month.toString().padLeft(2, '0');
    final deptSlug = department.isNotEmpty
        ? '_${_toAsciiSlug(department)}'
        : '';
    return 'shift_${year}_$monthStr$deptSlug';
  }

  /// Converts arbitrary text (which may contain Japanese or other non-ASCII
  /// characters) into an ASCII-only, filesystem/identifier-safe slug.
  /// Non ASCII-alphanumeric characters are replaced with underscores, and
  /// runs of underscores are collapsed.
  static String _toAsciiSlug(String input) {
    final buffer = StringBuffer();
    for (final unit in input.codeUnits) {
      final isAsciiAlnum =
          (unit >= 0x30 && unit <= 0x39) || // 0-9
          (unit >= 0x41 && unit <= 0x5A) || // A-Z
          (unit >= 0x61 && unit <= 0x7A); // a-z
      buffer.writeCharCode(isAsciiAlnum ? unit : 0x5F); // '_'
    }
    var result = buffer.toString().replaceAll(RegExp('_+'), '_');
    result = result.replaceAll(RegExp(r'^_|_$'), '');
    return result.isEmpty ? 'dept' : result;
  }

  static Future<Uint8List> _buildPdfBytes({
    required int year,
    required int month,
    required int daysInMonth,
    required String department,
    required List<ShiftMatrixPdfRow> rows,
  }) async {
    final regularFontData = await rootBundle.load(
      'assets/fonts/NotoSansJP-Regular.ttf',
    );
    final boldFontData = await rootBundle.load(
      'assets/fonts/NotoSansJP-Bold.ttf',
    );
    final regularFont = pw.Font.ttf(regularFontData);
    final boldFont = pw.Font.ttf(boldFontData);

    final doc = pw.Document();

    const pageFormat = PdfPageFormat.a4;
    final landscape = pageFormat.landscape;
    const margin = 16.0;
    const titleHeight = 22.0;
    const titleGap = 6.0;

    final printableWidth = landscape.width - margin * 2;
    final availableTableHeight =
        landscape.height - margin * 2 - titleHeight - titleGap;

    // --- Column widths: always consume exactly 100% of printableWidth,
    // never leaving blank space on the right regardless of daysInMonth
    // (28~31) - same reasoning as the on-screen adaptive-size fix. ---
    final nameColWidth = (printableWidth * 0.09).clamp(46.0, 70.0);
    final totalColWidth = (printableWidth * 0.045).clamp(24.0, 40.0);
    final dayColWidth =
        (printableWidth - nameColWidth - totalColWidth * 2) / daysInMonth;

    // --- Row height: always consume exactly 100% of availableTableHeight
    // across (header + every staff row + footer), so the whole month for
    // every member of staff fits on one landscape page no matter how many
    // rows there are. Floor kept only so degenerate cases (hundreds of
    // rows) still render something instead of a zero/negative height. ---
    final totalRowSlots = rows.length + 2; // header row + "合計" footer row
    final rowHeight = (availableTableHeight / totalRowSlots).clamp(
      6.0,
      30.0,
    );

    final rawScale = (rowHeight / 22.0).clamp(0.35, 1.15);
    double fs(double base) => base * rawScale;

    double weekdayOf(int day) => (DateTime(year, month, day).weekday % 7)
        .toDouble();

    String dateKey(int day) =>
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

    double totalHoursForDay(int day) {
      final key = dateKey(day);
      double total = 0;
      for (final row in rows) {
        final entry = row.entriesByDate[key];
        if (entry == null) continue;
        final h = double.tryParse(entry.hours);
        if (h != null) total += h;
      }
      return total;
    }

    final grandTotalHours = rows.fold<double>(0.0, (s, r) => s + r.totalHours);
    final grandTotalDays = rows.fold<int>(
      0,
      (s, r) => s + r.filledDaysCount,
    );

    pw.Widget headerDayCell(int day) {
      final dow = weekdayOf(day).toInt();
      final isSunday = dow == 0;
      final isSaturday = dow == 6;
      // Solid, dark backgrounds for Sun/Sat so white text stays readable
      // even when printed in monochrome (grayscale) - see comment on the
      // color constants above.
      final headerBg = isSunday
          ? _sundayHeaderBg
          : isSaturday
          ? _saturdayHeaderBg
          : _primaryDeep;
      return pw.Container(
        width: dayColWidth,
        height: rowHeight,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: headerBg,
          border: pw.Border(
            right: pw.BorderSide(color: PdfColors.white, width: 0.4),
          ),
        ),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              '$day',
              style: pw.TextStyle(
                font: boldFont,
                fontSize: fs(7.2),
                color: PdfColors.white,
              ),
            ),
            pw.Text(
              _dowJp[dow],
              style: pw.TextStyle(
                font: regularFont,
                fontSize: fs(5.4),
                color: PdfColors.white,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget headerTotalCell(String label) {
      return pw.Container(
        width: totalColWidth,
        height: rowHeight,
        alignment: pw.Alignment.center,
        color: _primaryDeep,
        padding: const pw.EdgeInsets.symmetric(horizontal: 1),
        child: pw.Text(
          label,
          textAlign: pw.TextAlign.center,
          maxLines: 2,
          style: pw.TextStyle(
            font: boldFont,
            fontSize: fs(5.6),
            color: PdfColors.white,
          ),
        ),
      );
    }

    pw.Widget dataCell(ShiftMatrixPdfRow row, int day) {
      final key = dateKey(day);
      final entry = row.entriesByDate[key];
      final dow = weekdayOf(day).toInt();
      final isWeekend = dow == 0 || dow == 6;

      if (entry == null || (entry.hours.isEmpty && entry.code.isEmpty)) {
        return pw.Container(
          width: dayColWidth,
          height: rowHeight,
          decoration: pw.BoxDecoration(
            color: (entry?.isHoliday ?? isWeekend) ? _weekendBg : _surface,
            border: pw.Border(right: pw.BorderSide(color: _line, width: 0.3)),
          ),
        );
      }

      final isPaidLeave = ShiftCode.isPaidLeave(entry.code);
      final label = isPaidLeave ? ShiftCode.paidLeaveCode : entry.code;
      final accent = isPaidLeave ? _paidLeave : _primaryDeep;

      return pw.Container(
        width: dayColWidth,
        height: rowHeight,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(
            isPaidLeave ? 0x333FA9D6 : 0x33EA5F98,
          ),
          border: pw.Border(right: pw.BorderSide(color: _line, width: 0.3)),
        ),
        child: pw.Text(
          label,
          style: pw.TextStyle(font: boldFont, fontSize: fs(7.0), color: accent),
        ),
      );
    }

    pw.Widget totalDayCell(double hours) {
      return pw.Container(
        width: dayColWidth,
        height: rowHeight,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border(right: pw.BorderSide(color: _line, width: 0.3)),
        ),
        child: pw.Text(
          hours > 0 ? hours.toStringAsFixed(2) : '',
          style: pw.TextStyle(
            font: boldFont,
            fontSize: fs(5.8),
            color: _primaryDeep,
          ),
        ),
      );
    }

    // --- Fixed name column (left): corner header + one cell per row + the
    // "合計" label row, stacked to exactly match the header/body/footer
    // rows on the right so borders line up perfectly. ---
    final nameColumn = pw.Column(
      children: [
        pw.Container(
          width: nameColWidth,
          height: rowHeight,
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          color: _primaryDeep,
          child: pw.Text(
            '氏名',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: fs(7.2),
              color: PdfColors.white,
            ),
          ),
        ),
        for (int i = 0; i < rows.length; i++)
          pw.Container(
            width: nameColWidth,
            height: rowHeight,
            alignment: pw.Alignment.centerLeft,
            padding: const pw.EdgeInsets.symmetric(horizontal: 4),
            decoration: pw.BoxDecoration(
              color: i.isEven ? _surface : _background,
              border: pw.Border(
                bottom: pw.BorderSide(color: _line, width: 0.3),
              ),
            ),
            child: pw.Text(
              rows[i].name,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(font: boldFont, fontSize: fs(6.6)),
            ),
          ),
        pw.Container(
          width: nameColWidth,
          height: rowHeight,
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          decoration: pw.BoxDecoration(
            color: _holidayBg,
            border: pw.Border(
              top: pw.BorderSide(color: _primaryDeep, width: 0.8),
            ),
          ),
          child: pw.Text(
            '合計',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: fs(6.6),
              color: _primaryDeep,
            ),
          ),
        ),
      ],
    );

    // --- Scrollable-on-screen area, but here just the full-width table
    // since a PDF page has no scrolling: header row, one row per staff
    // member, and the "合計" footer row. ---
    final gridColumn = pw.Column(
      children: [
        pw.Row(
          children: [
            for (int day = 1; day <= daysInMonth; day++) headerDayCell(day),
            headerTotalCell('出勤\n日数'),
            headerTotalCell('時間\n(h)'),
          ],
        ),
        for (int i = 0; i < rows.length; i++)
          pw.Container(
            decoration: pw.BoxDecoration(
              color: i.isEven ? _surface : _background,
              border: pw.Border(
                bottom: pw.BorderSide(color: _line, width: 0.3),
              ),
            ),
            child: pw.Row(
              children: [
                for (int day = 1; day <= daysInMonth; day++)
                  dataCell(rows[i], day),
                pw.Container(
                  width: totalColWidth,
                  height: rowHeight,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                      left: pw.BorderSide(color: _line, width: 0.4),
                    ),
                  ),
                  child: pw.Text(
                    '${rows[i].filledDaysCount}',
                    style: pw.TextStyle(font: boldFont, fontSize: fs(6.4)),
                  ),
                ),
                pw.Container(
                  width: totalColWidth,
                  height: rowHeight,
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    rows[i].totalHours.toStringAsFixed(2),
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: fs(5.8),
                      color: _primaryDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        pw.Container(
          decoration: pw.BoxDecoration(
            color: _holidayBg,
            border: pw.Border(
              top: pw.BorderSide(color: _primaryDeep, width: 0.8),
            ),
          ),
          child: pw.Row(
            children: [
              for (int day = 1; day <= daysInMonth; day++)
                totalDayCell(totalHoursForDay(day)),
              pw.Container(
                width: totalColWidth,
                height: rowHeight,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    left: pw.BorderSide(color: _line, width: 0.4),
                  ),
                ),
                child: pw.Text(
                  '$grandTotalDays',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: fs(6.4),
                    color: _primaryDeep,
                  ),
                ),
              ),
              pw.Container(
                width: totalColWidth,
                height: rowHeight,
                alignment: pw.Alignment.center,
                child: pw.Text(
                  grandTotalHours.toStringAsFixed(2),
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: fs(5.8),
                    color: _primaryDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final deptSuffix = department.isNotEmpty ? '（$department）' : '';

    doc.addPage(
      pw.Page(
        pageFormat: landscape,
        margin: const pw.EdgeInsets.all(margin),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                height: titleHeight,
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      '$year年$month月 シフト表$deptSuffix',
                      style: pw.TextStyle(font: boldFont, fontSize: 13),
                    ),
                    pw.Spacer(),
                    pw.Text(
                      '${rows.length}名',
                      style: pw.TextStyle(font: regularFont, fontSize: 9),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: titleGap),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  nameColumn,
                  pw.Expanded(child: gridColumn),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
