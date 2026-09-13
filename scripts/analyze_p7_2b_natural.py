#!/usr/bin/env python3
"""P7.2B paired natural experiment funnel (commitment vs holder_evidence)."""
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEEDS = list(range(61000, 61010))


def load(profile: str, seed: int) -> dict:
    path = ROOT / ".tmp/p7_2b/natural" / f"{profile}-{seed}.json"
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def funnel(data: dict) -> dict:
    out = {"replay": data.get("replay_verified")}
    mc = data.get("summary", {}).get("material_request_counts", {})
    cc = data.get("summary", {}).get("commitment_counts", {})
    info = data.get("summary", {}).get("information_counts", {})
    ev = data.get("summary", {}).get("event_counts", {})
    out["requests"] = mc.get("MATERIAL_REQUEST_CREATED", 0)
    out["no_subjective"] = mc.get("MATERIAL_REQUEST_NO_SUBJECTIVE_TARGET", 0)
    out["offered"] = mc.get("MATERIAL_REQUEST_OFFERED", 0)
    out["accepted"] = mc.get("MATERIAL_REQUEST_ACCEPTED", 0)
    out["refused"] = mc.get("MATERIAL_REQUEST_REFUSED", 0)
    out["counters"] = mc.get("MATERIAL_REQUEST_COUNTERED", 0)
    # holder funnel（information trace 中的 HOLDER_* 事件）
    out["holder_goals"] = info.get("HOLDER_GOAL_CREATED", 0)
    out["holder_resolved"] = info.get("HOLDER_GOAL_RESOLVED", 0)
    out["holder_cancelled"] = info.get("HOLDER_GOAL_CANCELLED", 0)
    # 询问漏斗（世界事件）
    out["holder_asks"] = ev.get("holder_information_requested", 0)
    out["holder_shared"] = ev.get("holder_information_shared", 0)
    out["holder_self_reports"] = sum(
        1 for e in data.get("events", [])
        if e.get("type") == "holder_information_shared"
        and e.get("evidence_kind") == "SELF_REPORT")
    out["holder_third_party"] = sum(
        1 for e in data.get("events", [])
        if e.get("type") == "holder_information_shared"
        and e.get("evidence_kind") == "TOM_REPORT")
    out["holder_self_absent"] = ev.get("holder_information_self_absent", 0)
    out["holder_unknown"] = ev.get("holder_information_unknown", 0)
    out["holder_refused"] = ev.get("holder_information_refused", 0)
    out["holder_stale"] = ev.get("holder_information_stale", 0)
    out["holder_evidence_applied"] = info.get("HOLDER_EVIDENCE_APPLIED", 0)
    out["subjective_targets"] = out["offered"]  # OFFERED = 获得可操作主观目标
    out["transfers"] = ev.get("ITEM_TRANSFER_COMPLETED", 0)
    out["commitments"] = cc.get("COMMITMENT_CREATED", 0)
    out["commitments_fulfilled"] = cc.get("COMMITMENT_FULFILLED", 0)
    out["commitments_violated"] = cc.get("COMMITMENT_VIOLATED", 0)
    out["crafted"] = ev.get("crafted", 0)
    out["full_chains"] = 0  # 由链证据脚本另行判定
    out["three_plus"] = 0
    return out


def main() -> int:
    keys = ["replay", "requests", "no_subjective", "holder_goals", "holder_resolved",
            "holder_cancelled", "holder_asks", "holder_shared", "holder_self_reports",
            "holder_third_party", "holder_self_absent", "holder_unknown",
            "holder_refused", "holder_stale", "holder_evidence_applied",
            "offered", "accepted", "refused", "counters", "commitments",
            "commitments_fulfilled", "commitments_violated", "transfers", "crafted"]
    totals = {"commitment": Counter(), "holder_evidence": Counter()}
    print("seed | profile | " + " ".join(keys[1:]))
    for seed in SEEDS:
        for profile in ("commitment", "holder_evidence"):
            data = load(profile, seed)
            if not data:
                print(f"{seed} {profile} MISSING")
                continue
            f = funnel(data)
            for k in keys[1:]:
                totals[profile][k] += f[k]
            print(f"{seed} {profile} " + " ".join(str(f[k]) for k in keys[1:]))
    print()
    for profile, total in totals.items():
        print(f"TOTAL {profile}: " + " ".join(f"{k}={total[k]}" for k in keys[1:]))
    all_replay = all(load(p, s).get("replay_verified") for s in SEEDS
                     for p in ("commitment", "holder_evidence"))
    print(f"ALL_REPLAY_VERIFIED={all_replay}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
