#!/usr/bin/env python3
"""P7.2 paired natural experiment analysis (material_request vs commitment)."""
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEEDS = list(range(61000, 61010))

MR_CREATED = "MATERIAL_REQUEST_CREATED"
COMMIT_EVENTS = [
    "COMMITMENT_CREATED", "COMMITMENT_ACTIVATED", "COMMITMENT_FULFILLED",
    "COMMITMENT_VIOLATED", "COMMITMENT_CANCELLED", "COMMITMENT_TERMS_MISMATCH",
    "COMMITMENT_TRANSFER_COMPLETED",
]


def load(profile: str, seed: int) -> dict:
    path = ROOT / ".tmp/p7_2/natural" / f"{profile}-{seed}.json"
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def stats(data: dict) -> dict:
    out = {"replay": data.get("replay_verified")}
    summary = data.get("summary", {})
    out["requests"] = summary.get("material_request_counts", {}).get(MR_CREATED, 0)
    mc = summary.get("material_request_counts", {})
    out["offers"] = mc.get("MATERIAL_REQUEST_OFFERED", 0)
    out["accepts"] = mc.get("MATERIAL_REQUEST_ACCEPTED", 0)
    out["refusals"] = mc.get("MATERIAL_REQUEST_REFUSED", 0)
    out["counters"] = mc.get("MATERIAL_REQUEST_COUNTERED", 0)
    out["counter_rejected"] = mc.get("MATERIAL_COUNTER_REJECTED", 0)
    out["counter_accepted"] = mc.get("MATERIAL_COUNTER_ACCEPTED", 0)
    cc = summary.get("commitment_counts", {})
    for name in COMMIT_EVENTS:
        key = name.replace("COMMITMENT_", "").lower()
        out[key] = cc.get(name, 0)
    ev = summary.get("event_counts", {})
    out["transfers"] = ev.get("ITEM_TRANSFER_COMPLETED", 0)
    out["revalidations"] = ev.get("PARENT_PLAN_REVALIDATED", 0)
    out["crafted"] = ev.get("crafted", 0)
    out["fished"] = ev.get("fished", 0)
    out["gathered_wood"] = ev.get("gathered_wood", 0)
    out["gathered_shells"] = ev.get("gathered_shells", 0)
    # exchange counters: counters whose trace rows show requires_exchange terms
    exchange = 0
    third_party_requests = 0
    for row in data.get("material_request_trace", []):
        pass  # counter terms live on request objects; count via counter events detail
    # unique actors in any material/commitment event
    actors = set()
    for e in data.get("events", []):
        t = str(e.get("type", ""))
        if t.startswith("MATERIAL_") or t in COMMIT_EVENTS or t == "ITEM_TRANSFER_COMPLETED":
            for key in ("requester_id", "debtor_id", "actor_id", "to_id", "to_actor_id"):
                v = str(e.get(key, ""))
                if v:
                    actors.add(v)
    out["unique_actors_touched"] = len(actors)
    return out


def main() -> int:
    keys = ["replay", "requests", "offers", "accepts", "refusals", "counters",
            "counter_rejected", "counter_accepted",
            "created", "activated", "fulfilled", "violated", "cancelled",
            "terms_mismatch", "transfer_completed",
            "transfers", "revalidations", "crafted", "fished",
            "gathered_wood", "gathered_shells", "unique_actors_touched"]
    totals = {"material_request": Counter(), "commitment": Counter()}
    print("seed | profile | " + " ".join(keys))
    for seed in SEEDS:
        for profile in ("material_request", "commitment"):
            data = load(profile, seed)
            if not data:
                print(f"{seed} {profile} MISSING")
                continue
            s = stats(data)
            for k in keys:
                if isinstance(s.get(k), (int, float)):
                    totals[profile][k] += s[k]
            print(f"{seed} {profile} " + " ".join(str(s.get(k, "")) for k in keys))
    print()
    for profile, total in totals.items():
        print(f"TOTAL {profile}: " + " ".join(f"{k}={total[k]}" for k in keys if k != "replay"))
    all_replay = all(load(p, s).get("replay_verified") for s in SEEDS for p in ("material_request", "commitment"))
    print(f"ALL_REPLAY_VERIFIED={all_replay}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
