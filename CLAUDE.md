# ISUCON14 チーム運用ルール

## サーバー接続情報

### ベンチマークサーバー
```bash
ssh -i ~/Downloads/isucon14.pem ubuntu@13.115.146.218
```

### アプリケーションサーバー
```bash
ssh -i ~/Downloads/isucon14.pem ubuntu@57.180.65.12
```

## ベンチマーク実行コマンド
```bash
ssh -i ~/Downloads/isucon14.pem ubuntu@13.115.146.218 \
  "cd ~/isucon14/bench && /usr/local/go/bin/go run . run \
   --target https://xiv.isucon.net:443 \
   --payment-url http://57.180.65.12:12345 \
   -t 60 --skip-static-sanity-check"
```

## 基本ルール

1. **全ての変更はGit管理**
   - ローカルで変更 → commit → push
   - サーバーでは `sudo git pull` のみ

2. **変更後の確認**
   - アプリケーションの再起動: `sudo systemctl restart isuride-go`
   - ログ確認: `sudo journalctl -u isuride-go -f`

3. **問題発生時**
   - まず `git diff` で変更内容を確認
   - ログで原因を特定してから対処