import 'package:flutter/material.dart';
import '../models/day_entry.dart';
import '../models/employee.dart';
import '../models/shift_code.dart';
import '../models/shift_submission.dart';
import '../theme/app_theme.dart';

/// One row of the matrix: a single person's per-day entries for the target
/// month, keyed by "YYYY-MM-DD" for O(1) lookup while building each cell.
class _PersonRow {
  final String name;
  final String department;
  final Map<String, DayEntry> entriesByDate;
  final double totalHours;
  final int filledDaysCount;

  _PersonRow({
    required this.name,
    required this.department,
    required this.entriesByDate,
    required this.totalHours,
    required this.filledDaysCount,
  });
}

/// Admin screen: "誰がいつ何のシフトか" all at a glance for the whole
/// target month, in a spreadsheet-like matrix (name x date), matching the
/// paper/Excel shift table the company used before. Rows = staff (in
/// roster registration order), columns = each day of the target month.
///
/// Layout is a classic "frozen first column + frozen header row" table:
///  - The name column (left) only scrolls vertically.
///  - The date header row (top) only scrolls horizontally.
///  - The data grid (body) scrolls both ways.
/// Since a single ScrollController does NOT propagate user drag between
/// multiple attached Scrollables (only programmatic jumpTo/animateTo do),
/// each pair of scroll views that must move together is kept in sync with
/// manual listeners instead of naively sharing one controller.
class MonthlyShiftMatrixScreen extends StatefulWidget {
  final List<ShiftSubmission> submissions;
  final String targetMonth; // "YYYY-MM"
  final List<String> availableDepartments;
  final String initialDepartment; // '' = first available department
  final List<Employee> employees;

  const MonthlyShiftMatrixScreen({
    super.key,
    required this.submissions,
    required this.targetMonth,
    required this.availableDepartments,
    this.initialDepartment = '',
    this.employees = const [],
  });

  @override
  State<MonthlyShiftMatrixScreen> createState() =>
      _MonthlyShiftMatrixScreenState();
}

class _MonthlyShiftMatrixScreenState extends State<MonthlyShiftMatrixScreen> {
  late String _selectedDepartment;
  late int _year;
  late int _month;
  late int _daysInMonth;
  late Map<String, int> _rosterOrder;

  // Vertical sync pair: fixed name column <-> data grid body.
  final ScrollController _nameVController = ScrollController();
  final ScrollController _gridVController = ScrollController();
  // Horizontal sync pair: date header row <-> data grid body.
  final ScrollController _headerHController = ScrollController();
  final ScrollController _bodyHController = ScrollController();
  bool _isSyncingV = false;
  bool _isSyncingH = false;

  static const List<String> _dowJp = ['日', '月', '火', '水', '木', '金', '土'];

  // These start at their "roomy" defaults but are shrunk dynamically in
  // [_computeAdaptiveSizes] (called from a LayoutBuilder in build()) so the
  // whole month fits on screen with as little scrolling as possible, per
  // the "一目で全体を見たい" request - while never going below a floor
  // that would make the table unreadable/untappable.
  double _nameColWidth = 92;
  double _dayColWidth = 34;
  double _totalColWidth = 46;
  double _rowHeight = 34;
  double _fontScale = 1.0;

