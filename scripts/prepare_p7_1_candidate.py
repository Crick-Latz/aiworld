#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

T = "\t"


def joined(lines: list[str]) -> str:
    return "\n".join(lines)


def read(path: str) -> tuple[Path, str]:
    target = Path(path)
    return target, target.read_text(encoding="utf-8")


def write(target: Path, text: str) -> None:
    text = re.sub(r"(?m)^ +\t", "\t", text)
    text = re.sub(
        r"(?m)^(?:\\t)+",
        lambda match: T * (len(match.group(0)) // 2),
        text,
    )
    if re.search(r"(?m)^ +\t", text):
        raise SystemExit(f"mixed indentation remains in {target}")
    target.write_text(text.rstrip() + "\n", encoding="utf-8")


def replace_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, lambda _: replacement, text, count=1)
    if count != 1:
        raise SystemExit(f"{label} replacement count={count}")
    return updated


def patch_tracker() -> None:
    target, text = read("game/src/simulation/material_request/material_request_tracker.gd")
    replacement = joined([
        "func record_response(",
        f"{T}request_id: String,",
        f"{T}responder_id: String,",
        f"{T}outcome: String,",
        f"{T}tick: int,",
        f"{T}accepted_quantity: int = 0,",
        f"{T}reason: String = \"\",",
        f"{T}counter: Dictionary = {{}}",
        ") -> bool:",
        f"{T}if not _requests.has(request_id):",
        f"{T}{T}return false",
        f"{T}var request: Dictionary = _requests[request_id]",
        f"{T}if String(request.get(\"status\", \"\")) != Contract.STATUS_WAITING_RESPONSE:",
        f"{T}{T}return false",
        f"{T}if responder_id != String(request.get(\"target_id\", \"\")):",
        f"{T}{T}return false",
        f"{T}if outcome not in [Contract.OUTCOME_ACCEPT, Contract.OUTCOME_REFUSE, Contract.OUTCOME_COUNTER, Contract.OUTCOME_UNKNOWN]:",
        f"{T}{T}return false",
        "",
        f"{T}var resolved_quantity := 0",
        f"{T}if outcome == Contract.OUTCOME_ACCEPT:",
        f"{T}{T}var requested := int(request.get(\"requested_quantity\", 0))",
        f"{T}{T}resolved_quantity = accepted_quantity if accepted_quantity > 0 else requested",
        f"{T}{T}if resolved_quantity <= 0 or resolved_quantity > requested:",
        f"{T}{T}{T}return false",
        f"{T}elif outcome == Contract.OUTCOME_COUNTER:",
        f"{T}{T}resolved_quantity = int(counter.get(\"quantity\", accepted_quantity))",
        f"{T}{T}if resolved_quantity <= 0 or resolved_quantity > int(request.get(\"requested_quantity\", 0)):",
        f"{T}{T}{T}return false",
        "",
        f"{T}request[\"response_outcome\"] = outcome",
        f"{T}request[\"response_reason\"] = reason",
        f"{T}request[\"updated_tick\"] = tick",
        f"{T}request[\"last_counter\"] = counter.duplicate(true)",
        "",
        f"{T}match outcome:",
        f"{T}{T}Contract.OUTCOME_ACCEPT:",
        f"{T}{T}{T}request[\"accepted_quantity\"] = resolved_quantity",
        f"{T}{T}{T}request[\"status\"] = Contract.STATUS_WAITING_TRANSFER",
        f"{T}{T}Contract.OUTCOME_COUNTER:",
        f"{T}{T}{T}request[\"accepted_quantity\"] = resolved_quantity",
        f"{T}{T}{T}request[\"status\"] = Contract.STATUS_WAITING_REQUESTER",
        f"{T}{T}Contract.OUTCOME_REFUSE, Contract.OUTCOME_UNKNOWN:",
        f"{T}{T}{T}request[\"accepted_quantity\"] = 0",
        f"{T}{T}{T}request[\"status\"] = Contract.STATUS_ACTIVE",
        "",
        f"{T}_append_history(request, \"RESPONSE_RECORDED\", tick, {{",
        f"{T}{T}\"responder_id\": responder_id,",
        f"{T}{T}\"outcome\": outcome,",
        f"{T}{T}\"accepted_quantity\": int(request.get(\"accepted_quantity\", 0)),",
        f"{T}{T}\"reason\": reason,",
        f"{T}{T}\"counter\": counter.duplicate(true),",
        f"{T}}})",
        f"{T}_requests[request_id] = request",
        f"{T}return true",
        "",
        "func accept_counter",
    ])
    text = replace_once(
        text,
        r"func record_response\([\s\S]*?\nfunc accept_counter",
        replacement,
        "record_response",
    )
    write(target, text)


