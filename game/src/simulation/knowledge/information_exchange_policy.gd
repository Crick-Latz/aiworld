class_name InformationExchangePolicy
extends RefCounted
## P7.0 信息回答策略。回答方只能使用自己的 SpatialBeliefMap；报告可以过期，
## 分享意愿受人格与关系影响。资源真值不进入本类。

const MAX_REPORT_AGE_TICKS := 72
const RESPONSE_SHARE := "SHARE"
const RESPONSE_REFUSE := "REFUSE"
const RESPONSE_UNKNOWN := "UNKNOWN"
const RESPONSE_STALE := "STALE"

static func evaluate(responder: Dictionary, asker_id: String, source_kind: String,
		trust_toward_asker: int, at_tick: int, rng: RandomNumberGenerator) -> Dictionary:
	var belief: SpatialBeliefMap = responder.get("spatial", null)
	if belief == null or source_kind == "":
		return {"response": RESPONSE_UNKNOWN, "reason_code": "NO_SUBJECTIVE_SOURCE"}
	var known := belief.resource_beliefs(source_kind)
	if known.is_empty():
		return {"response": RESPONSE_UNKNOWN, "reason_code": "NO_SUBJECTIVE_SOURCE"}
	var source: Dictionary = known[0]
	var observed_tick := int(source.get("last_seen_tick", -1))
	var age := maxi(0, at_tick - observed_tick)
	var source_confidence := clampf(float(source.get("confidence", 1.0)), 0.0, 1.0)
	var confidence := source_confidence * clampf(1.0 - float(age) / float(MAX_REPORT_AGE_TICKS + 1), 0.05, 1.0)
	var base := {
		"tile": source.get("tile", Vector2i.ZERO),
		"observed_tick": observed_tick,
		"age_ticks": age,
		"confidence": confidence,
		"source_kind": source_kind,
		"source_evidence_kind": str(source.get("evidence_kind", SpatialBeliefMap.EVIDENCE_PERCEPT)),
	}
	if age > MAX_REPORT_AGE_TICKS:
		base["response"] = RESPONSE_STALE
		base["reason_code"] = "REPORT_TOO_OLD"
		return base
	var assessment := assess_willingness(responder, asker_id, trust_toward_asker)
	for key in assessment:
		base[key] = assessment[key]
	if rng == null or rng.randf() > float(assessment.get("share_probability", 0.0)):
		base["response"] = RESPONSE_REFUSE
		base["reason_code"] = "UNWILLING_TO_SHARE"
		return base
	base["response"] = RESPONSE_SHARE
	base["reason_code"] = "FRESH_SUBJECTIVE_REPORT"
	return base

static func assess_willingness(responder: Dictionary, asker_id: String,
		trust_toward_asker: int) -> Dictionary:
	var p: PersonalityProfile = responder.get("personality", null)
	if p == null or asker_id == "":
		return {"share_probability": 0.0, "trust_norm": 0.0}
	var needs: Dictionary = responder.get("needs", {})
	var altruism := p.effective_trait("altruism", needs)
	var empathy := p.effective_trait("empathy", needs)
	var sociability := p.effective_trait("sociability", needs)
	var conflict_avoidance := p.effective_trait("conflict_avoidance", needs)
	var trust_norm := clampf((float(trust_toward_asker) + 1000.0) / 2000.0, 0.0, 1.0)
	var probability := clampf(0.08 + altruism * 0.25 + empathy * 0.20 + sociability * 0.12
		+ trust_norm * 0.30 + conflict_avoidance * 0.05, 0.05, 0.95)
	return {"share_probability": probability, "trust_norm": trust_norm}

static func knowledge_predicate(source_kind: String) -> String:
	return "knows_source:" + source_kind

# ── P7.2B：持有询问（FIND_HOLDER）应答 ──
# 回答方只有两类合法信息源：自己的库存自知（第一人称权威）与自己 ToM 中的
# 第三方持有证据。不读全局库存、不读他人 ToM、不读地图真值。

const HOLDER_SHARE := "HOLDER_SHARE"
const HOLDER_REFUSE := "HOLDER_REFUSE"
const HOLDER_UNKNOWN := "HOLDER_UNKNOWN"
const HOLDER_STALE := "HOLDER_STALE"
const HOLDER_SELF_ABSENT := "HOLDER_SELF_ABSENT"

