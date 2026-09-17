/// Represents a single day's shift entry in the calendar
class DayEntry {
  final String date; // "YYYY-MM-DD"
  final String dayOfWeek; // "日","月",...
  final bool isHoliday; // weekend or company holiday - disabled
  String hours; // e.g. "3.00" - normal worked hours (used by admin's
  // monthly shift matrix / total hours - NOT touched by the salary
  // calculator feature below, to avoid changing existing admin behavior).
  String code; // e.g. "E"
  String memo;

  /// User-entered number of hours for a paid-leave ('有') day, used ONLY
  /// by the personal salary calculator on the shift-request screen (see
  /// ShiftFormScreen). This is intentionally separate from [hours] so
  /// that paid-leave time can count toward the part-timer's own salary
  /// estimate without affecting the admin-facing total worked hours.
  String paidLeaveHours;

  /// Free-form start/end time ("HH:MM", 24h) entered via the dial-style
  /// time-range picker, for days that don't fit one of the fixed A~Y
  /// symbol codes. When both are non-empty, this day is shown with a
  /// distinct yellow highlight in the admin's monthly shift matrix (see
  /// MonthlyShiftMatrixScreen) so the exact requested time range can be
  /// checked at a glance instead of just a plain hour count. [hours] is
  /// still kept in sync (computed duration) so admin totals/exports
  /// continue to work unchanged; these two fields exist purely to
  /// preserve the human-readable time range for display.
  String customStartTime;
  String customEndTime;

  DayEntry({
    required this.date,
    required this.dayOfWeek,
    required this.isHoliday,
    this.hours = '',
    this.code = '',
    this.memo = '',
    this.paidLeaveHours = '',
    this.customStartTime = '',
    this.customEndTime = '',
  });

  int get day => int.parse(date.split('-')[2]);

  /// True once both a custom start and end time have been entered via
  /// the dial-style time-range picker (see [customStartTime]).
  bool get hasCustomTime => customStartTime.isNotEmpty && customEndTime.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'date': date,
    'dayOfWeek': dayOfWeek,
    'isHoliday': isHoliday,
    'hours': hours,
    'code': code,
    'memo': memo,
    'paidLeaveHours': paidLeaveHours,
    'customStartTime': customStartTime,
    'customEndTime': customEndTime,
  };

  factory DayEntry.fromMap(Map<String, dynamic> map) => DayEntry(
    date: map['date'] ?? '',
    dayOfWeek: map['dayOfWeek'] ?? '',
    isHoliday: map['isHoliday'] ?? false,
    hours: map['hours']?.toString() ?? '',
    code: map['code']?.toString() ?? '',
    memo: map['memo']?.toString() ?? '',
    paidLeaveHours: map['paidLeaveHours']?.toString() ?? '',
    customStartTime: map['customStartTime']?.toString() ?? '',
    customEndTime: map['customEndTime']?.toString() ?? '',
  );
}
