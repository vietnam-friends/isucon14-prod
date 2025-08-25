# IPアドレス変更時のチェックリスト

ISUCON14環境でサーバーのIPアドレスが変更された場合に実行する必要がある作業をまとめています。

## 前提条件
- アプリケーションサーバー: 新IPアドレス
- ベンチマーカーサーバー: 新IPアドレス

## 1. ローカル環境での設定変更

### CLAUDE.mdの更新
```bash
# CLAUDE.mdのサーバー接続情報を更新
vim CLAUDE.md
# アプリサーバー、ベンチサーバーのIPアドレスを新しいものに変更
```

### Payment Gateway URL の更新
```bash
# データベース設定ファイルを更新
vim home/isucon/webapp/sql/2-master-data.sql

# payment_gateway_url をベンチマーカーサーバーの新IPに変更
# 変更前: VALUES ('payment_gateway_url', 'http://OLD_BENCH_IP:12345')
# 変更後: VALUES ('payment_gateway_url', 'http://NEW_BENCH_IP:12345')
```

### Git管理による反映
```bash
# 変更をコミット・プッシュ
git add .
git commit -m "IPアドレス変更に伴う設定更新: NEW_APP_IP, NEW_BENCH_IP"
git push origin main
```

## 2. アプリケーションサーバーでの作業

### 設定の反映
```bash
# アプリサーバーにSSH接続
ssh -i ~/Downloads/isucon14.pem ubuntu@NEW_APP_IP

# 最新のコードを取得
cd /home/isucon
sudo git pull origin main
```

### サービスの確認
```bash
# 主要サービスの動作確認
sudo systemctl status isuride-go
sudo systemctl status nginx
sudo systemctl status isuride-matcher
sudo systemctl status isuride-payment_mock

# 必要に応じて再起動
sudo systemctl restart isuride-go
```

### 動作確認
```bash
# アプリケーションへのアクセス確認
curl -s http://localhost:8080/ 
curl -s -w 'time_total: %{time_total}s\n' http://localhost:8080/ -o /dev/null
```

## 3. ベンチマーカーサーバーでの作業

### hostsファイルの更新
```bash
# ベンチマーカーサーバーにSSH接続
ssh -i ~/Downloads/isucon14.pem ubuntu@NEW_BENCH_IP

# 古いIPエントリを削除
sudo sed -i '/OLD_APP_IP.*xiv.isucon.net/d' /etc/hosts

# 新しいIPエントリを追加
echo 'NEW_APP_IP xiv.isucon.net' | sudo tee -a /etc/hosts
```

### DNS解決の確認
```bash
# 正しいIPが解決されることを確認
nslookup xiv.isucon.net
# Name: xiv.isucon.net
# Address: NEW_APP_IP が表示されることを確認
```

### 接続テスト
```bash
# HTTP接続テスト
curl -w 'time_total: %{time_total}s\n' -s http://NEW_APP_IP:8080/ -o /dev/null

# HTTPS接続テスト
curl -w 'time_total: %{time_total}s\n' -s https://xiv.isucon.net:443/ -o /dev/null
```

## 4. ベンチマーク実行テスト

### 正しいコマンドで実行
```bash
# ベンチマーカーサーバーで実行
cd ~/isucon14/bench

# HTTPS:443での実行（推奨）
/usr/local/go/bin/go run . run \
  --target https://xiv.isucon.net:443 \
  --payment-url http://NEW_BENCH_IP:12345 \
  -t 60 \
  --skip-static-sanity-check
```

### 実行結果の確認
- スコアが表示されること
- 初期化タイムアウトが発生しないこと
- 接続エラーが発生しないこと

## 5. セキュリティグループの確認（AWS環境の場合）

### 必要なポートの開放確認
- **アプリサーバー**:
  - 22 (SSH)
  - 80 (HTTP)
  - 443 (HTTPS)
  - 8080 (アプリケーション直接アクセス)

- **ベンチマーカーサーバー**:
  - 22 (SSH)
  - 12345 (Payment Mock Server)

## 6. トラブルシューティング

### よくある問題と対処法

#### 1. DNS解決に古いIPが含まれる
```bash
# hostsファイルを確認
cat /etc/hosts | grep xiv

# 重複エントリや古いエントリを削除
sudo vi /etc/hosts
```

#### 2. HTTPS接続タイムアウト
```bash
# ポート443の確認
ss -tlnp | grep 443

# nginxの設定確認
sudo nginx -t
sudo systemctl status nginx

# SSL証明書の確認
sudo openssl x509 -in /etc/nginx/tls/_.xiv.isucon.net.crt -text -noout | grep -E 'Subject:|Issuer:|DNS:'
```

#### 3. 初期化処理タイムアウト
```bash
# アプリケーションログの確認
sudo journalctl -u isuride-go -f

# 直接初期化APIをテスト
curl -X POST https://xiv.isucon.net:443/api/initialize
```

## 7. 設定確認コマンド一覧

### 一括確認スクリプト
```bash
#!/bin/bash
echo "=== IP Address Change Verification ==="
echo "App Server: NEW_APP_IP"
echo "Bench Server: NEW_BENCH_IP"
echo ""

echo "1. DNS Resolution:"
nslookup xiv.isucon.net

echo "2. HTTP Connection:"
curl -w 'time_total: %{time_total}s\n' -s http://NEW_APP_IP:8080/ -o /dev/null

echo "3. HTTPS Connection:"
curl -w 'time_total: %{time_total}s\n' -s https://xiv.isucon.net:443/ -o /dev/null

echo "4. Payment Gateway Setting:"
mysql -u isucon -pisucon isuride -e "SELECT * FROM settings WHERE name = 'payment_gateway_url'"

echo "=== Verification Complete ==="
```

## 注意事項

1. **IPアドレス変更は必ずローカルでGit管理を行い、サーバーで `git pull` すること**
2. **payment_gateway_url はベンチマーカーサーバーのIPを指定すること**
3. **hostsファイルの変更後は必ずDNS解決を確認すること**
4. **ベンチマーク実行前に接続テストを必ず行うこと**
5. **変更作業はローカル → アプリサーバー → ベンチマーカーサーバーの順で実施すること**

## 参考

- ISUCON14 公式ドキュメント: `docs/ISURIDE.md`
- 当日マニュアル: `docs/manual.md`
- チーム運用ルール: `CLAUDE.md`