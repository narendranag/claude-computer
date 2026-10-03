"""Shared helpers for Python bin/ scripts. Mirrors lib/common.sh.

Import from a uv script with:
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
    import cc
"""

from __future__ import annotations

import os
import re
import shutil
import socket
import subprocess
import sys
from pathlib import Path

EX_OK, EX_FAIL, EX_USAGE, EX_DEPS, EX_LOCKED, EX_CONFIG = 0, 1, 2, 3, 4, 5
ROOT = Path(os.environ.get("CC_ROOT") or Path(__file__).resolve().parent.parent)
SECRETS_FILE = Path(os.environ.get("CC_SECRETS_FILE") or ROOT / "secrets" / "secrets.yaml")
# sops's macOS default is ~/Library/Application Support/sops/age/keys.txt; launchd jobs and
# hooks never read ~/.zshenv, so the one path is set here too (as lib/common.sh does).
os.environ.setdefault("SOPS_AGE_KEY_FILE", str(Path.home() / ".config" / "sops" / "age" / "keys.txt"))
_NAME = re.compile(r"^[A-Za-z0-9_-]+$")


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


def _state(name: str, field: str) -> str:
    """enc | empty | plain | '' (absent) for <name>.<field>, read without decrypting.

    Mirrors cc_secrets_list in lib/common.sh: sops writes one key per line, values on one line.
    """
    top, ind = "", 0
    for line in SECRETS_FILE.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[0].isspace():
            top, ind = line.split(":", 1)[0], 0
            continue
        if top != name:
            continue
        cur = len(line) - len(line.lstrip(" "))
        ind = ind or cur
        if cur != ind:
            continue
        k, _, v = line.strip().partition(":")
        if k == field:
            v = v.strip()
            if v.startswith("ENC["):
                return "enc"
            return "empty" if v in ("", '""', "''") else "plain"
    return ""


def secret(name: str, field: str) -> str:
    """Decrypt one value, <name>.<field>, from secrets/secrets.yaml. Never an argument to anything."""
    if not (_NAME.match(name) and _NAME.match(field)):
        raise CCError(EX_USAGE, f"not a secret name: {name}.{field}")
    if not shutil.which("sops"):
        raise CCError(EX_DEPS, "missing dependency: sops")
    if not SECRETS_FILE.is_file():
        raise CCError(EX_CONFIG, f"no secrets store at {SECRETS_FILE}. See docs/SECRETS.md")
    state = _state(name, field)
    if state in ("", "empty"):
        raise CCError(EX_CONFIG, f"secret '{name}.{field}' is not set. A human runs: secrets set {name}.{field}")
    if state != "enc":
        raise CCError(EX_FAIL, f"secret '{name}.{field}' is stored unencrypted — see secrets/README.md")
    if not Path(os.environ["SOPS_AGE_KEY_FILE"]).is_file():
        raise CCError(EX_LOCKED, f"no age key at {os.environ['SOPS_AGE_KEY_FILE']}. Run: secrets init")
    r = subprocess.run(
        ["sops", "decrypt", "--extract", f'["{name}"]["{field}"]', str(SECRETS_FILE)],
        capture_output=True, text=True, check=False,
    )
    if r.returncode != 0:
        raise CCError(EX_LOCKED, f"this machine's age key can't open the store. On a manager: secrets admit {host()}")
    return r.stdout


def set_secret(name: str, field: str, value: str) -> None:
    """Store <name>.<field> through `secrets set`: value on stdin, then lock, commit and push."""
    if not (_NAME.match(name) and _NAME.match(field)):
        raise CCError(EX_USAGE, f"not a secret name: {name}.{field}")
    r = subprocess.run(
        [str(ROOT / "bin" / "secrets"), "set", f"{name}.{field}"],
        input=value, capture_output=True, text=True, check=False,
    )
    if r.returncode != 0:
        raise CCError(r.returncode, f"secrets set {name}.{field} failed: {r.stderr.strip()}")


def run_main(fn) -> None:
    """Run fn(); turn CCError into '<script>: msg' on stderr and its exit code."""
    try:
        sys.exit(fn() or 0)
    except CCError as e:
        print(f"{Path(sys.argv[0]).name}: {e}", file=sys.stderr)
        sys.exit(e.code)
    except KeyboardInterrupt:
        sys.exit(130)
