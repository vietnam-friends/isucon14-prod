# ISUCON14 ログ設定手順

## 概要

AIエージェント（bottleneck-analyzer等）を動作させるために必要なログ設定手順です。

## 🚀 クイックセットアップ

### 1. サーバー起動後、一括設定スクリプトを実行

```bash
# アプリケーションサーバーにSSHログイン
ssh -i ~/Downloads/isucon14.pem ubuntu@13.230.155.251

# リポジトリ更新（ログ設定ファイルを取得）
cd /home/isucon && sudo git pull origin main

# 一括ログ設定実行
sudo bash scripts/setup_logging.sh
```

### 2. Go アプリケーションのpprof有効化

```bash
# pprofを自動で有効化
sudo bash scripts/enable_pprof.sh

# アプリケーション再起動
sudo systemctl restart isuride-go
```

### 3. 設定確認

```bash
# MySQLスロークエリログ設定確認
mysql -u isucon -pisucon -e "SHOW VARIABLES LIKE 'slow_query%';"

# pprofエンドポイント確認
curl http://localhost:8080/debug/pprof/

# ログファイル確認
ls -la /var/log/mysql/mysql-slow.log
ls -la /var/log/nginx/access.log
```

## 📋 詳細設定

### MySQL スロークエリログ

**設定ファイル**: `/etc/mysql/mysql.conf.d/mysqld.cnf`

```ini
[mysqld]
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 0.01              # 0.01秒以上のクエリを記録
log_queries_not_using_indexes = 1   # インデックス未使用クエリも記録
log_slow_admin_statements = 1       # 管理コマンドも記録
log_slow_slave_statements = 1       # レプリケーションも記録
log_output = FILE
```

### Nginx アクセスログ

**設定ファイル**: `/etc/nginx/conf.d/isucon-log.conf`

```nginx
# カスタムログフォーマット
log_format isucon '$remote_addr - $remote_user [$time_local] '
                  '"$request" $status $body_bytes_sent '
                  '"$http_referer" "$http_user_agent" '
                  '$request_time $upstream_response_time '
                  '$upstream_cache_status';

# 詳細分析用フォーマット
log_format detailed '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';
```

### Go アプリケーション pprof

**main.goに追加**:

```go
import _ "net/http/pprof"
```

**利用可能なエンドポイント**:
- `http://localhost:8080/debug/pprof/` - 一覧
- `http://localhost:8080/debug/pprof/profile` - CPUプロファイル
- `http://localhost:8080/debug/pprof/heap` - メモリプロファイル
- `http://localhost:8080/debug/pprof/goroutine` - ゴルーチン情報

## 🔍 動作確認

### 1. 設定が有効になっているか確認

```bash
# MySQL
mysql -u isucon -pisucon -e "SHOW VARIABLES LIKE 'slow_query_log';"

# Nginx
sudo nginx -t

# Go pprof
curl -s http://localhost:8080/debug/pprof/ | grep -c "profile"
```

### 2. ログファイルが作成されているか確認

```bash
ls -la /var/log/mysql/mysql-slow.log
ls -la /var/log/nginx/access.log
```

### 3. 簡単なベンチマークでテスト

```bash
# 軽いベンチマークを実行
ssh -i ~/Downloads/isucon14.pem ubuntu@3.112.110.105 \
  "cd ~/isucon14/bench && timeout 10s /usr/local/go/bin/go run . run \
   --target https://xiv.isucon.net:443 \
   --payment-url http://13.230.155.251:12345"

# ログが出力されたか確認
sudo tail -10 /var/log/mysql/mysql-slow.log
sudo tail -10 /var/log/nginx/access.log
```

## 🤖 AIエージェント実行

ログ設定完了後、AIエージェントが使用可能になります：

```bash
# bottleneck-analyzer エージェントを呼び出し
# → 自動的にベンチマーク + 分析が実行される
```

## ⚠️ トラブルシューティング

### MySQL再起動エラー

```bash
# 設定構文チェック
sudo mysqld --validate-config

# エラーログ確認
sudo journalctl -u mysql -f
```

### Nginx設定エラー

```bash
# 設定テスト
sudo nginx -t

# エラーログ確認
sudo tail -f /var/log/nginx/error.log
```

### pprof未応答

```bash
# アプリケーションログ確認
sudo journalctl -u isuride-go -f

# ポート確認
sudo netstat -tulpn | grep :8080
```

## 📁 設定ファイル一覧

- `scripts/setup_logging.sh` - 一括設定スクリプト
- `scripts/setup_logging_adaptive.sh` - 適応的設定スクリプト  
- `scripts/enable_pprof.sh` - pprof有効化スクリプト
- `scripts/detect_environment.sh` - 環境自動検出スクリプト