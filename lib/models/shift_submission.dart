import 'day_entry.dart';

/// Represents a full shift request submission from one employee
class ShiftSubmission {
  final String? id;
  final String name;
  final String department;
  final String targetMonth; // "YYYY-MM"
  final String monthMemo;
  final List<DayEntry> days;
  final double totalHours;
  final DateTime? submittedAt;

  /// Older submissions from the SAME person + department + target month,
  /// newest-first. This is populated client-side (by FirestoreService)
  /// when grouping raw Firestore docs - it is never written back to
  /// Firestore itself. Each entry in this list is a full historical
  /// ShiftSubmission (its own Firestore doc), so it can still be viewed
  /// or deleted individually via the normal detail screen.
  final List<ShiftSubmission> previousVersions;

  ShiftSubmission({
    this.id,
    required this.name,
    required this.department,
    required this.targetMonth,
    required this.monthMemo,
    required this.days,
    required this.totalHours,
    this.submittedAt,
    this.previousVersions = const [],
  });

  /// Total number of times this person submitted for this month
  /// (1 = first-time submission, 2+ = resubmitted).
  int get submissionCount => previousVersions.length + 1;

  bool get isResubmission => previousVersions.isNotEmpty;

  int get filledDaysCount =>
      days.where((d) => d.hours.isNotEmpty || d.code.isNotEmpty).length;

  int get memoCount => days.where((d) => d.memo.isNotEmpty).length;

  int get holidayCount => days.where((d) => d.isHoliday).length;

  Map<String, dynamic> toMap() => {
    'name': name,
    'department': department,
    'targetMonth': targetMonth,
    'monthMemo': monthMemo,
    'days': days.map((d) => d.toMap()).toList(),
    'totalHours': totalHours,
  };

  factory ShiftSubmission.fromMap(String id, Map<String, dynamic> map) {
    final rawDays = (map['days'] as List<dynamic>? ?? [])
        .map((d) => DayEntry.fromMap(Map<String, dynamic>.from(d as Map)))
        .toList();
    DateTime? submitted;
    final ts = map['submittedAt'];
    if (ts != null) {
      try {
        submitted = ts.toDate();
      } catch (_) {
        submitted = null;
      }
    }
    return ShiftSubmission(
      id: id,
      name: map['name']?.toString() ?? '',
      department: map['department']?.toString() ?? '',
      targetMonth: map['targetMonth']?.toString() ?? '',
      monthMemo: map['monthMemo']?.toString() ?? '',
      days: rawDays,
      totalHours: (map['totalHours'] is num)
          ? (map['totalHours'] as num).toDouble()
          : double.tryParse(map['totalHours']?.toString() ?? '0') ?? 0.0,
      submittedAt: submitted,
    );
  }
}
