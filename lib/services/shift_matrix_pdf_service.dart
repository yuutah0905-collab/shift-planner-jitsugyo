import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
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
  // Kept in sync with the on-screen matrix (monthly_shift_matrix_screen.dart):
  // no colored cell/header fills anywhere, plain black text throughout, and
  // holiday/day-off cells use the same moderate gray (_holidayGray) as the
  // on-screen AppColors.holidayGray - so the printed/exported PDF always
  // looks identical to what's shown on screen.
  static final _ink = PdfColor.fromInt(0xFF262425);
  static final _primaryDeep = PdfColor.fromInt(0xFFC4275F);
  static final _line = PdfColor.fromInt(0xFFD9D5D6);
  // Dedicated grid-line color for the table cells - matches
  // AppColors.gridLine on screen. Deliberately darker than _line above so
  // borders stay visible against the gray/light-blue cell fills.
  static final _gridLine = PdfColor.fromInt(0xFFBFBBBC);
  static final _holidayGray = PdfColor.fromInt(0xFFD9D9D9);
  static final _surface = PdfColor.fromInt(0xFFFFFFFF);
  static final _background = PdfColor.fromInt(0xFFFAFAFA);
  // Paid leave (有給) cell fill - light blue, mirrors
  // AppColors.paidLeaveBg on screen so it stands out from a normal
  // gray/white shift cell.
  static final _paidLeaveBg = PdfColor.fromInt(0xFFE3F3FA);

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
    String remarks = '',
  }) async {
    await Printing.layoutPdf(
      name: _fileBaseName(year, month, department),
      onLayout: (format) => _buildPdfBytes(
        year: year,
        month: month,
        daysInMonth: daysInMonth,
        department: department,
        rows: rows,
        remarks: remarks,
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
    String remarks = '',
  }) async {
    final bytes = await _buildPdfBytes(
      year: year,
      month: month,
      daysInMonth: daysInMonth,
      department: department,
      rows: rows,
      remarks: remarks,
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

  /// Test-only accessor for [_buildPdfBytes], so widget/unit tests can
  /// inspect the raw generated PDF bytes directly.
  @visibleForTesting
  static Future<Uint8List> exportAndShareForTest({
    required int year,
    required int month,
    required int daysInMonth,
    required String department,
    required List<ShiftMatrixPdfRow> rows,
    String remarks = '',
  }) => _buildPdfBytes(
    year: year,
    month: month,
    daysInMonth: daysInMonth,
    department: department,
    rows: rows,
    remarks: remarks,
  );

  static Future<Uint8List> _buildPdfBytes({
    required int year,
    required int month,
    required int daysInMonth,
    required String department,
    required List<ShiftMatrixPdfRow> rows,
    String remarks = '',
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

    // Total vertical space inside the page margins. IMPORTANT: reserve a
    // small safety buffer out of this before doing any height math below.
    // Without it, the title + table + remarks heights are computed to sum
    // to *exactly* this value with zero slack - and once the pdf package's
    // actual font metrics/rounding are applied during real rendering, the
    // true rendered height can come out a fraction of a point *larger*
    // than this estimate. `pw.Page` uses a single, non-paginating
    // `pw.Column`, so when that happens it doesn't error or wrap to a
    // second page - it silently drops the last overflowing child (in
    // practice, this made the whole "備考" box vanish for larger
    // rows/remarks combinations). Reserving a few points of slack keeps
    // the estimate comfortably under the real limit.
    const pageSafetyMargin = 10.0;
    final usableContentHeight = landscape.height - margin * 2 - pageSafetyMargin;

    // Reserve a "備考" box at the bottom of the page, matching the
    // on-screen remarks field, so the manually-typed notes are included in
    // the printed/exported PDF too - only reserve the space (and shrink
    // the table to fit) when there is actually something to show, so PDFs
    // without remarks keep using the full page for the table exactly as
    // before.
    //
    // IMPORTANT: the box height is NOT a fixed constant - a fixed 56pt box
    // clipped remarks text after ~3 lines even when the on-screen field
    // (which scrolls, so the user can freely type more) had 4+ lines
    // typed into it. Instead, estimate how many lines the text will need
    // once wrapped to `printableWidth` and size the box to fit all of it
    // (up to a generous cap so extremely long remarks can't push the
    // table off the page entirely).
    final hasRemarks = remarks.trim().isNotEmpty;
    const remarksGap = 6.0;
    const remarksBoxPadding = 6.0;
    const remarksLabelBlockHeight = 15.0; // "備考" label line + its gap
    const remarksFontSize = 8.5;
    const remarksLineHeight = remarksFontSize * 1.3; // font size + leading
    const remarksMinHeight = 40.0;
    double remarksHeight = 0.0;
    if (hasRemarks) {
      final textAreaWidth = printableWidth - remarksBoxPadding * 2;
      // Conservative (worst-case) estimate: assume every character could
      // be full-width (CJK), where glyph advance width is roughly equal to
      // the font size - this slightly over-reserves space for mixed
      // Japanese/ASCII text rather than risk under-reserving and clipping
      // lines again.
      final charsPerLine = (textAreaWidth / (remarksFontSize * 1.05))
          .floor()
          .clamp(8, 400);
      var wrappedLineCount = 0;
      for (final line in remarks.split('\n')) {
        wrappedLineCount += line.isEmpty
            ? 1
            : (line.length / charsPerLine).ceil();
      }
      final textBlockHeight = wrappedLineCount * remarksLineHeight;
      final maxRemarksHeight =
          (usableContentHeight - titleHeight - titleGap) * 0.5;
      remarksHeight =
          (remarksLabelBlockHeight +
                  textBlockHeight +
                  remarksBoxPadding * 2)
              .clamp(remarksMinHeight, maxRemarksHeight);
    }
    final remarksBlockHeight = hasRemarks ? remarksGap + remarksHeight : 0.0;

    final availableTableHeight =
        usableContentHeight -
        titleHeight -
        titleGap -
        remarksBlockHeight;

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

    // True if [day] is a weekend/company holiday - checked the same way as
    // a normal data cell (per-entry `isHoliday` flag if any row has an
    // entry for that date, otherwise fall back to weekend). Mirrors
    // `_isHolidayDay` in monthly_shift_matrix_screen.dart so the printed
    // "合計" footer row's per-day cells only get the gray holiday fill on
    // an actual holiday column, matching the on-screen matrix, instead of
    // graying out every day including normal work days.
    bool isHolidayDay(int day) {
      final dow = weekdayOf(day).toInt();
      final isWeekend = dow == 0 || dow == 6;
      final key = dateKey(day);
      for (final row in rows) {
        final entry = row.entriesByDate[key];
        if (entry != null) return entry.isHoliday;
      }
      return isWeekend;
    }

    pw.Widget headerDayCell(int day) {
      final dow = weekdayOf(day).toInt();
      final isWeekend = dow == 0 || dow == 6;
      // Weekend header cells get the same moderate holidayGray background
      // as the data/footer cells below them, matching the on-screen matrix
      // (a holiday column reads as one unbroken gray strip top to bottom).
      return pw.Container(
        width: dayColWidth,
        height: rowHeight,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: isWeekend ? _holidayGray : null,
          border: pw.Border.all(color: _gridLine, width: 0.4),
        ),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              '$day',
              style: pw.TextStyle(
                font: boldFont,
                fontSize: fs(7.2),
                color: _ink,
              ),
            ),
            pw.Text(
              _dowJp[dow],
              style: pw.TextStyle(
                font: regularFont,
                fontSize: fs(5.4),
                color: _ink,
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
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _gridLine, width: 0.4),
        ),
        padding: const pw.EdgeInsets.symmetric(horizontal: 1),
        child: pw.Text(
          label,
          textAlign: pw.TextAlign.center,
          maxLines: 2,
          style: pw.TextStyle(
            font: boldFont,
            fontSize: fs(5.6),
            color: _ink,
          ),
        ),
      );
    }

    pw.Widget dataCell(ShiftMatrixPdfRow row, int day) {
      final key = dateKey(day);
      final entry = row.entriesByDate[key];
      final dow = weekdayOf(day).toInt();
      final isWeekend = dow == 0 || dow == 6;

      final isHolidayCell = (entry?.isHoliday ?? isWeekend);

      if (entry == null || (entry.hours.isEmpty && entry.code.isEmpty)) {
        // Blank cell = that person is off that day - always shade it with
        // the same moderate gray regardless of weekday, matching the
        // on-screen matrix.
        return pw.Container(
          width: dayColWidth,
          height: rowHeight,
          decoration: pw.BoxDecoration(
            color: _holidayGray,
            border: pw.Border.all(color: _gridLine, width: 0.4),
          ),
        );
      }

      final isPaidLeave = ShiftCode.isPaidLeave(entry.code);
      // Prefer the numeric hour value ("4.25") over the internal letter code
      // for display, matching the on-screen matrix's shift-code formatting.
      final hoursValue = double.tryParse(entry.hours);
      final label = isPaidLeave
          ? ShiftCode.paidLeaveCode
          : (hoursValue != null ? hoursValue.toStringAsFixed(2) : entry.code);

      // Paid leave gets a distinct light-blue fill, matching the on-screen
      // matrix; otherwise fall back to the moderate gray for
      // weekend/holiday cells, or plain white for a normal work day.
      final cellColor = isPaidLeave
          ? _paidLeaveBg
          : (isHolidayCell ? _holidayGray : _surface);

      return pw.Container(
        width: dayColWidth,
        height: rowHeight,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: cellColor,
          border: pw.Border.all(color: _gridLine, width: 0.4),
        ),
        child: pw.Text(
          label,
          style: pw.TextStyle(
            font: boldFont,
            fontSize: fs(7.0),
            color: _ink,
          ),
        ),
      );
    }

    pw.Widget totalDayCell(double hours, bool isHoliday) {
      return pw.Container(
        width: dayColWidth,
        height: rowHeight,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: isHoliday ? _holidayGray : _surface,
          border: pw.Border.all(color: _gridLine, width: 0.4),
        ),
        child: pw.Text(
          hours > 0 ? hours.toStringAsFixed(2) : '',
          style: pw.TextStyle(font: boldFont, fontSize: fs(5.8), color: _ink),
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
          decoration: pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: _gridLine, width: 0.4),
              left: pw.BorderSide(color: _gridLine, width: 0.4),
              right: pw.BorderSide(color: _gridLine, width: 0.4),
              bottom: pw.BorderSide(color: _primaryDeep, width: 1.0),
            ),
          ),
          child: pw.Text(
            '氏名',
            style: pw.TextStyle(font: boldFont, fontSize: fs(7.2), color: _ink),
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
              border: pw.Border.all(color: _gridLine, width: 0.4),
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
            // Matches the on-screen "合計" label cell (AppColors.surface,
            // i.e. plain white) rather than the moderate holiday gray.
            color: _surface,
            border: pw.Border(
              left: pw.BorderSide(color: _gridLine, width: 0.4),
              right: pw.BorderSide(color: _gridLine, width: 0.4),
              bottom: pw.BorderSide(color: _gridLine, width: 0.4),
              top: pw.BorderSide(color: _primaryDeep, width: 0.8),
            ),
          ),
          child: pw.Text(
            '合計',
            style: pw.TextStyle(font: boldFont, fontSize: fs(6.6), color: _ink),
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
            // NOTE: header total cells get a grid border via
            // headerTotalCell() itself.
            headerTotalCell('時間\n(h)'),
          ],
        ),
        for (int i = 0; i < rows.length; i++)
          pw.Container(
            decoration: pw.BoxDecoration(
              color: i.isEven ? _surface : _background,
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
                    border: pw.Border.all(color: _gridLine, width: 0.4),
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
                      color: _ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        pw.Container(
          decoration: pw.BoxDecoration(
            // NOTE: no longer a solid _holidayGray fill across the whole
            // row - each day cell below now colors itself individually
            // (gray only on an actual holiday column, white otherwise),
            // matching the on-screen matrix's "合計" footer row instead of
            // graying out every normal work day too.
            color: _surface,
            border: pw.Border(
              top: pw.BorderSide(color: _primaryDeep, width: 0.8),
            ),
          ),
          child: pw.Row(
            children: [
              for (int day = 1; day <= daysInMonth; day++)
                totalDayCell(totalHoursForDay(day), isHolidayDay(day)),
              pw.Container(
                width: totalColWidth,
                height: rowHeight,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _gridLine, width: 0.4),
                ),
                // The grand-total attendance-day count in this corner cell
                // is not needed, matching the on-screen matrix - left
                // blank on purpose.
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
                    color: _ink,
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
              if (hasRemarks) ...[
                pw.SizedBox(height: remarksGap),
                pw.Container(
                  width: printableWidth,
                  height: remarksHeight,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _line, width: 0.6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        '備考',
                        style: pw.TextStyle(font: boldFont, fontSize: 9),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Expanded(
                        child: pw.Text(
                          remarks,
                          style: pw.TextStyle(
                            font: regularFont,
                            fontSize: 8.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