  /// Shrinks column widths / row height / font scale to fit the whole
  /// matrix (all days x all rows) inside [constraints] whenever possible,
  /// clamped to a minimum readable/tappable size. When the content still
  /// doesn't fit (e.g. very large staff count on a narrow phone), the
  /// minimum sizes are used and the remainder is reached via scrolling.
  ///
  /// Row height is deliberately kept close to the day-column width (not
  /// simply "whatever vertical space is available") so each day cell
  /// reads as a near-square instead of a tall rectangle with a lot of
  /// empty padding above/below the single-character code/number - even
  /// when there are few staff rows and plenty of unused vertical space.
  void _computeAdaptiveSizes(BoxConstraints constraints, int rowCount) {
    final newNameColWidth = (constraints.maxWidth * 0.14).clamp(60.0, 92.0);
    final newTotalColWidth = (constraints.maxWidth * 0.07).clamp(32.0, 46.0);
    final remaining =
        constraints.maxWidth - newNameColWidth - newTotalColWidth * 2;
    // IMPORTANT: no upper bound here. Capping this at a fixed max (as a
    // previous version did) meant that on wide PC screens the day columns
    // would stop growing while `remaining` kept growing with the window -
    // leaving an ever-larger strip of literally unused width in the
    // scrollable data grid (visually reported as "a gap between the name
    // column and the dates", worse the bigger the screen/window). Letting
    // the day columns freely grow to consume 100% of `remaining` guarantees
    // the table always exactly fills the available width with zero blank
    // space, on any screen size. Only a floor is kept, so cells never
    // shrink below a tappable/readable size on narrow phones.
    final newDayColWidth = (remaining / _daysInMonth).clamp(20.0, double.infinity);

    // +2 = the fixed header row + the "合計" footer row.
    final totalRowSlots = rowCount + 2;
    final availableRowHeight = constraints.maxHeight / totalRowSlots;
    // A little taller than the day column width reads better for Japanese
    // text + borders. Same reasoning as the width above: no upper cap, so
    // row height keeps scaling together with the (now-uncapped) day column
    // width and cells stay close to square instead of turning into wide,
    // flat rectangles on large screens. Still bounded above by whatever
    // vertical space is actually available, via the min() with
    // availableRowHeight.
    final squareTarget = newDayColWidth * 1.1;
    final newRowHeight =
        (availableRowHeight < squareTarget ? availableRowHeight : squareTarget)
            .clamp(20.0, double.infinity);

    final heightRatio = newRowHeight / 34.0;
    final widthRatio = newDayColWidth / 34.0;
    final rawScale = heightRatio < widthRatio ? heightRatio : widthRatio;
    // Text can grow a little on large screens along with the cells, but is
    // capped well below the raw scale so numbers/labels never become
    // oversized just because the day columns had to grow a lot to fill a
    // very wide window.
    final newFontScale = rawScale.clamp(0.65, 1.3);

    if (_rowHeight != newRowHeight ||
        _nameColWidth != newNameColWidth ||
        _totalColWidth != newTotalColWidth ||
        _dayColWidth != newDayColWidth ||
        _fontScale != newFontScale) {
      _rowHeight = newRowHeight;
      _nameColWidth = newNameColWidth;
      _totalColWidth = newTotalColWidth;
      _dayColWidth = newDayColWidth;
      _fontScale = newFontScale;
    }
  }

  @override
  void initState() {
    super.initState();
    _buildRosterOrder();
    if (widget.initialDepartment.isNotEmpty &&
        widget.availableDepartments.contains(widget.initialDepartment)) {
      _selectedDepartment = widget.initialDepartment;
    } else if (widget.availableDepartments.isNotEmpty) {
      _selectedDepartment = widget.availableDepartments.first;
    } else {
      _selectedDepartment = '';
    }
    final parts = widget.targetMonth.split('-');
    _year =
        int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? DateTime.now().year;
    _month =
        int.tryParse(parts.length > 1 ? parts[1] : '') ?? DateTime.now().month;
    _daysInMonth = DateTime(_year, _month + 1, 0).day;

    _nameVController.addListener(
      () => _syncOffset(_nameVController, _gridVController, isVertical: true),
    );
    _gridVController.addListener(
      () => _syncOffset(_gridVController, _nameVController, isVertical: true),
    );
    _headerHController.addListener(
      () =>
          _syncOffset(_headerHController, _bodyHController, isVertical: false),
    );
    _bodyHController.addListener(
      () =>
          _syncOffset(_bodyHController, _headerHController, isVertical: false),
    );
  }

