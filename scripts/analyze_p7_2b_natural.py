#!/usr/bin/env python3
"""P7.2B-R1 paired natural experiment funnel (commitment vs holder_evidence).

HOLDER goal attribution is by stable goal_id prefix "INFO:HOLDER:" (with
query_kind field as a secondary check) - NOT by explicit event names only,
because generic _transition() rows (GOAL_CANCELLED etc.) also terminate
holder goals.
"""
import json
import statistics
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEEDS = list(range(61000, 61010))


def load(profile: str, seed: int) -> dict:
    path = ROOT / ".tmp/p7_2b_r1/natural" / f"{profile}-{seed}.json"
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def is_holder(row: dict) -> bool:
    return str(row.get("goal_id", "")).startswith("INFO:HOLDER") \
        or str(row.get("query_kind", "")) == "HOLDER"


def holder_lifecycle(data: dict) -> dict:
    """Created / terminal / surviving / lifetime stats / cancel reasons."""
    created = 0
    terminals = 0
    cancel_reasons = Counter()
    created_tick = {}
    lifetimes = []
    for row in data.get("information_subgoal_trace", []):
        if not is_holder(row):
            continue
        ev = str(row.get("event", ""))
        gid = str(row.get("goal_id", ""))
        tick = int(row.get("tick", 0))
        if ev == "HOLDER_GOAL_CREATED":
            created += 1
            created_tick[gid] = tick
        elif ev in ("GOAL_CANCELLED", "HOLDER_GOAL_CANCELLED"):
            # cancel_holder_goal emits both rows for one cancellation - count once.
            reason = str(row.get("reason_code", row.get("reason", "?")))
            if gid not in created_tick or created_tick[gid] != -1:
                terminals += 1
                cancel_reasons[reason] += 1
                if gid in created_tick:
                    lifetimes.append(max(0, tick - created_tick[gid]))
                    created_tick[gid] = -1  # mark terminal (count once)
        elif ev == "GOAL_RESOLVED":
            terminals += 1
            if gid in created_tick and created_tick[gid] != -1:
                lifetimes.append(max(0, tick - created_tick[gid]))
                created_tick[gid] = -1
    surviving = sum(1 for t in created_tick.values() if t != -1)
    out = {
        "holder_goals": created,
        "holder_terminal": terminals,
        "holder_surviving": surviving,
        "holder_cancel_reasons": dict(cancel_reasons),
    }
    if lifetimes:
        out["holder_lifetime_avg"] = round(sum(lifetimes) / len(lifetimes), 2)
        out["holder_lifetime_median"] = statistics.median(lifetimes)
        ordered = sorted(lifetimes)
        out["holder_lifetime_p90"] = ordered[max(0, int(len(ordered) * 0.9) - 1)]
        out["holder_lifetime_le1"] = sum(1 for x in lifetimes if x <= 1)
        out["holder_lifetime_gt1"] = sum(1 for x in lifetimes if x > 1)
    else:
        out["holder_lifetime_avg"] = None
        out["holder_lifetime_le1"] = 0
        out["holder_lifetime_gt1"] = 0
    return out


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
    # HOLDER 生命周期（前缀归属，含通用 GOAL_* 行）
    out.update(holder_lifecycle(data))
    out["holder_resolved"] = sum(
        1 for row in data.get("information_subgoal_trace", [])
        if is_holder(row) and str(row.get("event", "")) in ("GOAL_RESOLVED", "HOLDER_GOAL_RESOLVED")) // 2
    # 询问漏斗（世界事件）
    out["holder_asks"] = ev.get("holder_information_requested", 0)
    out["holder_unique_asked"] = len({
        str(e.get("target_id", "")) for e in data.get("events", [])
        if e.get("type") == "holder_information_requested"})
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
    out["holder_evidence_applied"] = sum(
        1 for row in data.get("information_subgoal_trace", [])
        if is_holder(row) and str(row.get("event", "")) == "HOLDER_EVIDENCE_APPLIED")
    out["transfers"] = ev.get("ITEM_TRANSFER_COMPLETED", 0)
    out["commitments"] = cc.get("COMMITMENT_CREATED", 0)
    out["commitments_fulfilled"] = cc.get("COMMITMENT_FULFILLED", 0)
    out["commitments_violated"] = cc.get("COMMITMENT_VIOLATED", 0)
    out["crafted"] = ev.get("crafted", 0)
    return out


def main() -> int:
    keys = ["replay", "requests", "no_subjective",
            "holder_goals", "holder_terminal", "holder_surviving",
            "holder_lifetime_avg", "holder_lifetime_le1", "holder_lifetime_gt1",
            "holder_asks", "holder_unique_asked", "holder_shared",
            "holder_self_reports", "holder_third_party", "holder_self_absent",
            "holder_unknown", "holder_refused", "holder_stale",
            "holder_evidence_applied", "offered", "accepted", "refused",
            "counters", "commitments", "commitments_fulfilled",
            "commitments_violated", "transfers", "crafted"]
    totals = {"commitment": Counter(), "holder_evidence": Counter()}
    all_cancel_reasons = Counter()
    print("seed | profile | " + " ".join(keys[1:]))
    for seed in SEEDS:
        for profile in ("commitment", "holder_evidence"):
            data = load(profile, seed)
            if not data:
                print(f"{seed} {profile} MISSING")
                continue
            f = funnel(data)
            for k in keys[1:]:
                if isinstance(f.get(k), (int, float)) and f.get(k) is not None:
                    totals[profile][k] += f[k]
            if profile == "holder_evidence":
                all_cancel_reasons.update(f["holder_cancel_reasons"])
            row = " ".join(str(f.get(k, 0)) for k in keys[1:])
            print(f"{seed} {profile} {row}")
    print()
    for profile, total in totals.items():
        print(f"TOTAL {profile}: " + " ".join(f"{k}={total[k]}" for k in keys[1:]))
    print("HOLDER cancel reasons (holder_evidence, prefix-attributed):",
          dict(all_cancel_reasons))
    all_replay = all(load(p, s).get("replay_verified") for s in SEEDS
                     for p in ("commitment", "holder_evidence"))
    print(f"ALL_REPLAY_VERIFIED={all_replay}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
