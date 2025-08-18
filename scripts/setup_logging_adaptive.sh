#!/bin/bash

# 適応的ログ設定スクリプト
# detect_environment.sh の結果を使用して、環境に合わせたログ設定を行う

set -e

echo "======================================"
echo "適応的ログ設定セットアップ開始"
echo "======================================"

# 環境検出結果を読み込み
if [ -f "/tmp/isucon_env_detected.sh" ]; then
    source /tmp/isucon_env_detected.sh
    echo "✅ 環境設定を読み込みました"
else
    echo "⚠️  環境検出結果が見つかりません。detect_environment.sh を先に実行してください"
    exit 1
fi

# 1. MySQLスロークエリログ設定
echo ""
echo "1. MySQLスロークエリログ設定中..."

if [ -n "$ISUCON_MYSQL_CONFIG" ] && [ -f "$ISUCON_MYSQL_CONFIG" ]; then
    # 既存の設定をバックアップ
    sudo cp "$ISUCON_MYSQL_CONFIG" "${ISUCON_MYSQL_CONFIG}.backup"
    
    # スロークエリログ設定が既にあるかチェック
    if grep -q "slow_query_log" "$ISUCON_MYSQL_CONFIG"; then
        echo "   ⚠️  既存のスロークエリ設定を発見。手動で確認してください"
    else
        # 設定を追加
        sudo tee -a "$ISUCON_MYSQL_CONFIG" << 'EOF'

# ISUCON適応的スロークエリログ設定
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 0.01
log_queries_not_using_indexes = 1
log_slow_admin_statements = 1
log_slow_slave_statements = 1
log_output = FILE
EOF
        echo "   ✅ MySQL設定に追加完了"
    fi

    # ログファイルを作成
    sudo mkdir -p /var/log/mysql
    sudo touch /var/log/mysql/mysql-slow.log
    sudo chown mysql:mysql /var/log/mysql/mysql-slow.log
    sudo chmod 640 /var/log/mysql/mysql-slow.log
    
    # MySQL再起動
    echo "   MySQL再起動中..."
    sudo systemctl restart mysql
    sleep 2
    
    if sudo systemctl is-active --quiet mysql; then
        echo "   ✅ MySQL再起動完了"
    else
        echo "   ❌ MySQL再起動失敗"
        sudo journalctl -u mysql --no-pager -n 20
    fi
else
    echo "   ❌ MySQL設定ファイルが見つかりません: $ISUCON_MYSQL_CONFIG"
fi

# 2. Nginxアクセスログ設定
echo ""
echo "2. Nginxアクセスログ設定中..."

if [ -n "$ISUCON_NGINX_CONFIG" ] && [ -f "$ISUCON_NGINX_CONFIG" ]; then
    # バックアップ
    sudo cp "$ISUCON_NGINX_CONFIG" "${ISUCON_NGINX_CONFIG}.backup"
    
    # カスタムログフォーマット設定
    sudo tee /etc/nginx/conf.d/isucon-adaptive-log.conf << 'EOF'
# ISUCON適応的ログフォーマット
log_format isucon_adaptive '$remote_addr - $remote_user [$time_local] '
                           '"$request" $status $body_bytes_sent '
                           '"$http_referer" "$http_user_agent" '
                           'rt=$request_time urt="$upstream_response_time"';
EOF

    echo "   ✅ Nginxカスタムログフォーマット追加完了"
    
    # Nginx設定テスト
    if sudo nginx -t; then
        sudo systemctl reload nginx
        echo "   ✅ Nginx設定適用完了"
    else
        echo "   ❌ Nginx設定エラー"
        sudo nginx -t
    fi
else
    echo "   ❌ Nginx設定ファイルが見つかりません: $ISUCON_NGINX_CONFIG"
fi

# 3. Go アプリケーションのpprof設定
echo ""
echo "3. Go アプリケーションpprof設定中..."

