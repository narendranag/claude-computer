"""Shared helpers for Python bin/ scripts. Mirrors lib/common.sh.

Import from a uv script with:
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
    import cc
"""

from __future__ import annotations

import base64
import json
import os
import platform
import shutil
import socket
import subprocess
import sys
from pathlib import Path

EX_OK, EX_FAIL, EX_USAGE, EX_DEPS, EX_LOCKED, EX_CONFIG = 0, 1, 2, 3, 4, 5
ROOT = Path(__file__).resolve().parent.parent
BW_PREFIX = os.environ.get("CC_BW_PREFIX", "claude-computer/")
_KC_SERVICE = "claude-computer-bw-session"


class CCError(Exception):
    def __init__(self, code: int, msg: str):
        super().__init__(msg)
        self.code = code


def host() -> str:
    if shutil.which("scutil"):
        r = subprocess.run(["scutil", "--get", "LocalHostName"], capture_output=True, text=True, check=False)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    return socket.gethostname().split(".")[0]


def _load_session() -> None:
    if os.environ.get("BW_SESSION"):
        return
    s = ""
    if platform.system() == "Darwin":
        r = subprocess.run(
            ["security", "find-generic-password", "-a", os.environ.get("USER", ""), "-s", _KC_SERVICE, "-w"],
            capture_output=True, text=True, check=False,
        )
        s = r.stdout.strip() if r.returncode == 0 else ""
    else:
        f = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "claude-computer-bw-session"
        s = f.read_text().strip() if f.is_file() else ""
    if s:
        os.environ["BW_SESSION"] = s


def _bw(*args: str, stdin: str | None = None) -> str:
    if not shutil.which("bw"):
        raise CCError(EX_DEPS, "missing dependency: bw")
    _load_session()
    r = subprocess.run(["bw", *args], input=stdin, capture_output=True, text=True, check=False)
    if r.returncode != 0:
        raise CCError(EX_FAIL, f"bw {args[0]} failed: {r.stderr.strip()}")
    return r.stdout


def require_unlocked() -> None:
    status = json.loads(_bw("status") or "{}").get("status", "unauthenticated")
    if status == "unauthenticated":
        raise CCError(EX_LOCKED, "Bitwarden not logged in. Run: bw login")
    if status != "unlocked":
        raise CCError(EX_LOCKED, "Bitwarden is locked. Run: secrets-unlock (in a terminal)")


def secret(name: str, field: str = "password") -> str:
    """password field, a custom field by name, or 'notes' of item <prefix><name>."""
    require_unlocked()
    item = BW_PREFIX + name
    try:
        if field in ("password", "notes"):
            v = _bw("get", field, item)
        else:
            data = json.loads(_bw("get", "item", item))
            v = next((f["value"] for f in data.get("fields") or [] if f["name"] == field), "")
    except CCError:
        v = ""
    if not v:
        raise CCError(EX_CONFIG, f"Bitwarden item '{item}' has no '{field}'. See docs/SECRETS.md")
    return v


def set_note(name: str, notes: str) -> None:
    """Create or update secure note <prefix><name>. Used only for OAuth tokens a wrapper minted."""
    require_unlocked()
    item = BW_PREFIX + name
    try:
        data = json.loads(_bw("get", "item", item))
    except CCError:
        data = None
    if data is None:
        tmpl = json.loads(_bw("get", "template", "item"))
        tmpl.update({"type": 2, "name": item, "notes": notes, "secureNote": {"type": 0}, "login": None})
        _bw("create", "item", _encode(tmpl))
    else:
        data["notes"] = notes
        _bw("edit", "item", data["id"], _encode(data))


def _encode(obj: dict) -> str:
    return base64.b64encode(json.dumps(obj).encode()).decode()


def run_main(fn) -> None:
    """Run fn(); turn CCError into '<script>: msg' on stderr and its exit code."""
    try:
        sys.exit(fn() or 0)
    except CCError as e:
        print(f"{Path(sys.argv[0]).name}: {e}", file=sys.stderr)
        sys.exit(e.code)
    except KeyboardInterrupt:
        sys.exit(130)
