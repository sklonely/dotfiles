<# bootstrap.ps1
- 記錄日誌、可提權、錯誤停留
- 取得 repo：優先 Git；失敗→下載 ZIP（無需 Git）
- 執行：windows/scripts/install.ps1 → settings_install.ps1
用法（建議管理員）：irm https://raw.githubusercontent.com/sklonely/dotfiles/main/windows/bootstrap.ps1 | iex
#>

param(
  [string]$Branch = "main",
  [switch]$ApplyDotfiles,
  [string]$LogPath,
  [switch]$PreferZip   # 可選：強制走 ZIP（跳過 Git）
)

$ErrorActionPreference = 'Stop'
function Has-Cmd($n){ [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function Info($m){ Write-Host "INFO  $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "WARN  $m" -ForegroundColor Yellow }
function Ok($m){ Write-Host "OK    $m" -ForegroundColor Green }

# 常數
$RepoUrl   = "https://github.com/sklonely/dotfiles.git"
$RawSelf   = "https://raw.githubusercontent.com/sklonely/dotfiles/$Branch/windows/bootstrap.ps1"
$HomeDir   = $env:USERPROFILE
$RepoRoot  = Join-Path $HomeDir "dev"
$RepoPath  = Join-Path $RepoRoot "dotfiles"
$ZipUrl    = "https://github.com/sklonely/dotfiles/archive/refs/heads/$Branch.zip"

# 日誌
if (-not $LogPath -or [string]::IsNullOrWhiteSpace($LogPath)) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $LogPath = Join-Path $HomeDir ("bootstrap_{0}.log" -f $stamp)
}
try {
  if (-not (Get-Variable -Name global:TranscriptStarted -ErrorAction SilentlyContinue)) {
    Start-Transcript -Path $LogPath -Append | Out-Null
    $global:TranscriptStarted = $true
    Info ("日誌寫入：{0}" -f $LogPath)
  }
} catch { Warn ("Start-Transcript 失敗：{0}" -f $_.Exception.Message) }

# 提權（支援 irm|iex：沒實體檔就先下載到 TEMP 再提權）
try {
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Info "以管理員權限重新啟動 bootstrap.ps1…"
    $selfPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($selfPath)) {
      $selfPath = Join-Path $env:TEMP "bootstrap.ps1"
      Info "下載自身腳本到暫存：$selfPath"
      Invoke-WebRequest -UseBasicParsing -Uri $RawSelf -OutFile $selfPath
    }
    $argList = @(
      '-NoProfile','-ExecutionPolicy','Bypass',
      '-File', $selfPath,
      '-Branch', $Branch,
      '-LogPath', $LogPath
    )
    if ($ApplyDotfiles) { $argList += '-ApplyDotfiles' }
    if ($PreferZip)     { $argList += '-PreferZip' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    exit
  }
} catch { Warn ("提權檢查/重啟失敗：{0}" -f $_.Exception.Message) }

# 主流程
try {
  try { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force } catch {}
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  New-Item -ItemType Directory -Force -Path $RepoRoot | Out-Null

  # --- 取得/更新 repo：Git 優先；失敗→ZIP ---
  $gotRepo = $false
  if (-not $PreferZip) {
    if (Has-Cmd "git") {
      try {
        if (-not (Test-Path $RepoPath)) {
          Info ("Git clone：{0} → {1}（{2}）" -f $RepoUrl, $RepoPath, $Branch)
          git clone --branch $Branch --depth 1 $RepoUrl $RepoPath
        } else {
          Info "Git update：$RepoPath"
          Push-Location $RepoPath
          git fetch origin $Branch --prune
          git checkout $Branch
          git pull --rebase origin $Branch
          Pop-Location
        }
        $gotRepo = $true
      } catch {
        Warn ("Git 取得失敗：{0}" -f $_.Exception.Message)
      }
    } else {
      Warn "未安裝 Git，改用 ZIP 模式。"
    }
  }

  if (-not $gotRepo) {
    # ZIP 下載與解壓
    $tmp = Join-Path $env:TEMP ("dotfiles_{0}" -f ([System.Guid]::NewGuid().ToString("N")))
    $zip = "$tmp.zip"
    $ext = "$tmp"
    Info ("下載 ZIP：{0}" -f $ZipUrl)
    Invoke-WebRequest -UseBasicParsing -Uri $ZipUrl -OutFile $zip
    Info ("解壓到：{0}" -f $ext)
    Expand-Archive -Path $zip -DestinationPath $ext -Force
    # GitHub 檔名會是 dotfiles-<branch>
    $unz = Join-Path $ext ("dotfiles-{0}" -f $Branch)
    if (-not (Test-Path $unz)) {
      # branch 不是 main 時，名稱可能不同；抓第一個子資料夾兜底
      $dirs = Get-ChildItem $ext -Directory | Select-Object -First 1
      if ($dirs) { $unz = $dirs.FullName }
    }
    if (-not (Test-Path $unz)) { throw "ZIP 解壓後找不到 repo 內容。" }

    # 覆蓋到 $RepoPath（保留目標目錄，覆寫檔案）
    New-Item -ItemType Directory -Force -Path $RepoPath | Out-Null
    Info ("同步檔案到 {0}" -f $RepoPath)
    robocopy $unz $RepoPath /MIR /NFL /NDL /NJH /NJS /NP | Out-Null

    # 清理
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Remove-Item $ext -Recurse -Force -ErrorAction SilentlyContinue
    $gotRepo = $true
    Ok "已透過 ZIP 取得 repo。"
  }

  # --- 執行子腳本 ---
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
