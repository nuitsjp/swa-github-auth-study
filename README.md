# swa-github-auth-study

Azure Static Web Appの組み込み認証をGitHubリポジトリのコラボレーターと同期するPowerShellサンプルです。`scripts/Sync-SwaUsers.ps1`がGitHubとAzureのユーザー差分を検出し、招待・削除・通知までを一括で実行します。

## 主な機能

- GitHubリポジトリのpush権限（maintain/admin含む）を持つユーザーを自動取得
- Azure Static Web Appの`github_collaborator`ロールを持つユーザーと差分比較
- 新規ユーザーの自動招待、権限を失ったユーザーの`anonymous`へのロールダウン
- ドライランでの安全な事前確認と詳細なログ出力
- 招待リンクをGitHub Discussionsへ自動投稿（任意設定）
- `origin`リモートから対象リポジトリを自動判別

## 前提条件

### ツール
- PowerShell 5.1以上（PowerShell 7系推奨）
- Azure CLI 2.x以上（`az login`済みであること）
- GitHub CLI 2.x以上（`gh auth login`済みであること）

### アクセス権
- GitHub: 対象リポジトリの読み取り権限（コラボレーター一覧取得用）
- Azure: 対象Static Web Appへの共同作成者ロール以上

## クイックスタート

```bash
# 1. リポジトリを取得
git clone https://github.com/nuitsjp/swa-github-auth-study.git
cd swa-github-auth-study

# 2. 認証を実行（セッションごとに1回）
az login
gh auth login

# 3. 設定ファイルを作成
cp config.json.template config.json

# 4. config.jsonを編集し、Azure設定を入力
# - azure.subscriptionId
# - azure.resourceGroup
# - azure.staticWebAppName

# 5. ドライランで確認（sync.dryRun: true）
pwsh -File .\scripts\Sync-SwaUsers.ps1

# 6. 問題なければ本番実行（sync.dryRun: false）
```

## 詳細セットアップ

### ローカル実行

#### 1. 設定ファイルの編集

`config.json`の各項目を設定：

| セクション | キー | 説明 |
|------------|------|------|
| `azure` | `subscriptionId` | 対象サブスクリプションID |
| | `resourceGroup` | Static Web Appが属するリソースグループ |
| | `staticWebAppName` | Static Web App名 |
| `servicePrincipal` | `name` | Service Principal名（自動化スクリプト用） |
| `sync` | `dryRun` | デフォルトの実行モード（初回は`true`推奨） |
| `discussion` | `enabled` | 招待リンクをDiscussionに投稿する場合は`true` |
| | `categoryId` | 投稿先カテゴリID（`gh api graphql`で取得） |
| | `title` | 招待スレッドのタイトル（`{username}`がGitHub IDに置換） |
| | `bodyTemplate` | 招待文テンプレート（リポジトリルートからの相対パス） |

#### 2. Discussionカテゴリーの取得（任意）

```bash
gh api graphql -f query='
{ repository(owner: "owner", name: "repo") {
    discussionCategories(first: 20) {
      nodes { id name }
    }
  }
}'
```

#### 3. 実行

```powershell
# 引数で設定を上書き可能
pwsh -File .\scripts\Sync-SwaUsers.ps1 `
  -StaticWebAppName 'my-static-web-app' `
  -ResourceGroup 'rg-my-static-web-app' `
  -DryRun $true `
  -DiscussionEnabled $false
```

### GitHub Actions自動化

#### 自動セットアップ（推奨）

`scripts/Initialize-GithubSecrets.ps1`を使用して必要なシークレットを自動登録：

```powershell
.\scripts\Initialize-GithubSecrets.ps1 `
  -SubscriptionId "12345678-1234-1234-1234-123456789012" `
  -ResourceGroup "my-resource-group" `
  -StaticWebAppName "my-static-web-app"
