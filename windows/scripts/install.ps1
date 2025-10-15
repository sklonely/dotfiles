<# windows/scripts/install.ps1
順序：Scoop → 1Password → Git → uv → GlazeWM → Flow → Discord → ChatGPT
#>
$ErrorActionPreference = 'Stop'
function Info($m){ Write-Host "INFO  $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "WARN  $m" -ForegroundColor Yellow }
function Ok($m){ Write-Host "OK    $m" -ForegroundColor Green }
function Has-Cmd($n){ [bool](Get-Command $n -ErrorAction SilentlyContinue) }

# 通用安裝：先 Scoop，再 winget（支援 msstore）
function Install-App {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string[]]$ScoopPkgs = @(),
    [hashtable[]]$Winget = @()   # 例如 @{ Id="9NT1R1C2HH7J"; Source="msstore" }
  )
  Write-Host "`n=== 安裝：$Name ===" -ForegroundColor Magenta
  if (Has-Cmd $Name) { Ok "$Name 已存在"; return }
  $installed = $false

  foreach ($pkg in $ScoopPkgs) {
    try { Info "Scoop：$pkg"; scoop install $pkg -g; $installed=$true; break }
    catch { Warn "Scoop 安裝 $pkg 失敗，改試 winget…" }
  }
  if (-not $installed -and $Winget.Count -gt 0) {
    foreach ($w in $Winget) {
      $id=$w.Id; $src=$w.Source
      try {
        Info "winget：$id$([string]::IsNullOrWhiteSpace($src)?'':" (source=$src)")"
        $args=@("install","--id",$id,"-e","--accept-package-agreements","--accept-source-agreements")
        if ($src){ $args+=@("--source",$src) }
        winget @args
        $installed=$true; break
      } catch { Warn "winget 安裝 $id 失敗，嘗試下一個…" }
    }
  }
  if ($installed) { Ok "$Name 安裝完成" } else { Warn "$Name 安裝未成功" }
}

# 1) Scoop
Write-Host "`n=== [1/8] Scoop ===" -ForegroundColor Magenta
if (-not (Has-Cmd "scoop")) {
  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
  iwr -useb get.scoop.sh | iex
  Ok "Scoop 安裝完成"
} else { Ok "Scoop 已存在" }
scoop bucket add main   -q 2>$null | Out-Null
scoop bucket add extras -q 2>$null | Out-Null

# 2) 1Password（桌面版；CLI 之後要再加 1password-cli）
Install-App -Name "1password" -Winget @(@{ Id="AgileBits.1Password" })

# 3) Git
Install-App -Name "git" -ScoopPkgs @("git") -Winget @(@{ Id="Git.Git" })

# 4) uv（Astral）
Install-App -Name "uv" -ScoopPkgs @("uv") -Winget @(@{ Id="astral-sh.uv" })

# 5) GlazeWM
Install-App -Name "glazewm" -ScoopPkgs @("glazewm") -Winget @(@{ Id="glzr-io.glazewm" })

# 6) Flow Launcher
Install-App -Name "flow-launcher" -ScoopPkgs @("flow-launcher") -Winget @(@{ Id="Flow-Launcher.Flow-Launcher" })

# 7) Discord
Install-App -Name "discord" -ScoopPkgs @("discord") -Winget @(@{ Id="Discord.Discord" })

# 8) ChatGPT（Windows App / msstore）
Install-App -Name "chatgpt" -Winget @(@{ Id="9NT1R1C2HH7J"; Source="msstore" })

Ok "`n安裝腳本完成。"
exit 0
