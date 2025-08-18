#!/bin/bash

# ISUCON環境自動検出スクリプト
# 各ISUCONごとに異なるアプリ名、ファイル構成を自動検出

set -e

echo "======================================"
echo "ISUCON環境自動検出"
echo "======================================"

# 環境情報を格納する変数
APP_SERVICE=""
APP_PORT=""
GO_MAIN_PATH=""
NGINX_CONFIG=""
MYSQL_CONFIG=""

# 1. systemdサービスの検出
echo "1. アプリケーションサービスの検出中..."

# ISUCONでよくあるサービス名パターン
SERVICE_PATTERNS=(
    "isuride-go"
    "isucon*-go"
    "app-go"
    "webapp"
    "isucon*"
    "*-app"
    "go-*"
)

for pattern in "${SERVICE_PATTERNS[@]}"; do
    services=$(sudo systemctl list-units --type=service --state=active | grep -E "$pattern" | awk '{print $1}' || true)
    if [ -n "$services" ]; then
        APP_SERVICE=$(echo "$services" | head -1 | sed 's/.service$//')
        echo "✅ 発見されたサービス: $APP_SERVICE"
        break
    fi
done

if [ -z "$APP_SERVICE" ]; then
    echo "⚠️  自動検出できませんでした。手動でサービス名を確認してください："
    sudo systemctl list-units --type=service --state=active | grep -v "system\|user\|dbus\|network"
fi

# 2. アプリケーションポート検出
echo ""
echo "2. アプリケーションポートの検出中..."

if [ -n "$APP_SERVICE" ]; then
    # systemdサービスの設定から検出を試行
    service_config=$(sudo systemctl cat "$APP_SERVICE" 2>/dev/null || true)
    if [ -n "$service_config" ]; then
        # ExecStartからポート番号を抽出
        port_from_service=$(echo "$service_config" | grep -oE ":[0-9]{4,5}" | head -1 | sed 's/://' || true)
        if [ -n "$port_from_service" ]; then
            APP_PORT="$port_from_service"
        fi
    fi
fi

# listenしているポートから検出
listening_ports=$(sudo netstat -tulpn 2>/dev/null | grep LISTEN | grep -E ":80[0-9][0-9]|:90[0-9][0-9]" | awk '{print $4}' | cut -d: -f2 | sort -u || true)
if [ -n "$listening_ports" ]; then
    if [ -z "$APP_PORT" ]; then
        APP_PORT=$(echo "$listening_ports" | head -1)
    fi
    echo "✅ 検出されたポート: $APP_PORT"
    echo "   リスニング中のポート一覧: $(echo $listening_ports | tr '\n' ' ')"
else
    echo "⚠️  ポート自動検出失敗。デフォルト8080を使用"
    APP_PORT="8080"
fi

# 3. Go main.goファイルの検出
echo ""
echo "3. Go アプリケーションファイルの検出中..."

# 検索対象ディレクトリ
SEARCH_DIRS=(
    "/home/isucon/webapp/go"
    "/home/isucon/webapp/golang" 
    "/home/isucon/go"
    "/home/isucon/app"
    "/home/isucon/src"
    "/opt/isucon*"
    "/var/www/isucon*"
    "$(pwd)"
    "$(pwd)/webapp/go"
)

for dir in "${SEARCH_DIRS[@]}"; do
    # ワイルドカード展開
    for expanded_dir in $dir; do
        if [ -d "$expanded_dir" ]; then
            main_files=$(find "$expanded_dir" -name "main.go" -type f 2>/dev/null || true)
            if [ -n "$main_files" ]; then
                GO_MAIN_PATH=$(echo "$main_files" | head -1)
                echo "✅ Go main.go発見: $GO_MAIN_PATH"
                break 2
            fi
        fi
    done
done

if [ -z "$GO_MAIN_PATH" ]; then
    echo "⚠️  main.go が見つかりませんでした"
    # 代替として、.goファイルがあるディレクトリを探す
    go_dirs=$(find /home/isucon -name "*.go" -type f 2>/dev/null | head -5 | xargs dirname | sort -u || true)
    if [ -n "$go_dirs" ]; then
        echo "   Goファイルが見つかったディレクトリ："
        echo "$go_dirs"
    fi
fi

# 4. Nginx設定ファイルの検出
echo ""
echo "4. Nginx設定ファイルの検出中..."

NGINX_CONFIGS=(
    "/etc/nginx/nginx.conf"
    "/etc/nginx/sites-available/default"
    "/etc/nginx/sites-enabled/default"
    "/etc/nginx/conf.d/default.conf"
)

for config in "${NGINX_CONFIGS[@]}"; do
    if [ -f "$config" ]; then
        NGINX_CONFIG="$config"
        echo "✅ Nginx設定発見: $NGINX_CONFIG"
        break
    fi
done

# 5. MySQL設定ファイルの検出
echo ""
echo "5. MySQL設定ファイルの検出中..."

MYSQL_CONFIGS=(
    "/etc/mysql/mysql.conf.d/mysqld.cnf"
    "/etc/mysql/my.cnf"
    "/etc/my.cnf"
    "/usr/local/mysql/etc/my.cnf"
)

for config in "${MYSQL_CONFIGS[@]}"; do
    if [ -f "$config" ]; then
        MYSQL_CONFIG="$config"
        echo "✅ MySQL設定発見: $MYSQL_CONFIG"
        break
    fi
done

# 6. 検出結果の保存
echo ""
echo "======================================"
echo "環境検出結果"
echo "======================================"

cat > /tmp/isucon_env_detected.sh << EOF
#!/bin/bash
# 自動検出されたISUCON環境設定

export ISUCON_APP_SERVICE="${APP_SERVICE}"
export ISUCON_APP_PORT="${APP_PORT}"
export ISUCON_GO_MAIN_PATH="${GO_MAIN_PATH}"
export ISUCON_NGINX_CONFIG="${NGINX_CONFIG}"
export ISUCON_MYSQL_CONFIG="${MYSQL_CONFIG}"

echo "=== 検出された環境設定 ==="
echo "アプリサービス名: \${ISUCON_APP_SERVICE}"
echo "アプリポート番号: \${ISUCON_APP_PORT}"
echo "Go main.go: \${ISUCON_GO_MAIN_PATH}"
echo "Nginx設定: \${ISUCON_NGINX_CONFIG}"
echo "MySQL設定: \${ISUCON_MYSQL_CONFIG}"
EOF

chmod +x /tmp/isucon_env_detected.sh

echo "アプリサービス名: $APP_SERVICE"
echo "アプリポート番号: $APP_PORT"
echo "Go main.go: $GO_MAIN_PATH"
echo "Nginx設定: $NGINX_CONFIG"
echo "MySQL設定: $MYSQL_CONFIG"

echo ""
echo "✅ 環境検出完了"
echo "検出結果は /tmp/isucon_env_detected.sh に保存されました"
echo ""
echo "次のステップ："
echo "1. source /tmp/isucon_env_detected.sh で環境変数を読み込み"
echo "2. scripts/setup_logging_adaptive.sh で適応的ログ設定を実行"