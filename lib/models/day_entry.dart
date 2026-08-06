/// Represents a single day's shift entry in the calendar
class DayEntry {
  final String date; // "YYYY-MM-DD"
  final String dayOfWeek; // "日","月",...
  final bool isHoliday; // weekend or company holiday - disabled
  String hours; // e.g. "3.00"
  String code; // e.g. "E"
  String memo;

  DayEntry({
    required this.date,
    required this.dayOfWeek,
    required this.isHoliday,
    this.hours = '',
    this.code = '',
    this.memo = '',
  });

  int get day => int.parse(date.split('-')[2]);

  Map<String, dynamic> toMap() => {
    'date': date,
    'dayOfWeek': dayOfWeek,
    'isHoliday': isHoliday,
    'hours': hours,
    'code': code,
    'memo': memo,
  };

  factory DayEntry.fromMap(Map<String, dynamic> map) => DayEntry(
    date: map['date'] ?? '',
    dayOfWeek: map['dayOfWeek'] ?? '',
    isHoliday: map['isHoliday'] ?? false,
    hours: map['hours']?.toString() ?? '',
    code: map['code']?.toString() ?? '',
    memo: map['memo']?.toString() ?? '',
  );
}
