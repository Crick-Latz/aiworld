#!/usr/bin/env python3
"""Run the complete strict suite manifest on Linux or Windows with retained evidence."""
from __future__ import annotations
import argparse
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import sys
from runtime_tools import ROOT, GAME, execute, resolve_godot, source_fingerprint, engine_errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot")
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    try:
        godot = resolve_godot(args.godot)
        if args.timeout < 1: raise ValueError("--timeout must be positive")
        evidence = (args.evidence or ROOT / ".tmp" / ("strict-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))).resolve()
        if evidence.exists(): raise ValueError(f"Evidence directory already exists: {evidence}")
        node = shutil.which("node")
        if not node: raise ValueError("Node.js is required for the module boundary gate.")
        manifest = json.loads((ROOT / "scripts/strict_suites.json").read_text(encoding="utf-8"))
        suites = manifest["suites"]
        if manifest["schema_version"] != 1 or not suites: raise ValueError("Invalid suite manifest")
        evidence.mkdir(parents=True)
    except (ValueError, OSError, KeyError) as exc:
        print(f"STRICT_SETUP_FAIL {exc}"); return 2
    before = source_fingerprint()
    report = {"schema_version": 1, "scope": "FULL_MANIFEST", "source_sha256_before": before,
              "expected_suites": len(suites), "expected_assertions": sum(s["expected"] for s in suites),
              "engine": "", "gates": [], "suites": [], "ok": False}

    def gate(name, command, expected=None, allowed=(), expected_engine_errors=None):
        result = execute(command, evidence / (name + ".log"), args.timeout)
        text = result.pop("text")
        errors = engine_errors(text, allowed)
        if expected_engine_errors is not None:
            actual_errors = [line for line in text.splitlines() if line.startswith("ERROR:")]
            if Counter(actual_errors) != Counter(expected_engine_errors):
                errors.append("EXPECTED_FAULT_INJECTION_ERRORS_MISMATCH")
        row = dict(name=name, **result, errors=errors)
        row["ok"] = row["exit"] == 0 and not errors
        if expected is not None:
            summaries = re.findall(r"^SUMMARY(?::)? (?:pass|passed)=(\d+) (?:fail|failed)=(\d+)$", text, re.MULTILINE)
            passed, failed = map(int, summaries[0]) if len(summaries) == 1 else (-1, -1)
            row.update(expected=expected, passed=passed, failed=failed)
            row["ok"] = row["ok"] and passed == expected and failed == 0
        report["suites" if expected is not None else "gates"].append(row)
        (evidence / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        print(json.dumps(row, ensure_ascii=False), flush=True)
        return text, row["ok"]

    version, version_ok = gate("engine_version", [str(godot), "--version"])
    report["engine"] = version.strip()
    _, imported = gate("editor_import", [str(godot), "--headless", "--path", str(GAME), "--editor", "--quit"])
    if imported and version_ok:
        for suite in suites:
            command = [str(godot), "--headless"]
            if suite.get("fixed_fps"): command += ["--fixed-fps", str(suite["fixed_fps"])]
            command += ["--path", str(GAME), "--script", suite["script"]]
            gate(suite["name"], command, suite["expected"], suite.get("allowed_engine_errors", ()), suite.get("expected_engine_errors"))
    gate("module_boundaries", [node, str(ROOT / "scripts/check-module-boundaries.mjs")])
    text, python_ok = gate("cognitive_import_python", [sys.executable, "-m", "unittest", "discover", "-s", "tests/cognition", "-v"])
    found = re.search(r"Ran (\d+) tests? in", text)
    report["python_tests"] = int(found[1]) if found else 0
    report["source_sha256_after"] = source_fingerprint()
    report["source_unchanged"] = before == report["source_sha256_after"]
    report["passed_assertions"] = sum(max(row.get("passed", 0), 0) for row in report["suites"])
    report["ok"] = (len(report["suites"]) == len(suites) and all(row["ok"] for row in report["suites"] + report["gates"])
                    and report["source_unchanged"] and report["python_tests"] == 27 and python_ok)
    (evidence / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(f"STRICT_REGRESSION {'PASS' if report['ok'] else 'FAIL'} suites={len(report['suites'])} assertions={report['passed_assertions']} python_tests={report['python_tests']} evidence={evidence}", flush=True)
    return 0 if report["ok"] else 1

if __name__ == "__main__": raise SystemExit(main())
