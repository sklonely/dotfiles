<# bootstrap.ps1
功能：
  1) 紀錄完整日誌（Start-Transcript）
  2) 檢查/安裝 Git
  3) 下載/更新 https://github.com/sklonely/dotfiles.git
  4) 執行 windows/scripts/install.ps1 → settings_install.ps1
  5) 出錯時不自動關閉視窗，顯示錯誤並等待按鍵

用法（建議系統管理員 PowerShell）：
  irm https://raw.githubusercontent.com/sklonely/dotfiles/main/windows/bootstrap.ps1 | iex
#>

param(
  [string]$Branch = "main",
  [switch]$ApplyDotfiles,
  [string]$LogPath # 可自訂日誌檔路徑；未提供則自動產生
)

# ===== 共用工具 =====
$ErrorActionPreference = 'Stop'
function Has-Cmd($n){ [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function Info($m){ Write-Host "INFO  $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "WARN  $m" -ForegroundColor Yellow }
function Ok($m){ Write-Host "OK    $m" -ForegroundColor Green }

# ===== 常數 =====
$RepoUrl  = "https://github.com/sklonely/dotfiles.git"
$HOME     = $env:USERPROFILE
$RepoRoot = Join-Path $HOME "dev"
$RepoPath = Join-Path $RepoRoot "dotfiles"

# ===== 日誌檔 =====
if (-not $LogPath -or [string]::IsNullOrWhiteSpace($LogPath)) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $LogPath = Join-Path $HOME ("bootstrap_{0}.log" -f $stamp)
}
try {
  # 若已經在 Transcript 中，避免重複開啟報錯
  if (-not (Get-Variable -Name global:TranscriptStarted -ErrorAction SilentlyContinue)) {
    Start-Transcript -Path $LogPath -Append | Out-Null
    $global:TranscriptStarted = $true
    Info ("日誌寫入：{0}" -f $LogPath)
  }
} catch {
  Warn ("Start-Transcript 失敗：{0}" -f $_.Exception.Message)
}

# ===== 提權（相容 5.1；不使用 ?: 三元） =====
try {
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Info "以管理員權限重新啟動 bootstrap.ps1…"
    $argList = @(
      '-NoProfile','-ExecutionPolicy','Bypass',
      '-File', ('"{0}"' -f $PSCommandPath),
      '-Branch', ('"{0}"' -f $Branch),
      '-LogPath', ('"{0}"' -f $LogPath)
    )
    if ($ApplyDotfiles) { $argList += '-ApplyDotfiles' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    exit
  }
} catch {
  # 若判斷提權出現例外，仍嘗試繼續但記錄訊息
  Warn ("提權檢查失敗：{0}" -f $_.Exception.Message)
}

# ===== 主流程 =====
try {
  try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force } catch {}
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  # 1) 安裝 Git
  if (-not (Has-Cmd "git")) {
    Info "安裝 Git（winget）…"
    try {
      winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
    } catch {
      throw "winget 安裝 Git 失敗，請手動安裝 Git 後重試。`n原始錯誤：$($_.Exception.Message)"
    }
  } else { Ok "Git 已存在。" }

  # 2) 取得/更新 repo
  New-Item -ItemType Directory -Force -Path $RepoRoot | Out-Null
  if (-not (Test-Path $RepoPath)) {
    Info ("Clone：{0} → {1}（{2}）" -f $RepoUrl, $RepoPath, $Branch)
    git clone --branch $Branch --depth 1 $RepoUrl $RepoPath
  } else {
    Info "更新 repo：$RepoPath"
    Push-Location $RepoPath
    git fetch origin $Branch --prune
    git checkout $Branch
    git pull --rebase origin $Branch
    Pop-Location
  }

  # 3) 執行腳本
  $InstallScript  = Join-Path $RepoPath "windows\scripts\install.ps1"
  $SettingsScript = Join-Path $RepoPath "windows\scripts\settings_install.ps1"
  if (-not (Test-Path $InstallScript))  { throw "找不到 $InstallScript" }
  if (-not (Test-Path $SettingsScript)) { throw "找不到 $SettingsScript" }

  Write-Host "`n=== [1/2] 執行 install.ps1 ===`n" -ForegroundColor Magenta
  & $InstallScript
  if ($LASTEXITCODE -ne 0) { throw "install.ps1 執行失敗（ExitCode=$LASTEXITCODE）" }

  Write-Host "`n=== [2/2] 執行 settings_install.ps1 ===`n" -ForegroundColor Magenta
  $settingsArgs = @('-DotfilesRepoPath', $RepoPath)
  if ($ApplyDotfiles) { $settingsArgs += '-ApplyDotfiles' }
  & $SettingsScript @settingsArgs
  if ($LASTEXITCODE -ne 0) { throw "settings_install.ps1 執行失敗（ExitCode=$LASTEXITCODE）" }

  Ok "`n✅ 完成！GlazeWM 與 Zebar 已設定自啟。建議登出/重開確認環境。"
}
catch {
  Write-Host "`n❌ 發生錯誤：" -ForegroundColor Red
  Write-Host $_.Exception.Message -ForegroundColor Red
  # 顯示更完整的錯誤（含堆疊）
  if ($_.ScriptStackTrace) {
    Write-Host "`nStackTrace:" -ForegroundColor DarkRed
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
  }
  Write-Host "`n日誌檔：$LogPath" -ForegroundColor Yellow
  Write-Host "`n按任意鍵關閉視窗…" -ForegroundColor Yellow
  $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
finally {
  try {
    if (Get-Variable -Name global:TranscriptStarted -ErrorAction SilentlyContinue) {
      Stop-Transcript | Out-Null
      Remove-Variable -Name global:TranscriptStarted -Scope Global -ErrorAction SilentlyContinue
    }
  } catch {}
}
