# テスト実行例

このファイルは、`sync-swa-users.ps1`のテスト方法と実行例を示します。

## 前提条件の確認

スクリプトを実行する前に、以下を確認してください：

```powershell
# Azure CLIのバージョン確認
az --version

# GitHub CLIのバージョン確認
gh --version

# Azure認証状態の確認
az account show

# GitHub認証状態の確認
gh auth status
```

## テスト1: ドライランモード

設定を変更せずに実行結果だけを確認します。

1. `config.json` の `sync.dryRun` を `true` に設定します。
2. 以下のコマンドを実行します。

```powershell
pwsh -File .\scripts\Sync-SwaUsers.ps1
```

**期待される結果:**
- スクリプトが正常に起動する
- GitHubコラボレーターが取得される
- Azureユーザーが取得される
- 差分が計算される
- 「ドライランモードのため、変更は適用されません」というメッセージが表示される

## テスト2: ヘルプの表示

スクリプトのヘルプを表示して、概要と使用例を確認します。

```powershell
Get-Help .\scripts\Sync-SwaUsers.ps1 -Full
```

## テスト3: 必須設定の検証

`config.json` が存在しない場合に適切にエラーになるか確認します。

```powershell
Rename-Item -Path .\config.json -NewName config.json.bak
pwsh -File .\scripts\Sync-SwaUsers.ps1
# 実行後は必ず元に戻してください
Rename-Item -Path .\config.json.bak -NewName config.json
```

**期待される結果:**
- 「設定ファイルが見つかりません」というエラーが表示される
- スクリプトが終了コード1で停止する

## テスト4: 実際の同期（注意して実行）

⚠️ **警告**: このテストは実際にAzure Static Web Appのユーザー設定を変更します。

1. ドライランで結果を確認済みであることを前提とします。
2. `config.json` の `sync.dryRun` を `false` に設定します。
3. 以下のコマンドを実行します。

```powershell
pwsh -File .\scripts\Sync-SwaUsers.ps1
```

**期待される結果:**
- GitHubコラボレーターとAzureユーザーが同期される
- 新規ユーザーが招待される
- 不要なユーザーが削除（anonymousロールに変更）される
- 成功/失敗のサマリーが表示される

## テスト5: エラーハンドリング

設定値を意図的に誤らせて、エラーハンドリングを確認します。

> ⚠️ 次の例では`origin`リモートを書き換えるため、必ず検証用クローンで実行し、最後に元のURLへ戻してください。

```powershell
# 起点となるリモートURLを保存
$originalRemote = git remote get-url origin

# 存在しないリポジトリを指すように変更
git remote set-url origin git@github.com:nonexistent/repo.git
pwsh -File .\scripts\Sync-SwaUsers.ps1

# テスト後は必ず元に戻す
git remote set-url origin $originalRemote

# 存在しないStatic Web App名を設定
(Get-Content .\config.json -Raw) |
  ConvertFrom-Json |
  ForEach-Object { $_.azure.staticWebAppName = "nonexistent-app"; $_ } |
  ConvertTo-Json -Depth 5 |
  Set-Content .\config.json

pwsh -File .\scripts\Sync-SwaUsers.ps1
# 実運用の値に戻すことを忘れないでください
```

**期待される結果:**
- エラーメッセージが表示される
- スクリプトが適切に終了する（exit code 1）

## テスト6: 認証エラーのシミュレーション

```powershell
# Azureからログアウト
az logout

# スクリプトを実行（認証エラーになるはず）
pwsh -File .\scripts\Sync-SwaUsers.ps1

# 再度ログイン
az login
```

## ログの確認

スクリプト実行時のログは、カラーコードで分類されます：

- **白色**: 一般情報（INFO）
- **緑色**: 成功メッセージ（SUCCESS）
- **黄色**: 警告メッセージ（WARNING）
- **赤色**: エラーメッセージ（ERROR）

## トラブルシューティング

### よくある問題

1. **「Azure CLI (az) がインストールされていません」**
   - Azure CLIをインストールしてください: https://docs.microsoft.com/cli/azure/install-azure-cli

2. **「GitHub CLI (gh) がインストールされていません」**
   - GitHub CLIをインストールしてください: https://cli.github.com/

3. **「Azureにログインしていません」**
   - `az login` を実行してください

4. **「GitHubにログインしていません」**
   - `gh auth login` を実行してください

5. **「GitHubコラボレーターの取得に失敗しました」**
   - GitHubリポジトリへのアクセス権限を確認してください
   - `git remote get-url origin` が正しいGitHubリポジトリを指しているか確認してください

6. **「Azureユーザーの取得に失敗しました」**
   - Azure Static Web Appのリソース名とリソースグループ名が正しいか確認してください
   - 適切な権限（共同作成者ロール以上）があるか確認してください
7. **「Azureユーザー数が0と表示されるがポータルではユーザーが表示される」**
   - Azure CLI 2.75 以降では `roles` が `"authenticated,github_collaborator"` のようなカンマ区切り文字列で返る場合があります
   - 以下で実際のレスポンスを確認し、`roles` の内容を把握してください

```powershell
az staticwebapp users list `
  --name <AppName> `
  --resource-group <ResourceGroup> `
  --query "[].{userId:userId,roles:roles}" `
  -o table
```

   - `userId` がハッシュ値または `provider|username` の形式でも、スクリプトは `--user-id` を用いて削除するためそのまま実行できます
   - 2025-11-05 の修正以降、スクリプトはこの形式にも対応しています。古いコピーを使っている場合は最新のスクリプトへ置き換えてください

## 実行結果の例

### 成功時

```
[2025-11-03 16:00:08] [SUCCESS] 同期完了
[2025-11-03 16:00:08] [SUCCESS] 成功: 3 件
[2025-11-03 16:00:08] [INFO] 失敗: 0 件
```

終了コード: 0

### 部分的な失敗時

```
[2025-11-03 16:00:08] [SUCCESS] 同期完了
[2025-11-03 16:00:08] [SUCCESS] 成功: 2 件
[2025-11-03 16:00:08] [ERROR] 失敗: 1 件
```

終了コード: 1

### エラー時

```
[2025-11-03 16:00:08] [ERROR] 予期しないエラーが発生しました: <エラーメッセージ>
```

終了コード: 1

## 次のステップ

テストが成功したら：

1. 定期実行の設定を検討（Windowsタスクスケジューラ、GitHub Actionsなど）
2. ログ監視の仕組みを構築
3. チームメンバーへの使用方法の共有

詳細は[USAGE.md](USAGE.md)を参照してください。
