# ISUCON適応的セットアップガイド

## 概要

このガイドは、異なるISUCON年度・環境に対応するための適応的セットアップ方法を説明します。
アプリケーション名、ポート番号、ファイル構成が異なっても自動検出して適切に設定します。

## 🔍 なぜ適応的セットアップが必要？

### ISUCONごとに変わる要素
- **アプリケーション名**: `isuride-go`, `isucon12-go`, `webapp`, `app` など
- **ポート番号**: `8080`, `3000`, `8000`, `9000` など  
- **ファイル構成**: `/home/isucon/webapp/go/`, `/opt/isucon/` など
- **サービス名**: `isuride-go.service`, `isucon-app.service` など

### 従来の問題点
- 固定値でハードコーディング → 他の年度で動作しない
- 手動設定が必要 → セットアップに時間がかかる
- エラーが発生しやすい → 設定ミスでエージェントが動作しない

## 🚀 適応的セットアップの使用方法

### 1. 環境の自動検出

```bash
# サーバーにSSH接続
ssh -i ~/Downloads/isucon14.pem ubuntu@13.230.155.251

# 環境の自動検出
bash scripts/detect_environment.sh
```

**検出される情報**:
- アプリケーションサービス名（systemdから自動検出）
- アプリケーションポート番号（netstatから自動検出）
- Go main.goファイルの場所（find検索で自動検出）
- Nginx設定ファイルの場所
- MySQL設定ファイルの場所

### 2. 適応的ログ設定

```bash
# 検出結果を使用してログ設定
bash scripts/setup_logging_adaptive.sh
```

**自動で行われること**:
- 検出されたMySQLファイルにスロークエリ設定を追加
- 検出されたNginx設定にカスタムログフォーマット追加
- 検出されたGo main.goにpprof設定を追加
- 検出されたサービス名でアプリケーション再起動

### 3. 動作確認

```bash
# 環境設定の確認
source /home/isucon/isucon_env.sh
echo "アプリポート: $ISUCON_APP_PORT"
echo "サービス名: $ISUCON_APP_SERVICE"

# pprofエンドポイント確認
curl http://localhost:$ISUCON_APP_PORT/debug/pprof/
```

## 📋 検出アルゴリズム

### アプリケーションサービス検出

```bash
# 検索パターン（優先度順）
SERVICE_PATTERNS=(
    "isuride-go"      # ISUCON14固有
    "isucon*-go"      # 汎用パターン 
    "app-go"          # アプリ系
    "webapp"          # Webアプリ系
    "isucon*"         # ISUCON汎用
    "*-app"           # 任意のアプリ
    "go-*"            # Go系
)
```

### ポート番号検出

```bash
# 1. systemdサービス設定から抽出
# 2. listenしているポート（8000-9999）から検出
# 3. デフォルト8080にフォールバック
```

### ファイルパス検出

```bash
# 検索ディレクトリ（優先度順）
SEARCH_DIRS=(
    "/home/isucon/webapp/go"
    "/home/isucon/webapp/golang" 
    "/home/isucon/go"
    "/home/isucon/app"
    "/opt/isucon*"           # ワイルドカード展開
    "/var/www/isucon*"
)
```

## 🔧 AIエージェントとの連携

### bottleneck-analyzer エージェント

適応的セットアップ後、エージェントは自動検出された値を使用：

```bash
# 環境変数の自動使用
APP_PORT=$ISUCON_APP_PORT
SERVICE_NAME=$ISUCON_APP_SERVICE
GO_MAIN_PATH=$ISUCON_GO_MAIN_PATH

# pprofエンドポイント
curl http://localhost:$APP_PORT/debug/pprof/profile
```

### 設定の永続化

検出結果は以下に保存されます：
- `/tmp/isucon_env_detected.sh` - 一時的な検出結果
- `/home/isucon/isucon_env.sh` - 永続化された環境設定

## ⚠️ トラブルシューティング

### 自動検出が失敗する場合

```bash
# 手動でサービス一覧を確認
sudo systemctl list-units --type=service --state=active

# 手動でポート確認
sudo netstat -tulpn | grep LISTEN

# 手動でGoファイル検索
find /home/isucon -name "*.go" -type f
```

### 部分的失敗への対処

```bash
# 環境変数を手動設定
export ISUCON_APP_SERVICE="your-app-service"
export ISUCON_APP_PORT="8080"  
export ISUCON_GO_MAIN_PATH="/path/to/main.go"

# 設定を保存
cat > /home/isucon/isucon_env.sh << EOF
export ISUCON_APP_SERVICE="$ISUCON_APP_SERVICE"
export ISUCON_APP_PORT="$ISUCON_APP_PORT"
export ISUCON_GO_MAIN_PATH="$ISUCON_GO_MAIN_PATH"
EOF
```

## 📈 対応済み環境

### テスト済みパターン

- **ISUCON14**: `isuride-go`, ポート8080, `/home/isucon/webapp/go/`
- **汎用Go**: `webapp`, ポート3000, `/home/isucon/go/`
- **典型的構成**: `app-go`, ポート8000, `/opt/isucon/app/`

### 想定される他年度対応

- **ISUCON13**: `isucon13-go.service` 
- **ISUCON12**: `isucon12-webapp.service`
- **ISUCON11**: `isucondition.service`

## 🎯 使用例

### ISUCON14（実際の設定）

```bash
bash scripts/detect_environment.sh
# → サービス: isuride-go
# → ポート: 8080
# → メインファイル: /home/isucon/webapp/go/main.go

bash scripts/setup_logging_adaptive.sh
# → 全て自動設定完了
```

### 仮想的なISUCON13

```bash
bash scripts/detect_environment.sh
# → サービス: isucon13-go
# → ポート: 3000
# → メインファイル: /home/isucon/go/main.go

bash scripts/setup_logging_adaptive.sh
# → 適応的に設定完了
```

## 🔄 継続的改善

### 新しいパターンの追加

新しいISUCON環境で検出に失敗した場合：

1. `scripts/detect_environment.sh` の検索パターンを追加
2. `scripts/setup_logging_adaptive.sh` のエラーハンドリング強化
3. テストパターンを `docs/adaptive-setup-guide.md` に追記

### フィードバック循環

1. 実際の環境で検出結果を確認
2. 失敗パターンを記録
3. スクリプトを改善
4. ドキュメントを更新

これにより、毎年のISUCONで確実に動作するセットアップシステムが完成します。