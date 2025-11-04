# GitHub Actionsでの定期実行設定例

## 概要

このファイルでは、GitHub Actionsを使用してユーザー同期スクリプトを定期実行する方法を説明します。

## ワークフローファイルの作成

`.github/workflows/sync-swa-users.yml` を作成してください：

```yaml
name: Sync Azure Static Web App Users

on:
  workflow_dispatch:
    inputs:
      dry_run:
        description: '変更を適用せずに差分だけ確認する'
        required: false
        default: 'false'
        type: choice
        options:
          - 'false'
          - 'true'
  schedule:
    - cron: '0 0 * * *'

jobs:
  sync-users:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      discussions: write
    env:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      DRY_RUN_INPUT: ${{ github.event_name == 'workflow_dispatch' && github.event.inputs.dry_run || 'false' }}
      STATIC_WEB_APP_NAME: ${{ secrets.AZURE_STATIC_WEB_APP_NAME }}
      RESOURCE_GROUP: ${{ secrets.AZURE_RESOURCE_GROUP }}
      SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      DISCUSSION_ENABLED: ${{ secrets.SWA_DISCUSSION_ENABLED }}
      DISCUSSION_CATEGORY_ID: ${{ secrets.SWA_DISCUSSION_CATEGORY_ID }}
      DISCUSSION_TITLE: ${{ secrets.SWA_DISCUSSION_TITLE }}
      DISCUSSION_BODY_TEMPLATE: ${{ secrets.SWA_DISCUSSION_BODY_TEMPLATE }}
      INVITATION_EXPIRES_HOURS: ${{ secrets.SWA_INVITATION_EXPIRES_HOURS }}

    steps:
      - name: Ensure GITHUB_TOKEN is available
        run: |
          if [ -z "${GH_TOKEN:-}" ]; then
            echo "GITHUB_TOKEN is required." >&2
            exit 1
          fi

      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Install GitHub CLI if needed
        run: |
          if ! command -v gh >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y gh
          fi
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Validate GitHub CLI authentication
        run: gh auth status
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Sync Static Web App users
        shell: pwsh
        run: |
          if ([string]::IsNullOrWhiteSpace($env:STATIC_WEB_APP_NAME)) {
              Write-Error "AZURE_STATIC_WEB_APP_NAME secret is required."
              exit 1
          }
          if ([string]::IsNullOrWhiteSpace($env:RESOURCE_GROUP)) {
              Write-Error "AZURE_RESOURCE_GROUP secret is required."
              exit 1
          }

          $params = @{}
          $params["StaticWebAppName"] = $env:STATIC_WEB_APP_NAME
          $params["ResourceGroup"] = $env:RESOURCE_GROUP
          if (-not [string]::IsNullOrWhiteSpace($env:SUBSCRIPTION_ID)) {
              $params["SubscriptionId"] = $env:SUBSCRIPTION_ID
          }

          try {
              $dryRun = [System.Convert]::ToBoolean($env:DRY_RUN_INPUT)
          }
          catch {
              Write-Warning "Invalid dry_run input '$($env:DRY_RUN_INPUT)'. Falling back to false."
              $dryRun = $false
          }
          $params["DryRun"] = [bool]$dryRun

          if (-not [string]::IsNullOrWhiteSpace($env:DISCUSSION_ENABLED)) {
              try {
                  $discussionEnabled = [System.Convert]::ToBoolean($env:DISCUSSION_ENABLED)
              }
              catch {
                  Write-Warning "Invalid SWA_DISCUSSION_ENABLED value: $($env:DISCUSSION_ENABLED)"
                  $discussionEnabled = $false
              }
              $params["DiscussionEnabled"] = [bool]$discussionEnabled

              if ($discussionEnabled -and [string]::IsNullOrWhiteSpace($env:DISCUSSION_CATEGORY_ID)) {
                  Write-Error "SWA_DISCUSSION_CATEGORY_ID secret is required when SWA_DISCUSSION_ENABLED is true."
                  exit 1
              }
              if ($discussionEnabled -and [string]::IsNullOrWhiteSpace($env:DISCUSSION_BODY_TEMPLATE) -and -not (Test-Path "$PWD/invitation-body-template.txt")) {
                  Write-Error "SWA_DISCUSSION_BODY_TEMPLATE secret or default template file is required when SWA_DISCUSSION_ENABLED is true."
                  exit 1
              }
          }

          if (-not [string]::IsNullOrWhiteSpace($env:DISCUSSION_CATEGORY_ID)) {
              $params["DiscussionCategoryId"] = $env:DISCUSSION_CATEGORY_ID
          }
          if (-not [string]::IsNullOrWhiteSpace($env:DISCUSSION_TITLE)) {
              $params["DiscussionTitle"] = $env:DISCUSSION_TITLE
          }

          if (-not [string]::IsNullOrWhiteSpace($env:DISCUSSION_BODY_TEMPLATE)) {
              $params["DiscussionBodyTemplate"] = $env:DISCUSSION_BODY_TEMPLATE
          }
          elseif (Test-Path "$PWD/invitation-body-template.txt") {
              $params["DiscussionBodyTemplate"] = "invitation-body-template.txt"
          }

          if (-not [string]::IsNullOrWhiteSpace($env:INVITATION_EXPIRES_HOURS)) {
              $expires = 0
              if ([int]::TryParse($env:INVITATION_EXPIRES_HOURS, [ref]$expires) -and $expires -gt 0) {
                  $params["InvitationExpiresInHours"] = $expires
              }
              else {
                  Write-Warning "Invalid SWA_INVITATION_EXPIRES_HOURS value: $env:INVITATION_EXPIRES_HOURS"
              }
          }

          Write-Host "Starting Sync-SwaUsers.ps1 with parameters:"
          foreach ($key in $params.Keys) {
              Write-Host ("  {0} = {1}" -f $key, $params[$key])
          }

          & "$PWD/scripts/Sync-SwaUsers.ps1" @params
```

