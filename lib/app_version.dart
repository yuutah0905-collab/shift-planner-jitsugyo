/// Central place to track the app's version number and update history.
///
/// VERSIONING RULE:
/// Bump by +0.1 on every deploy that includes a user-facing change, no
/// matter how small (bug fix or new feature) - treating the version as
/// a simple decimal counter: 1.0 -> 1.1 -> 1.2 -> ... -> 1.8 -> 1.9 ->
/// 2.0 -> 2.1 -> ... (i.e. after .9 the whole-number part increments and
/// the decimal resets to .0, just like an odometer - NOT 1.10). This
/// keeps the rule simple and predictable for everyone: "the number goes
/// up = something changed".
///
/// HOW TO USE (for future updates):
/// Every time a new feature/fix is deployed to production, bump
/// [currentVersion] by +0.1 (with odometer-style rollover per the rule
/// above - e.g. 1.9 -> 2.0, not 1.10) and add a new [UpdateEntry] at the
/// TOP of [updateHistory] (newest first) describing what changed and
/// the date.
///
/// This is intentionally a plain Dart file (not fetched from Firestore)
/// since version history is the same for everyone and doesn't need to be
/// editable by admins - it's tied 1:1 to each deployed build.
class UpdateEntry {
  final String version;
  final String date; // "YYYY-MM-DD"
  final List<String> notes;

  const UpdateEntry({
    required this.version,
    required this.date,
    required this.notes,
  });
}

class AppVersion {
  /// The current app version shown in the shift-request screen and at
  /// the top of the update history list. Bump this on every deploy that
  /// includes a user-facing change.
  static const String currentVersion = '1.7';

  /// Newest first. The very first entry (v1.0) marks the state of the
  /// app at the point this versioning system was introduced.
  static const List<UpdateEntry> updateHistory = [
    UpdateEntry(
      version: '1.7',
      date: '2026-09-01',
      notes: [
        'iPhone（Safari）で、部署や人マークなどのボタンをタップしても反応しない（少し上を押さないと反応しない）不具合を修正しました',
      ],
    ),
    UpdateEntry(
      version: '1.6',
      date: '2026-09-01',
      notes: [
        '有給休暇を取り消した際に、給料計算の時間が残ってしまう不具合を修正しました',
        '（有給ではない日の時間が、給料計算に誤って含まれないようにしました）',
      ],
    ),
    UpdateEntry(
      version: '1.5',
      date: '2026-08-31',
      notes: [
        '月間シフト一覧表を、配布したまま自動で最新の内容に更新されるようにしました',
        '（管理者がシフトを修正しても、一旦配布を停止して再配布する必要がなくなりました）',
      ],
    ),
    UpdateEntry(
      version: '1.4',
      date: '2026-08-31',
      notes: ['有給休暇の時間入力を、シフト希望と同じA〜Yの記号選択方式に変更しました（手入力は不要になりました）'],
    ),
    UpdateEntry(
      version: '1.3',
      date: '2026-08-29',
      notes: [
        '自分の給料計算を、タップで開閉できるようにしました（▽▲マークをタップ）',
        '普段は閉じた状態なので、画面を人に見せても給料情報が表示されません',
      ],
    ),
    UpdateEntry(
      version: '1.2',
      date: '2026-08-29',
      notes: ['バージョン表示の文字が見切れる不具合を修正しました（今回で完全に直りました）'],
    ),
    UpdateEntry(
      version: '1.1',
      date: '2026-08-29',
      notes: [
        'バージョン表示を「v」から「ver」表記に変更しました',
        '新しいバージョンが出た時に気づけるよう「NEW」マークを追加しました',
      ],
    ),
    UpdateEntry(
      version: '1.0',
      date: '2026-08-29',
      notes: [
        'バージョン表示・アップデート情報画面を追加しました',
        'アプリの更新が反映されにくい問題を修正しました（キャッシュの不具合）',
        'シフト送信前に確認ダイアログを追加しました（誤送信防止）',
        '自分の給料計算機能を追加しました（時給を入力すると自動で給料を計算・保存できます）',
        '有給休暇の時間を入力できるようにしました（給料計算に反映されます）',
        '従業員名簿を部署ごとに絞り込んで表示できるようにしました（管理画面）',
        '部署ごとに「シフト配布」ボタンを分けました（部署ごとに管理者が違う場合に対応）',
        'シフトが配布された瞬間に通知が届くようにしました（画面を開いている場合）',
        'パートさん・管理者向けのヘルプガイドを更新しました',
      ],
    ),
  ];
}
