<#
.SYNOPSIS
    Azure Static Web AppとGitHubリポジトリのユーザーを同期するスクリプト

.DESCRIPTION
    GitHubリポジトリでpush権限を持つユーザーを取得し、Azure Static Web Appの認証済みユーザーと同期します。
    GitHubにあってAzureにないユーザーは追加し、Azureにのみ存在するユーザーは削除します。
    対象となるGitHubリポジトリは、スクリプトを実行したGitリポジトリの`origin`リモートから自動検出されます。
    設定値はリポジトリルートの config.json から読み込みます。

.EXAMPLE
    pwsh -File .\scripts\Sync-SwaUsers.ps1

.NOTES
    必要な権限:
    - GitHub: リポジトリの読み取り権限
    - Azure: Static Web Appの共同作成者ロール以上
    
    事前準備:
    - Azure CLI (az) のインストールと認証 (az login)
    - GitHub CLI (gh) のインストールと認証 (gh auth login)
#>

# エラー発生時に停止
$ErrorActionPreference = "Stop"

# 共通関数を読み込む
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "common-functions.ps1")

# GitHubリポジトリのコラボレーター取得（push権限以上）
function Get-GitHubCollaborators {
    param([string]$Repo)
    
    Write-Log "GitHubリポジトリのコラボレーター一覧を取得中: $Repo"
    
    try {
        # GitHub APIでコラボレーター一覧を取得（最大3回リトライ）
        $retries = 3
        $collaborators = $null
        
        for ($i = 1; $i -le $retries; $i++) {
            try {
                # GitHub CLIを使用してコラボレーター一覧を取得
                $result = gh api "repos/$Repo/collaborators" --jq '.[] | select(.permissions.push == true or .permissions.admin == true or .permissions.maintain == true) | .login' 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    $collaborators = $result | Where-Object { $_ -ne "" }
                    break
                }
                else {
                    if ($i -lt $retries) {
                        Write-Log "GitHub API呼び出しに失敗しました。リトライします... ($i/$retries)" -Level WARNING
                        Start-Sleep -Seconds 2
                    }
                    else {
                        throw "GitHub API呼び出しに失敗しました: $result"
                    }
                }
            }
            catch {
                if ($i -eq $retries) {
                    throw
                }
            }
        }
        
        if ($null -eq $collaborators -or $collaborators.Count -eq 0) {
            Write-Log "push権限を持つコラボレーターが見つかりませんでした" -Level WARNING
            return @()
        }
        
        Write-Log "push権限を持つコラボレーター数: $($collaborators.Count)" -Level SUCCESS
        return $collaborators
    }
    catch {
        Write-Log "GitHubコラボレーターの取得に失敗しました: $_" -Level ERROR
        throw
    }
}

