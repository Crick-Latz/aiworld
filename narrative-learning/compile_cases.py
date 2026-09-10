#!/usr/bin/env python3
"""Validate evidence-linked cognitive cases and compile a read-only advisory pack.

No model call, code execution, world-state mutation or model fine-tuning is performed.
Character offsets are zero-based Unicode code points, with an exclusive end offset.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FIELDS = (
    "problem", "perceived_situation", "knowledge_used", "available_resources",
    "candidate_strategies", "chosen_strategy", "prerequisites", "tool_capability",
    "social_dependency", "risk", "failure", "adaptation", "long_term_consequence",
)
TOP_KEYS = {"case_id", "origin", "source", "review", "evidence", "cognition", "field_evidence", "inferred_fields", "retrieval"}
RETRIEVAL_KEYS = {"problem_id", "required_source_tags", "required_recipe_refs", "candidate_rule_ids", "confidence"}
PROBLEMS = {"HUNGER", "THIRST", "ISOLATION"}

class CaseError(ValueError):
    """An untrusted extraction failed validation."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CaseError(message)


def _strings(value: Any, name: str, *, allow_empty: bool = True) -> list[str]:
    _require(isinstance(value, list), f"{name}: expected array")
    _require(all(isinstance(x, str) and x.strip() for x in value), f"{name}: expected nonempty strings")
    _require(len(value) == len(set(value)), f"{name}: duplicate entries")
    _require(allow_empty or len(value) > 0, f"{name}: empty")
    return value


def validate_case(case: Any, source_root: Path) -> dict[str, Any]:
    _require(isinstance(case, dict) and set(case) == TOP_KEYS, "case: missing or unknown fields")
    _require(isinstance(case["case_id"], str) and bool(case["case_id"].strip()), "case_id: missing")
    _require(isinstance(case["origin"], str) and case["origin"] in {"ENGINEERING_FIXTURE", "SOURCE_DERIVED"}, "origin: unsupported")
    source = case["source"]
    _require(isinstance(source, dict) and set(source) == {"path", "sha256", "title", "rights_basis"}, "source: invalid fields")
    for key in source:
        _require(isinstance(source[key], str) and bool(source[key].strip()), f"source.{key}: missing")
    root = source_root.resolve()
    path = (root / source["path"]).resolve()
    _require(not Path(source["path"]).is_absolute() and path.is_relative_to(root), "source.path: escapes source root")
    _require(path.is_file(), "source.path: file missing")
    _require(path.stat().st_size <= 2_000_000, "source: excerpt exceeds 2MB; split by chapter")
    raw = path.read_bytes()
    _require(hashlib.sha256(raw).hexdigest() == source["sha256"], "source.sha256: mismatch")
    try:
        text = raw.decode("utf-8")
    except UnicodeError as exc:
        raise CaseError("source: UTF-8 required") from exc
    review = case["review"]
    _require(isinstance(review, dict) and set(review) == {"status", "reviewed_by"}, "review: invalid fields")
    _require(review["status"] == "APPROVED" and isinstance(review["reviewed_by"], str) and bool(review["reviewed_by"].strip()), "review: approval required")
    evidence = case["evidence"]
    _require(isinstance(evidence, list) and 0 < len(evidence) <= 128, "evidence: invalid count")
    refs: set[str] = set()
    for item in evidence:
        _require(isinstance(item, dict) and set(item) == {"id", "start", "end", "quote", "perspective", "subject_id"}, "evidence: invalid fields")
        eid = item["id"]
        _require(isinstance(eid, str) and bool(eid) and eid not in refs, "evidence.id: missing or duplicate")
        refs.add(eid)
        _require(type(item["start"]) is int and type(item["end"]) is int and 0 <= item["start"] < item["end"] <= len(text), "evidence: invalid span")
        _require(isinstance(item["quote"], str) and text[item["start"]:item["end"]] == item["quote"], "evidence.quote: span mismatch")
        _require(isinstance(item["perspective"], str) and item["perspective"] in {"NARRATOR", "CHARACTER", "DIALOGUE"}, "evidence.perspective: invalid")
        _require(isinstance(item["subject_id"], str) and bool(item["subject_id"]), "evidence.subject_id: missing")
    cognition = case["cognition"]
    _require(isinstance(cognition, dict) and set(cognition) == set(FIELDS), "cognition: all 13 fields required")
    for field in FIELDS:
        _strings(cognition[field], "cognition." + field, allow_empty=False)
    _require(len(cognition["candidate_strategies"]) >= 2, "candidate_strategies: at least two alternatives")
    mapping = case["field_evidence"]
    _require(isinstance(mapping, dict) and set(mapping) == set(FIELDS), "field_evidence: all 13 fields required")
    for field in FIELDS:
        field_refs = _strings(mapping[field], "field_evidence." + field, allow_empty=False)
        _require(set(field_refs) <= refs, "field_evidence: unknown reference")
    inferred = _strings(case["inferred_fields"], "inferred_fields")
    _require(set(inferred) <= set(FIELDS), "inferred_fields: unknown field")
    retrieval = case["retrieval"]
    _require(isinstance(retrieval, dict) and set(retrieval) == RETRIEVAL_KEYS, "retrieval: invalid fields")
    _require(isinstance(retrieval["problem_id"], str) and retrieval["problem_id"] in PROBLEMS, "retrieval.problem_id: unsupported")
    for name in ("required_source_tags", "required_recipe_refs", "candidate_rule_ids"):
        _strings(retrieval[name], "retrieval." + name, allow_empty=(name != "candidate_rule_ids"))
    confidence = retrieval["confidence"]
    _require(type(confidence) in {int, float} and 0 <= confidence <= 1, "retrieval.confidence: invalid")
    # Source text stays outside the runtime pack; pointers and interpretation remain auditable.
    return {"case_id": case["case_id"], "origin": case["origin"], "source_sha256": source["sha256"],
            "source_path": source["path"], "review": review, "retrieval": retrieval,
            "cognition": cognition, "field_evidence": mapping, "inferred_fields": inferred,
            "evidence": [{k: v for k, v in item.items() if k != "quote"} for item in evidence]}


def compile_pack(document: Any, source_root: Path) -> dict[str, Any]:
    _require(isinstance(document, dict) and set(document) == {"schema_version", "cases"}, "document: invalid fields")
    _require(type(document["schema_version"]) is int and document["schema_version"] == 1, "document: unsupported version")
    cases = document["cases"]
    _require(isinstance(cases, list) and 0 < len(cases) <= 512, "cases: invalid count")
    compiled = [validate_case(case, source_root) for case in cases]
    ids = [case["case_id"] for case in compiled]
    _require(len(ids) == len(set(ids)), "case_id: duplicate across pack")
    compiled.sort(key=lambda case: case["case_id"])
    canonical = json.dumps(compiled, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return {"schema_version": 1, "pack_id": "cognitive-cases-" + hashlib.sha256(canonical.encode()).hexdigest()[:16],
            "runtime_policy": "ADVISORY_ONLY", "cases": compiled}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    try:
        pack = compile_pack(json.loads(args.input.read_text(encoding="utf-8")), args.source_root)
        if args.out:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            # Exclusive create protects previously approved packs from accidental overwrite.
            with args.out.open("x", encoding="utf-8", newline="\n") as handle:
                json.dump(pack, handle, ensure_ascii=False, sort_keys=True, indent=2)
                handle.write("\n")
        print(json.dumps({"ok": True, "pack_id": pack["pack_id"], "cases": len(pack["cases"]), "runtime_policy": pack["runtime_policy"]}))
        return 0
    except (CaseError, OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
