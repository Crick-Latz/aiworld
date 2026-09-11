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
