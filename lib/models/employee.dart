/// Represents a registered employee (part-time staff) used to compute
/// who has NOT yet submitted their shift request for the target month.
/// This is a simple name+department roster maintained by the admin -
/// it is entirely separate from actual shift_submissions documents.
class Employee {
  final String name;
  final String department;

  Employee({required this.name, required this.department});

  Map<String, dynamic> toMap() => {'name': name, 'department': department};

  factory Employee.fromMap(Map<String, dynamic> map) => Employee(
    name: map['name']?.toString() ?? '',
    department: map['department']?.toString() ?? '',
  );

  /// Normalizes a name for "submitted vs not submitted" matching purposes.
  /// Removes all whitespace (half-width and full-width spaces/tabs) and
  /// lowercases the result, so that e.g. "山田 太郎" (with a space) and
  /// "山田太郎" (without) are treated as the same person. This prevents
  /// the unsubmitted-employee list from showing false positives just
  /// because the admin roster and the staff's own submission used
  /// slightly different spacing when typing the same name.
  static String normalizeName(String name) {
    return name.replaceAll(RegExp(r'[\s\u3000]+'), '').trim().toLowerCase();
  }
}
