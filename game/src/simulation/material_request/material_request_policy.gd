extends RefCounted
class_name MaterialRequestPolicy

func choose_target(request: Dictionary, candidate_beliefs: Array, now_tick: int, seed: int) -> Dictionary:
	var requested_quantity := maxi(1, int(request.get("requested_quantity", 1)))
	var urgency := clampf(float(request.get("urgency", 0.5)), 0.0, 1.0)
	var requester_id := String(request.get("requester_id", ""))
	var request_id := String(request.get("request_id", ""))
	var ranked: Array = []

	for raw_candidate in candidate_beliefs:
		if not raw_candidate is Dictionary:
			continue
		var candidate: Dictionary = raw_candidate
		var actor_id := String(candidate.get("actor_id", ""))
		if actor_id.is_empty() or actor_id == requester_id:
			continue
		if not bool(candidate.get("visible", false)):
			continue
		var believed_quantity := maxi(0, int(candidate.get("believed_quantity", 0)))
		if believed_quantity <= 0:
			continue

		var confidence := clampf(float(candidate.get("confidence", 0.0)), 0.0, 1.0)
		var age := maxi(0, now_tick - int(candidate.get("last_observed_tick", now_tick)))
		var freshness := 1.0 / (1.0 + float(age) / 60.0)
		var coverage := minf(1.0, float(believed_quantity) / float(requested_quantity))
		var relationship := clampf((float(candidate.get("relationship", 0.0)) + 1.0) * 0.5, 0.0, 1.0)
		var cooperation := clampf(float(candidate.get("expected_cooperation", relationship)), 0.0, 1.0)
		var distance := maxf(0.0, float(candidate.get("distance", 0.0)))
		var proximity := 1.0 / (1.0 + distance / 8.0)
		var evidence_strength := confidence * freshness
		var base_score := (
			coverage * 0.30
			+ evidence_strength * 0.25
			+ cooperation * 0.20
			+ relationship * 0.10
			+ proximity * 0.10
			+ urgency * confidence * 0.05
		)
		var jitter := _candidate_jitter(seed, request_id, actor_id)
		var score := clampf(base_score + jitter, 0.0, 1.0)
		ranked.append({
			"actor_id": actor_id,
			"score": score,
			"believed_quantity": believed_quantity,
			"confidence": confidence,
			"freshness": freshness,
			"coverage": coverage,
			"relationship": relationship,
			"expected_cooperation": cooperation,
			"distance": distance,
			"jitter": jitter,
			"source": String(candidate.get("source", "ACTOR_BELIEF")),
		})

	ranked.sort_custom(_sort_ranked)
	if ranked.is_empty():
		return {
			"ok": false,
			"reason": "NO_SUBJECTIVE_TARGET",
			"target_id": "",
			"ranked_candidates": [],
			"subjective_only": true,
		}

	var chosen: Dictionary = ranked[0]
	return {
		"ok": true,
		"reason": "SUBJECTIVE_HOLDER_SELECTED",
		"target_id": String(chosen.get("actor_id", "")),
		"score": float(chosen.get("score", 0.0)),
		"ranked_candidates": ranked.duplicate(true),
		"subjective_only": true,
	}

func build_offer(request: Dictionary, target_decision: Dictionary, exchange_offer: Dictionary = {}) -> Dictionary:
	if not bool(target_decision.get("ok", false)):
		return {}
	return {
		"request_id": String(request.get("request_id", "")),
		"requester_id": String(request.get("requester_id", "")),
		"target_id": String(target_decision.get("target_id", "")),
		"item_id": String(request.get("item_id", "")),
		"quantity": int(request.get("requested_quantity", 0)),
		"root_goal": String(request.get("root_goal", "")),
		"parent_plan_id": String(request.get("parent_plan_id", "")),
		"urgency": clampf(float(request.get("urgency", 0.5)), 0.0, 1.0),
		"exchange_offer": exchange_offer.duplicate(true),
		"belief_basis": {
			"score": float(target_decision.get("score", 0.0)),
			"subjective_only": bool(target_decision.get("subjective_only", false)),
		},
	}

static func _candidate_jitter(seed: int, request_id: String, actor_id: String) -> float:
	var rng := RandomNumberGenerator.new()
	var stable := _stable_hash("%s|%s" % [request_id, actor_id])
	rng.seed = int(seed) ^ stable
	return rng.randf_range(-0.015, 0.015)

static func _stable_hash(value: String) -> int:
	var hash_value: int = 2166136261
	for byte_value in value.to_utf8_buffer():
		hash_value = int((hash_value ^ int(byte_value)) * 16777619) & 0x7fffffff
	return hash_value

static func _sort_ranked(a: Dictionary, b: Dictionary) -> bool:
	var a_score := float(a.get("score", 0.0))
	var b_score := float(b.get("score", 0.0))
	if not is_equal_approx(a_score, b_score):
		return a_score > b_score
	return String(a.get("actor_id", "")) < String(b.get("actor_id", ""))
