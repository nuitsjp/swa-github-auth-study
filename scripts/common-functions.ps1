<#
.SYNOPSIS
    スクリプト間で共有される共通関数とユーティリティ

.DESCRIPTION
    設定ファイルの読み込み、ログ出力、CLI存在確認などの共通機能を提供します。
#>

# ログ関数
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "INFO"    { "White" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# 設定ファイルの読み込み
function Get-Configuration {
    param(
        [string]$ConfigPath = "config.json"
    )
    
    # 相対パスの場合は、呼び出し元のスクリプトのディレクトリまたはカレントディレクトリからの相対パスとして解決
    if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
        # まず、PSScriptRootの親ディレクトリ（リポジトリルート）から探す
        $rootPath = Split-Path -Parent $PSScriptRoot
        $configFile = Join-Path $rootPath $ConfigPath
        
        # 見つからない場合は、カレントディレクトリから探す
        if (-not (Test-Path $configFile)) {
            $configFile = Join-Path (Get-Location).Path $ConfigPath
        }
    }
    else {
        $configFile = $ConfigPath
    }
    
    # 設定ファイルが存在しない場合
    if (-not (Test-Path $configFile)) {
        Write-Log "設定ファイルが見つかりません: $configFile" -Level ERROR
        Write-Log "config.json.template をコピーして config.json を作成してください" -Level ERROR
        throw "設定ファイルが見つかりません"
    }
    
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json

        if ($config.PSObject.Properties.Name -contains "github") {
            Write-Log "config.json 内の 'github' セクションは使用されなくなりました（gitのoriginから自動検出します）。" -Level WARNING
        }
        
        # 設定をハッシュテーブルに変換
        $configHash = @{
            Azure = @{
                SubscriptionId = $config.azure.subscriptionId
                ResourceGroup = $config.azure.resourceGroup
                StaticWebAppName = $config.azure.staticWebAppName
            }
            ServicePrincipal = @{
                Name = $config.servicePrincipal.name
            }
            InvitationSettings = @{
                ExpiresInHours = $config.invitationSettings.expiresInHours
            }
            Discussion = @{
                Enabled = if ($config.PSObject.Properties.Name -contains "discussion") { $config.discussion.enabled } else { $false }
                CategoryId = if ($config.PSObject.Properties.Name -contains "discussion") { $config.discussion.categoryId } else { "" }
                Title = if ($config.PSObject.Properties.Name -contains "discussion") { $config.discussion.title } else { "Azure Static Web App への招待: {username}" }
                BodyTemplate = if ($config.PSObject.Properties.Name -contains "discussion") { $config.discussion.bodyTemplate } else { "" }
            }
            Sync = @{
                DryRun = $false
            }
        }
        
        if ($config.PSObject.Properties.Name -contains "sync" -and $null -ne $config.sync) {
            if ($config.sync.PSObject.Properties.Name -contains "dryRun") {
                $configHash.Sync.DryRun = [bool]$config.sync.dryRun
            }
        }
        
        return $configHash
    }
    catch {
        Write-Log "設定ファイルの読み込みに失敗しました: $_" -Level ERROR
        throw
    }
}

# GitリモートからGitHubリポジトリ (owner/repo) を解決
function Get-GitHubRepositoryFromGit {
    param(
        [string]$StartPath
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git コマンドが見つかりません。Gitをインストールし、PATHに追加してください。"
    }

    try {
        $basePath = if ($StartPath) { $StartPath } else { (Get-Location).Path }
        $resolvedPath = (Resolve-Path -Path $basePath -ErrorAction Stop).Path

        $gitRoot = (& git -C $resolvedPath rev-parse --show-toplevel 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Gitリポジトリを特定できませんでした。'git rev-parse --show-toplevel' の出力: $gitRoot"
        }
        $gitRoot = $gitRoot.Trim()

        $remoteUrl = (& git -C $gitRoot remote get-url origin 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "origin リモートの取得に失敗しました。'git remote get-url origin' の出力: $remoteUrl"
        }
        $remoteUrl = $remoteUrl.Trim()

        if ($remoteUrl -match 'github\.com[:/](?<repo>[^/]+/[^/]+?)(?:\.git)?$') {
            return $Matches.repo.Trim()
        }

        throw "origin リモートが GitHub リポジトリを指していません: $remoteUrl"
    }
    catch {
        throw $_
    }
}

