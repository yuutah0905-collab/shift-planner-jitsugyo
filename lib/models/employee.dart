/// Represents a registered employee (part-time staff) used to compute
/// who has NOT yet submitted their shift request for the target month.
/// This is a simple name+department roster maintained by the admin -
/// it is entirely separate from actual shift_submissions documents.
class Employee {
  final String name;
  final String department;

  /// 4-digit PIN used to confirm identity the first time this person
  /// selects their name on a new device (prevents someone else from
  /// picking their name and submitting on their behalf). Empty string
  /// means no PIN has been set yet by the admin - in that case staff can
  /// select the name without a PIN prompt (backward-compatible grace
  /// period until the admin sets one).
  final String pin;

  Employee({required this.name, required this.department, this.pin = ''});

  Map<String, dynamic> toMap() => {
    'name': name,
    'department': department,
    'pin': pin,
  };

  factory Employee.fromMap(Map<String, dynamic> map) => Employee(
    name: map['name']?.toString() ?? '',
    department: map['department']?.toString() ?? '',
    pin: map['pin']?.toString() ?? '',
  );

  /// Normalizes a name for "submitted vs not submitted" matching purposes.
  /// Converts half-width katakana to full-width katakana, removes all
  /// whitespace (half-width and full-width spaces/tabs), and lowercases
  /// the result, so that e.g. "山田 太郎" (with a space) and "山田太郎"
  /// (without) - or "ﾌｧﾝ ﾃｨ ﾎﾝ ｺﾞｯｸ" (half-width katakana) and
  /// "ファン ティホン ゴック" (full-width katakana) - are treated as the
  /// same person. This prevents the unsubmitted-employee list from
  /// showing false positives just because the admin roster and the
  /// staff's own submission used slightly different spacing or
  /// half-width/full-width character variants when typing the same name.
  static String normalizeName(String name) {
    final fullWidth = _toFullWidthKatakana(name);
    return fullWidth.replaceAll(RegExp(r'[\s\u3000]+'), '').trim().toLowerCase();
  }

  // Half-width katakana (U+FF61-FF9F) -> full-width katakana base mapping.
  static const Map<String, String> _halfToFullKatakana = {
    'ｦ': 'ヲ', 'ｧ': 'ァ', 'ｨ': 'ィ', 'ｩ': 'ゥ', 'ｪ': 'ェ', 'ｫ': 'ォ',
    'ｬ': 'ャ', 'ｭ': 'ュ', 'ｮ': 'ョ', 'ｯ': 'ッ', 'ｰ': 'ー',
    'ｱ': 'ア', 'ｲ': 'イ', 'ｳ': 'ウ', 'ｴ': 'エ', 'ｵ': 'オ',
    'ｶ': 'カ', 'ｷ': 'キ', 'ｸ': 'ク', 'ｹ': 'ケ', 'ｺ': 'コ',
    'ｻ': 'サ', 'ｼ': 'シ', 'ｽ': 'ス', 'ｾ': 'セ', 'ｿ': 'ソ',
    'ﾀ': 'タ', 'ﾁ': 'チ', 'ﾂ': 'ツ', 'ﾃ': 'テ', 'ﾄ': 'ト',
    'ﾅ': 'ナ', 'ﾆ': 'ニ', 'ﾇ': 'ヌ', 'ﾈ': 'ネ', 'ﾉ': 'ノ',
    'ﾊ': 'ハ', 'ﾋ': 'ヒ', 'ﾌ': 'フ', 'ﾍ': 'ヘ', 'ﾎ': 'ホ',
    'ﾏ': 'マ', 'ﾐ': 'ミ', 'ﾑ': 'ム', 'ﾒ': 'メ', 'ﾓ': 'モ',
    'ﾔ': 'ヤ', 'ﾕ': 'ユ', 'ﾖ': 'ヨ',
    'ﾗ': 'ラ', 'ﾘ': 'リ', 'ﾙ': 'ル', 'ﾚ': 'レ', 'ﾛ': 'ロ',
    'ﾜ': 'ワ', 'ﾝ': 'ン', 'ﾞ': '゛', 'ﾟ': '゜',
  };

  // Base full-width katakana -> voiced (dakuten) form.
  static const Map<String, String> _dakutenMap = {
    'カ': 'ガ', 'キ': 'ギ', 'ク': 'グ', 'ケ': 'ゲ', 'コ': 'ゴ',
    'サ': 'ザ', 'シ': 'ジ', 'ス': 'ズ', 'セ': 'ゼ', 'ソ': 'ゾ',
    'タ': 'ダ', 'チ': 'ヂ', 'ツ': 'ヅ', 'テ': 'デ', 'ト': 'ド',
    'ハ': 'バ', 'ヒ': 'ビ', 'フ': 'ブ', 'ヘ': 'ベ', 'ホ': 'ボ',
    'ウ': 'ヴ',
  };

  // Base full-width katakana -> semi-voiced (handakuten) form.
  static const Map<String, String> _handakutenMap = {
    'ハ': 'パ', 'ヒ': 'ピ', 'フ': 'プ', 'ヘ': 'ペ', 'ホ': 'ポ',
  };

  /// Converts half-width katakana characters (including trailing
  /// voiced/semi-voiced sound marks ﾞ/ﾟ) found in [input] to their
  /// full-width katakana equivalents. Any other characters (kanji,
  /// hiragana, already-full-width katakana, ascii, etc.) pass through
  /// unchanged.
  static String _toFullWidthKatakana(String input) {
    final chars = input.split('');
    final buffer = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      final full = _halfToFullKatakana[c];
      if (full == null) {
        buffer.write(c);
        continue;
      }
      if (i + 1 < chars.length) {
        final next = chars[i + 1];
        if (next == 'ﾞ' && _dakutenMap.containsKey(full)) {
          buffer.write(_dakutenMap[full]);
          i++;
          continue;
        } else if (next == 'ﾟ' && _handakutenMap.containsKey(full)) {
          buffer.write(_handakutenMap[full]);
          i++;
          continue;
        }
      }
      buffer.write(full);
    }
    return buffer.toString();
  }
}