# Azure Static Web Appのユーザー一覧を取得
function Get-AzureStaticWebAppUsers {
    param(
        [string]$AppName,
        [string]$ResourceGroup
    )
    
    Write-Log "Azure Static Web Appのユーザー一覧を取得中: $AppName"
    
    try {
        # Azure CLIでユーザー一覧を取得
        $retries = 3
        $users = $null
        
        for ($i = 1; $i -le $retries; $i++) {
            try {
                $output = az staticwebapp users list --name $AppName --resource-group $ResourceGroup 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    # JSONパースを試行
                    try {
                        $result = $output | ConvertFrom-Json
                        # github_collaboratorロールを持つユーザーを抽出
                        $users = @()

                        foreach ($user in $result) {
                            $rolesValue = $null
                            if ($user.PSObject.Properties.Name -contains "roles") {
                                $rolesValue = $user.roles
                            }
                            elseif ($user.PSObject.Properties.Name -contains "assignedRoleNames") {
                                $rolesValue = $user.assignedRoleNames
                            }

                            $roleList = @()

                            if ($null -ne $rolesValue) {
                                if ($rolesValue -is [System.Array]) {
                                    $roleList = $rolesValue | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }
                                }
                                else {
                                    $rolesText = $rolesValue.ToString().Trim()

                                    if ($rolesText.StartsWith("[") -and $rolesText.EndsWith("]")) {
                                        try {
                                            $parsedRoles = $rolesText | ConvertFrom-Json
                                            if ($parsedRoles -is [System.Array]) {
                                                $roleList = $parsedRoles | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }
                                            }
                                            elseif ($null -ne $parsedRoles) {
                                                $roleList = @($parsedRoles.ToString().Trim())
                                            }
                                        }
                                        catch {
                                            $roleList = @()
                                        }
                                    }

                                    if ($roleList.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($rolesText)) {
                                        $roleList = ($rolesText -split '[,\\s]+') |
                                            ForEach-Object { $_.Trim() } |
                                            Where-Object { $_ }
                                    }
                                }
                            }

                            if ($roleList -contains "github_collaborator") {
                                $provider = ""
                                if ($user.PSObject.Properties.Name -contains "provider" -and $null -ne $user.provider) {
                                    $provider = $user.provider.ToString().Trim()
                                }

                                $displayName = ""
                                if ($user.PSObject.Properties.Name -contains "displayName" -and $null -ne $user.displayName) {
                                    $displayName = $user.displayName.ToString().Trim()
                                }
                                elseif ($user.PSObject.Properties.Name -contains "userDetails" -and $null -ne $user.userDetails) {
                                    $displayName = $user.userDetails.ToString().Trim()
                                }

                                $userId = if ($user.PSObject.Properties.Name -contains "userId") { $user.userId } else { $null }
                                if ($null -eq $userId -and $user.PSObject.Properties.Name -contains "name") {
                                    $userId = $user.name
                                }

                                $userId = if ($null -ne $userId) { $userId.ToString().Trim() } else { "" }

                                if ([string]::IsNullOrWhiteSpace($displayName) -and -not [string]::IsNullOrWhiteSpace($userId)) {
                                    if ($userId -match '^[^|]+\|(.+)$') {
                                        $displayName = $Matches[1]
                                    }
                                    else {
                                        $displayName = $userId
                                    }
                                }

                                $normalizedName = $displayName
                                if ([string]::IsNullOrWhiteSpace($normalizedName)) {
                                    $normalizedName = $userId
                                }

                                $normalizedNameLower = if (-not [string]::IsNullOrWhiteSpace($normalizedName)) {
                                    $normalizedName.ToLowerInvariant()
                                }
                                else {
                                    ""
                                }

                                $users += [pscustomobject]@{
                                    UserId = $userId
                                    DisplayName = $displayName
                                    Provider = $provider
                                    NormalizedName = $normalizedName
                                    NormalizedNameLower = $normalizedNameLower
                                }
                            }
                        }

                        break
                    }
                    catch {
                        throw "Azure APIレスポンスのJSON解析に失敗しました: $output"
                    }
                }
                else {
                    if ($i -lt $retries) {
                        Write-Log "Azure API呼び出しに失敗しました。リトライします... ($i/$retries)" -Level WARNING
                        Start-Sleep -Seconds 2
                    }
                    else {
                        throw "Azure API呼び出しに失敗しました: $output"
                    }
                }
            }
            catch {
                if ($i -eq $retries) {
                    throw
                }
            }
        }
        
        if ($null -eq $users) {
            $users = @()
        }
        
        Write-Log "現在のAzureユーザー数: $($users.Count)" -Level SUCCESS
        return $users
    }
    catch {
        Write-Log "Azureユーザーの取得に失敗しました: $_" -Level ERROR
        throw
    }
}