スクリプトは、チェックアウトされたリポジトリの `origin` リモート (`${{ github.repository }}`) から GitHub リポジトリ名を自動検出します。ローカル・CI ともに `git remote get-url origin` が期待するGitHubリポジトリを指しているか必ず確認してください。`origin` が未設定、または GitHub 以外を指す場合はスクリプトがエラーで停止します。

> ℹ️ `GITHUB_TOKEN` のワークフローパーミッションをリポジトリ設定で `Read and write` にしておくと、Discussions への投稿権限（`discussions: write`）が付与されます。追加の PAT は不要です。

## 必要なGitHub Secretsの設定

リポジトリの Settings > Secrets and variables > Actions で以下のシークレットを設定してください：

### 1. AZURE_CREDENTIALS

Azureサービスプリンシパルの認証情報（JSON形式）

```json
{
  "clientId": "<GUID>",
  "clientSecret": "<STRING>",
  "subscriptionId": "<GUID>",
  "tenantId": "<GUID>"
}
```

**作成方法:**

```bash
az ad sp create-for-rbac --name "github-actions-swa-sync" --role contributor \
  --scopes /subscriptions/{subscription-id}/resourceGroups/{resource-group}/providers/Microsoft.Web/staticSites/{static-site-name} \
  --sdk-auth
```

このコマンドの出力をそのままシークレットに設定してください。

### 2. AZURE_STATIC_WEB_APP_NAME / AZURE_RESOURCE_GROUP / AZURE_SUBSCRIPTION_ID

- `AZURE_STATIC_WEB_APP_NAME`: 対象の Static Web App 名
- `AZURE_RESOURCE_GROUP`: Static Web App が所属するリソースグループ名
- `AZURE_SUBSCRIPTION_ID` (任意): サブスクリプション ID を指定したい場合に設定します

