#!/usr/bin/env python3
"""Import and run the rendering-independent world loop. No LLM credentials required."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
from pathlib import Path
import sys
from runtime_tools import ROOT, GAME, execute, resolve_godot, engine_errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot")
    parser.add_argument("--ticks", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=61000)
    parser.add_argument("--profile", choices=["legacy", "execution", "causal", "framework", "information", "material_request", "commitment", "holder_evidence"], default="framework")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--verify-replay", action="store_true")
    parser.add_argument("--skip-import", action="store_true", help="Only use after importing this exact source tree.")
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    try:
        godot = resolve_godot(args.godot)
        output = args.out.resolve()
        if output.exists() or output.with_name(output.name + ".tmp").exists(): raise ValueError("Output or temporary output already exists")
        if not 1 <= args.ticks <= 100000 or args.seed < 0 or args.seed > 9223372036854775807: raise ValueError("Invalid ticks or seed")
        if args.timeout < 1: raise ValueError("--timeout must be positive")
        logs = ROOT / ".tmp" / ("run-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
        logs.mkdir(parents=True)
        if not args.skip_import:
            result = execute([str(godot), "--headless", "--path", str(GAME), "--editor", "--quit"], logs / "import.log", args.timeout)
            if result["exit"] or engine_errors(result["text"]):
                print(result["text"]); return 1
        command = [str(godot), "--headless", "--path", str(GAME), "--script", "res://src/runtime/simulation_cli.gd", "--",
                   f"--ticks={args.ticks}", f"--seed={args.seed}", f"--profile={args.profile}", f"--out={output}"]
        if args.verify_replay: command.append("--verify-replay")
        result = execute(command, logs / "simulation.log", args.timeout)
        print(result["text"], end="")
        print(f"RUN_LOGS {logs}")
        return 0 if result["exit"] == 0 and not engine_errors(result["text"]) and output.is_file() else 1
    except (OSError, ValueError) as exc:
        print(f"RUN_SETUP_FAIL {exc}"); return 2

if __name__ == "__main__": raise SystemExit(main())
