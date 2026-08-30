# shift_planner

A new Flutter project.

## デプロイ手順（本番反映）

**必ず `scripts/deploy.sh` 経由でデプロイすること。** `flutter build web` と
`wrangler pages deploy` を手動で個別に実行しない（キャッシュ自動更新の
仕組みが壊れるため。詳細は `scripts/deploy.sh` 内のコメント参照）。

```bash
export CLOUDFLARE_API_TOKEN="cfut_..."
bash scripts/deploy.sh
```

このスクリプトが自動で行うこと（順番厳守）:
1. `flutter build web --release`
2. `scripts/inject_build_ts.sh`（キャッシュ自動更新用のビルドIDを埋め込む）
3. `wrangler pages deploy build/web`

ユーザー向けの機能変更・修正をデプロイする場合は、`lib/app_version.dart` の
`currentVersion` を+0.1し、`updateHistory` の先頭に変更内容を追記してから
デプロイすること（ヘルプ文言のみの修正など、ユーザーから明示的に
「verは上げなくていい」と指示された場合を除く）。

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