  /// Mirrors [source]'s scroll offset onto [target], guarded by a
  /// re-entrancy flag so the two listeners don't bounce off each other
  /// infinitely (target.jumpTo triggers target's own listener too).
  void _syncOffset(
    ScrollController source,
    ScrollController target, {
    required bool isVertical,
  }) {
    final guard = isVertical ? _isSyncingV : _isSyncingH;
    if (guard) return;
    if (!target.hasClients || !source.hasClients) return;
    if (isVertical) {
      _isSyncingV = true;
    } else {
      _isSyncingH = true;
    }
    final maxExtent = target.position.maxScrollExtent;
    final clamped = source.offset.clamp(0.0, maxExtent < 0 ? 0.0 : maxExtent);
    if (target.offset != clamped) {
      target.jumpTo(clamped);
    }
    if (isVertical) {
      _isSyncingV = false;
    } else {
      _isSyncingH = false;
    }
  }

  @override
  void dispose() {
    _nameVController.dispose();
    _gridVController.dispose();
    _headerHController.dispose();
    _bodyHController.dispose();
    super.dispose();
  }

  void _buildRosterOrder() {
    _rosterOrder = {};
    for (int i = 0; i < widget.employees.length; i++) {
      _rosterOrder[Employee.normalizeName(widget.employees[i].name)] = i;
    }
  }

  int _weekdayOf(int day) => DateTime(_year, _month, day).weekday % 7; // 日=0

  /// One row per submission in the currently selected department,
  /// pre-indexed by date for fast cell lookup, sorted by roster
  /// registration order (falling back to name order, appended after
  /// roster members) - matching daily_attendance_screen.dart's convention.
  List<_PersonRow> get _rows {
    final filtered = _selectedDepartment.isEmpty
        ? widget.submissions
        : widget.submissions
              .where((s) => s.department == _selectedDepartment)
              .toList();

    final rows = filtered.map((s) {
      final map = <String, DayEntry>{};
      for (final d in s.days) {
        map[d.date] = d;
      }
      return _PersonRow(
        name: s.name,
        department: s.department,
        entriesByDate: map,
        totalHours: s.totalHours,
        filledDaysCount: s.filledDaysCount,
      );
    }).toList();

    rows.sort((a, b) {
      final orderA = _rosterOrder[Employee.normalizeName(a.name)];
      final orderB = _rosterOrder[Employee.normalizeName(b.name)];
      if (orderA != null && orderB != null) return orderA.compareTo(orderB);
      if (orderA != null) return -1;
      if (orderB != null) return 1;
      return a.name.compareTo(b.name);
    });
    return rows;
  }

  String _dateKey(int day) =>
      '${_year.toString().padLeft(4, '0')}-${_month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  /// Sum of hours worked by everyone (in the currently filtered
  /// department) on [day] - shown as a "合計" footer row at the bottom of
  /// the matrix, matching the paper shift table's per-day total row.
  double _totalHoursForDay(List<_PersonRow> rows, int day) {
    final key = _dateKey(day);
    double total = 0;
    for (final row in rows) {
      final entry = row.entriesByDate[key];
      if (entry == null) continue;
      final h = double.tryParse(entry.hours);
      if (h != null) total += h;
    }
    return total;
  }

  /// Grand total across the whole month, for the bottom-right corner of
  /// the footer row (sum of every day's total = sum of every person's
  /// total).
  double _grandTotalHours(List<_PersonRow> rows) =>
      rows.fold(0.0, (sum, r) => sum + r.totalHours);

  int _grandTotalFilledDays(List<_PersonRow> rows) =>
      rows.fold(0, (sum, r) => sum + r.filledDaysCount);

