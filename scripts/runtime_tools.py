"""Shared, standard-library-only utilities for local engine execution."""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import time
from typing import Sequence

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
ENV = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")


def _decode_output(data: bytes) -> str:
    """Decode subprocess output and normalize Windows console newlines.

    Godot's Windows console build can emit CRCRLF when stdout is captured by
    Python.  Leaving the duplicate carriage return in place breaks anchored
    SUMMARY parsing and creates blank lines when the evidence log is written.
    """
    return data.decode("utf-8", errors="replace").replace("\r\r\n", "\n").replace("\r\n", "\n").replace("\r", "\n")


def resolve_godot(supplied: str | None) -> Path:
    explicit = supplied or os.environ.get("GODOT_BIN")
    if explicit:
        expanded = Path(os.path.expandvars(explicit)).expanduser()
        path = expanded if expanded.is_file() else Path(shutil.which(str(expanded)) or str(expanded))
        if not path.is_file():
            raise ValueError(f"Godot executable not found: {explicit}")
        return path.resolve()
    for name in ("Godot_v4.7.2-stable_win64_console.exe", "Godot_v4.7.2-stable_linux.x86_64"):
        path = ROOT / "tools" / name
        if path.is_file(): return path.resolve()
    for name in ("godot4", "godot"):
        found = shutil.which(name)
        if found: return Path(found).resolve()
    raise ValueError("Supply --godot /path/to/engine or set GODOT_BIN.")


def source_fingerprint() -> str:
    """Hash runtime/test inputs, not caches, secrets, timestamps or output logs."""
    sha = hashlib.sha256()
    ignored = {".godot", ".tmp", "node_modules", "__pycache__", "docs"}
    paths = []
    for directory in ("game", "scripts", "narrative-learning", "lore", "tests"):
        for path in (ROOT / directory).rglob("*"):
            if not path.is_file() or any(p in ignored for p in path.relative_to(ROOT).parts): continue
            if path.name.endswith((".local.json", ".pyc", ".log")) or path.suffix == ".uid": continue
            paths.append(path)
    for path in sorted(paths):
        sha.update(path.relative_to(ROOT).as_posix().encode("utf-8") + b"\0")
        sha.update(path.read_bytes())
        sha.update(b"\0")
    return sha.hexdigest()


def execute(command: Sequence[str], log: Path, timeout: int = 300) -> dict:
    started = time.monotonic()
    try:
        result = subprocess.run(list(command), cwd=ROOT, env=ENV, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout, check=False)
        text = _decode_output(result.stdout)
        code = result.returncode
    except subprocess.TimeoutExpired as exc:
        text = _decode_output(exc.stdout or b"") + "\nRUNNER_TIMEOUT\n"
        code = 124
    except OSError as exc:
        text, code = f"RUNNER_OS_ERROR: {exc}\n", 127
    log.write_text(text, encoding="utf-8")
    return {"exit": code, "seconds": round(time.monotonic() - started, 3), "text": text}


def engine_errors(text: str, allowed: Sequence[str] = ()) -> list[str]:
    errors = []
    for line in text.splitlines():
        if "SCRIPT ERROR" in line or line.startswith("FAIL "):
            errors.append(line)
        elif line.startswith("ERROR:") and not any(line.startswith(prefix) for prefix in allowed):
            errors.append(line)
    return errors
