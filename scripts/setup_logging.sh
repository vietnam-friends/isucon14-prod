#!/bin/bash

# ISUCON14 ログ設定セットアップスクリプト
# サーバー起動後に実行してログ設定を有効化する

set -e

echo "======================================"
echo "ISUCON14 ログ設定セットアップ開始"
echo "======================================"

# 1. MySQLスロークエリログ設定
echo "1. MySQLスロークエリログ設定中..."

# MySQLの設定ファイルに追記
sudo tee -a /etc/mysql/mysql.conf.d/mysqld.cnf << 'EOF'

# ISUCON14 スロークエリログ設定
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 0.01
log_queries_not_using_indexes = 1
log_slow_admin_statements = 1
log_slow_slave_statements = 1
log_output = FILE
EOF

# スロークエリログファイルを作成
sudo touch /var/log/mysql/mysql-slow.log
sudo chown mysql:mysql /var/log/mysql/mysql-slow.log
sudo chmod 640 /var/log/mysql/mysql-slow.log

echo "   ✅ MySQLスロークエリログ設定完了"

# 2. Nginxアクセスログ設定
echo "2. Nginxアクセスログ設定中..."

# Nginxの設定をバックアップ
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# カスタムログフォーマットを追加
sudo tee /etc/nginx/conf.d/isucon-log.conf << 'EOF'
# ISUCON14 カスタムログフォーマット
log_format isucon '$remote_addr - $remote_user [$time_local] '
                  '"$request" $status $body_bytes_sent '
                  '"$http_referer" "$http_user_agent" '
                  '$request_time $upstream_response_time '
                  '$upstream_cache_status';

log_format detailed '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time" '
                    'cs=$upstream_cache_status';
EOF

echo "   ✅ Nginxログフォーマット設定完了"

# 3. Go アプリケーションのpprof設定確認
echo "3. Go アプリケーションのpprof設定確認中..."

# Goアプリのソースコードでpprofが有効かチェック
if [ -f "/home/isucon/webapp/go/main.go" ]; then
    if grep -q "net/http/pprof" /home/isucon/webapp/go/main.go; then
        echo "   ✅ pprof既に有効"
    else
        echo "   ⚠️  pprofが無効 - 手動でアプリケーションコードを確認してください"
    fi
else
    echo "   ⚠️  Goアプリケーションファイルが見つかりません"
fi

# 4. ログディレクトリの権限設定
echo "4. ログディレクトリ権限設定中..."

sudo mkdir -p /var/log/isucon
sudo chown isucon:isucon /var/log/isucon
sudo chmod 755 /var/log/isucon

echo "   ✅ ログディレクトリ設定完了"

# 5. サービス再起動
echo "5. サービス再起動中..."

# MySQL再起動
echo "   MySQL再起動中..."
sudo systemctl restart mysql
sleep 2

if sudo systemctl is-active --quiet mysql; then
    echo "   ✅ MySQL再起動完了"
else
    echo "   ❌ MySQL再起動失敗"
    exit 1
fi

# Nginx設定テスト
echo "   Nginx設定テスト中..."
if sudo nginx -t; then
    echo "   ✅ Nginx設定OK"
    sudo systemctl reload nginx
    echo "   ✅ Nginx reload完了"
else
    echo "   ❌ Nginx設定エラー"
    exit 1
fi

# 6. 設定確認
echo "6. 設定確認中..."

# MySQLスロークエリ設定確認
mysql -u isucon -pisucon -e "SHOW VARIABLES LIKE 'slow_query%';"
mysql -u isucon -pisucon -e "SHOW VARIABLES LIKE 'long_query_time';"

echo ""
echo "======================================"
echo "ログ設定セットアップ完了！"
echo "======================================"
echo ""
echo "設定されたログファイル："
echo "- MySQLスロークエリ: /var/log/mysql/mysql-slow.log"
echo "- Nginxアクセス: /var/log/nginx/access.log"
echo "- Nginxエラー: /var/log/nginx/error.log"
echo ""
echo "次のステップ："
echo "1. pprofが有効でない場合は、Goアプリケーションにpprofを追加"
echo "2. ベンチマーク実行してログが出力されることを確認"
echo "3. bottleneck-analyzerエージェントでテスト実行"
echo ""