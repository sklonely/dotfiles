from __future__ import annotations
import json, os, shutil, subprocess, sys, time
from pathlib import Path
import typer

app = typer.Typer(help="Dotfiles Windows Orchestrator")

TEMP_SUMMARY = Path(os.environ.get("TEMP", str(Path.home() / "AppData/Local/Temp"))) / "dotfiles_stage1_result.json"

def write_summary(stage: str, ok: bool, message: str, extra: dict | None = None, code: int = 0):
    data = {
        "stage": stage,
        "ok": ok,
        "message": message,
        "extra": extra or {},
        "ts": time.time(),
    }
    TEMP_SUMMARY.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    # 讓 pwsh 主控可用「讀最後一行」快速抓
    print("STAGE_SUMMARY:" + json.dumps(data, ensure_ascii=False))
    sys.exit(code)

def run(cmd: list[str], check=True, capture=False):
    return subprocess.run(cmd, check=check,
                          stdout=(subprocess.PIPE if capture else None),
                          stderr=(subprocess.STDOUT if capture else None),
                          text=True)

def ensure_dir(p: Path): p.mkdir(parents=True, exist_ok=True)

def mk_junction(link: Path, target: Path):
    # 用 cmd mklink /J（在 Windows）
    if link.exists() or link.is_symlink():
        try:
            if link.is_symlink(): link.unlink()
            else: shutil.rmtree(link)
        except Exception:
            pass
    ensure_dir(link.parent)
    run(["cmd", "/c", "mklink", "/J", str(link), str(target)])

def robocopy_sync(src: Path, dst: Path):
    ensure_dir(dst)
    run(["robocopy", str(src), str(dst), "/MIR", "/NFL", "/NDL", "/NJH", "/NJS", "/NP"], check=False)

def schtasks_create_glazewm():
    tn = r"\GlazeWM\Start"
    # 刪除既有
    run(["schtasks", "/Delete", "/TN", tn, "/F"], check=False)
    # 建立（最高權限）
    run(["schtasks", "/Create", "/TN", tn, "/SC", "ONLOGON", "/RL", "HIGHEST", "/TR", "glazewm start"])

def which(name: str) -> Path | None:
    p = shutil.which(name)
    return Path(p) if p else None

def winget_list_id(app_id: str) -> bool:
    try:
        r = run(["winget", "list", "--id", app_id], check=False, capture=True)
        return (r.returncode == 0) and (app_id.lower() in r.stdout.lower())
    except Exception:
        return False

# ---------- Commands ----------
@app.command()
def link_glazewm(repo: Path, apply: bool = False):
    src = repo / "windows" / "settings" / "glazewm"
    dst = Path.home() / ".glzr" / "glazewm"
    if not src.exists():
        write_summary("settings", False, f"missing {src}", code=30)
    if apply:
        mk_junction(dst, src)
        write_summary("settings", True, f"linked {dst} -> {src}")
    else:
        write_summary("settings", True, f"dry-run link {dst} -> {src}")

@app.command()
def sync_zebar(repo: Path, apply: bool = False):
    src = repo / "windows" / "settings" / "zebar"
    dst = Path(os.environ.get("APPDATA", "")) / "zebar"
    if not src.exists():
        write_summary("settings", True, f"skip (missing {src})")
    if apply:
        robocopy_sync(src, dst)
        write_summary("settings", True, f"synced {src} -> {dst}")
    else:
        write_summary("settings", True, f"dry-run sync {src} -> {dst}")

@app.command()
def task_glazewm():
    try:
        schtasks_create_glazewm()
        write_summary("task", True, "task created")
    except subprocess.CalledProcessError as e:
        write_summary("task", False, f"schtasks failed: {e}", code=31)

@app.command()
def reload_glazewm():
    run(["glazewm", "stop"], check=False)
    run(["glazewm", "start"])
    write_summary("reload", True, "glazewm restarted")

@app.command()
def ensure_chatgpt():
    # 如果 OpenAI.ChatGPT 沒裝，再試 9NT1R1C2HH7J
    ok = winget_list_id("OpenAI.ChatGPT") or winget_list_id("9NT1R1C2HH7J")
    if ok:
        write_summary("postcheck", True, "ChatGPT present")
    # 嘗試安裝
    tried = []
    for candidate in ["OpenAI.ChatGPT", "9NT1R1C2HH7J"]:
        tried.append(candidate)
        r = run(["winget", "install", "--id", candidate, "-e",
                 "--accept-package-agreements", "--accept-source-agreements"], check=False, capture=True)
        if r.returncode == 0:
            write_summary("postcheck", True, f"ChatGPT installed ({candidate})")
    write_summary("postcheck", False, f"ChatGPT not installed; tried: {tried}", code=21)

if __name__ == "__main__":
    app()