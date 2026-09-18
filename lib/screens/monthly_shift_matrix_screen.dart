import 'dart:async';
import 'package:flutter/material.dart';
import '../models/day_entry.dart';
import '../models/employee.dart';
import '../models/shift_code.dart';
import '../models/shift_submission.dart';
import '../services/firestore_service.dart';
import '../services/shift_matrix_pdf_service.dart';
import '../theme/app_theme.dart';

/// One row of the matrix: a single person's per-day entries for the target
/// month, keyed by "YYYY-MM-DD" for O(1) lookup while building each cell.
class _PersonRow {
  final ShiftSubmission submission;
  final String name;
  final String department;
  final Map<String, DayEntry> entriesByDate;
  final double totalHours;
  final int filledDaysCount;

  _PersonRow({
    required this.submission,
    required this.name,
    required this.department,
    required this.entriesByDate,
    required this.totalHours,
    required this.filledDaysCount,
  });
}

/// Result returned from [_HourEditSheet] when the admin taps "保存" or
/// "クリア" - null means the sheet was dismissed without any change.
class _HourEditResult {
  final bool clear;
  final bool paidLeave;
  final double? hours;

  const _HourEditResult({this.clear = false, this.paidLeave = false, this.hours});
}

/// Bottom sheet used by the monthly shift matrix's tap-to-edit-hours
/// feature: lets the admin manually correct a single day's worked hours
/// (free-text numeric entry), mark the day as paid leave, or clear it
/// back to a day-off. Also shows the day's memo (if any) as read-only
/// context, since tapping a cell used to only be for viewing the memo.
class _HourEditSheet extends StatefulWidget {
  final String personName;
  final String dateLabel;
  final String initialHours;
  final bool initialPaidLeave;
  final String memo;

  const _HourEditSheet({
    required this.personName,
    required this.dateLabel,
    required this.initialHours,
    required this.initialPaidLeave,
    required this.memo,
  });

  @override
  State<_HourEditSheet> createState() => _HourEditSheetState();
}

class _HourEditSheetState extends State<_HourEditSheet> {
  late TextEditingController _hoursController;
  late bool _paidLeave;

  @override
  void initState() {
    super.initState();
    _hoursController = TextEditingController(text: widget.initialHours);
    _paidLeave = widget.initialPaidLeave;
  }

  @override
  void dispose() {
    _hoursController.dispose();
    super.dispose();
  }

  void _save() {
    if (_paidLeave) {
      Navigator.of(context).pop(const _HourEditResult(paidLeave: true));
      return;
    }
    final text = _hoursController.text.trim();
    if (text.isEmpty) {
      // Empty + not paid leave = same as clearing the day back to off.
      Navigator.of(context).pop(const _HourEditResult(clear: true));
      return;
    }
    final h = double.tryParse(text);
    if (h == null || h < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('時間を正しく入力してください（例：3.5）')),
      );
      return;
    }
    Navigator.of(context).pop(_HourEditResult(hours: h));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.personName} ・ ${widget.dateLabel}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDeep,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (widget.memo.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.sticky_note_2_outlined,
                    size: 16,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.memo,
                      style: const TextStyle(fontSize: 13, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('有給休暇にする'),
            value: _paidLeave,
            activeThumbColor: AppColors.paidLeave,
            onChanged: (v) => setState(() => _paidLeave = v),
          ),
          if (!_paidLeave) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _hoursController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '時間（h）',
                hintText: '例）3.5',
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.clear),
              label: const Text('クリア（休みにする）'),
              onPressed: () => Navigator.of(
                context,
              ).pop(const _HourEditResult(clear: true)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(onPressed: _save, child: const Text('保存')),
          ),
        ],
      ),
    );
  }
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
  // true = part-time staff's read-only view (opened via "月間シフト一覧表を見る"
  // on their own shift-request screen, after the admin has published this
  // month's matrix). Hides admin-only actions (tap-to-edit-hours, PDF
  // export, remarks editing, "シフト配布" toggle) so staff can only view.
  final bool readOnly;

  const MonthlyShiftMatrixScreen({
    super.key,
    required this.submissions,
    required this.targetMonth,
    required this.availableDepartments,
    this.initialDepartment = '',
    this.employees = const [],
    this.readOnly = false,
  });

  @override
  State<MonthlyShiftMatrixScreen> createState() =>
      _MonthlyShiftMatrixScreenState();
}

