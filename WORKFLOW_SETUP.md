# GitHub Actions ワークフロー セットアップガイド

このドキュメントでは、Azure Static Web Appのユーザー同期を自動化するGitHub Actionsワークフローの設定方法を説明します。

## 概要

`sync-swa-users.yml` ワークフローは、PowerShellスクリプト `sync-swa-users.ps1` と同等の処理を実行し、GitHubリポジトリのコラボレーター（push権限以上）とAzure Static Web Appの認証済みユーザーを自動的に同期します。

## トリガー

このワークフローは以下の2つの方法で実行できます：

1. **手動トリガー** (`workflow_dispatch`)
   - GitHubリポジトリの「Actions」タブから手動で実行
   - 実行時にパラメータを指定可能

2. **スケジュール実行** (`schedule`)
   - 毎日UTC 00:00（日本時間 09:00）に自動実行
   - デフォルト値を使用

## 必要な権限

### GitHub
- リポジトリの読み取り権限
- GitHub APIアクセス用のPersonal Access Token（PAT）

### Azure
- Static Web Appの共同作成者ロール以上
- Service Principalの認証情報

## セットアップ手順

### 1. GitHub Secretsの設定

リポジトリの Settings > Secrets and variables > Actions から以下のシークレットを追加します：

#### 必須シークレット

- **`AZURE_CREDENTIALS`**
  ```json
  {
    "clientId": "YOUR_CLIENT_ID",
    "clientSecret": "YOUR_CLIENT_SECRET",
    "subscriptionId": "YOUR_SUBSCRIPTION_ID",
    "tenantId": "YOUR_TENANT_ID"
  }
  ```

  取得方法：
  ```bash
  az ad sp create-for-rbac --name "GitHub-Actions-SWA-Sync" \
    --role contributor \
    --scopes /subscriptions/{subscription-id}/resourceGroups/{resource-group} \
    --sdk-auth
  ```

- **`GH_TOKEN`**
  - GitHub Personal Access Token（classic）
  - 必要なスコープ：`repo` (フルアクセス)
  - 作成方法：Settings > Developer settings > Personal access tokens > Generate new token

#### スケジュール実行用のシークレット（オプション）

日次スケジュール実行を使用する場合は以下も設定してください：

- **`AZURE_STATIC_WEB_APP_NAME`**
  - Azure Static Web App名

- **`AZURE_RESOURCE_GROUP`**
  - Azureリソースグループ名

### 2. Azure Service Principalの権限設定

Service Principalに適切な権限を付与します：

```bash
# リソースグループレベルでの権限付与
az role assignment create \
  --assignee YOUR_CLIENT_ID \
  --role "Website Contributor" \
  --scope /subscriptions/{subscription-id}/resourceGroups/{resource-group}
```

### 3. GitHub CLI認証の確認

ワークフローはGitHub CLIを使用してコラボレーター情報を取得します。`GH_TOKEN`シークレットが正しく設定されていることを確認してください。

## 使用方法

### 手動実行

1. GitHubリポジトリの「Actions」タブを開く
2. 「Sync Azure Static Web App Users」ワークフローを選択
3. 「Run workflow」ボタンをクリック
4. 以下のパラメータを入力：
   - **Azure Static Web App名**: 対象のStatic Web App名
   - **Azureリソースグループ名**: リソースグループ名
   - **GitHubリポジトリ**: `owner/repo` 形式（例：`microsoft/vscode`）
   - **ドライラン**: 変更を適用せずに確認する場合はチェック
5. 「Run workflow」をクリックして実行

### スケジュール実行

シークレットが正しく設定されていれば、毎日自動的に実行されます。実行履歴は「Actions」タブで確認できます。

## ワークフローの動作

1. **認証**
   - Azure CLIでAzureにログイン
   - GitHub CLIでGitHubに認証

2. **データ収集**
   - GitHubリポジトリからpush権限を持つコラボレーターを取得
   - Azure Static Web Appから現在の認証済みユーザーを取得

3. **差分計算**
   - 追加が必要なユーザー（GitHubにいてAzureにいない）
   - 削除が必要なユーザー（Azureにのみ存在）

4. **同期処理**（ドライランでない場合）
   - 新規ユーザーをAzure Static Web Appに招待
   - 不要なユーザーをanonymousロールに変更（削除）

5. **結果サマリー**
   - 実行結果を出力

## トラブルシューティング

### 認証エラー

**エラー**: Azure認証に失敗する
- `AZURE_CREDENTIALS`シークレットのJSON形式が正しいか確認
- Service Principalが有効であることを確認
- 権限スコープが正しく設定されているか確認

**エラー**: GitHub API認証に失敗する
- `GH_TOKEN`が有効であることを確認
- トークンに`repo`スコープが付与されているか確認

### API呼び出しエラー

ワークフローは各API呼び出しで最大3回リトライします。それでも失敗する場合：

- Azureサービスの状態を確認
- GitHubサービスの状態を確認
- レート制限に達していないか確認

### ユーザー同期エラー

**問題**: ユーザーの追加/削除が失敗する
- Static Web Appのドメイン名が取得できているか確認
- 対象ユーザー名が正しい形式か確認
- Service Principalの権限が十分か確認

## ログの確認

1. GitHubリポジトリの「Actions」タブを開く
2. 対象のワークフロー実行を選択
3. 各ステップをクリックして詳細ログを確認

各ステップで以下の情報が出力されます：
- 取得したユーザー数
- 追加/削除対象のユーザーリスト
- 処理の成功/失敗状況

## セキュリティに関する注意事項

- GitHub Secretsは暗号化されて保存されます
- ワークフローログにシークレット値は表示されません
- Personal Access Tokenは定期的に更新してください
- Service Principalの権限は最小限に設定してください

## カスタマイズ

### スケジュール実行の時刻変更

[.github/workflows/sync-swa-users.yml](.github/workflows/sync-swa-users.yml) の `cron` 式を変更：

```yaml
schedule:
  - cron: '0 0 * * *'  # UTC 00:00 = JST 09:00
```

例：
- `'0 12 * * *'` - UTC 12:00（JST 21:00）
- `'0 0 * * 1'` - 毎週月曜日 UTC 00:00
- `'0 */6 * * *'` - 6時間ごと

### 招待有効期限の変更

デフォルトは168時間（7日間）です。変更する場合は、[.github/workflows/sync-swa-users.yml](.github/workflows/sync-swa-users.yml#L145) の `--invitation-expiration-in-hours` 値を変更してください。

## 参考リンク

- [GitHub Actions ドキュメント](https://docs.github.com/actions)
- [Azure Static Web Apps CLI リファレンス](https://learn.microsoft.com/cli/azure/staticwebapp)
- [GitHub CLI ドキュメント](https://cli.github.com/manual/)
