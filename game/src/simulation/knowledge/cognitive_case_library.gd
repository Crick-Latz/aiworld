class_name CognitiveCaseLibrary
extends RefCounted
## P6.N0: read-only, evidence-linked case retrieval. Advice never creates capabilities,
## actions, memories or world facts. A caller must supply already-available rules.
var _cases: Array = []
var last_error := ""

func load_pack(pack: Dictionary) -> bool:
	last_error = ""
	if int(pack.get("schema_version", 0)) != 1 or pack.get("runtime_policy", "") != "ADVISORY_ONLY" \
			or typeof(pack.get("cases")) != TYPE_ARRAY:
		last_error = "INVALID_CASE_PACK"
		return false
	if pack["cases"].is_empty() or pack["cases"].size() > 512:
		last_error = "INVALID_CASE_COUNT"
		return false
	var staged: Array = []
	var seen := {}
	for value in pack["cases"]:
		if typeof(value) != TYPE_DICTIONARY:
			last_error = "INVALID_CASE"
			return false
		var row: Dictionary = value
		var cid := str(row.get("case_id", ""))
		var retrieval: Variant = row.get("retrieval", null)
		var review: Variant = row.get("review", null)
		if cid == "" or seen.has(cid) or typeof(retrieval) != TYPE_DICTIONARY \
				or typeof(review) != TYPE_DICTIONARY or review.get("status", "") != "APPROVED" \
				or not _is_sha256(str(row.get("source_sha256", ""))) \
				or row.get("origin", "") not in ["ENGINEERING_FIXTURE", "SOURCE_DERIVED"]:
			last_error = "UNREVIEWED_OR_INVALID_CASE"
			return false
		if retrieval.get("problem_id", "") not in ["HUNGER", "THIRST", "ISOLATION"]:
			last_error = "UNSUPPORTED_PROBLEM"
			return false
		for field in ["required_source_tags", "required_recipe_refs", "candidate_rule_ids"]:
			if typeof(retrieval.get(field)) != TYPE_ARRAY:
				last_error = "INVALID_RETRIEVAL"
				return false
			for token in retrieval[field]:
				if typeof(token) != TYPE_STRING or token == "":
					last_error = "INVALID_RETRIEVAL"
					return false
		if typeof(row.get("evidence")) != TYPE_ARRAY or row["evidence"].is_empty():
			last_error = "MISSING_EVIDENCE"
			return false
		var seen_evidence := {}
		for evidence in row["evidence"]:
			if typeof(evidence) != TYPE_DICTIONARY or str(evidence.get("id", "")) == "" \
					or seen_evidence.has(str(evidence["id"])) \
					or typeof(evidence.get("start")) not in [TYPE_INT, TYPE_FLOAT] \
					or typeof(evidence.get("end")) not in [TYPE_INT, TYPE_FLOAT] \
					or int(evidence["start"]) < 0 or int(evidence["end"]) <= int(evidence["start"]) \
					or evidence.get("perspective", "") not in ["NARRATOR", "CHARACTER", "DIALOGUE"]:
				last_error = "INVALID_EVIDENCE"
				return false
			seen_evidence[str(evidence["id"])] = true
		if typeof(retrieval.get("confidence")) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(retrieval["confidence"])) \
				or float(retrieval["confidence"]) < 0.0 or float(retrieval["confidence"]) > 1.0:
			last_error = "INVALID_CONFIDENCE"
			return false
		seen[cid] = true
		staged.append(row.duplicate(true))
	staged.sort_custom(func(a, b): return str(a["case_id"]) < str(b["case_id"]))
	_cases = staged
	return true

func retrieve(problem_id: String, context: Dictionary, available_rule_ids: Array) -> Array:
	var advice: Array = []
	if typeof(context.get("known_source_tags", [])) != TYPE_ARRAY \
			or typeof(context.get("known_recipe_refs", [])) != TYPE_ARRAY:
		return advice
	for case in _cases:
		var r: Dictionary = case["retrieval"]
		if r.get("problem_id", "") != problem_id:
			continue
		var matches := true
		for tag in r["required_source_tags"]:
			if not (context.get("known_source_tags", []) as Array).has(tag): matches = false
		for ref in r["required_recipe_refs"]:
			if not (context.get("known_recipe_refs", []) as Array).has(ref): matches = false
		if not matches: continue
		var rules: Array = []
		for rule in r["candidate_rule_ids"]:
			if available_rule_ids.has(rule) and not rules.has(rule): rules.append(rule)
		rules.sort()
		if rules.is_empty(): continue
		advice.append({"case_id": case["case_id"], "origin": case["origin"],
			"candidate_rule_ids": rules, "confidence": r["confidence"],
			"source_sha256": case["source_sha256"], "evidence": case["evidence"].duplicate(true),
			"mode": "ADVISORY_ONLY"})
	return advice

static func _is_sha256(value: String) -> bool:
	if value.length() != 64: return false
	for ch in value:
		if not "0123456789abcdef".contains(ch): return false
	return true