class _MonthlyShiftMatrixScreenState extends State<MonthlyShiftMatrixScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late String _selectedDepartment;
  late int _year;
  late int _month;
  late int _daysInMonth;
  late Map<String, int> _rosterOrder;

  // Mutable working copy of widget.submissions. In readOnly mode (part-time
  // staff's published view) this is kept live-updated via
  // [_submissionsSub] below, so an admin's edit to a shift (e.g. correcting
  // hours from the matrix screen) shows up immediately for staff who
  // already have this screen open - without the admin needing to
  // un-publish/re-publish just to force a refresh. In admin (editable)
  // mode this is simply mutated in place by [_editHours], same as before.
  late List<ShiftSubmission> _submissions;

  // Only used in readOnly mode: keeps the matrix in sync with Firestore in
  // real time so admin edits made WHILE staff are viewing the published
  // matrix appear automatically.
  StreamSubscription<List<ShiftSubmission>>? _submissionsSub;
  // Whether the currently selected department is published ("シフト配布")
  // for this target month, for part-time staff of that department to
  // view. Admin-only state, irrelevant in readOnly mode. Per-department
  // (each department has its own admin/manager), re-loaded whenever the
  // selected department tab changes. Loaded from
  // AppConfig.publishedDepartments in initState / _switchDepartment.
  bool _isPublished = false;
  bool _publishLoading = false;

  // Vertical sync pair: fixed name column <-> data grid body.
  final ScrollController _nameVController = ScrollController();
  final ScrollController _gridVController = ScrollController();
  // Horizontal sync pair: date header row <-> data grid body.
  final ScrollController _headerHController = ScrollController();
  final ScrollController _bodyHController = ScrollController();
  bool _isSyncingV = false;
  bool _isSyncingH = false;
  bool _isExportingPdf = false;

  // Free-typed "備考" (remarks) notes at the bottom of the matrix, matching
  // the paper/Excel shift table's bottom remarks section (per-employee
  // free-text notes about date/time exceptions, etc). Stored in Firestore
  // (matrix_remarks/{targetMonth}_{department}) - not local-only - so
  // part-time staff can see the same note in their read-only published
  // view once "シフト配布" is turned on.
  final TextEditingController _remarksController = TextEditingController();
  Timer? _remarksSaveDebounce;
  bool _remarksLoaded = false;

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
    _submissions = List<ShiftSubmission>.from(widget.submissions);
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
    _loadRemarks();
    if (!widget.readOnly) {
      _loadPublishedState();
    } else {
      // Part-time staff's published view: subscribe to real-time updates
      // so admin edits (hour corrections, etc.) appear immediately without
      // needing to un-publish/re-publish or reopen this screen.
      _submissionsSub = _firestoreService
          .watchSubmissionsForMonth(widget.targetMonth)
          .listen((all) {
            if (!mounted) return;
            setState(() {
              _submissions = all
                  .where((s) => widget.availableDepartments.contains(s.department))
                  .toList();
            });
          });
    }
  }

  /// Loads whether the CURRENTLY SELECTED department is published for
  /// this target month, to show the "シフト配布" button in the correct
  /// on/off state. Publishing is per-department (each department has its
  /// own admin/manager), so this is re-run every time the admin switches
  /// department tabs via [_switchDepartment]. Admin-only (never called in
  /// readOnly mode, since staff don't see this button at all).
  Future<void> _loadPublishedState() async {
    if (_selectedDepartment.isEmpty) {
      if (mounted) setState(() => _isPublished = false);
      return;
    }
    final config = await _firestoreService.fetchConfig();
    if (!mounted) return;
    setState(() {
      _isPublished = config.isDepartmentPublished(_selectedDepartment);
    });
  }

  /// Toggles "シフト配布" on/off for the CURRENTLY SELECTED department only:
  /// ON makes that department's completed monthly shift matrix viewable
  /// (read-only) by that department's part-time staff from their own
  /// shift-request screen; OFF hides it again. Other departments' publish
  /// states are untouched.
  Future<void> _togglePublish() async {
    if (_selectedDepartment.isEmpty) return;
    setState(() => _publishLoading = true);
    try {
      final newValue = !_isPublished;
      await _firestoreService.setDepartmentPublished(
        _selectedDepartment,
        newValue,
        widget.targetMonth,
      );
      if (!mounted) return;
      setState(() {
        _isPublished = newValue;
        _publishLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newValue
                ? '$_selectedDepartmentのシフトを配布しました。パートさんの画面から見られるようになります。'
                : '$_selectedDepartmentのシフトの配布を停止しました。',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _publishLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('配布状態の更新に失敗しました: $e')));
    }
  }

  Future<void> _loadRemarks() async {
    final saved = await _firestoreService.fetchMatrixRemarks(
      widget.targetMonth,
      _selectedDepartment,
    );
    if (!mounted) return;
    _remarksController.text = saved;
    _remarksLoaded = true;
    setState(() {});
  }

  void _onRemarksChanged(String value) {
    _remarksSaveDebounce?.cancel();
    _remarksSaveDebounce = Timer(const Duration(milliseconds: 500), () async {
      await _firestoreService.saveMatrixRemarks(
        widget.targetMonth,
        _selectedDepartment,
        value,
      );
    });
  }

  Future<void> _switchDepartment(String department) async {
    setState(() => _selectedDepartment = department);
    _remarksLoaded = false;
    await _loadRemarks();
    if (!widget.readOnly) await _loadPublishedState();
    if (mounted) setState(() {});
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
    _submissionsSub?.cancel();
    _nameVController.dispose();
    _gridVController.dispose();
    _headerHController.dispose();
    _bodyHController.dispose();
    _remarksSaveDebounce?.cancel();
    _remarksController.dispose();
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
        ? _submissions
        : _submissions
              .where((s) => s.department == _selectedDepartment)
              .toList();

    final rows = filtered.map((s) {
      final map = <String, DayEntry>{};
      for (final d in s.days) {
        map[d.date] = d;
      }
      return _PersonRow(
        submission: s,
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

  /// True if [day] is a weekend/company holiday - checked the same way
  /// as a normal data cell (per-entry `isHoliday` flag if any row has an
  /// entry for that date, otherwise fall back to weekend). Used by the
  /// footer "合計" row so holiday columns keep their gray background
  /// instead of being flagged red by the under-staffed check, even when
  /// their total is (correctly) 0 or low because nobody is scheduled to
  /// work that day.
  bool _isHolidayDay(List<_PersonRow> rows, int day) {
    final dow = _weekdayOf(day);
    final isWeekend = dow == 0 || dow == 6;
    final key = _dateKey(day);
    for (final row in rows) {
      final entry = row.entriesByDate[key];
      if (entry != null) return entry.isHoliday;
    }
    return isWeekend;
  }

  /// Grand total across the whole month, for the bottom-right corner of
  /// the footer row (sum of every day's total = sum of every person's
  /// total).
  double _grandTotalHours(List<_PersonRow> rows) =>
      rows.fold(0.0, (sum, r) => sum + r.totalHours);

  /// Read-only memo viewer used only in [widget.readOnly] mode (part-time
  /// staff's published view), where tapping a cell must never trigger an
  /// edit - just let them read the memo the admin left, if any.
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

  /// Shows the exact start/end time for a day with a dial-picker custom
  /// time range (see [DayEntry.hasCustomTime]) - used for BOTH the
  /// readOnly staff view and the admin view, since this is purely
  /// informational (viewing the already-entered range), not an edit
  /// action. The admin can still fall back to the normal tap-to-edit
  /// sheet by closing this dialog and tapping again... actually no -
  /// since a custom-time cell always opens this detail dialog first,
  /// a small "時間を修正" button is offered here so the admin isn't
  /// stuck unable to reach the normal edit sheet for that day.
  void _showCustomTimeDialog(_PersonRow row, DayEntry entry, int day) {
    // The bright "customTime" yellow/gold accent is deliberately only used
    // in the ADMIN's own editing view, to help the admin spot custom-time
    // entries at a glance. In the readOnly staff-facing view (the matrix
    // published/distributed to part-time staff), this popup must look
    // like any other plain detail view - no yellow highlight - matching
    // the cell itself, which already skips the yellow fill in readOnly
    // mode (see `cellColor` in `_dataCell`).
    final accentColor = widget.readOnly ? AppColors.ink : AppColors.customTime;
    final accentBg = widget.readOnly ? AppColors.surface : AppColors.customTimeBg;
    final accentBorder = widget.readOnly ? AppColors.line : AppColors.customTime.withValues(alpha: 0.4);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.schedule, color: accentColor, size: 20),
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accentBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.customStartTime} 〜 ${entry.customEndTime}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.free_breakfast_outlined,
                        size: 14,
                        color: entry.customHasBreak
                            ? accentColor
                            : AppColors.inkMute,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        entry.customHasBreak ? '10分休憩あり' : '10分休憩なし',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '合計 ${entry.hours}h（任意の時間で入力）',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            // Memo is admin-only context (see `hasMemo` in _dataCell for
            // the full rationale) - never shown in the readOnly staff
            // view, even inside this custom-time detail popup.
            if (!widget.readOnly && entry.memo.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.sticky_note_2_outlined,
                    size: 16,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.memo,
                      style: const TextStyle(fontSize: 13, height: 1.35),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          if (!widget.readOnly)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _editHours(row, day);
              },
              child: const Text('時間を修正'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  /// Opens the manual hour-correction bottom sheet for [row]'s entry on
  /// [day], applies the admin's change to the in-memory `DayEntry`
  /// (mutating it in place - see DayEntry's mutable hours/code fields),
  /// recomputes the submission's `totalHours`, persists both back to
  /// Firestore, and refreshes the screen. If the day has a memo, it's
  /// shown read-only inside the same sheet (this used to be a separate
  /// tap-to-view-memo-only dialog, now merged into one tap target).
  Future<void> _editHours(_PersonRow row, int day) async {
    final key = _dateKey(day);
    var entry = row.entriesByDate[key];
    final dow = _weekdayOf(day);
    final isWeekend = dow == 0 || dow == 6;
    final dateLabel = '$_month月$day日（${_dowJp[dow]}）';

    // A blank cell has no DayEntry yet - synthesize one on the fly so the
    // sheet has something to edit; it's inserted into the submission's
    // `days` list only if the admin actually saves a value.
    final isNewEntry = entry == null;
    entry ??= DayEntry(
      date: key,
      dayOfWeek: _dowJp[dow],
      isHoliday: isWeekend,
    );

    final result = await showModalBottomSheet<_HourEditResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _HourEditSheet(
        personName: row.name,
        dateLabel: dateLabel,
        initialHours: entry!.hours,
        initialPaidLeave: ShiftCode.isPaidLeave(entry.code),
        memo: entry.memo,
      ),
    );
    if (result == null) return;

    setState(() {
      if (result.clear) {
        entry!.hours = '';
        entry.code = '';
      } else if (result.paidLeave) {
        entry!.code = ShiftCode.paidLeaveCode;
        entry.hours = '';
      } else if (result.hours != null) {
        entry!.hours = result.hours!.toStringAsFixed(2);
        entry.code = '';
      }
      // Any change made through this normal admin edit sheet is a
      // different representation than the staff-side dial-picker time
      // range (plain hours / paid-leave / cleared, vs. a "HH:MM〜HH:MM"
      // range) - clear the custom range so the cell stops being shown
      // as a yellow "custom time" day once the admin has explicitly
      // overridden it here.
      entry!.customStartTime = '';
      entry.customEndTime = '';
      entry.customHasBreak = false;
      if (isNewEntry) {
        row.submission.days.add(entry);
      }
    });

    double newTotal = 0;
    for (final d in row.submission.days) {
      final h = double.tryParse(d.hours);
      if (h != null) newTotal += h;
    }
    final updated = ShiftSubmission(
      id: row.submission.id,
      name: row.submission.name,
      department: row.submission.department,
      targetMonth: row.submission.targetMonth,
      monthMemo: row.submission.monthMemo,
      days: row.submission.days,
      totalHours: newTotal,
      submittedAt: row.submission.submittedAt,
      previousVersions: row.submission.previousVersions,
    );

    try {
      await _firestoreService.updateSubmission(updated);
      if (!mounted) return;
      setState(() {
        final idx = _submissions.indexWhere(
          (s) => s.id == row.submission.id,
        );
        if (idx != -1) _submissions[idx] = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('時間を修正しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存に失敗しました: $e')));
    }
  }

  /// Exports the currently-displayed matrix (selected department, target
  /// month) exactly as shown on screen to a single A4-landscape PDF page,
  /// then opens the platform print/preview sheet so the user can save or
  /// print it. Uses the same rows/ordering already computed for the
  /// on-screen table via [_rows], just repackaged into the PDF service's
  /// plain public row type.
  Future<void> _exportPdf() async {
    if (_isExportingPdf) return;
    final rows = _rows;
    if (rows.isEmpty) return;

    setState(() => _isExportingPdf = true);
    try {
      final pdfRows = rows
          .map(
            (r) => ShiftMatrixPdfRow(
              name: r.name,
              entriesByDate: r.entriesByDate,
              totalHours: r.totalHours,
              filledDaysCount: r.filledDaysCount,
            ),
          )
          .toList();

      await ShiftMatrixPdfService.previewAndPrint(
        year: _year,
        month: _month,
        daysInMonth: _daysInMonth,
        department: _selectedDepartment,
        rows: pdfRows,
        remarks: _remarksController.text,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF出力に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        title: const Text('月間シフト一覧表'),
        actions: [
          if (!widget.readOnly && _selectedDepartment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: _publishLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  // Keep this button compact: on narrow phone screens the
                  // AppBar has to fit the back arrow, title, this button,
                  // AND the PDF icon all on one row. A longer label (e.g.
                  // one that also included the department name) would
                  // wrap onto a 2nd line and get vertically clipped by the
                  // AppBar's fixed height, corrupting the text (a glyph's
                  // descender gets cut off, making "布" look like a
                  // garbled character). So: short 1-line-only label, no
                  // icon (icon+text together didn't fit), tight padding.
                  : OutlinedButton(
                      onPressed: _togglePublish,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: _isPublished
                            ? AppColors.success
                            : Colors.transparent,
                        side: const BorderSide(color: Colors.white),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 36),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        _isPublished ? '配布中' : 'シフト配布',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
            ),
          if (!widget.readOnly)
            IconButton(
              tooltip: 'PDF出力（A4横1ページ）',
              onPressed: rows.isEmpty || _isExportingPdf ? null : _exportPdf,
              icon: _isExportingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
            ),
        ],
      ),
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
                      widget.readOnly
                          ? '$_month月（$_daysInMonth日分）／ ${rows.length}名 ・ 最下部の「合計」行はその日の全員の合計時間'
                          : '$_month月（$_daysInMonth日分）／ ${rows.length}名 ・ セルをタップで時間を修正 ・ 最下部の「合計」行はその日の全員の合計時間',
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
            _buildRemarksSection(),
          ],
        ),
      ),
    );
  }

  /// Free-typed remarks box pinned to the very bottom of the screen,
  /// matching the "備考" section at the bottom of the paper/Excel shift
  /// table (per-employee free-text notes about date/time exceptions,
  /// etc). Manually typed by the admin - not auto-generated from the
  /// shift data above. In [widget.readOnly] mode (part-time staff's
  /// published view), this becomes a plain read-only text display -
  /// hidden entirely if the admin hasn't written anything, so staff
  /// don't see an empty box with no purpose.
  Widget _buildRemarksSection() {
    if (widget.readOnly && _remarksController.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.edit_note, size: 16, color: AppColors.primaryDeep),
              SizedBox(width: 4),
              Text(
                '備考',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primaryDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (widget.readOnly)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Text(
                _remarksController.text,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            )
          else
            TextField(
              controller: _remarksController,
              enabled: _remarksLoaded,
              onChanged: _onRemarksChanged,
              maxLines: 4,
              minLines: 3,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: '例）米下さん 9/1,2,3【9:00〜15:30】 9/7【8:30〜14:30】…',
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: AppColors.inkMute,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _deptTab(String label) {
    final selected = _selectedDepartment == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _switchDepartment(label),
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
                  border: Border(
                    top: BorderSide(color: AppColors.gridLine, width: 0.6),
                    left: BorderSide(color: AppColors.gridLine, width: 0.6),
                    right: BorderSide(color: AppColors.gridLine, width: 0.6),
                    bottom: BorderSide(
                      color: AppColors.primaryDeep,
                      width: 1.4,
                    ),
                  ),
                ),
                child: Text(
                  '氏名',
                  style: TextStyle(
                    color: AppColors.ink,
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
                            border: Border.all(
                              color: AppColors.gridLine,
                              width: 0.6,
                            ),
                          ),
                          // FittedBox + scaleDown auto-shrinks the font
                          // just enough for long names (e.g. names with
                          // many kanji/characters) to fit the fixed-width
                          // name column on one line, instead of getting
                          // clipped by ellipsis like a plain Text would.
                          // Short names are unaffected - FittedBox never
                          // scales UP past the natural 12 * _fontScale
                          // size, only down.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              rows[i].name,
                              maxLines: 1,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12 * _fontScale,
                              ),
                            ),
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
                          color: AppColors.surface,
                          border: Border(
                            left: BorderSide(color: AppColors.gridLine, width: 0.6),
                            right: BorderSide(color: AppColors.gridLine, width: 0.6),
                            bottom: BorderSide(color: AppColors.gridLine, width: 0.6),
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
                            color: AppColors.ink,
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
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.gridLine, width: 0.6),
                        bottom: BorderSide(
                          color: AppColors.primaryDeep,
                          width: 1.4,
                        ),
                      ),
                    ),
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
    // Text is always plain black (no weekday-specific color), but weekend
    // header cells still get the same moderate holidayGray background as
    // the data/footer cells below them, so a holiday column reads as a
    // single unbroken gray strip from the header all the way down.
    return Container(
      width: _dayColWidth,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isWeekend ? AppColors.holidayGray : Colors.transparent,
        border: const Border(
          left: BorderSide(color: AppColors.gridLine, width: 0.5),
          right: BorderSide(color: AppColors.gridLine, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$day',
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.bold,
              fontSize: 12 * _fontScale,
            ),
          ),
          Text(
            _dowJp[dow],
            style: TextStyle(color: AppColors.ink, fontSize: 9 * _fontScale),
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
        border: Border(left: BorderSide(color: AppColors.gridLine, width: 0.6)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.ink,
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
          bottom: BorderSide(color: AppColors.gridLine, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          for (int day = 1; day <= _daysInMonth; day++) _dataCell(row, day),
          Container(
            width: _totalColWidth,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppColors.gridLine, width: 0.6)),
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
                color: AppColors.ink,
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
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.primaryDeep, width: 1.4),
        ),
      ),
      child: Row(
        children: [
          for (int day = 1; day <= _daysInMonth; day++)
            _totalDayCell(
              _totalHoursForDay(rows, day),
              _isHolidayDay(rows, day),
            ),
          Container(
            width: _totalColWidth,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppColors.gridLine, width: 0.6)),
            ),
            // The grand-total attendance-day count in this corner cell is
            // not needed - left blank on purpose (per-employee counts in
            // the rows above are unaffected).
          ),
          Container(
            width: _totalColWidth,
            alignment: Alignment.center,
            child: Text(
              _grandTotalHours(rows).toStringAsFixed(2),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11 * _fontScale,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Minimum total hours (summed across everyone in the currently
  /// filtered department) required to cover a single day's shift. Below
  /// this, that day's footer cell is highlighted red as a "understaffed"
  /// warning so the admin notices at a glance without adding up numbers.
  static const double _minDailyTotalHours = 25.0;

  /// [isHoliday] = true skips the red under-staffed highlight entirely
  /// (holiday columns keep their normal gray background even if nobody's
  /// scheduled - that's expected, not a staffing problem) and keeps the
  /// day's usual gray fill for consistency with the data rows above it.
  Widget _totalDayCell(double hours, bool isHoliday) {
    final isUnderStaffed = !isHoliday && hours < _minDailyTotalHours;
    final Color bg = isUnderStaffed
        ? Colors.red
        : (isHoliday ? AppColors.holidayGray : Colors.transparent);
    return Container(
      width: _dayColWidth,
      height: _rowHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: const Border(
          right: BorderSide(color: AppColors.gridLine, width: 0.6),
        ),
      ),
      child: Text(
        hours > 0 ? hours.toStringAsFixed(2) : '',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 10 * _fontScale,
          color: isUnderStaffed ? Colors.white : AppColors.ink,
        ),
      ),
    );
  }

  Widget _dataCell(_PersonRow row, int day) {
    final key = _dateKey(day);
    final entry = row.entriesByDate[key];
    final dow = _weekdayOf(day);
    final isWeekend = dow == 0 || dow == 6;

    final isHolidayCell = entry?.isHoliday ?? isWeekend;
    final isBlank = entry == null || (entry.hours.isEmpty && entry.code.isEmpty);
    final hasCustomTime = !isBlank && entry.hasCustomTime;

    final isPaidLeave = !isBlank && ShiftCode.isPaidLeave(entry.code);
    // Memos are notes the part-time staff member wrote for the ADMIN only
    // (e.g. personal circumstances, explanations for an odd shift) - once
    // a shift is published/distributed, every other staff member on the
    // team can open this same readOnly matrix, so a memo must never be
    // visible there (no green dot, no tap-to-view dialog). Only the
    // admin's own editing view (readOnly == false) shows memos.
    final hasMemo = !isBlank && !widget.readOnly && entry.memo.isNotEmpty;
    // Prefer the numeric hour value ("4.25") over the internal A~Y letter
    // code for display, matching the paper/Excel shift table the company
    // uses (see the reference image) - the letter codes are just an
    // internal shorthand for data entry, not what should be printed/shown.
    // Paid leave has no fixed hour value, so it keeps its "有" label. A
    // custom dial-picker time range shows its computed hour count (e.g.
    // "6.00", no "h" suffix - matches the plain numeric style used by
    // every other filled-in cell) rather than the raw "HH:MM〜HH:MM"
    // range, since the exact clock time is available on tap via the
    // detail popup - the cell itself just needs to say "this day used a
    // custom time" (via its yellow fill) and roughly how many hours.
    final hoursValue = isBlank ? null : double.tryParse(entry.hours);
    final label = isBlank
        ? ''
        : (hasCustomTime
              ? (hoursValue != null ? hoursValue.toStringAsFixed(2) : entry.hours)
              : (isPaidLeave
                    ? ShiftCode.paidLeaveCode
                    : (hoursValue != null
                          ? hoursValue.toStringAsFixed(2)
                          : entry.code)));

    // Paid leave gets a distinct light-blue fill so it stands out clearly
    // from a normal work shift; a custom (non A~Y) dial-picker time range
    // gets a bright yellow fill so the admin can immediately spot it and
    // needs a closer look via its detail popup - but ONLY in the admin's
    // own editing view. In the readOnly staff-facing view (the matrix that
    // gets published/distributed to part-time staff), a custom time day
    // is shown with the normal plain background like any other filled
    // work day, since staff shouldn't see it visually flagged/highlighted;
    // blank cells (day off) and weekend/holiday cells share the same
    // moderate gray; a normal filled work day is plain white/transparent.
    final Color cellColor = (hasCustomTime && !widget.readOnly)
        ? AppColors.customTimeCell
        : (isPaidLeave
              ? AppColors.paidLeaveBg
              : ((isBlank || isHolidayCell)
                    ? AppColors.holidayGray
                    : Colors.transparent));

    // Every cell (including blank ones) is tappable so the admin can
    // manually correct/enter the day's hours by hand. In readOnly mode
    // (part-time staff's published view), cells are not editable - only
    // a memo (if any) can be viewed. A custom time-range day ALWAYS opens
    // its detail popup first (in both modes), since simply glancing at a
    // "13:15〜18:45"-style label crammed into a narrow day column isn't
    // enough - tapping surfaces the full range clearly. The admin can
    // still reach the normal edit sheet from a button inside that popup.
    return InkWell(
      onTap: hasCustomTime
          ? () => _showCustomTimeDialog(row, entry, day)
          : (widget.readOnly
                ? (hasMemo ? () => _showMemoDialog(row, entry, day) : null)
                : () => _editHours(row, day)),
      child: Container(
        width: _dayColWidth,
        height: _rowHeight,
        decoration: BoxDecoration(
          color: cellColor,
          border: Border.all(color: AppColors.gridLine, width: 0.5),
        ),
        child: Stack(
          children: [
            // The hour/code label stays centered, but is nudged slightly
            // toward the bottom-right whenever a memo dot is shown in the
            // top-left corner, so the two never overlap even in the
            // narrowest day columns (as low as 20px wide).
            Positioned.fill(
              child: Align(
                alignment: hasMemo
                    ? const Alignment(0.2, 0.35)
                    : Alignment.center,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11 * _fontScale,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
            if (hasMemo)
              Positioned(
                top: 2,
                left: 2,
                child: Container(
                  width: 5 * _fontScale,
                  height: 5 * _fontScale,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
