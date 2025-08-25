# ISUCON14 プロジェクトオンボーディング

## プロジェクト概要

ISUCON14（Iikanjini Speed Up Contest）の競技用プロジェクトです。タクシー配車サービス「ISURIDE」のパフォーマンス改善を行います。

## ディレクトリ構造

```
isucon14-prod/
├── CLAUDE.md                 # チーム運用ルール（必読）
├── docs/                     # ドキュメント
│   ├── adaptive-setup-guide.md  # 適応的セットアップガイド
│   └── logging-setup.md         # ログ設定手順
├── home/isucon/
│   ├── webapp/
│   │   ├── go/              # Goアプリケーション（メイン）
│   │   │   ├── main.go      # エントリーポイント
│   │   │   ├── app_handlers.go     # ユーザー向けハンドラ
│   │   │   ├── chair_handlers.go   # ドライバー向けハンドラ
│   │   │   ├── owner_handlers.go   # オーナー向けハンドラ
│   │   │   ├── internal_handlers.go # 内部API
│   │   │   ├── models.go           # データモデル
│   │   │   ├── middlewares.go      # ミドルウェア
│   │   │   └── payment_gateway.go  # 決済ゲートウェイ
│   │   └── payment_mock/    # 決済モックサービス
│   └── bench/               # ベンチマーカー
├── scripts/                 # 自動化スクリプト
│   ├── setup_logging.sh          # ログ設定（固定版）
│   ├── setup_logging_adaptive.sh # ログ設定（適応版）
│   ├── detect_environment.sh     # 環境自動検出
│   ├── enable_pprof.sh          # pprof有効化
│   ├── monitor_resources.sh     # リソース監視
│   └── analyze_slow_queries.sh  # スロークエリ分析
└── etc/                     # 設定ファイル群
    ├── nginx/               # Nginx設定
    └── mysql/               # MySQL設定
```

## 主要コンポーネント

### 1. ISURIDEアプリケーション
- **言語**: Go
- **ポート**: 8080
- **サービス名**: isuride-go
- **役割**: タクシー配車サービスのバックエンドAPI

### 2. サーバー構成
- **ベンチマークサーバー**: 35.74.1.209
- **アプリケーションサーバー**: 18.182.64.47
- **SSH鍵**: ~/Downloads/isucon14.pem

### 3. データベース
- **MySQL**: ユーザー名 isucon / パスワード isucon
- **主要テーブル**: rides, chairs, users, owners など

## 開発ルール

### Git管理（重要）
1. **全ての変更はローカルで実施**
2. **サーバー側での直接編集は禁止**
3. **git pullでのみサーバーに反映**

### 変更フロー
```bash
# ローカル
git checkout -b feature/[改善内容]
# 変更実装
git add .
git commit -m "[詳細説明]"
git push origin feature/[改善内容]

# サーバー反映
ssh [server] "cd /home/isucon && sudo git pull origin [branch]"
```

## パフォーマンス改善の流れ

### 1. ボトルネック分析
```bash
# AIエージェント使用（推奨）
bottleneck-analyzer エージェントを呼び出し

# 手動分析
- MySQLスロークエリログ確認
- Nginxアクセスログ分析
- Go pprofプロファイリング
```

### 2. 改善優先順位
1. 🔴 Critical: ベンチマーク失敗要因
2. 🟡 High: 高頻度エンドポイント
3. 🔵 Medium: DBクエリ最適化
4. ⚪ Low: キャッシュ導入

### 3. ベンチマーク実行
```bash
ssh -i ~/Downloads/isucon14.pem ubuntu@${ベンチマークIPアドレス} \
  "cd ~/isucon14/bench && /usr/local/go/bin/go run . run \
   --target https://xiv.isucon.net:443 \
   --payment-url http://${アプリサーバIPアドレス}:12345 \
   -t 60 --skip-static-sanity-check"
```

## 初期セットアップ

### サーバー起動時に必須
```bash
# 1. ログ設定
sudo bash scripts/setup_logging.sh

# 2. pprof有効化
sudo bash scripts/enable_pprof.sh

# 3. 動作確認
curl http://localhost:8080/debug/pprof/
```

## AIエージェント

### 利用可能なエージェント
- **bottleneck-analyzer**: マスターエージェント（ベンチマーク実行+分析）
- **slow-query-analyzer**: DB専門エージェント
- **app-bottleneck-analyzer**: Goアプリ専門エージェント

### エージェントが分析する内容
- リソース使用率（CPU、メモリ、I/O）
- データベーススロークエリ
- N+1問題の検出
- メモリリーク、ゴルーチンリーク
- コードレベルのボトルネック

## 注意事項

### 絶対に守るべきこと
- ❌ サーバー側での直接ファイル編集
- ❌ 動作している基盤コードの不用意な修正
- ❌ git diffを確認せずに広範囲変更
- ❌ 複数機能の同時変更

### 推奨事項
- ✅ 変更前にgit diffで影響範囲確認
- ✅ エラー時は最初にgit diffで原因特定
- ✅ 段階的な改善とベンチマーク確認
- ✅ ドキュメントへの発見事項記録

## トラブルシューティング

### ログ確認
```bash
# アプリケーション
sudo journalctl -u isuride-go -f

# MySQL
sudo tail -f /var/log/mysql/mysql-slow.log

# Nginx
sudo tail -f /var/log/nginx/access.log
```

### サービス再起動
```bash
sudo systemctl restart isuride-go
sudo systemctl restart mysql
sudo systemctl restart nginx
```

## 関連ドキュメント

- [CLAUDE.md](/Users/mynameis/Documents/Cursor/isucon14-prod/CLAUDE.md) - 詳細な運用ルール