/// Shift code to hours mapping (A~Y => 2.0h ~ 8.0h in 0.25h steps)
class ShiftCode {
  static const List<MapEntry<String, double>> codes = [
    MapEntry('A', 2.0),
    MapEntry('B', 2.25),
    MapEntry('C', 2.5),
    MapEntry('D', 2.75),
    MapEntry('E', 3.0),
    MapEntry('F', 3.25),
    MapEntry('G', 3.5),
    MapEntry('H', 3.75),
    MapEntry('I', 4.0),
    MapEntry('J', 4.25),
    MapEntry('K', 4.5),
    MapEntry('L', 4.75),
    MapEntry('M', 5.0),
    MapEntry('N', 5.25),
    MapEntry('O', 5.5),
    MapEntry('P', 5.75),
    MapEntry('Q', 6.0),
    MapEntry('R', 6.25),
    MapEntry('S', 6.5),
    MapEntry('T', 6.75),
    MapEntry('U', 7.0),
    MapEntry('V', 7.25),
    MapEntry('W', 7.5),
    MapEntry('X', 7.75),
    MapEntry('Y', 8.0),
  ];

  static final Map<String, double> codeToHours = Map.fromEntries(codes);

  static double? hoursForCode(String code) => codeToHours[code];

  static String labelFor(String code, double hours) =>
      '$code (${hours.toStringAsFixed(2)}h)';
}