# ユーザーをAzure Static Web Appに招待
function Add-AzureStaticWebAppUser {
    param(
        [string]$AppName,
        [string]$ResourceGroup,
        [string]$UserName,
        [int]$InvitationExpiresInHours = 168  # 7日間
    )

    Write-Log "ユーザーを招待中: $UserName"

    try {
        # ドメイン名を取得
        $domain = az staticwebapp show --name $AppName --resource-group $ResourceGroup --query 'defaultHostname' -o tsv 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "ドメイン取得に失敗しました: $domain"
        }

        $result = az staticwebapp users invite `
            --name $AppName `
            --resource-group $ResourceGroup `
            --authentication-provider GitHub `
            --user-details $UserName `
            --domain $domain `
            --role github_collaborator `
            --invitation-expiration-in-hours $InvitationExpiresInHours `
            --output json `
            2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "ユーザーの招待に成功しました: $UserName" -Level SUCCESS
            
            # JSON応答から招待URLを抽出
            try {
                $invitationObj = $result | ConvertFrom-Json
                $invitationUrl = $invitationObj.invitationUrl
                
                return @{
                    Success = $true
                    UserName = $UserName
                    InvitationUrl = $invitationUrl
                }
            }
            catch {
                Write-Log "招待URLの抽出に失敗しました: $_" -Level WARNING
                return @{
                    Success = $true
                    UserName = $UserName
                    InvitationUrl = $null
                }
            }
        }
        else {
            Write-Log "ユーザーの招待に失敗しました: $UserName - $result" -Level ERROR
            return @{
                Success = $false
                UserName = $UserName
                InvitationUrl = $null
            }
        }
    }
    catch {
        Write-Log "ユーザーの招待中にエラーが発生しました: $UserName - $_" -Level ERROR
        return @{
            Success = $false
            UserName = $UserName
            InvitationUrl = $null
        }
    }
}

# ユーザーをAzure Static Web Appから削除（anonymousロールに変更）
function Remove-AzureStaticWebAppUser {
    param(
        [string]$AppName,
        [string]$ResourceGroup,
        [string]$UserId,
        [string]$DisplayName,
        [string]$Provider
    )

    $targetLabel = if (-not [string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName
    }
    elseif (-not [string]::IsNullOrWhiteSpace($UserId)) {
        $UserId
    }
    else {
        "(unknown)"
    }
    
    Write-Log "ユーザーを削除中: $targetLabel"
    
    try {
        # ユーザーをanonymousロールに更新することで実質的に削除
        $azArgs = @(
            "staticwebapp", "users", "update",
            "--name", $AppName,
            "--resource-group", $ResourceGroup
        )

        if (-not [string]::IsNullOrWhiteSpace($UserId)) {
            $azArgs += @("--user-id", $UserId)
        }
        elseif (-not [string]::IsNullOrWhiteSpace($DisplayName)) {
            $azArgs += @("--user-details", $DisplayName)
            if (-not [string]::IsNullOrWhiteSpace($Provider)) {
                $azArgs += @("--authentication-provider", $Provider)
            }
        }

        $azArgs += @("--role", "anonymous")

        $result = az @azArgs 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "ユーザーの削除に成功しました: $targetLabel" -Level SUCCESS
            return $true
        }
        else {
            Write-Log "ユーザーの削除に失敗しました: $targetLabel - $result" -Level ERROR
            return $false
        }
    }
    catch {
        Write-Log "ユーザーの削除中にエラーが発生しました: $targetLabel - $_" -Level ERROR
        return $false
    }
}

# メイン処理
try {
    # 設定ファイルを読み込む
    $config = Get-Configuration
    
    # 設定から値を取得
    $AppName = $config.Azure.StaticWebAppName
    $ResourceGroup = $config.Azure.ResourceGroup
    $DryRun = [bool]$config.Sync.DryRun
    $GitHubRepo = Get-GitHubRepositoryFromGit -StartPath $scriptDir
    
    Write-Log "========================================" -Level INFO
    Write-Log "Azure Static Web App ユーザー同期スクリプト" -Level INFO
    Write-Log "========================================" -Level INFO
    Write-Log "AppName: $AppName" -Level INFO
    Write-Log "ResourceGroup: $ResourceGroup" -Level INFO
    Write-Log "GitHubRepo: $GitHubRepo (detected from git)" -Level INFO
    if ($DryRun) {
        Write-Log "実行モード: ドライラン（変更は適用されません）" -Level WARNING
    }
    Write-Log "========================================" -Level INFO
    
    # 前提条件の確認
    if (-not (Test-Prerequisites)) {
        exit 1
    }
    
    Write-Log "========================================" -Level INFO
    
    # 1. GitHubコラボレーターを取得
    $githubUsers = Get-GitHubCollaborators -Repo $GitHubRepo
    
    # 2. Azureユーザーを取得
    $azureUsers = Get-AzureStaticWebAppUsers -AppName $AppName -ResourceGroup $ResourceGroup
    
    # 3. 差分を計算
    Write-Log "========================================" -Level INFO
    Write-Log "差分を計算中..." -Level INFO
    
    $githubUsersNormalized = @()
    foreach ($user in $githubUsers) {
        if (-not [string]::IsNullOrWhiteSpace($user)) {
            $githubUsersNormalized += $user.ToLowerInvariant()
        }
    }

    $azureUserNamesNormalized = @()
    foreach ($azureUser in $azureUsers) {
        $normalizedLower = ""
        if ($azureUser.PSObject.Properties.Name -contains "NormalizedNameLower" -and -not [string]::IsNullOrWhiteSpace($azureUser.NormalizedNameLower)) {
            $normalizedLower = $azureUser.NormalizedNameLower
        }
        elseif ($azureUser.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace($azureUser.NormalizedName)) {
            $normalizedLower = $azureUser.NormalizedName.ToLowerInvariant()
        }
        elseif ($azureUser.PSObject.Properties.Name -contains "UserId" -and -not [string]::IsNullOrWhiteSpace($azureUser.UserId)) {
            $normalizedLower = $azureUser.UserId.ToLowerInvariant()
        }

        $azureUserNamesNormalized += $normalizedLower
    }

    $usersToAdd = @()
    foreach ($user in $githubUsers) {
        if ([string]::IsNullOrWhiteSpace($user)) {
            continue
        }

        $normalized = $user.ToLowerInvariant()
        if ($azureUserNamesNormalized -notcontains $normalized) {
            $usersToAdd += $user
        }
    }

    $usersToRemove = @()
    foreach ($azureUser in $azureUsers) {
        $normalizedLower = ""
        if ($azureUser.PSObject.Properties.Name -contains "NormalizedNameLower") {
            $normalizedLower = $azureUser.NormalizedNameLower
        }

        if ([string]::IsNullOrWhiteSpace($normalizedLower)) {
            $usersToRemove += $azureUser
            continue
        }

        if ($githubUsersNormalized -notcontains $normalizedLower) {
            $usersToRemove += $azureUser
        }
    }
    
    Write-Log "追加対象ユーザー数: $($usersToAdd.Count)" -Level INFO
    if ($usersToAdd.Count -gt 0) {
        $usersToAdd | ForEach-Object { Write-Log "  - $_" -Level INFO }
    }
    
    Write-Log "削除対象ユーザー数: $($usersToRemove.Count)" -Level INFO
    if ($usersToRemove.Count -gt 0) {
        foreach ($user in $usersToRemove) {
            $label = if ($user.PSObject.Properties.Name -contains "DisplayName" -and -not [string]::IsNullOrWhiteSpace($user.DisplayName)) {
                $user.DisplayName
            }
            elseif ($user.PSObject.Properties.Name -contains "NormalizedName" -and -not [string]::IsNullOrWhiteSpace($user.NormalizedName)) {
                $user.NormalizedName
            }
            elseif ($user.PSObject.Properties.Name -contains "UserId" -and -not [string]::IsNullOrWhiteSpace($user.UserId)) {
                $user.UserId
            }
            else {
                "(unknown)"
            }

            Write-Log "  - $label" -Level INFO
        }
    }
    
    if ($usersToAdd.Count -eq 0 -and $usersToRemove.Count -eq 0) {
        Write-Log "同期が必要なユーザーはありません" -Level SUCCESS
        Write-Log "========================================" -Level INFO
        exit 0
    }
    
    Write-Log "========================================" -Level INFO
    
    if ($DryRun) {
        Write-Log "ドライランモードのため、変更は適用されません" -Level WARNING
        Write-Log "========================================" -Level INFO
        exit 0
    }
    
    # 4. ユーザー同期
    $successCount = 0
    $failureCount = 0
    $invitations = @()
    
    # 新規ユーザーを追加
    if ($usersToAdd.Count -gt 0) {
        Write-Log "ユーザーを追加中..." -Level INFO
        foreach ($user in $usersToAdd) {
            $result = Add-AzureStaticWebAppUser -AppName $AppName -ResourceGroup $ResourceGroup -UserName $user
            if ($result.Success) {
                $successCount++
                if ($result.InvitationUrl) {
                    $invitations += $result
                }
            }
            else {
                $failureCount++
            }
        }
    }
    
    # 不要なユーザーを削除
    if ($usersToRemove.Count -gt 0) {
        Write-Log "ユーザーを削除中..." -Level INFO
        foreach ($user in $usersToRemove) {
            $userId = if ($user.PSObject.Properties.Name -contains "UserId") { $user.UserId } else { "" }
            $displayName = if ($user.PSObject.Properties.Name -contains "DisplayName") { $user.DisplayName } else { "" }
            $provider = if ($user.PSObject.Properties.Name -contains "Provider") { $user.Provider } else { "" }

            if (Remove-AzureStaticWebAppUser -AppName $AppName -ResourceGroup $ResourceGroup -UserId $userId -DisplayName $displayName -Provider $provider) {
                $successCount++
            }
            else {
                $failureCount++
            }
        }
    }
    
    # 結果サマリー
    Write-Log "========================================" -Level INFO
    Write-Log "同期完了" -Level SUCCESS
    Write-Log "成功: $successCount 件" -Level SUCCESS
    Write-Log "失敗: $failureCount 件" -Level $(if ($failureCount -gt 0) { "ERROR" } else { "INFO" })
    Write-Log "========================================" -Level INFO
    
    # 5. GitHub Discussionに招待リンクを投稿
    if ($invitations.Count -gt 0 -and $config.Discussion.Enabled) {
        Write-Log "========================================" -Level INFO
        Write-Log "GitHub Discussionに招待リンクを投稿中..." -Level INFO
        
        try {
            # テンプレートファイルを読み込む
            $bodyTemplate = Get-TemplateContent -TemplatePath (Join-Path $PSScriptRoot ".." $config.Discussion.BodyTemplate)
            
            # 各ユーザーごとに個別のDiscussionを作成
            $successCount = 0
            $failCount = 0
            
            foreach ($invitation in $invitations) {
                try {
                    # タイトルのプレースホルダーを置換
                    $title = $config.Discussion.Title -replace "\{username\}", $invitation.UserName
                    
                    # 本文のプレースホルダーを置換
                    $body = $bodyTemplate -replace "\{\{USERNAME\}\}", $invitation.UserName
                    $body = $body -replace "\{\{INVITATION_URL\}\}", $invitation.InvitationUrl
                    
                    # Discussionを作成
                    $discussionUrl = New-GitHubDiscussion `
                        -Repo $GitHubRepo `
                        -CategoryId $config.Discussion.CategoryId `
                        -Title $title `
                        -Body $body
                    
                    Write-Log "Discussionを投稿しました: $($invitation.UserName) -> $discussionUrl" -Level SUCCESS
                    $successCount++
                }
                catch {
                    Write-Log "Discussion投稿に失敗しました（$($invitation.UserName)）: $_" -Level ERROR
                    $failCount++
                }
            }
            
            Write-Log "Discussion投稿完了: 成功 $successCount 件、失敗 $failCount 件" -Level INFO
            
            if ($failCount -gt 0) {
                Write-Log "一部のDiscussion投稿に失敗しましたが、招待は完了しています" -Level WARNING
            }
        }
        catch {
            Write-Log "Discussion投稿処理に失敗しました: $_" -Level ERROR
            Write-Log "招待は完了していますが、リンクの通知ができませんでした" -Level WARNING
        }
        
        Write-Log "========================================" -Level INFO
    }
    
    if ($failureCount -gt 0) {
        exit 1
    }
}
catch {
    Write-Log "予期しないエラーが発生しました: $_" -Level ERROR
    Write-Log "スタックトレース: $($_.ScriptStackTrace)" -Level ERROR
    exit 1
}