### 3. Discussion 関連シークレット（任意）

- `SWA_DISCUSSION_ENABLED`: `true` または `false`
- `SWA_DISCUSSION_CATEGORY_ID`: Discussion カテゴリ ID（enabled が `true` の場合必須）
- `SWA_DISCUSSION_TITLE`: Discussion タイトルテンプレート（`{username}` を置換可能）
- `SWA_DISCUSSION_BODY_TEMPLATE`: Discussion 本文テンプレートのパス（リポジトリルートからの相対パスを推奨）

### 4. 招待期限の調整（任意）

- `SWA_INVITATION_EXPIRES_HOURS`: 招待リンクの有効期間（時間単位）

## cronスケジュールの例

```yaml
# 毎日午前0時（UTC）
- cron: '0 0 * * *'

# 毎日午前9時（JST = UTC+9、つまりUTC 0時）
- cron: '0 0 * * *'

# 毎週月曜日の午前0時（UTC）
- cron: '0 0 * * 1'

# 毎月1日の午前0時（UTC）
- cron: '0 0 1 * *'

# 毎時0分
- cron: '0 * * * *'
```

## ドライランモードでのテスト

手動実行 (`Run workflow`) 時に `dry_run` 入力を `true` に切り替えると、ワークフローが `-DryRun $true` を指定し、差分のみを表示します。スケジュール実行時は常に `false` が適用され、本番同期が実行されます。

## 手動実行の方法

1. GitHubリポジトリのActionsタブに移動
2. "Sync Azure SWA Users"ワークフローを選択
3. "Run workflow"ボタンをクリックし、必要に応じて `dry_run` を `true` に変更
4. ブランチを選択して "Run workflow" を実行

## ログの確認

1. GitHubリポジトリのActionsタブに移動
2. 実行されたワークフローをクリック
3. "Sync Users"ステップを展開してログを確認

## トラブルシューティング

### "Azure Login failed"

**原因:** AZURE_CREDENTIALSが正しく設定されていない

**解決方法:**
- シークレットが正しいJSON形式であることを確認
- サービスプリンシパルに適切な権限があることを確認

### "GitHub authentication failed"

**原因:** `GITHUB_TOKEN` のパーミッションが不足、またはリポジトリ設定でワークフロートークンが無効化されている

**解決方法:**
- リポジトリ設定の「Actions > General > Workflow permissions」で `Read and write permissions` を選択
- ワークフロー内の `permissions` セクションに `discussions: write` が含まれているか確認

### "Resource not found"

**原因:** `AZURE_STATIC_WEB_APP_NAME` または `AZURE_RESOURCE_GROUP` が正しく設定されていない

**解決方法:**
- シークレット値が正しいか確認
- Static Web App が削除されていないか Azure Portal で確認

## セキュリティのベストプラクティス

1. **最小権限の原則**: サービスプリンシパルには必要最小限の権限のみを付与
2. **トークンのローテーション**: Personal Access Tokenは定期的に更新
3. **シークレットの管理**: シークレットをコードにハードコーディングしない
4. **監査ログの確認**: 定期的にワークフローの実行ログを確認

## 通知の追加（オプション）

### Slackへの通知

```yaml
      - name: Notify Slack
        if: always()
        uses: slackapi/slack-github-action@v1.24.0
        with:
          payload: |
            {
              "text": "Azure SWA User Sync: ${{ job.status }}",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "User sync completed with status: *${{ job.status }}*"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

### Emailでの通知

GitHub Actionsはデフォルトでワークフロー失敗時にメール通知を送信します。
Settings > Notifications で設定を確認してください。

## まとめ

GitHub Actionsを使用することで、ユーザー同期を完全に自動化できます。
定期実行により、GitHubリポジトリの権限変更が自動的にAzure Static Web Appに反映されます。

詳細は[USAGE.md](USAGE.md)を参照してください。
