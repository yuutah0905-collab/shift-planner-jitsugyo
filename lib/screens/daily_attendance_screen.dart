import 'package:flutter/material.dart';
import '../models/day_entry.dart';
import '../models/shift_code.dart';
import '../models/shift_submission.dart';
import '../theme/app_theme.dart';

/// One person's shift entry for a single day, resolved for display.
class _DayAttendance {
  final String name;
  final String department;
  final DayEntry entry;

  _DayAttendance({required this.name, required this.department, required this.entry});

  double get hours => double.tryParse(entry.hours) ?? 0.0;
  bool get isPaidLeave => ShiftCode.isPaidLeave(entry.code);
}

/// Admin screen: "今日、誰が出勤して合計何時間か" at a glance, grouped by
/// department. Shows one date at a time (with prev/next day navigation
/// and a date picker), so the admin can quickly check any day in the
/// target month without hunting through each person's individual
/// submission.
class DailyAttendanceScreen extends StatefulWidget {
  final List<ShiftSubmission> submissions;
  final String targetMonth; // "YYYY-MM"
  final List<String> departmentOrder;

  const DailyAttendanceScreen({
    super.key,
    required this.submissions,
    required this.targetMonth,
    required this.departmentOrder,
  });

  @override
  State<DailyAttendanceScreen> createState() => _DailyAttendanceScreenState();
}

class _DailyAttendanceScreenState extends State<DailyAttendanceScreen> {
  late DateTime _selectedDate;
  late DateTime _firstDay;
  late DateTime _lastDay;

  @override
  void initState() {
    super.initState();
    final parts = widget.targetMonth.split('-');
    final year = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? DateTime.now().year;
    final month = int.tryParse(parts.length > 1 ? parts[1] : '') ?? DateTime.now().month;
    _firstDay = DateTime(year, month, 1);
    _lastDay = DateTime(year, month + 1, 0);

    // Default to today if it falls within the target month, otherwise
    // the 1st of the target month.
    final today = DateTime.now();
    final todayInRange = DateTime(today.year, today.month, today.day);
    if (!todayInRange.isBefore(_firstDay) && !todayInRange.isAfter(_lastDay)) {
      _selectedDate = todayInRange;
    } else {
      _selectedDate = _firstDay;
    }
  }

  String get _dateKey =>
      '${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  static const List<String> _dowJp = ['日', '月', '火', '水', '木', '金', '土'];

  String get _dateLabel {
    final dow = _dowJp[_selectedDate.weekday % 7];
    return '${_selectedDate.month}月${_selectedDate.day}日（$dow）';
  }

  bool get _isToday {
    final today = DateTime.now();
    return _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;
  }

  void _changeDay(int delta) {
    final next = _selectedDate.add(Duration(days: delta));
    if (next.isBefore(_firstDay) || next.isAfter(_lastDay)) return;
    setState(() => _selectedDate = next);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: _firstDay,
      lastDate: _lastDay,
      locale: const Locale('ja', 'JP'),
      helpText: '日付を選択',
      cancelText: 'キャンセル',
      confirmText: '選択',
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  /// All (name, department, entry) rows for the currently selected date,
  /// across every submission - only rows that actually have a code/hours
  /// entered (not blank days) are included.
  List<_DayAttendance> get _attendanceForSelectedDate {
    final key = _dateKey;
    final result = <_DayAttendance>[];
    for (final s in widget.submissions) {
      for (final d in s.days) {
        if (d.date != key) continue;
        if (d.hours.isEmpty && d.code.isEmpty) continue;
        result.add(_DayAttendance(name: s.name, department: s.department, entry: d));
      }
    }
    return result;
  }

  /// Grouped by department, in the app's configured department order,
  /// then sorted by name within each department.
  Map<String, List<_DayAttendance>> get _groupedByDepartment {
    final list = _attendanceForSelectedDate;
    final Map<String, List<_DayAttendance>> map = {};
    for (final a in list) {
      final key = a.department.isEmpty ? '未設定' : a.department;
      map.putIfAbsent(key, () => []).add(a);
    }
    for (final entries in map.values) {
      entries.sort((a, b) => a.name.compareTo(b.name));
    }
    final keys = map.keys.toList();
    keys.sort((a, b) {
      final ia = widget.departmentOrder.indexOf(a);
      final ib = widget.departmentOrder.indexOf(b);
      if (ia == -1 && ib == -1) return a.compareTo(b);
      if (ia == -1) return 1;
      if (ib == -1) return -1;
      return ia.compareTo(ib);
    });
    return {for (final k in keys) k: map[k]!};
  }

  double get _grandTotalHours =>
      _attendanceForSelectedDate.fold(0.0, (sum, a) => sum + a.hours);

  int get _grandTotalCount => _attendanceForSelectedDate.length;

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedByDepartment;
    final canGoPrev = !_selectedDate.isBefore(_firstDay.add(const Duration(days: 1)));
    final canGoNext = !_selectedDate.isAfter(_lastDay.subtract(const Duration(days: 1)));

    return Scaffold(
      appBar: AppBar(title: const Text('日別出勤状況')),
      body: SafeArea(
        child: Column(
          children: [
            // Date navigator
            Container(
              color: AppColors.primary,
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    onPressed: canGoPrev ? () => _changeDay(-1) : null,
                    disabledColor: Colors.white38,
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _dateLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.calendar_today,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ],
                            ),
                            if (_isToday)
                              Container(
                                margin: const EdgeInsets.only(top: 3),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  '今日',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                    onPressed: canGoNext ? () => _changeDay(1) : null,
                    disabledColor: Colors.white38,
                  ),
                ],
              ),
            ),
            // Grand total summary
            Container(
              width: double.infinity,
              color: AppColors.primaryDeep,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _summaryStat(Icons.groups, '$_grandTotalCount名', '出勤人数'),
                  Container(
                    width: 1,
                    height: 34,
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  _summaryStat(
                    Icons.schedule,
                    '${_grandTotalHours.toStringAsFixed(2)}h',
                    '合計労働時間',
                  ),
                ],
              ),
            ),
            Expanded(
              child: grouped.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_busy,
                            size: 48,
                            color: AppColors.inkMute.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'この日の出勤予定はありません',
                            style: TextStyle(color: AppColors.inkMute),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
                      children: [
                        for (final entry in grouped.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _departmentSection(entry.key, entry.value),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
        ),
      ],
    );
  }

  Widget _departmentSection(String department, List<_DayAttendance> list) {
    final subtotal = list.fold(0.0, (sum, a) => sum + a.hours);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    department,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDeep,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  '${list.length}名',
                  style: const TextStyle(
                    color: AppColors.inkSoft,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryDeep,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${subtotal.toStringAsFixed(2)}h',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < list.length; i++)
            _attendanceRow(list[i], isLast: i == list.length - 1),
        ],
      ),
    );
  }

  Widget _attendanceRow(_DayAttendance a, {required bool isLast}) {
    final accent = a.isPaidLeave ? AppColors.paidLeave : AppColors.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.line, width: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              a.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (a.entry.memo.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.sticky_note_2_outlined, size: 15, color: AppColors.success),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Text(
              a.isPaidLeave ? ShiftCode.paidLeaveCode : a.entry.code,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: a.isPaidLeave ? AppColors.paidLeave : AppColors.primaryDeep,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 62,
            child: Text(
              '${a.hours.toStringAsFixed(2)}h',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
