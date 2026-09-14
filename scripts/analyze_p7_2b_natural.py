#!/usr/bin/env python3
"""P7.2B-R1.1 paired natural experiment funnel (commitment vs holder_evidence).

Aggregation rules (locked by tests/cognition/test_p7_2b_aggregation.py):
- lifetime avg / median / p90 / min / max are computed from the POOLED raw
  per-goal lifetime samples across all runs, never from per-run averages.
- unique asked actors are reported as global_unique_actor_ids (set union);
  per-run unique sums are reported separately, never as "unique".
- HOLDER rows are attributed by goal_id prefix "INFO:HOLDER:" with the
  query_kind field as a secondary check; generic GOAL_CANCELLED /
  GOAL_RESOLVED terminations count exactly once per goal.
"""
import json
import statistics
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEEDS = list(range(61000, 61010))


def load(profile: str, seed: int) -> dict:
    path = ROOT / ".tmp/p7_2b_r11/natural" / f"{profile}-{seed}.json"
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def is_holder(row: dict) -> bool:
    return str(row.get("goal_id", "")).startswith("INFO:HOLDER") \
        or str(row.get("query_kind", "")) == "HOLDER"


def holder_lifecycle_samples(data: dict) -> dict:
    """Raw samples: created count, lifetimes list, terminal reasons, resolved."""
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
                reason = str(row.get("reason_code", row.get("reason", "?")))
                cancel_reasons[reason] += 1
                lifetimes.append(max(0, tick - created_tick[gid]))
                created_tick[gid] = -1
        elif ev in ("GOAL_RESOLVED", "HOLDER_GOAL_RESOLVED"):
            if gid in created_tick and created_tick[gid] != -1:
                resolved += 1
                lifetimes.append(max(0, tick - created_tick[gid]))
                created_tick[gid] = -1
    surviving = sum(1 for t in created_tick.values() if t != -1)
    return {
        "created": created,
        "lifetimes": lifetimes,
        "cancel_reasons": cancel_reasons,
        "resolved": resolved,
        "surviving": surviving,
    }


def lifetime_stats(lifetimes: list) -> dict:
    if not lifetimes:
        return {"count": 0, "avg": None, "median": None, "p90": None,
                "min": None, "max": None, "le1": 0, "gt1": 0}
    ordered = sorted(lifetimes)
    return {
        "count": len(ordered),
        "avg": round(sum(ordered) / len(ordered), 4),
        "median": statistics.median(ordered),
        "p90": ordered[max(0, int(len(ordered) * 0.9) - 1)],
        "min": ordered[0],
        "max": ordered[-1],
        "le1": sum(1 for x in ordered if x <= 1),
        "gt1": sum(1 for x in ordered if x > 1),
    }


def pooled_stats(samples_list: list) -> dict:
    """Pool raw samples from many runs, then compute aggregate stats once."""
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


def funnel(data: dict) -> dict:
    out = {"replay": data.get("replay_verified")}
    mc = data.get("summary", {}).get("material_request_counts", {})
    cc = data.get("summary", {}).get("commitment_counts", {})
    ev = data.get("summary", {}).get("event_counts", {})
    out["requests"] = mc.get("MATERIAL_REQUEST_CREATED", 0)
    out["no_subjective"] = mc.get("MATERIAL_REQUEST_NO_SUBJECTIVE_TARGET", 0)
    out["offered"] = mc.get("MATERIAL_REQUEST_OFFERED", 0)
    out["accepted"] = mc.get("MATERIAL_REQUEST_ACCEPTED", 0)
    out["refused"] = mc.get("MATERIAL_REQUEST_REFUSED", 0)
    out["counters"] = mc.get("MATERIAL_REQUEST_COUNTERED", 0)
    lc = holder_lifecycle_samples(data)
    out["holder_goals"] = lc["created"]
    out.update({"lifetime_" + k: v for k, v in lifetime_stats(lc["lifetimes"]).items()})
    out["holder_asks"] = ev.get("holder_information_requested", 0)
    out["holder_unique_asked_this_run"] = len(asked_actor_ids(data))
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
    out["transfers"] = ev.get("ITEM_TRANSFER_COMPLETED", 0)
    out["commitments"] = cc.get("COMMITMENT_CREATED", 0)
    out["commitments_fulfilled"] = cc.get("COMMITMENT_FULFILLED", 0)
    out["commitments_violated"] = cc.get("COMMITMENT_VIOLATED", 0)
    out["crafted"] = ev.get("crafted", 0)
    out["diag"] = data.get("summary", {}).get("holder_funnel", {}) or {}
    return out


ADDITIVE_FUNNEL_KEYS = [
    "holder_active_ticks", "holder_decision_ticks",
    "holder_ticks_with_visible_peers", "holder_ticks_with_eligible_peers",
    "holder_ticks_with_no_eligible_peer",
    "holder_ask_candidates_emitted", "holder_ask_actions_selected",
    "holder_ask_actions_started", "holder_ask_actions_completed",
    "holder_ask_target_missed", "holder_queries_received",
    "holder_responder_self_holder_at_query",
    "holder_responder_fresh_third_party_available",
    "holder_responder_stale_third_party_available",
    "holder_peer_excluded_already_asked",
    "holder_peer_excluded_request_refused",
]


def main() -> int:
    per_run = {"commitment": [], "holder_evidence": []}
    for seed in SEEDS:
        for profile in ("commitment", "holder_evidence"):
            data = load(profile, seed)
            if data:
                per_run[profile].append((seed, funnel(data)))
    print("seed | profile | requests no_subj goals asks shared self_absent")
    for profile, runs in per_run.items():
        for seed, f in runs:
            print(f"{seed} {profile} {f['requests']} {f['no_subjective']} "
                  f"{f['holder_goals']} {f['holder_asks']} {f['holder_shared']} "
                  f"{f['holder_self_absent']}")
    print()
    for profile, runs in per_run.items():
        totals = Counter()
        for _, f in runs:
            for k in ["requests", "no_subjective", "offered", "accepted",
                      "refused", "counters", "holder_goals", "holder_asks",
                      "holder_shared", "holder_self_reports",
                      "holder_third_party", "holder_self_absent",
                      "holder_unknown", "holder_refused", "holder_stale",
                      "transfers", "commitments", "commitments_fulfilled",
                      "commitments_violated", "crafted"]:
                totals[k] += f[k]
            for k in ADDITIVE_FUNNEL_KEYS:
                totals["diag_" + k] += int((f.get("diag") or {}).get(k, 0))
        print(f"TOTAL {profile}: " + " ".join(f"{k}={v}" for k, v in sorted(totals.items())))
    samples = [holder_lifecycle_samples(load("holder_evidence", s)) for s in SEEDS]
    pooled = pooled_stats(samples)
    print()
    print("POOLED holder lifecycle (holder_evidence):", json.dumps(pooled, ensure_ascii=False))
    global_asked = set()
    per_run_unique_sum = 0
    for s in SEEDS:
        d = load("holder_evidence", s)
        if d:
            ids = asked_actor_ids(d)
            global_asked |= ids
            per_run_unique_sum += len(ids)
    print(f"unique_asked: global_unique_actor_ids={sorted(global_asked)} "
          f"per_run_unique_sum={per_run_unique_sum}")
    all_replay = all(f["replay"] for runs in per_run.values() for _, f in runs)
    print(f"ALL_REPLAY_VERIFIED={all_replay} runs={sum(len(r) for r in per_run.values())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