static func evaluate_holder_query(responder: Dictionary, asker_id: String, item_id: String,
		trust_toward_asker: int, at_tick: int, rng: RandomNumberGenerator) -> Dictionary:
	var responder_id := str(responder.get("id", ""))
	var self_count := int(responder.get("inventory", {}).get(item_id, 0))
	if self_count > 0:
		# 自己持有——第一人称权威；是否告知仍受意愿支配。
		var assessment := assess_willingness(responder, asker_id, trust_toward_asker)
		if rng == null or rng.randf() > float(assessment.get("share_probability", 0.0)):
			return _holder_result(HOLDER_REFUSE, "UNWILLING_TO_SHARE", responder_id, responder_id,
				at_tick, at_tick, 0.0, "SELF_REPORT", assessment)
		return _holder_result(HOLDER_SHARE, "SELF_REPORT", responder_id, responder_id,
			at_tick, at_tick, 1.0, "SELF_REPORT", assessment)
	# 第三方：只从自己的 ToM 找（subjective only）。
	var tom: TheoryOfMind = responder.get("tom", null)
	if tom != null:
		var candidates: Array = tom.subjects_with_evidence(TheoryOfMind.possession_predicate(item_id))
		var best: Dictionary = {}
		var stale_best: Dictionary = {}
		for row in candidates:
			var holder_id := str(row.get("actor_id", ""))
			if holder_id == "" or holder_id == asker_id or holder_id == responder_id:
				continue
			if float(row.get("belief", 0.0)) <= 0.0:
				continue
			var observed := int(row.get("last_evidence_tick", -1))
			if observed >= 0 and at_tick - observed <= MAX_REPORT_AGE_TICKS:
				if best.is_empty():
					best = row
			elif stale_best.is_empty():
				stale_best = row
		if not best.is_empty():
			var assessment2 := assess_willingness(responder, asker_id, trust_toward_asker)
			var holder_id2 := str(best.get("actor_id", ""))
			if rng == null or rng.randf() > float(assessment2.get("share_probability", 0.0)):
				return _holder_result(HOLDER_REFUSE, "UNWILLING_TO_SHARE", responder_id, holder_id2,
					int(best.get("last_evidence_tick", -1)), at_tick, 0.0, "TOM_REPORT", assessment2)
			return _holder_result(HOLDER_SHARE, "FRESH_TOM_REPORT", responder_id, holder_id2,
				int(best.get("last_evidence_tick", -1)), at_tick,
				clampf(float(best.get("confidence", 0.0)), 0.0, 1.0), "TOM_REPORT", assessment2)
		if not stale_best.is_empty():
			return _holder_result(HOLDER_STALE, "REPORT_TOO_OLD", responder_id,
				str(stale_best.get("actor_id", "")),
				int(stale_best.get("last_evidence_tick", -1)), at_tick,
				clampf(float(stale_best.get("confidence", 0.0)), 0.0, 1.0), "TOM_REPORT", {})
	# 自知不持有，且无可分享的第三方知识。
	return _holder_result(HOLDER_SELF_ABSENT, "SELF_NOT_HOLDER", responder_id, responder_id,
		at_tick, at_tick, 1.0, "SELF_REPORT", {})

static func _holder_result(response: String, reason: String, reporter_id: String,
		reported_holder_id: String, observed_tick: int, received_tick: int,
		confidence: float, evidence_kind: String, assessment: Dictionary) -> Dictionary:
	var out := {
		"response": response,
		"reason_code": reason,
		"reporter_id": reporter_id,
		"reported_holder_id": reported_holder_id,
		"observed_tick": observed_tick,
		"received_tick": received_tick,
		"confidence": confidence,
		"evidence_kind": evidence_kind,
	}
	for key in assessment:
		out[key] = assessment[key]
	return out

static func source_kind_for_event(event_type: String) -> String:
	return {
		"foraged": "berry",
		"drank": "water",
		"fished": "fish",
		"gathered_shells": "shell",
		"ruins_loot": "ruin",
		"ruins_empty": "ruin",
		"gathered_wood": "tree",
		"fire_lit": "fire",
		"source_information_shared": "__EVENT_FIELD__",
	}.get(event_type, "")
