// Generates a Japanese PDF manual for part-time staff (パートさん向け
// マニュアル), covering the shift-request screen end to end, including the
// newest features: hourly-wage / salary calculator (collapsible), the
// pre-submit confirmation dialog, and the version label + update-history
// screen.
//
// Run with:
//   dart run tool/generate_part_manual_pdf.dart
//
// Output: manuals/shift_planner_part_manual.pdf (repo-relative)

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> main() async {
  final regularFontData = await File(
    'assets/fonts/NotoSansJP-Regular.ttf',
  ).readAsBytes();
  final boldFontData = await File(
    'assets/fonts/NotoSansJP-Bold.ttf',
  ).readAsBytes();
  final regularFont = pw.Font.ttf(regularFontData.buffer.asByteData());
  final boldFont = pw.Font.ttf(boldFontData.buffer.asByteData());

  final logoBytes = await File(
    'assets/icon/jitsugyo_logo.png',
  ).readAsBytes();
  final logoImage = pw.MemoryImage(logoBytes);

  final theme = pw.ThemeData.withFont(base: regularFont, bold: boldFont);

  // Brand colors, matching the app's theme.
  final primary = PdfColor.fromInt(0xFFE94F86);
  final primaryDeep = PdfColor.fromInt(0xFFC4275F);
  final ink = PdfColor.fromInt(0xFF262425);
  final inkSoft = PdfColor.fromInt(0xFF55504F);
  final inkMute = PdfColor.fromInt(0xFF8A8586);
  final line = PdfColor.fromInt(0xFFD9D5D6);
  final background = PdfColor.fromInt(0xFFFAF7F8);
  final paidLeave = PdfColor.fromInt(0xFF3AA0C8);
  final paidLeaveBg = PdfColor.fromInt(0xFFE3F3FA);
  final success = PdfColor.fromInt(0xFF3FA654);
  final warnColor = PdfColor.fromInt(0xFFE08A2E);
  final warnBg = PdfColor.fromInt(0xFFFBF0E2);

  final doc = pw.Document(theme: theme);

  // ---------------------------------------------------------------------
  // Shared building blocks
  // ---------------------------------------------------------------------

  pw.Widget sectionHeader(String title, {PdfColor? color}) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 18, bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: color ?? primaryDeep, width: 1.4)),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          font: boldFont,
          fontSize: 15,
          color: color ?? primaryDeep,
        ),
      ),
    );
  }

  pw.Widget stepTile({
    required String step,
    required String title,
    required String body,
    PdfColor? accent,
    String? badgeLabel,
    PdfColor? badgeColor,
    PdfColor? badgeBg,
    bool warn = false,
  }) {
    final acc = accent ?? primary;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: line, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 20,
                height: 20,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: acc,
                  shape: pw.BoxShape.circle,
                ),
                child: pw.Text(
                  step,
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 10,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Text(
                  title,
                  style: pw.TextStyle(font: boldFont, fontSize: 12, color: ink),
                ),
              ),
              if (badgeLabel != null) ...[
                pw.SizedBox(width: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: badgeBg ?? PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(10),
                    border: pw.Border.all(color: badgeColor ?? acc, width: 0.8),
                  ),
                  child: pw.Text(
                    badgeLabel,
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 8.5,
                      color: badgeColor ?? acc,
                    ),
                  ),
                ),
              ],
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 28),
            child: pw.Text(
              body,
              style: pw.TextStyle(fontSize: 10.3, color: inkSoft, lineSpacing: 2.5),
            ),
          ),
          if (warn) ...[
            pw.SizedBox(height: 8),
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 28),
              child: pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: warnBg,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: warnColor, width: 0.6),
                ),
                child: pw.Text(
                  '⚠ 送信ボタンを押し忘れると内容は届きません。必ず最後まで進めてください。',
                  style: pw.TextStyle(fontSize: 9.5, color: ink),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget faqTile(String q, String a) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: line, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Q. $q',
            style: pw.TextStyle(font: boldFont, fontSize: 10.5, color: primaryDeep),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'A. $a',
            style: pw.TextStyle(fontSize: 10, color: inkSoft, lineSpacing: 2),
          ),
        ],
      ),
    );
  }

  pw.Widget headerBar(String pageTitle) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.7)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 22,
            height: 22,
            padding: const pw.EdgeInsets.all(2),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(4),
              border: pw.Border.all(color: line, width: 0.5),
            ),
            child: pw.Image(logoImage, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            'Shift Planner パートさん向けマニュアル',
            style: pw.TextStyle(font: boldFont, fontSize: 9, color: inkMute),
          ),
          pw.Spacer(),
          pw.Text(
            pageTitle,
            style: pw.TextStyle(fontSize: 9, color: inkMute),
          ),
        ],
      ),
    );
  }

  pw.Widget footerBar(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: line, width: 0.5)),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'Shift Planner（ver1.3）',
            style: pw.TextStyle(fontSize: 8, color: inkMute),
          ),
          pw.Spacer(),
          pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: inkMute),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Cover page
  // ---------------------------------------------------------------------
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(0),
      build: (context) {
        return pw.Stack(
          children: [
            pw.Positioned.fill(
              child: pw.Container(color: background),
            ),
            pw.Positioned.fill(
              child: pw.Container(
                margin: const pw.EdgeInsets.all(0),
                decoration: pw.BoxDecoration(
                  gradient: pw.LinearGradient(
                    begin: pw.Alignment.topLeft,
                    end: pw.Alignment.bottomRight,
                    colors: [primary, primaryDeep],
                  ),
                ),
                height: 260,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(48, 64, 48, 0),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 56,
                    height: 56,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(height: 28),
                  pw.Text(
                    'Shift Planner',
                    style: pw.TextStyle(font: boldFont, fontSize: 15, color: PdfColors.white),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'パートさん向け\nご利用マニュアル',
                    style: pw.TextStyle(font: boldFont, fontSize: 27, color: PdfColors.white, lineSpacing: 6),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'シフト希望の入力から、給料の見積り確認まで',
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.white),
                  ),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(48, 300, 48, 48),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'この一冊でわかること',
                    style: pw.TextStyle(font: boldFont, fontSize: 13, color: ink),
                  ),
                  pw.SizedBox(height: 14),
                  _CoverItem(text: '氏名・部署の登録とPIN確認のしかた', icon: '①', color: primary, boldFont: boldFont, ink: ink),
                  _CoverItem(text: 'シフト希望の入力・一括入力・送信のしかた', icon: '②', color: primary, boldFont: boldFont, ink: ink),
                  _CoverItem(text: '有給休暇の入力方法', icon: '③', color: paidLeave, boldFont: boldFont, ink: ink),
                  _CoverItem(text: '【新機能】自分の給料計算（時給・見積り給料）', icon: '④', color: primaryDeep, boldFont: boldFont, ink: ink),
                  _CoverItem(text: '確定したシフト一覧表の見方', icon: '⑤', color: success, boldFont: boldFont, ink: ink),
                  _CoverItem(text: 'バージョン表示・アップデート情報の見方', icon: '⑥', color: inkMute, boldFont: boldFont, ink: ink),
                  _CoverItem(text: 'よくある質問（Q&A）', icon: '⑦', color: inkMute, boldFont: boldFont, ink: ink),
                  pw.Spacer(),
                  pw.Divider(color: line),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    '対応バージョン：ver1.3',
                    style: pw.TextStyle(fontSize: 9.5, color: inkMute),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  // ---------------------------------------------------------------------
  // Page: 基本情報の入力（氏名・部署・PIN）
  // ---------------------------------------------------------------------
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            headerBar('基本情報の入力'),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFFDEEF3),
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: primary, width: 0.6),
              ),
              child: pw.Text(
                'POINT　シフト希望の入力方法をこの1冊にまとめました。困ったときはいつでも見返してください。',
                style: pw.TextStyle(font: boldFont, fontSize: 10.5, color: ink, lineSpacing: 2),
              ),
            ),
            sectionHeader('シフト希望の出し方（基本の流れ）'),
            stepTile(
              step: '1',
              title: '氏名・部署を入力する',
              body:
                  '画面上部の「基本情報」の名前欄をタップすると、名簿から自分の名前を選べます。同じ氏名・部署で送信すると、次回以降も同じ人として認識されます。',
            ),
            stepTile(
              step: '2',
              title: '（初回のみ）本人確認のPINを入力する',
              accent: primaryDeep,
              badgeLabel: '鍵 初回のみ',
              badgeColor: primaryDeep,
              badgeBg: PdfColor.fromInt(0xFFFCE9EF),
              body:
                  '名簿から名前を選んだときに、名前の横に鍵マークが付いている場合はPIN（4桁の確認番号）の入力が求められます。\n'
                  '・自分になりすまして他の人が名前を選んで提出することを防ぐための機能です\n'
                  '・正しいPINを入力すれば、その端末（今使っているスマホ・パソコン）では次回から二度と聞かれません\n'
                  '・月が変わって新しいシフト希望を出すときも、同じ端末であればPINの再入力は不要です\n'
                  '・PINが分からない場合は、管理者に確認してください',
            ),
            stepTile(
              step: '3',
              title: '希望日をタップする',
              body: 'カレンダーの入力したい日付をタップすると、記号（勤務コード）を選ぶ画面が開きます。',
            ),
            stepTile(
              step: '4',
              title: '勤務コードを選ぶ',
              body: '記号（A〜Y）を選ぶと、労働時間が自動で入力されます。時間やメモを追加で入力することもできます。',
            ),
            stepTile(
              step: '5',
              title: '有給休暇を入力する',
              accent: paidLeave,
              badgeLabel: '有',
              badgeColor: paidLeave,
              badgeBg: paidLeaveBg,
              body:
                  '記号の選択肢から「有（有給休暇）」を選ぶと、通常勤務（ピンク色）と区別できるよう、カレンダー上に水色のバッジで表示されます。\n'
                  'さらに「有」を選ぶと、その場で有給の時間（例：8時間）を自分で入力できます。ここで入力した時間は、次のページで説明する「自分の給料計算」に自動的に反映されます。',
            ),
            stepTile(
              step: '6',
              title: '複数日をまとめて入力する（一括入力）',
              body:
                  '毎週同じ曜日は同じ勤務、というときに便利な機能です。\n'
                  '① 画面上部の「一括入力」スイッチをONにする\n'
                  '② 同じ内容にしたい日付を次々にタップして選ぶ\n'
                  '③ 選び終わったら、上部に表示される「（日数）日に適用」ボタンをタップ\n'
                  '④ 開いたシートで記号（時間）を選び「適用」を押すと、選んだ日すべてに反映されます',
            ),
            footerBar(context),
          ],
        );
      },
    ),
  );

  // ---------------------------------------------------------------------
  // Page: 送信・確認ダイアログ
  // ---------------------------------------------------------------------
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            headerBar('送信のしかた'),
            sectionHeader('入力が終わったら送信する'),
            stepTile(
              step: '7',
              title: '「シフト送信」ボタンをタップする',
              body:
                  '画面下部の「シフト送信」ボタンをタップします。\n'
                  '【新機能】タップすると「シフトを送信しますか？」という確認画面が表示されるようになりました。氏名・部署・対象月を確認し、間違いなければ「送信する」をタップしてください。誤って別の場所をタップしてしまっても、この確認画面があるので安心です。「キャンセル」を押せば送信されずに戻れます。',
              warn: true,
            ),
            stepTile(
              step: '8',
              title: '送信完了メッセージを確認する',
              accent: success,
              body: '送信が成功すると「送信完了」というメッセージが表示されます。これで管理者にシフト希望が届きました。',
            ),
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 4),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: warnBg,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: warnColor, width: 0.6),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('⚠', style: pw.TextStyle(fontSize: 12, color: warnColor)),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Text(
                      '一度送信した後に内容を間違えていたことに気づいた場合は、もう一度同じ氏名・部署で入力し直し、再度「シフト送信」を押してください。自動的に「再提出」として記録され、最新の内容が優先されます。以前の内容も履歴として残るので消えてしまう心配はありません。',
                      style: pw.TextStyle(fontSize: 9.7, color: ink, lineSpacing: 2),
                    ),
                  ),
                ],
              ),
            ),
            sectionHeader('確定したシフトを確認する', color: success),
            stepTile(
              step: '表',
              title: '「月間シフト一覧表を見る」バナーが出たら',
              accent: success,
              body:
                  '管理者が自分の部署のシフトを確定して配布すると、画面上部に緑色のバナー「シフトが確定しました。月間シフト一覧表を見る」が表示されます。タップすると、自分の部署の全員分のシフトが1つの表で確認できます。\n'
                  '・確認できるのは自分の部署の分だけです（他の部署の一覧表は見られません）\n'
                  '・表の下部に管理者からの「備考」欄が表示されている場合があります（連絡事項など）',
            ),
            stepTile(
              step: '鈴',
              title: '配布された瞬間に通知でお知らせ',
              accent: success,
              body:
                  'この画面（シフト希望の入力画面）を開いたままにしていると、管理者が配布した瞬間に画面下部に通知（メッセージ）が表示され、バナーも自動的に現れます。画面を下に引っ張って更新する必要はありません。\n'
                  '※ アプリを閉じている間は通知が届きません。配布されたかどうかは、この画面を開いたときにバナーが出ているかどうかで確認してください。',
            ),
            footerBar(context),
          ],
        );
      },
    ),
  );

  // ---------------------------------------------------------------------
  // Page: 自分の給料計算（新機能特集ページ）
  // ---------------------------------------------------------------------
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            headerBar('新機能：自分の給料計算'),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const pw.EdgeInsets.only(top: 8, bottom: 12),
              decoration: pw.BoxDecoration(
                gradient: pw.LinearGradient(colors: [primary, primaryDeep]),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Row(
                children: [
                  pw.Text('NEW', style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.white)),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Text(
                      '自分の給料計算 — 時給を入力するだけで、今月のおおよその給料が自動でわかります',
                      style: pw.TextStyle(font: boldFont, fontSize: 11.5, color: PdfColors.white, lineSpacing: 2),
                    ),
                  ),
                ],
              ),
            ),
            stepTile(
              step: '①',
              title: 'カードをタップして開く（▽マーク）',
              body:
                  '入力画面を下にスクロールすると「自分の給料計算（任意）」というカードがあります。最初は閉じた状態（▽マーク）になっています。タップすると開き、画面が自動で見やすい位置までスクロールします。もう一度タップすれば閉じられます（▲マークに変わります）。',
            ),
            stepTile(
              step: '②',
              title: '時給を入力する',
              body: '「時給」の欄に、自分の時給（円）を入力します。例：1200 と入力すると「1200円」として計算されます。',
            ),
            stepTile(
              step: '③',
              title: '対象時間・見積り給料が自動で表示される',
              accent: primaryDeep,
              body:
                  '入力した時給 × 今月の希望時間（通常勤務＋有給休暇の時間）で、今月のおおよその給料が自動的に計算されます。\n'
                  '「対象時間（労働＋有給）」には、入力済みの勤務時間と、有給の日に入力した時間の合計が表示されます。\n'
                  '「今月の給料（見積り）」には、時給 × 対象時間で計算された金額が大きく表示されます。',
            ),
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: background,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: line, width: 0.7),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Text('対象時間（労働＋有給）', style: pw.TextStyle(fontSize: 10, color: inkMute)),
                      pw.Spacer(),
                      pw.Text('32.50 h', style: pw.TextStyle(font: boldFont, fontSize: 11, color: ink)),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    children: [
                      pw.Text('今月の給料（見積り）', style: pw.TextStyle(font: boldFont, fontSize: 11, color: primaryDeep)),
                      pw.Spacer(),
                      pw.Text('39,000 円', style: pw.TextStyle(font: boldFont, fontSize: 16, color: primaryDeep)),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('（イメージ：時給1,200円 × 32.5時間の場合）', style: pw.TextStyle(fontSize: 8.5, color: inkMute)),
                ],
              ),
            ),
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 4),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFEFF7EF),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: success, width: 0.6),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('鍵', style: pw.TextStyle(font: boldFont, fontSize: 11, color: success)),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Text(
                      'ここで入力した時給は、あなたが今使っている端末（スマホ・パソコン）にのみ保存されます。管理者に送信されることはなく、他の誰にも見られません。安心してご利用ください。',
                      style: pw.TextStyle(fontSize: 9.7, color: ink, lineSpacing: 2),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '※ 有給（有）の日は、日付をタップして時間を入力すると給料計算に含まれます。\n'
              '※ この機能は普段は閉じた状態なので、他の人に画面を見せても給料情報は表示されません。',
              style: pw.TextStyle(fontSize: 9, color: inkMute, lineSpacing: 2),
            ),
            footerBar(context),
          ],
        );
      },
    ),
  );

  // ---------------------------------------------------------------------
  // Page: バージョン表示・アップデート情報
  // ---------------------------------------------------------------------
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            headerBar('バージョン表示・アップデート情報'),
            sectionHeader('アプリのバージョンを確認する', color: inkMute),
            stepTile(
              step: 'V',
              title: '画面上部にバージョンが表示されています',
              accent: inkMute,
              body:
                  '画面タイトルの下に、小さく「ver1.3」のようにバージョン番号が表示されています。アプリが更新されるたびに、この番号が上がっていきます（例：ver1.3 → ver1.4）。目立たない表示なので、気にせず普段通り使って大丈夫です。',
            ),
            stepTile(
              step: 'NEW',
              title: '新しいアップデートがあると「NEW」マークが出る',
              accent: primaryDeep,
              badgeLabel: 'NEW',
              badgeColor: PdfColors.white,
              badgeBg: PdfColor.fromInt(0xFFE0455A),
              body:
                  'アプリが更新され、まだ確認していない新しいバージョンがある場合、バージョン表示の横に赤い「NEW」マークが表示されます。見た人がすぐに「何か変わった」と気づけるようにするための表示です。',
            ),
            stepTile(
              step: 'i',
              title: 'タップするとアップデート内容が見られる',
              body:
                  'バージョン表示（「ver1.3」の部分）をタップすると、「アップデート情報」画面が開き、いつ・どんな機能が追加・修正されたのかを一覧で確認できます。確認すると「NEW」マークは自動的に消えます。',
            ),
            sectionHeader('よくある質問（Q&A）'),
            faqTile(
              '有給休暇を取りたい日はどう入力すればいいですか？',
              '該当の日をタップし、勤務コードの選択肢から「有給休暇」を選んでください。その場で有給の時間も入力できます。カレンダー上に水色のバッジで表示され、通常勤務（ピンク色）と区別できます。入力した時間は「自分の給料計算」に反映されます。',
            ),
            faqTile(
              '何日も同じ内容を入力するのが大変です。',
              '「一括入力」機能をご利用ください。一括入力モードをONにして複数の日を選び、まとめて同じ勤務コード・時間を設定できます。',
            ),
            faqTile(
              '入力した内容はどこかに保存されますか？',
              '入力内容は端末に自動的に保存され、アプリを閉じても消えません。次にアプリを開いたときも、続きから入力・確認ができます。',
            ),
            faqTile(
              '名前を選んだらPIN（4桁の番号）を聞かれました。何を入力すればいいですか？',
              '本人確認のための4桁のPINです。管理者が名簿にあなたの名前を登録した際に設定されています。PINが分からない場合は、管理者に確認してください。',
            ),
            faqTile(
              '毎回シフトを提出するたびにPINを入力しないといけませんか？',
              'いいえ。一度正しいPINを入力すると、その端末では確認済みとして記録され、次回からは聞かれません。月が変わって新しいシフト希望を出す場合も、同じ端末であれば再入力は不要です。',
            ),
            footerBar(context),
          ],
        );
      },
    ),
  );

  // ---------------------------------------------------------------------
  // Page: よくある質問（続き）
  // ---------------------------------------------------------------------
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            headerBar('よくある質問（つづき）'),
            sectionHeader('よくある質問（Q&A）つづき'),
            faqTile(
              '一度送信した後に、内容を間違えていたことに気づきました。',
              'もう一度同じ氏名・部署で入力し直し、再度「シフト送信」を押してください。自動的に「再提出」として記録され、最新の内容が優先されます。以前の内容も履歴として残るので消えてしまう心配はありません。',
            ),
            faqTile(
              '別のスマホやパソコンから提出したら、またPINを聞かれました。',
              'PINの確認は端末ごとに記録されるため、初めて使う端末（新しいスマホや別のパソコン、ブラウザのデータを消去した場合など）では、その端末で改めてPINの入力が必要になります。一度入力すれば、その端末では以降不要になります。',
            ),
            faqTile(
              '名前の横に鍵マークが付いていないのはなぜですか？',
              '鍵マークは管理者がその人にPINを設定している場合に表示されます。マークが付いていない場合はPINの入力なしで名前を選べます。',
            ),
            faqTile(
              '「月間シフト一覧表を見る」バナーが出てきません。',
              '管理者がまだあなたの部署のシフトを配布していない可能性があります。部署は正しく選択されているか確認のうえ、しばらく待ってから確認してください。管理者に配布済みか直接確認するのも確実です。',
            ),
            faqTile(
              '他の部署のシフト一覧表も見られますか？',
              'いいえ。一覧表で確認できるのは、自分が選択している部署のシフトのみです。他の部署のシフトは表示されません。',
            ),
            faqTile(
              'アプリを閉じていても配布の通知は届きますか？',
              '現在は、シフト希望の入力画面を開いている間のみ通知（画面下部のメッセージとバナー）が表示される仕組みです。アプリを閉じている間は通知が届きませんので、画面を開いたときにバナーが出ているかどうかで配布状況を確認してください。',
            ),
            faqTile(
              '給料の見積りは実際の給料と完全に一致しますか？',
              'いいえ、あくまで「見積り」です。実際の給料は勤怠実績や会社の計算方法（残業・deduction等）により異なる場合があります。目安としてご利用ください。',
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: background,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: line, width: 0.7),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('その他、わからないことがあれば', style: pw.TextStyle(font: boldFont, fontSize: 11, color: ink)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'アプリ内の画面右上「？」アイコン（使い方ガイド・ヘルプ）でも同じ内容をいつでも確認できます。それでも解決しない場合は、管理者にお問い合わせください。',
                    style: pw.TextStyle(fontSize: 9.7, color: inkSoft, lineSpacing: 2),
                  ),
                ],
              ),
            ),
            footerBar(context),
          ],
        );
      },
    ),
  );

  final outputDir = Directory('manuals');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }
  final outputFile = File('manuals/shift_planner_part_manual.pdf');
  await outputFile.writeAsBytes(await doc.save());
  // ignore: avoid_print
  print('PDF generated: ${outputFile.path}');
}

class _CoverItem extends pw.StatelessWidget {
  final String text;
  final String icon;
  final PdfColor color;
  final pw.Font boldFont;
  final PdfColor ink;

  _CoverItem({
    required this.text,
    required this.icon,
    required this.color,
    required this.boldFont,
    required this.ink,
  });

  @override
  pw.Widget build(pw.Context context) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 22,
            height: 22,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
            child: pw.Text(
              icon,
              style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.white),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Text(text, style: pw.TextStyle(fontSize: 11, color: ink)),
          ),
        ],
      ),
    );
  }
}
