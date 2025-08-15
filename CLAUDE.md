# ISUCON14 チーム運用ルール

## 基本方針

このドキュメントは、ISUCON14競技における開発・運用ルールを定めます。
効率的で安全な改善作業のため、以下のルールを厳守してください。

## 1. 変更管理ルール

### Git管理の徹底
- **全ての変更はローカル側で実施**し、git管理を行う
- サーバー側では`sudo git pull`でのみ変更を反映
- **サーバー側で直接ファイル編集は禁止**

### 変更フロー
```bash
# ローカルで変更
vim [ファイル]
git add [ファイル]
git commit -m "[変更内容]"
git push origin [ブランチ名]

# サーバーで反映
ssh [サーバー] "cd /home/isucon && sudo git pull origin [ブランチ名]"
```

## 2. サーバー接続情報

### ベンチマークサーバー
```bash
ssh -i ~/Downloads/isucon14.pem ubuntu@3.112.110.105
```

### アプリケーションサーバー
```bash
ssh -i ~/Downloads/isucon14.pem ubuntu@13.230.155.251
```

### SSH操作時の注意
- 設定変更後は必要なサービスを再起動
- systemdサービスの場合は`sudo systemctl daemon-reload`を忘れずに

## 3. エラー解析・ログ調査

### ログ確認方法
```bash
# アプリケーションログ（isuride-go）
sudo journalctl -u isuride-go -f

# 特定時間以降のログ
sudo journalctl -u isuride-go --since "5 minutes ago"

# エラーのみ抽出
sudo journalctl -u isuride-go | grep -E "ERROR|WARN"

# その他のサービス
sudo journalctl -u nginx -f
sudo journalctl -u isuride-matcher -f
sudo journalctl -u mysql -f
```

### ログ解析の手順
1. エラー発生時刻の特定
2. 関連するサービスのログを時系列で確認
3. エラーメッセージから根本原因を特定
4. 再現可能性の確認

## 4. ボトルネック分析・パフォーマンス改善

### 分析対象
- **DBスロークエリ**: MySQL slow query log
- **重いエンドポイント**: アクセスログの応答時間分析
- **リソース使用量**: CPU、メモリ、ディスクI/O
- **ネットワーク**: 通信遅延、タイムアウト

### 分析方法
```bash
# MySQLスロークエリログ
sudo tail -f /var/log/mysql/mysql-slow.log

# nginxアクセスログから応答時間分析
sudo tail -f /var/log/nginx/access.log | awk '{print $NF, $7}' | sort -nr

# システムリソース確認
top
iostat 1
```

### 改善の優先順位
1. **クリティカルエラーの解消**（ベンチマーク失敗要因）
2. **高頻度エンドポイントの最適化**
3. **データベースクエリの最適化**
4. **キャッシュの導入・改善**

## 5. 開発・テストフロー

### ブランチ戦略
```bash
# 新しい改善案の開始
git checkout main
git pull origin main
git checkout -b feature/[改善内容]

# 変更の実装
# ...

# コミット・プッシュ
git add .
git commit -m "[改善内容の詳細説明]"
git push origin feature/[改善内容]
```

### ベンチマーク実行・評価
```bash
# ベンチマーク実行
ssh -i ~/Downloads/isucon14.pem ubuntu@3.112.110.105 \
  "cd ~/isucon14/bench && /usr/local/go/bin/go run . run \
   --target https://xiv.isucon.net:443 \
   --payment-url http://13.230.155.251:12345 \
   -t 60 --skip-static-sanity-check"
```

### マージ条件
- ✅ ベンチマークスコアの向上が確認できた場合
- ✅ 新たなエラーが発生していない場合
- ✅ 既存機能に悪影響がない場合

```bash
# スコア向上確認後のマージ
git checkout main
git merge feature/[改善内容]
git push origin main

# アプリサーバーに反映
ssh [アプリサーバー] "cd /home/isucon && sudo git pull origin main"
```

## 6. 開発時の注意事項

### 修正範囲の制限
- **改修したい範囲に集中**し、基盤部分への影響を最小限に
- 1つのPRでは1つの改善に集中
- 副作用のリスクを常に考慮

### ステップバイステップ解決
1. 問題の切り分け
2. 最小限の修正で仮説検証
3. 段階的な改善
4. 各段階でのベンチマーク確認

### エラー対応の原則
- ログを必ず確認
- 再現手順の特定
- 根本原因の究明
- 対症療法ではなく原因治療

## 7. ドメイン知識管理

### 知識の蓄積場所
- **既存知識**: `docs/` ディレクトリ内のファイル
- **新たな発見**: `docs/` 配下に新規ファイル作成

### ドキュメント化対象
- API仕様の理解
- データベーススキーマの詳細
- ビジネスロジックの把握
- パフォーマンスボトルネックの発見
- 解決済み問題の記録

### ファイル命名規則
```
docs/
├── api-analysis.md          # API分析結果
├── database-schema.md       # DB構造理解
├── performance-issues.md    # パフォーマンス問題
├── troubleshooting.md       # トラブルシューティング履歴
└── business-logic.md        # ビジネスロジック理解
```

## 8. チェックリスト

### 変更前
- [ ] ログ確認済み
- [ ] 現状のボトルネック特定済み
- [ ] 改善案の影響範囲確認済み
- [ ] ブランチ作成済み

### 変更後
- [ ] ローカルでgit管理済み
- [ ] サーバーで動作確認済み
- [ ] ベンチマーク実行済み
- [ ] スコア向上確認済み
- [ ] ログでエラー確認済み

### マージ前
- [ ] スコア向上確認済み
- [ ] 副作用なし確認済み
- [ ] ドキュメント更新済み（必要に応じて）

---

**重要**: このルールに従わない変更は、システムの不安定化やスコア低下の原因となる可能性があります。必ず遵守してください。