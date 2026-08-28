import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 管理者向けアプリ内ヘルプ画面。
/// 管理者ダッシュボード・設定画面・月間シフト一覧表・日別出勤状況の
/// 使い方をまとめたガイド（アコーディオン形式）＋よくある質問で構成される。
class AdminHelpScreen extends StatelessWidget {
  const AdminHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('管理者向け使い方ガイド')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
          children: [
            _IntroCard(),
            const SizedBox(height: 20),
            const _SectionHeader(title: '基本の流れ', icon: Icons.map_outlined),
            const SizedBox(height: 8),
            _HelpTile(
              step: '1',
              title: 'まず「設定」で対象年月・部署・従業員名簿を用意する',
              body:
                  '右上の⚙️（設定）アイコンから開きます。ここで①対象年月 ②提出締切・案内文 ③部署一覧 '
                  '④休業日 ⑤管理者パスワード ⑥従業員名簿 をまとめて設定します。\n\n'
                  '毎月の運用では「①対象年月を今月／来月に進める」「④休業日を確認する」の2点だけ '
                  '見直せば十分なことが多いです。',
            ),
            _HelpTile(
              step: '2',
              title: 'パートさんにシフト希望を入力してもらう',
              body:
                  '設定を保存すると、パートさん側の入力画面に反映されます。あとはパートさんが各自の'
                  'スマホ・パソコンからシフト希望を入力し、「シフト送信」を押すだけです。\n\n'
                  '入力方法はパートさん向けの「使い方ガイド・ヘルプ」（アプリ内）にまとめてあります。',
            ),
            _HelpTile(
              step: '3',
              title: 'ダッシュボードで提出状況を確認する',
              body:
                  '管理者ダッシュボード（一番最初の画面）に、提出されたシフト希望が一覧表示されます。\n\n'
                  '・「今月のみ表示」：設定した対象年月の提出だけを表示\n'
                  '・「すべて表示」：過去分も含めた全提出を表示\n'
                  '・部署チップ（すべて／出庫／入庫…）をタップすると、その部署だけに絞り込めます\n'
                  '・「未提出者」バナーを開くと、まだ提出していない人の名前が分かります',
            ),
            _HelpTile(
              step: '4',
              title: '一覧表・出勤状況をチェックする',
              body:
                  '画面右下の2つのボタンから、それぞれの一覧画面に移動できます。\n\n'
                  '・「月間シフト一覧表」：全員分を1つの表（氏名×日付）にまとめて確認。右上のPDFアイコン'
                  'からA4横1ページのPDFに書き出して印刷できます\n'
                  '・「日別出勤状況」：1日ごとに「誰が出勤し、合計何時間か」を確認',
            ),
            _HelpTile(
              step: '5',
              title: '内容が確定したら「シフト配布」でパートさんに公開する',
              accentColor: AppColors.success,
              badge: _ColorBadge(
                label: '部署ごと',
                color: AppColors.success,
                bg: AppColors.success.withValues(alpha: 0.1),
              ),
              body:
                  '月間シフト一覧表の画面で部署タブを選び、右上の「シフト配布」ボタンを押すと、'
                  'その部署のパートさんが自分のシフト希望画面から一覧表を見られるようになります。\n\n'
                  '・配布は部署ごとに独立しています。他の部署のタブに切り替えて別々にON/OFFできます\n'
                  '・パートさんは自分の部署の一覧表しか見られません（他部署は見えません）\n'
                  '・パートさんがシフト希望画面を開いている間に配布すると、自動的に通知とバナーが'
                  '表示されます（画面の更新操作は不要ですが、アプリを閉じている間は届きません）\n'
                  '・配布後に内容を修正したい場合は、いったん配布をOFFにしてから編集し、'
                  '再度ONにするのがおすすめです',
            ),
            const SizedBox(height: 24),
            const _SectionHeader(
              title: 'ダッシュボード（提出一覧）',
              icon: Icons.dashboard_outlined,
            ),
            const SizedBox(height: 8),
            _HelpTile(
              step: 'A',
              title: '部署で絞り込む',
              body:
                  '画面上部のチップ（すべて／出庫／入庫／小分け／梱包／その他…）をタップすると、その部署の'
                  '提出だけが表示されます。数字は該当件数です。「すべて」を選んでいるときは部署ごとに'
                  'グループ分けして表示されます。',
            ),
            _HelpTile(
              step: 'B',
              title: '未提出者を確認する',
              body:
                  '対象年月を選んでいる（すべて表示ではない）ときに、提出済み・未提出の状況が'
                  'バナーで表示されます。緑色なら全員提出済み、赤色の場合はタップすると未提出者の'
                  '名前一覧が開きます。\n\n'
                  '※ 部署チップと連動しているので、部署を選ぶとその部署の未提出者だけが表示されます。',
            ),
            _HelpTile(
              step: 'C',
              title: '提出内容を見る・訂正する・削除する',
              body:
                  '一覧の各カードをタップすると、その人の提出内容（日ごとの記号・時間）の詳細画面が'
                  '開きます。そこから内容の確認や削除ができます。\n\n'
                  '再提出があった場合は「再提出 ○回目」というオレンジのバッジが付き、常に最新の内容が'
                  '優先されます（古い内容が消えるわけではなく履歴として残ります）。',
            ),
            const SizedBox(height: 24),
            const _SectionHeader(title: '設定画面', icon: Icons.settings_outlined),
            const SizedBox(height: 8),
            _HelpTile(
              step: '①',
              title: '対象年月',
              body:
                  'パートさんの入力画面に表示される「今回のシフト希望を出す月」です。月が変わったら'
                  '忘れずにここを次の月に進めてください（進めないと、いつまでも同じ月の希望を'
                  '入力する状態になります）。',
            ),
            _HelpTile(
              step: '②',
              title: '提出締切・案内文',
              body:
                  '締切日を設定すると、パートさんの画面に締切が表示されます。案内文には'
                  '「今月分は月末までに提出してください」のような一言メモを自由に入力できます'
                  '（空欄でも問題ありません）。',
            ),
            _HelpTile(
              step: '③',
              title: '部署一覧',
              body:
                  'テキストを入力して「追加」を押すと部署が増えます。チップの×で削除できます。\n\n'
                  'ここで登録した部署が、パートさん側の部署選択肢、管理者側の部署フィルタ、'
                  '従業員名簿の部署プルダウンすべてに反映されます。',
            ),
            _HelpTile(
              step: '④',
              title: '休業日カレンダー',
              body:
                  'カレンダーの日付をタップすると休業日として設定/解除できます（ピンク色＝休業日）。'
                  '休業日に設定した日は、パートさんの入力画面やシフト一覧表で見分けが付きやすく'
                  'なります。「全消去」で今まで設定した休業日を一括削除できます。',
            ),
            _HelpTile(
              step: '⑤',
              title: '管理者パスワード',
              accentColor: AppColors.primaryDeep,
              badge: _ColorBadge(
                label: '🔒 重要',
                color: AppColors.primaryDeep,
                bg: AppColors.primaryDeep.withValues(alpha: 0.1),
              ),
              body:
                  '管理者ログイン画面で入力するパスワードです。空欄のまま保存すると初期値'
                  '「shift2024」になります。第三者に見られないよう、分かりやすいパスワードは'
                  '避けて定期的に変更することをおすすめします。',
            ),
            _HelpTile(
              step: '⑥',
              title: '従業員名簿（未提出者チェック・PIN）',
              body:
                  'ここに登録した人が、ダッシュボードの「未提出者チェック」の対象になります。\n\n'
                  '・氏名と部署を入力して「従業員を追加」で登録\n'
                  '・追加すると自動でランダムな4桁PINが割り当てられます\n'
                  '・鍵アイコン🔒をタップするとPINの確認・再設定ができます（本人がPINを忘れた場合はここで確認）\n'
                  '・右端の「☰」を長押ししてドラッグすると並び順を変更でき、月間シフト一覧表・'
                  '日別出勤状況の表示順にも反映されます\n'
                  '・PINは、パートさんが自分の名前を初めて選んだ端末での本人確認に使われ、'
                  'なりすまし提出を防ぐための機能です\n\n'
                  '一覧の上部に部署チップ（すべて／出庫／入庫…）があり、タップするとその部署の'
                  '従業員だけに絞り込んで表示できます。人数が多い場合に見やすくするための'
                  '表示上の絞り込みなので、フィルタを変えてもデータが消えたり移動したりする'
                  'ことはありません。並び替え（ドラッグ）も、絞り込んだ部署内だけで行われ、'
                  '他の部署の順番には影響しません。',
            ),
            _HelpTile(
              step: '⑦',
              title: '設定を保存する',
              body:
                  '変更したら必ず画面下の「設定を保存」を押してください。保存を忘れると、'
                  'せっかく変更した内容がパートさん側に反映されません。',
              warn: true,
            ),
            const SizedBox(height: 24),
            const _SectionHeader(
              title: '月間シフト一覧表・PDF出力',
              icon: Icons.table_chart_outlined,
            ),
            const SizedBox(height: 8),
            _HelpTile(
              step: 'i',
              title: '一覧表の見方',
              body:
                  '縦に氏名、横に日付が並んだ表で、全員分のシフトを一目で確認できます。'
                  '右端には各自の出勤日数・合計時間、一番下には日ごとの合計時間が表示されます。\n\n'
                  '上部の部署タブで表示する部署を切り替えられます。',
            ),
            _HelpTile(
              step: 'ii',
              title: 'マスをタップして時間を手直しする',
              body:
                  '各セル（時間・記号が入っているマス）をタップすると、その場で時間や記号を'
                  '手入力で修正できます。パートさんからの申請後に、勤怠の実績に合わせて微調整'
                  'したいときに使います。修正するとその場ですぐに表・合計時間に反映されます。',
            ),
            _HelpTile(
              step: 'iii',
              title: 'メモ（緑の点）の確認',
              body:
                  'パートさんが入力時にメモを残したセルには、右上に小さな緑の点が付きます。'
                  'セルをタップするとメモの内容を確認できます。',
            ),
            _HelpTile(
              step: 'iv',
              title: '「備考」欄にメモを残す',
              body:
                  '表の下にある「備考」欄には、その部署・月に関する連絡事項を自由に入力できます。'
                  '入力するとFirestore（クラウド）に自動保存され、配布ONにするとパートさんにも'
                  '読み取り専用で表示されます。',
            ),
            _HelpTile(
              step: 'v',
              title: 'PDFに書き出して印刷する',
              body:
                  '画面右上のPDFアイコンをタップすると、画面の表がそのままA4横1ページの'
                  'PDFとして出力され、印刷プレビュー（またはPDF保存）画面が開きます。\n\n'
                  '何人・何日分のデータでも自動で1ページに収まるようにレイアウトされます。',
            ),
            _HelpTile(
              step: 'vi',
              title: 'モノクロ印刷でも見やすい配色',
              body:
                  'PDFの土日ヘッダーやシフト記号のセルは、モノクロ（白黒）プリンターで印刷しても'
                  'はっきり見えるよう、濃い背景色＋白文字で表示されるようになっています。',
            ),
            const SizedBox(height: 24),
            const _SectionHeader(title: '日別出勤状況', icon: Icons.today),
            const SizedBox(height: 8),
            _HelpTile(
              step: 'x',
              title: '特定の1日の出勤者を確認する',
              body:
                  '日付の前後移動ボタンやカレンダーアイコンで日付を選ぶと、その日に誰が出勤していて'
                  '合計何時間かが一覧表示されます。部署タブで絞り込むこともできます。急な欠員確認や'
                  '当日の人員把握に便利です。',
            ),
            const SizedBox(height: 24),
            const _SectionHeader(
              title: 'よくある質問（Q&A）',
              icon: Icons.help_outline,
            ),
            const SizedBox(height: 8),
            const _FaqTile(
              question: '月が変わったら何をすればいいですか？',
              answer:
                  '設定画面の「①対象年月」を次の月に進めて保存してください。必要であれば'
                  '「④休業日」も新しい月の分を設定しておくと、パートさんが入力する際の目安になります。',
            ),
            const _FaqTile(
              question: 'パートさんがPINを忘れたと言っています。',
              answer:
                  '設定画面の「⑥従業員名簿」から該当の人の鍵アイコン🔒をタップすると、現在のPINを'
                  '確認したり、新しいPINに再設定したりできます。',
            ),
            const _FaqTile(
              question: '部署を追加・削除するとどうなりますか？',
              answer:
                  '追加した部署は、パートさんの部署選択肢・管理者側の絞り込みチップ・従業員名簿の'
                  '部署プルダウンにすぐ反映されます。削除しても、すでに提出済みのデータや'
                  '登録済みの従業員情報が消えることはありません。',
            ),
            const _FaqTile(
              question: '設定を変更したのにパートさん側に反映されません。',
              answer:
                  '設定画面下部の「設定を保存」を押し忘れている可能性があります。変更後は必ず'
                  '保存ボタンを押してください。保存が成功すると画面が閉じ、「設定を保存しました」'
                  'と表示されます。',
            ),
            const _FaqTile(
              question: '再提出があった場合、古い内容はどうなりますか？',
              answer:
                  '古い内容が消えることはなく、履歴として残ります。一覧・一覧表・出勤状況には'
                  '常に最新の提出内容が反映されます。',
            ),
            const _FaqTile(
              question: '月間シフト一覧表のPDFが正しく開けません。',
              answer:
                  'ブラウザの印刷/PDF保存ダイアログがブロックされている可能性があります。'
                  'ポップアップブロックの解除、またはブラウザの再読み込み後にもう一度お試しください。',
            ),
            const _FaqTile(
              question: '未提出者バナーに、辞めた人の名前が出てきます。',
              answer:
                  '設定画面の「⑥従業員名簿」からその人を削除（×アイコン）してください。'
                  '削除しても過去の提出データ自体は残ります。',
            ),
            const _FaqTile(
              question: '管理者パスワードを変更したい／忘れました。',
              answer:
                  '設定画面の「⑤管理者パスワード」で新しいパスワードを入力し保存すれば'
                  '変更できます。忘れてしまった場合は、開発担当者にお問い合わせください。',
            ),
            const _FaqTile(
              question: '「シフト配布」は部署ごとに別々にON/OFFできますか？',
              answer:
                  'はい。月間シフト一覧表の部署タブを切り替えて、それぞれ独立して配布ON/OFFを'
                  '設定できます。ある部署だけ先に確定して配布し、別の部署はまだ調整中、といった'
                  '使い方が可能です。',
            ),
            const _FaqTile(
              question: 'パートさんは他の部署の一覧表も見えてしまいますか？',
              answer:
                  'いいえ。パートさんは自分が選択している部署のシフト一覧表しか見られません。'
                  '配布をONにした部署以外（および他の部署の一覧表）は表示されない仕組みです。',
            ),
            const _FaqTile(
              question: '配布した後にシフトの内容を間違えて修正したい場合は？',
              answer:
                  'マス（セル）をタップすればいつでも時間・記号を修正できます。配布中でも修正'
                  '内容はそのまま反映されますが、パートさんに気づかれにくい場合は、一度「配布」を'
                  'OFFにして修正後、再度ONにすると確実です。',
            ),
            const _FaqTile(
              question: 'パートさんに配布したことを気づいてもらえますか？',
              answer:
                  'パートさんがシフト希望の入力画面を開いている間に配布をONにすると、自動的に'
                  '通知（画面下部のメッセージ）とバナーが表示されます。ただし、パートさんが'
                  'アプリを閉じている間は通知が届かないため、確実に伝えたい場合は口頭やチャット'
                  'などでも一声かけることをおすすめします。',
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, color: AppColors.primaryDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '管理者側の使い方をまとめました。設定・提出確認・一覧表の操作に困ったときは'
              'このページをいつでも見返せます。',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryDeep, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _HelpTile extends StatelessWidget {
  final String step;
  final String title;
  final String body;
  final Color accentColor;
  final Widget? badge;
  final bool warn;

  const _HelpTile({
    required this.step,
    required this.title,
    required this.body,
    this.accentColor = AppColors.primary,
    this.badge,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: accentColor,
            child: Text(
              step,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 6), badge!],
            ],
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                body,
                style: const TextStyle(
                  color: AppColors.inkSoft,
                  height: 1.5,
                  fontSize: 13.5,
                ),
              ),
            ),
            if (warn) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '保存を押し忘れると変更内容はパートさん側に反映されません。必ず保存してください。',
                        style: TextStyle(fontSize: 12.5, color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColorBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _ColorBadge({
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: const Icon(
            Icons.chat_bubble_outline,
            color: AppColors.primaryDeep,
            size: 20,
          ),
          title: Text(
            'Q. $question',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: AppColors.primaryDeep,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'A. $answer',
                style: const TextStyle(
                  color: AppColors.inkSoft,
                  height: 1.5,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