if [ -n "$ISUCON_GO_MAIN_PATH" ] && [ -f "$ISUCON_GO_MAIN_PATH" ]; then
    # バックアップ
    sudo cp "$ISUCON_GO_MAIN_PATH" "${ISUCON_GO_MAIN_PATH}.backup"
    
    # pprofが既に有効かチェック
    if grep -q "net/http/pprof" "$ISUCON_GO_MAIN_PATH"; then
        echo "   ✅ pprof既に有効"
    else
        echo "   pprofを追加中..."
        
        # より安全なsed操作
        if grep -q "import (" "$ISUCON_GO_MAIN_PATH"; then
            # 複数行のimport文がある場合
            sudo sed -i '/^import ($/a\\t_ "net/http/pprof"' "$ISUCON_GO_MAIN_PATH"
        elif grep -q "^import" "$ISUCON_GO_MAIN_PATH"; then
            # 単一行のimport文を複数行に変換
            sudo sed -i 's/^import "/import (\n\t"/; /^import ($/a\\t_ "net/http/pprof"' "$ISUCON_GO_MAIN_PATH"
            # 対応する閉じ括弧を追加
            sudo sed -i '/^import (/,/^[[:space:]]*"[^"]*"[[:space:]]*$/{/^[[:space:]]*"[^"]*"[[:space:]]*$/a\)
}' "$ISUCON_GO_MAIN_PATH"
        else
            # importが見つからない場合は、package文の後に追加
            sudo sed -i '/^package /a\\nimport _ "net/http/pprof"' "$ISUCON_GO_MAIN_PATH"
        fi
        
        echo "   ✅ pprof追加完了"
    fi
    
    # アプリケーションの再起動
    if [ -n "$ISUCON_APP_SERVICE" ]; then
        echo "   アプリケーション再起動中: $ISUCON_APP_SERVICE"
        sudo systemctl restart "$ISUCON_APP_SERVICE"
        sleep 3
        
        if sudo systemctl is-active --quiet "$ISUCON_APP_SERVICE"; then
            echo "   ✅ アプリケーション再起動完了"
        else
            echo "   ❌ アプリケーション再起動失敗"
            sudo journalctl -u "$ISUCON_APP_SERVICE" --no-pager -n 10
        fi
    else
        echo "   ⚠️  アプリケーションサービス名が不明。手動で再起動してください"
    fi
else
    echo "   ❌ Go main.goファイルが見つかりません: $ISUCON_GO_MAIN_PATH"
fi

# 4. 設定確認
echo ""
echo "4. 設定確認中..."

# MySQL確認
if command -v mysql >/dev/null 2>&1; then
    echo "   MySQL設定確認："
    mysql -u isucon -pisucon -e "SHOW VARIABLES LIKE 'slow_query_log';" 2>/dev/null || echo "     MySQL接続失敗"
fi

# pprof確認（ポート番号を適応的に使用）
if [ -n "$ISUCON_APP_PORT" ]; then
    echo "   pprof確認 (port: $ISUCON_APP_PORT)："
    if curl -s --connect-timeout 3 "http://localhost:${ISUCON_APP_PORT}/debug/pprof/" | grep -q "profile" 2>/dev/null; then
        echo "     ✅ pprofエンドポイント応答OK"
    else
        echo "     ⚠️  pprofエンドポイント未応答（アプリ起動中かもしれません）"
    fi
fi

# ログファイル確認
echo "   ログファイル確認："
[ -f "/var/log/mysql/mysql-slow.log" ] && echo "     ✅ MySQLスロークエリログ作成済み" || echo "     ❌ MySQLスロークエリログなし"
[ -f "/var/log/nginx/access.log" ] && echo "     ✅ Nginxアクセスログ確認済み" || echo "     ❌ Nginxアクセスログなし"

echo ""
echo "======================================"
echo "適応的ログ設定完了！"
echo "======================================"
echo ""
echo "設定されたエンドポイント："
[ -n "$ISUCON_APP_PORT" ] && echo "- pprof: http://localhost:${ISUCON_APP_PORT}/debug/pprof/"
echo ""
echo "設定されたログファイル："
echo "- MySQLスロークエリ: /var/log/mysql/mysql-slow.log"
echo "- Nginxアクセス: /var/log/nginx/access.log"
echo ""
echo "次のステップ："
echo "1. 軽いベンチマーク実行でログが出力されることを確認"
echo "2. bottleneck-analyzerエージェントでテスト実行"
echo ""

# 環境設定を永続化
sudo cp /tmp/isucon_env_detected.sh /home/isucon/isucon_env.sh
echo "環境設定を /home/isucon/isucon_env.sh に保存しました"