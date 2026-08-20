import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// パートさん向けのアプリ内ヘルプ画面。
/// 使い方ガイド（アコーディオン形式）＋よくある質問で構成される。
/// PDFマニュアルの内容をアプリ内でいつでも参照できるようにしたもの。
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使い方ガイド・ヘルプ')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
          children: [
            _IntroCard(),
            const SizedBox(height: 20),
            const _SectionHeader(title: 'シフト希望の出し方', icon: Icons.event_note),
            const SizedBox(height: 8),
            _HelpTile(
              step: '1',
              title: '氏名・部署を入力する',
              body:
                  '画面上部の「基本情報」の名前欄をタップすると、名簿から自分の名前を選べます。同じ氏名・部署で送信すると、次回以降も同じ人として認識されます。',
            ),
            _HelpTile(
              step: '2',
              title: '（初回のみ）本人確認のPINを入力する',
              accentColor: AppColors.primaryDeep,
              badge: _ColorBadge(
                label: '🔒 初回のみ',
                color: AppColors.primaryDeep,
                bg: AppColors.primaryDeep.withValues(alpha: 0.1),
              ),
              body:
                  '名簿から名前を選んだときに、名前の横に🔒マークが付いている場合はPIN（4桁の確認番号）の入力が求められます。\n\n'
                  '・自分になりすまして他の人が名前を選んで提出することを防ぐための機能です\n'
                  '・正しいPINを入力すれば、その端末（今使っているスマホ・パソコン）では次回から二度と聞かれません\n'
                  '・月が変わって新しいシフト希望を出すときも、同じ端末であればPINの再入力は不要です\n'
                  '・PINが分からない場合は、管理者に確認してください（管理者側の設定画面で確認・再設定できます）',
            ),
            _HelpTile(
              step: '3',
              title: '希望日をタップする',
              body: 'カレンダーの入力したい日付をタップすると、記号（勤務コード）を選ぶ画面が開きます。',
            ),
            _HelpTile(
              step: '4',
              title: '勤務コードを選ぶ',
              body: '記号（A〜Y）を選ぶと、労働時間が自動で入力されます。時間やメモを追加で入力することもできます。',
            ),
            _HelpTile(
              step: '5',
              title: '有給休暇を入力する',
              accentColor: AppColors.paidLeave,
              body:
                  '記号の選択肢から「有（有給休暇）」を選ぶと、通常勤務（ピンク色）と区別できるよう、カレンダー上に水色のバッジで表示されます。',
              badge: const _ColorBadge(
                label: '有',
                color: AppColors.paidLeave,
                bg: AppColors.paidLeaveBg,
              ),
            ),
            _HelpTile(
              step: '6',
              title: '複数日をまとめて入力する（一括入力）',
              body:
                  '毎週同じ曜日は同じ勤務、というときに便利な機能です。\n\n'
                  '① 画面上部の「一括入力」スイッチをONにする\n'
                  '② 同じ内容にしたい日付を次々にタップして選ぶ\n'
                  '③ 選び終わったら、上部に表示される「（日数）日に適用」ボタンをタップ\n'
                  '④ 開いたシートで記号（時間）を選び「適用」を押すと、選んだ日すべてに反映されます',
            ),
            _HelpTile(
              step: '7',
              title: '入力が終わったら送信する',
              body:
                  '画面下部の「シフト送信」ボタンをタップして完了です。送信が成功すると「送信完了」というメッセージが表示されます。\n\n'
                  '送信ボタンを押し忘れると、内容は管理者に届きません。必ず最後まで進めてください。',
              warn: true,
            ),
            const SizedBox(height: 24),
            const _SectionHeader(
              title: 'よくある質問（Q&A）',
              icon: Icons.help_outline,
            ),
            const SizedBox(height: 8),
            const _FaqTile(
              question: '一度送信した後に、内容を間違えていたことに気づきました。',
              answer:
                  'もう一度同じ氏名・部署で入力し直し、再度「シフト送信」を押してください。自動的に「再提出」として記録され、最新の内容が優先されます。以前の内容も履歴として残るので消えてしまう心配はありません。',
            ),
            const _FaqTile(
              question: '有給休暇を取りたい日はどう入力すればいいですか？',
              answer:
                  '該当の日をタップし、勤務コードの選択肢から「有給休暇」を選んでください。カレンダー上に水色のバッジで表示され、通常勤務（ピンク色）と区別できます。',
            ),
            const _FaqTile(
              question: '何日も同じ内容を入力するのが大変です。',
              answer:
                  '「一括入力」機能をご利用ください。一括入力モードをONにして複数の日を選び、まとめて同じ勤務コード・時間を設定できます。',
            ),
            const _FaqTile(
              question: '入力した内容はどこかに保存されますか？',
              answer:
                  '入力内容は端末に自動的に保存され、アプリを閉じても消えません。次にアプリを開いたときも、続きから入力・確認ができます。',
            ),
            const _FaqTile(
              question: '名前を選んだらPIN（4桁の番号）を聞かれました。何を入力すればいいですか？',
              answer:
                  '本人確認のための4桁のPINです。管理者が名簿にあなたの名前を登録した際に設定されています。PINが分からない場合は、管理者に確認してください（管理者側の設定画面で確認・再設定できます）。',
            ),
            const _FaqTile(
              question: '毎回シフトを提出するたびにPINを入力しないといけませんか？',
              answer:
                  'いいえ。一度正しいPINを入力すると、その端末（今使っているスマホ・パソコン・ブラウザ）では確認済みとして記録され、次回からは聞かれません。月が変わって新しいシフト希望を出す場合も、同じ端末であれば再入力は不要です。',
            ),
            const _FaqTile(
              question: '別のスマホやパソコンから提出したら、またPINを聞かれました。',
              answer:
                  'PINの確認は端末ごとに記録されるため、初めて使う端末（新しいスマホや別のパソコン、ブラウザのデータを消去した場合など）では、その端末で改めてPINの入力が必要になります。一度入力すれば、その端末では以降不要になります。',
            ),
            const _FaqTile(
              question: '名前の横に🔒マークが付いていないのはなぜですか？',
              answer:
                  '🔒マークは管理者がその人にPINを設定している場合に表示されます。マークが付いていない場合はPINの入力なしで名前を選べます。',
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
              'シフト希望の入力方法をまとめました。困ったときはこのページをいつでも見返せます。',
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
                        '送信ボタンを押し忘れると内容は届きません。必ず最後まで進めてください。',
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
