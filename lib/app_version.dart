/// Central place to track the app's version number and update history.
///
/// HOW TO USE (for future updates):
/// Every time a new feature/fix is deployed to production, bump
/// [currentVersion] and add a new [UpdateEntry] at the TOP of
/// [updateHistory] (newest first) describing what changed and the date.
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
  static const String currentVersion = '1.0';

  /// Newest first. The very first entry (v1.0) marks the state of the
  /// app at the point this versioning system was introduced.
  static const List<UpdateEntry> updateHistory = [
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
