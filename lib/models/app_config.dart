/// Represents the app-wide configuration set by admin (app_settings/config)
class AppConfig {
  final String targetMonth; // "YYYY-MM"
  final List<String> holidays; // list of "YYYY-MM-DD"
  final String deadline; // "YYYY-MM-DD"
  final String notice;
  final List<String> departments;
  final String adminPassword;

  AppConfig({
    required this.targetMonth,
    required this.holidays,
    required this.deadline,
    required this.notice,
    required this.departments,
    required this.adminPassword,
  });

  factory AppConfig.fromMap(Map<String, dynamic> map) => AppConfig(
    targetMonth: map['targetMonth']?.toString() ?? '',
    holidays: (map['holidays'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList(),
    deadline: map['deadline']?.toString() ?? '',
    notice: map['notice']?.toString() ?? '',
    departments: (map['departments'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList(),
    adminPassword: map['adminPassword']?.toString() ?? '',
  );

  AppConfig copyWith({
    String? targetMonth,
    List<String>? holidays,
    String? deadline,
    String? notice,
    List<String>? departments,
    String? adminPassword,
  }) {
    return AppConfig(
      targetMonth: targetMonth ?? this.targetMonth,
      holidays: holidays ?? this.holidays,
      deadline: deadline ?? this.deadline,
      notice: notice ?? this.notice,
      departments: departments ?? this.departments,
      adminPassword: adminPassword ?? this.adminPassword,
    );
  }

  static AppConfig fallback() {
    final now = DateTime.now();
    final nextMonth = now.month == 12
        ? DateTime(now.year + 1, 1)
        : DateTime(now.year, now.month + 1);
    final ym =
        '${nextMonth.year.toString().padLeft(4, '0')}-${nextMonth.month.toString().padLeft(2, '0')}';
    return AppConfig(
      targetMonth: ym,
      holidays: [],
      deadline: '',
      notice: '',
      departments: ['出庫', '入庫', '小分け', '梱包', 'その他'],
      adminPassword: 'shift2024',
    );
  }
}