  void _showMemoDialog(_PersonRow row, DayEntry entry, int day) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.sticky_note_2_outlined,
              color: AppColors.success,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                row.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.department.isNotEmpty
                  ? '${row.department} ・ $_month月$day日'
                  : '$_month月$day日',
              style: const TextStyle(fontSize: 12, color: AppColors.inkMute),
            ),
            const SizedBox(height: 12),
            Text(entry.memo, style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('月間シフト一覧表')),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.availableDepartments.isNotEmpty)
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (
                          int i = 0;
                          i < widget.availableDepartments.length;
                          i++
                        )
                          Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                            child: _deptTab(widget.availableDepartments[i]),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: AppColors.inkMute,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '$_month月（$_daysInMonth日分）／ ${rows.length}名 ・ セルをタップでメモ確認 ・ 最下部の「合計」行はその日の全員の合計時間',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.inkMute,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.table_chart_outlined,
                            size: 48,
                            color: AppColors.inkMute.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'この部署の提出はまだありません',
                            style: TextStyle(color: AppColors.inkMute),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        _computeAdaptiveSizes(constraints, rows.length);
                        return _buildMatrix(rows);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deptTab(String label) {
    final selected = _selectedDepartment == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _selectedDepartment = label),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.background,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.ink,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.line),
    );
  }

  /// Frozen-pane table: fixed name column (left) + fixed header row (top),
  /// with the data grid scrolling both directions in between. See the
  /// class doc comment for why manual scroll-offset syncing is used.
  Widget _buildMatrix(List<_PersonRow> rows) {
    final tableWidth = _dayColWidth * _daysInMonth + _totalColWidth * 2;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fixed name column: corner header + vertically-scrollable rows.
        SizedBox(
          width: _nameColWidth,
          child: Column(
            children: [
              Container(
                height: _rowHeight,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: const BoxDecoration(
                  color: AppColors.primaryDeep,
                  border: Border(right: BorderSide(color: Colors.white24)),
                ),
                child: Text(
                  '氏名',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12 * _fontScale,
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _nameVController,
                  child: Column(
                    children: [
                      for (int i = 0; i < rows.length; i++)
                        Container(
                          height: _rowHeight,
                          width: double.infinity,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: i.isEven
                                ? AppColors.surface
                                : AppColors.background,
                            border: const Border(
                              right: BorderSide(color: AppColors.line),
                              bottom: BorderSide(
                                color: AppColors.line,
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Text(
                            rows[i].name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12 * _fontScale,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      // "合計" label row, aligned with the footer totals
                      // row on the right side of the table.
                      Container(
                        height: _rowHeight,
                        width: double.infinity,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: const BoxDecoration(
                          color: AppColors.holidayBg,
                          border: Border(
                            right: BorderSide(color: AppColors.line),
                            top: BorderSide(
                              color: AppColors.primaryDeep,
                              width: 1.4,
                            ),
                          ),
                        ),
                        child: Text(
                          '合計',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12 * _fontScale,
                            color: AppColors.primaryDeep,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Fixed header row + scrollable data grid.
        Expanded(
          child: Column(
            // IMPORTANT: Column's default crossAxisAlignment is `center`,
            // which would shrink-wrap the header/body SingleChildScrollViews
            // to exactly `tableWidth` and then center them - leaving a
            // blank gap on both sides whenever `tableWidth` (shrunk day
            // column width x day count) is narrower than the actual space
            // available in this Expanded (e.g. on wide PC screens). Stretch
            // forces both children to fill the full available width instead,
            // so the table always starts flush against the name column.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _rowHeight,
                child: SingleChildScrollView(
                  controller: _headerHController,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Container(
                    width: tableWidth,
                    color: AppColors.primaryDeep,
                    child: Row(
                      children: [
                        for (int day = 1; day <= _daysInMonth; day++)
                          _headerDayCell(day),
                        _headerTotalCell('出勤日数'),
                        _headerTotalCell('時間(h)'),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _bodyHController,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: tableWidth,
                    child: SingleChildScrollView(
                      controller: _gridVController,
                      child: Column(
                        children: [
                          for (int i = 0; i < rows.length; i++)
                            _dataRow(rows[i], i.isEven),
                          _totalRow(rows),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _headerDayCell(int day) {
    final dow = _weekdayOf(day);
    final isWeekend = dow == 0 || dow == 6;
    return Container(
      width: _dayColWidth,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isWeekend
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.transparent,
        border: const Border(right: BorderSide(color: Colors.white24)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$day',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12 * _fontScale,
            ),
          ),
          Text(
            _dowJp[dow],
            style: TextStyle(
              color: dow == 0
                  ? Colors.pinkAccent.shade100
                  : dow == 6
                  ? Colors.lightBlueAccent.shade100
                  : Colors.white70,
              fontSize: 9 * _fontScale,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerTotalCell(String label) {
    return Container(
      width: _totalColWidth,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.black12,
        border: Border(left: BorderSide(color: Colors.white24)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 10 * _fontScale,
        ),
      ),
    );
  }

  Widget _dataRow(_PersonRow row, bool isEvenRow) {
    final bg = isEvenRow ? AppColors.surface : AppColors.background;
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: bg,
        border: const Border(
          bottom: BorderSide(color: AppColors.line, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          for (int day = 1; day <= _daysInMonth; day++) _dataCell(row, day),
          Container(
            width: _totalColWidth,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppColors.line)),
            ),
            child: Text(
              '${row.filledDaysCount}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12 * _fontScale,
              ),
            ),
          ),
          Container(
            width: _totalColWidth,
            alignment: Alignment.center,
            child: Text(
              row.totalHours.toStringAsFixed(2),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11 * _fontScale,
                color: AppColors.primaryDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Footer row shown at the very bottom of the matrix: for each date
  /// column, the sum of everyone's hours on that day (matching the paper
  /// shift table's "出勤パート人工時間" bottom row), plus the grand total
  /// in the bottom-right corner.
  Widget _totalRow(List<_PersonRow> rows) {
    return Container(
      height: _rowHeight,
      decoration: const BoxDecoration(
        color: AppColors.holidayBg,
        border: Border(
          top: BorderSide(color: AppColors.primaryDeep, width: 1.4),
        ),
      ),
      child: Row(
        children: [
          for (int day = 1; day <= _daysInMonth; day++)
            _totalDayCell(_totalHoursForDay(rows, day)),
          Container(
            width: _totalColWidth,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppColors.line)),
            ),
            child: Text(
              '${_grandTotalFilledDays(rows)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12 * _fontScale,
                color: AppColors.primaryDeep,
              ),
            ),
          ),
          Container(
            width: _totalColWidth,
            alignment: Alignment.center,
            child: Text(
              _grandTotalHours(rows).toStringAsFixed(2),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11 * _fontScale,
                color: AppColors.primaryDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalDayCell(double hours) {
    return Container(
      width: _dayColWidth,
      height: _rowHeight,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.line, width: 0.4)),
      ),
      child: Text(
        hours > 0 ? hours.toStringAsFixed(2) : '',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 10 * _fontScale,
          color: AppColors.primaryDeep,
        ),
      ),
    );
  }

  Widget _dataCell(_PersonRow row, int day) {
    final key = _dateKey(day);
    final entry = row.entriesByDate[key];
    final dow = _weekdayOf(day);
    final isWeekend = dow == 0 || dow == 6;

    if (entry == null || (entry.hours.isEmpty && entry.code.isEmpty)) {
      // Blank cell - still shade weekends/holidays lightly for readability.
      return Container(
        width: _dayColWidth,
        height: _rowHeight,
        decoration: BoxDecoration(
          color: (entry?.isHoliday ?? isWeekend)
              ? AppColors.weekendBg
              : Colors.transparent,
          border: const Border(
            right: BorderSide(color: AppColors.line, width: 0.4),
          ),
        ),
      );
    }

    final isPaidLeave = ShiftCode.isPaidLeave(entry.code);
    final accent = isPaidLeave ? AppColors.paidLeave : AppColors.primary;
    final hasMemo = entry.memo.isNotEmpty;

    return InkWell(
      onTap: hasMemo ? () => _showMemoDialog(row, entry, day) : null,
      child: Container(
        width: _dayColWidth,
        height: _rowHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          border: const Border(
            right: BorderSide(color: AppColors.line, width: 0.4),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              isPaidLeave ? ShiftCode.paidLeaveCode : entry.code,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12 * _fontScale,
                color: isPaidLeave
                    ? AppColors.paidLeave
                    : AppColors.primaryDeep,
              ),
            ),
            if (hasMemo)
              Positioned(
                top: 2,
                right: 2,
                child: Icon(
                  Icons.circle,
                  size: 5 * _fontScale,
                  color: AppColors.success,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
