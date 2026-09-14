#!/usr/bin/env python3
"""P7.2C-R1.1 paired natural experiment funnel + residence distribution + flow ledger.

Aggregation rules (locked by tests/cognition/test_p7_2b_aggregation.py):
- lifetime / residence avg / median / p90 computed from POOLED raw samples.
- unique asked = global set union; per-run sums reported separately.
- HOLDER rows attributed by goal_id prefix; generic terminations counted once.
- found→ask funnel joins seek_found events to subsequent ask events by goal_id.
"""
import json
import statistics
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEEDS = list(range(61000, 61010))


def load(profile: str, seed: int, base: str = "p7_2c_r11") -> dict:
    path = ROOT / ".tmp" / base / "natural" / f"{profile}-{seed}.json"
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def is_holder(row: dict) -> bool:
    return str(row.get("goal_id", "")).startswith("INFO:HOLDER") \
        or str(row.get("query_kind", "")) == "HOLDER"


def holder_lifecycle_samples(data: dict) -> dict:
    created = 0
    created_tick = {}
    lifetimes = []
    cancel_reasons = Counter()
    resolved = 0
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
            if gid in created_tick and created_tick[gid] != -1:
                cancel_reasons[str(row.get("reason_code", row.get("reason", "?")))] += 1
                lifetimes.append(max(0, tick - created_tick[gid]))
                created_tick[gid] = -1
        elif ev in ("GOAL_RESOLVED", "HOLDER_GOAL_RESOLVED"):
            if gid in created_tick and created_tick[gid] != -1:
                resolved += 1
                lifetimes.append(max(0, tick - created_tick[gid]))
                created_tick[gid] = -1
    return {"created": created, "lifetimes": lifetimes,
            "cancel_reasons": cancel_reasons, "resolved": resolved,
            "surviving": sum(1 for t in created_tick.values() if t != -1)}


def lifetime_stats(lifetimes: list) -> dict:
    if not lifetimes:
        return {"count": 0, "avg": None, "median": None, "p90": None,
                "min": None, "max": None, "le1": 0, "gt1": 0}
    ordered = sorted(lifetimes)
    return {"count": len(ordered), "avg": round(sum(ordered) / len(ordered), 4),
            "median": statistics.median(ordered),
            "p90": ordered[max(0, int(len(ordered) * 0.9) - 1)],
            "min": ordered[0], "max": ordered[-1],
            "le1": sum(1 for x in ordered if x <= 1),
            "gt1": sum(1 for x in ordered if x > 1)}


def pooled_stats(samples_list: list) -> dict:
    """Pool raw lifetimes from many runs, then compute stats once."""
    pooled_lifetimes = []
    created = 0
    resolved = 0
    surviving = 0
    cancel_reasons = Counter()
    for s in samples_list:
        pooled_lifetimes.extend(s["lifetimes"])
        created += s["created"]
        resolved += s["resolved"]
        surviving += s["surviving"]
        cancel_reasons.update(s["cancel_reasons"])
    out = {"holder_goals": created, "holder_resolved": resolved,
           "holder_surviving": surviving,
           "holder_cancel_reasons": dict(cancel_reasons)}
    out.update(lifetime_stats(pooled_lifetimes))
    return out


def asked_actor_ids(data: dict) -> set:
    return {str(e.get("target_id", "")) for e in data.get("events", [])
            if e.get("type") == "holder_information_requested"}