# Azure CLIの存在確認
function Test-AzureCLI {
    try {
        $null = az --version 2>&1
        return $true
    }
    catch {
        return $false
    }
}

# GitHub CLIの存在確認
function Test-GitHubCLI {
    try {
        $null = gh --version 2>&1
        return $true
    }
    catch {
        return $false
    }
}

# 前提条件の確認（Azure CLI、GitHub CLI、認証状態）
function Test-Prerequisites {
    param(
        [switch]$SkipGitHub
    )
    
    Write-Log "前提条件を確認中..." -Level INFO
    
    if (-not (Test-AzureCLI)) {
        Write-Log "Azure CLI (az) がインストールされていません" -Level ERROR
        Write-Log "https://docs.microsoft.com/cli/azure/install-azure-cli からインストールしてください" -Level ERROR
        return $false
    }
    Write-Log "Azure CLI: OK" -Level SUCCESS
    
    if (-not $SkipGitHub) {
        if (-not (Test-GitHubCLI)) {
            Write-Log "GitHub CLI (gh) がインストールされていません" -Level ERROR
            Write-Log "https://cli.github.com/ からインストールしてください" -Level ERROR
            return $false
        }
        Write-Log "GitHub CLI: OK" -Level SUCCESS
    }
    
    # Azure認証状態の確認
    $azAccountOutput = az account show 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Azureにログインしていません。'az login' を実行してください" -Level ERROR
        if ($azAccountOutput) {
            Write-Log "詳細: $azAccountOutput" -Level ERROR
        }
        return $false
    }
    Write-Log "Azure認証: OK" -Level SUCCESS
    
    if (-not $SkipGitHub) {
        # GitHub認証状態の確認
        $ghAuthOutput = gh auth status 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "GitHubにログインしていません。'gh auth login' を実行してください" -Level ERROR
            if ($ghAuthOutput) {
                Write-Log "詳細: $ghAuthOutput" -Level ERROR
            }
            return $false
        }
        Write-Log "GitHub認証: OK" -Level SUCCESS
    }
    
    return $true
}

# テンプレートファイルを読み込む
function Get-TemplateContent {
    param(
        [string]$TemplatePath
    )
    
    if (-not (Test-Path $TemplatePath)) {
        Write-Log "テンプレートファイルが見つかりません: $TemplatePath" -Level ERROR
        throw "テンプレートファイルが見つかりません: $TemplatePath"
    }
    
    try {
        $content = Get-Content $TemplatePath -Raw -Encoding UTF8
        return $content
    }
    catch {
        Write-Log "テンプレートファイルの読み込みに失敗しました: $_" -Level ERROR
        throw
    }
}

# GitHub Discussionを作成
function New-GitHubDiscussion {
    param(
        [string]$Repo,
        [string]$CategoryId,
        [string]$Title,
        [string]$Body
    )
    
    Write-Log "GitHub Discussionを作成中: $Repo" -Level INFO
    
    try {
        # まずリポジトリIDを取得
        $repoInfo = gh api "repos/$Repo" --jq '{id: .node_id}' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "リポジトリ情報の取得に失敗しました: $repoInfo"
        }
        
        $repoObj = $repoInfo | ConvertFrom-Json
        $repoId = $repoObj.id
        
        # GitHub CLI GraphQL APIを使用してDiscussionを作成
        # -F オプションを使用して変数を直接渡す
        $mutation = 'mutation($repositoryId: ID!, $categoryId: ID!, $title: String!, $body: String!) { createDiscussion(input: { repositoryId: $repositoryId, categoryId: $categoryId, title: $title, body: $body }) { discussion { url } } }'
        
        # Discussionを作成
        $result = gh api graphql -f query="$mutation" -F repositoryId="$repoId" -F categoryId="$CategoryId" -F title="$Title" -F body="$Body" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Discussion作成に失敗しました: $result"
        }
        
        $discussionObj = $result | ConvertFrom-Json
        $discussionUrl = $discussionObj.data.createDiscussion.discussion.url
        
        Write-Log "Discussionを作成しました: $discussionUrl" -Level SUCCESS
        return $discussionUrl
    }
    catch {
        Write-Log "Discussion作成中にエラーが発生しました: $_" -Level ERROR
        throw
    }
}
