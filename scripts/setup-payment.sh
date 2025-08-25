#!/bin/bash

# Payment gateway URL設定スクリプト
BENCH_IP=${1:-"13.115.146.218"}
PAYMENT_URL="http://${BENCH_IP}:12345"

echo "Setting payment gateway URL to: $PAYMENT_URL"

# SQLファイルを更新
sed -i "s|payment_gateway_url', 'http://[^']*'|payment_gateway_url', '$PAYMENT_URL'|g" \
  /home/isucon/webapp/sql/2-master-data.sql

# DBを直接更新
mysql -u isucon -pisucon isuride -e \
  "UPDATE settings SET value = '$PAYMENT_URL' WHERE name = 'payment_gateway_url'"

echo "Payment gateway URL updated successfully"
echo "Current setting:"
mysql -u isucon -pisucon isuride -e \
  "SELECT * FROM settings WHERE name = 'payment_gateway_url'" 2>/dev/null