```

このスクリプトは以下を自動実行：
1. Azure Service Principalの作成
2. 必要な権限の付与
3. GitHub Secretsの登録（AZURE_CREDENTIALS、AZURE_STATIC_WEB_APP_NAME、AZURE_RESOURCE_GROUP）

**前提条件：**
- Azure CLI（`az login`済み）
- GitHub CLI（`gh auth login`済み）
- Azureサブスクリプションの所有者/管理者ロール
- GitHubリポジトリの管理者権限

#### 手動セットアップ

リポジトリの Settings > Secrets and variables > Actions から以下を追加：

**必須シークレット：**

1. `AZURE_CREDENTIALS`（JSON形式）
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

2. `AZURE_STATIC_WEB_APP_NAME`: Azure Static Web App名
3. `AZURE_RESOURCE_GROUP`: Azureリソースグループ名

**Discussion関連シークレット（任意）：**
- `SWA_DISCUSSION_ENABLED`: `true`または`false`
- `SWA_DISCUSSION_CATEGORY_ID`: DiscussionカテゴリID
- `SWA_DISCUSSION_TITLE`: タイトルテンプレート（`{username}`を置換可能）
- `SWA_DISCUSSION_BODY_TEMPLATE`: 本文テンプレート

#### ワークフローの実行

**手動実行：**
1. GitHubリポジトリの「Actions」タブを開く
2. 「Sync Azure Static Web App Users」ワークフローを選択
3. 「Run workflow」をクリック
4. `dry_run`オプションを選択して実行

**スケジュール実行：**
- 毎日UTC 00:00（JST 09:00）に自動実行
- `.github/workflows/azure-static-web-apps-calm-hill-0f33a0910.yml`の`cron`式で変更可能

## テスト

### 1. ドライランモード

`config.json`の`sync.dryRun`を`true`に設定して実行：

```powershell
pwsh -File .\scripts\Sync-SwaUsers.ps1
```

**期待される結果：**
- GitHubコラボレーターとAzureユーザーの取得
- 差分の計算と表示
- 「ドライランモードのため、変更は適用されません」のメッセージ

### 2. 本番実行

`sync.dryRun`を`false`に設定して再実行：

```powershell
pwsh -File .\scripts\Sync-SwaUsers.ps1
```

**期待される結果：**
- 新規ユーザーの招待
- 不要なユーザーの削除（anonymousロールに変更）
- 成功/失敗のサマリー表示

### 3. エラーハンドリング

```powershell
# 認証エラーのシミュレーション
az logout
pwsh -File .\scripts\Sync-SwaUsers.ps1
az login

# 存在しないリソースでのテスト
# config.jsonの値を一時的に変更してテスト
```

## トラブルシューティング

### ツールが見つからない
- **「Azure CLI (az) がインストールされていません」**: [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)をインストールし、`az login`を実行
- **「GitHub CLI (gh) がインストールされていません」**: [GitHub CLI](https://cli.github.com/)をインストールし、`gh auth login`で認証

### 認証エラー
- **「Azureにログインしていません」**: `az login`を実行
- **「GitHubにログインしていません」**: `gh auth login`を実行

### API呼び出しエラー
- **「GitHubコラボレーターの取得に失敗」**:
  - GitHubリポジトリへのアクセス権限を確認
  - `git remote get-url origin`が正しいGitHubリポジトリを指しているか確認
- **「Azureユーザーの取得に失敗」**:
  - Azure Static Web Appのリソース名とリソースグループ名を確認
  - 適切な権限（共同作成者ロール以上）があるか確認

### ユーザー数が0と表示される
Azure CLI 2.75以降では`roles`がカンマ区切り文字列で返る場合があります：

```powershell
az staticwebapp users list `
  --name <AppName> `
  --resource-group <ResourceGroup> `
  --query "[].{userId:userId,roles:roles}" `
  -o table
```

スクリプトは2025-11-05の修正以降、この形式に対応しています。

### GitHub Actionsエラー
- **Azure認証失敗**: `AZURE_CREDENTIALS`シークレットのJSON形式を確認
- **GitHub認証失敗**: リポジトリ設定の「Actions > General > Workflow permissions」で`Read and write permissions`を選択
- **リソースが見つからない**: シークレット値が正しいかAzure Portalで確認

## 制約事項

- GitHubユーザー名での招待となるため、ユーザーは初回アクセス時にGitHub認証が必要
- Azure CLIでのユーザー完全削除には制限がある（anonymousロールへの変更で対応）
- 招待の有効期限は168時間（7日間）固定
- Azure Static Web App無償プランで動作

## ライセンス

MIT License