def found_then_ask_funnel(data: dict) -> dict:
    """Join seek_found events to subsequent ask events by goal_id + target."""
    found_events = []
    ask_events = []
    goal_terminal = {}
    for e in data.get("events", []):
        t = str(e.get("type", ""))
        gid = str(e.get("information_goal_id", ""))
        tick = int(e.get("tick", 0))
        if t == "holder_seek_found_person":
            found_events.append({"goal_id": gid, "tick": tick,
                                "target": str(e.get("target_id", ""))})
        elif t == "holder_information_requested":
            ask_events.append({"goal_id": gid, "tick": tick,
                              "target": str(e.get("target_id", ""))})
    # Goal terminal reasons (from information trace)
    for row in data.get("information_subgoal_trace", []):
        if is_holder(row) and str(row.get("event", "")) in ("GOAL_CANCELLED", "HOLDER_GOAL_CANCELLED"):
            goal_terminal[str(row.get("goal_id", ""))] = str(row.get("reason_code", "?"))
    out = {"found_count": len(found_events)}
    matched = 0
    terminal_before = 0
    alive_without = 0
    for f in found_events:
        # Look for an ask on the same goal after the found tick.
        asked = False
        for a in ask_events:
            if a["goal_id"] == f["goal_id"] and a["tick"] >= f["tick"]:
                asked = True
                break
        if asked:
            matched += 1
        elif f["goal_id"] in goal_terminal:
            terminal_before += 1
        else:
            alive_without += 1
    out["found_then_ask"] = matched
    out["found_goal_terminal_before_ask"] = terminal_before
    out["found_alive_without_ask"] = alive_without
    return out


def residence_and_flow(data: dict) -> dict:
    obj = data.get("summary", {}).get("objective_material_audit", {}) or {}
    out = {}
    for item in ("wood", "shells"):
        samples = obj.get(f"residence_duration_samples_{item}", [])
        closed = lifetime_stats(samples)
        out[f"residence_{item}"] = closed
        out[f"residence_{item}_censored_count"] = int(obj.get(f"residence_censored_count_{item}", 0))
        out[f"residence_{item}_censored_sum"] = int(obj.get(f"residence_censored_duration_sum_{item}", 0))
        out[f"carriage_{item}"] = int(obj.get(f"carriage_{item}_actor_ticks", 0))
        # Flow ledger
        out[f"acquired_{item}"] = int(obj.get(f"material_acquired_units_{item}", 0))
        for sink in ("SHELTER", "FIRE", "CRAFT"):
            out[f"consumed_{item}_{sink}"] = int(obj.get(f"material_consumed_units_{item}_{sink}", 0))
        out[f"craft_consuming_{item}"] = int(obj.get(f"craft_success_consuming_{item}", 0))
        out[f"surplus_events_{item}"] = int(obj.get(f"post_craft_surplus_actor_events_{item}", 0))
    return out


def main() -> int:
    all_lifetimes = []
    all_found_funnel = Counter()
    all_residence = defaultdict(list)
    totals = Counter()
    for profile in ("holder_evidence", "holder_reachability"):
        for seed in SEEDS:
            data = load(profile, seed)
            if not data:
                continue
            lc = holder_lifecycle_samples(data)
            all_lifetimes.extend(lc["lifetimes"])
            fta = found_then_ask_funnel(data)
            for k, v in fta.items():
                all_found_funnel[f"{profile}_{k}"] += v
            rf = residence_and_flow(data)
            for k, v in rf.items():
                if isinstance(v, dict) and "count" in v:
                    # pool raw samples
                    pass
                elif isinstance(v, (int, float)):
                    totals[f"{profile}_{k}"] += v
            # accumulate raw residence samples
            obj = data.get("summary", {}).get("objective_material_audit", {}) or {}
            for item in ("wood", "shells"):
                samples = obj.get(f"residence_duration_samples_{item}", [])
                if samples:
                    all_residence[f"{profile}_{item}"].extend(samples)
    print("=== HOLDER lifecycle (pooled) ===")
    print(json.dumps(lifetime_stats(all_lifetimes), indent=1))
    print()
    print("=== FOUND→ASK funnel ===")
    for k in sorted(all_found_funnel):
        print(f"  {k}: {all_found_funnel[k]}")
    print()
    print("=== Residence distribution (pooled raw samples) ===")
    for key, samples in sorted(all_residence.items()):
        if samples:
            print(f"  {key}: {json.dumps(lifetime_stats(samples), indent=1)}")
        else:
            print(f"  {key}: no samples")
    print()
    print("=== Flow ledger & surplus (totals) ===")
    for k in sorted(totals):
        print(f"  {k}: {totals[k]}")
    print()
    # Replay check
    replays = sum(1 for p in ("holder_evidence", "holder_reachability")
                  for s in SEEDS if load(p, s).get("replay_verified"))
    print(f"ALL_REPLAY_VERIFIED={replays == 20} ({replays}/20)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
