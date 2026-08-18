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
}