def patch_request_policy() -> None:
    target, text = read("game/src/simulation/material_request/material_request_policy.gd")
    text = text.replace(
        f"{T}{T}if not raw_candidate is Dictionary:",
        f"{T}{T}if not (raw_candidate is Dictionary):",
        1,
    )
    replacement = joined([
        f"{T}{T}if not bool(candidate.get(\"visible\", false)):",
        f"{T}{T}{T}continue",
        f"{T}{T}if bool(candidate.get(\"stale\", false)):",
        f"{T}{T}{T}continue",
        f"{T}{T}var candidate_item := String(candidate.get(\"item_id\", request.get(\"item_id\", \"\")))",
        f"{T}{T}if candidate_item != String(request.get(\"item_id\", \"\")):",
        f"{T}{T}{T}continue",
        f"{T}{T}var believed_quantity := maxi(0, int(candidate.get(\"believed_quantity\", 0)))",
    ])
    text = replace_once(
        text,
        rf"{T}{T}if not bool\(candidate\.get\(\"visible\", false\)\):[\s\S]*?{T}{T}var believed_quantity := maxi\(0, int\(candidate\.get\(\"believed_quantity\", 0\)\)\)",
        replacement,
        "subjective holder filters",
    )
    if f"{T}{T}if not (raw_candidate is Dictionary):" not in text:
        raise SystemExit("candidate type guard was not normalized")
    write(target, text)


def patch_response_policy() -> None:
    target, text = read("game/src/simulation/material_request/material_request_response_policy.gd")
    replacement = joined([
        f"{T}if surplus < requested:",
        f"{T}{T}var counter_quantity := surplus",
        f"{T}{T}if bounded_roll <= accept_probability or offer_value >= 0.35 or relationship >= 0.65:",
        f"{T}{T}{T}return _result(",
        f"{T}{T}{T}{T}Contract.OUTCOME_COUNTER,",
        f"{T}{T}{T}{T}\"PARTIAL_SURPLUS_COUNTER\",",
        f"{T}{T}{T}{T}counter_quantity,",
        f"{T}{T}{T}{T}accept_probability,",
        f"{T}{T}{T}{T}surplus,",
        f"{T}{T}{T}{T}{{",
        f"{T}{T}{T}{T}{T}\"quantity\": counter_quantity,",
        f"{T}{T}{T}{T}{T}\"requires_exchange\": offer_value < 0.35 and own_need > 0.35,",
        f"{T}{T}{T}{T}}}",
        f"{T}{T}{T})",
        f"{T}{T}return _result(",
        f"{T}{T}{T}Contract.OUTCOME_REFUSE,",
        f"{T}{T}{T}\"PARTIAL_SURPLUS_WITHHELD\",",
        f"{T}{T}{T}0,",
        f"{T}{T}{T}accept_probability,",
        f"{T}{T}{T}surplus,",
        f"{T}{T}{T}{{}}",
        f"{T}{T})",
        "",
        f"{T}if bounded_roll <= accept_probability:",
    ])
    text = replace_once(
        text,
        rf"{T}if surplus < requested:[\s\S]*?{T}if bounded_roll <= accept_probability:",
        replacement,
        "partial surplus policy",
    )
    write(target, text)


def main() -> None:
    patch_tracker()
    patch_request_policy()
    patch_response_policy()
    print("P7.1 source hardening prepared")


if __name__ == "__main__":
    main()
