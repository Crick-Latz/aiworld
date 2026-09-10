extends "res://test/intention_revalidation_probe.gd"
class UtilityObserved extends ObservedSimulation:
	var utility_records := {}
	var stale_bypasses := 0
	var examples: Array = []
	func _agency_prepare(id: String, a: Dictionary) -> Dictionary:
		var result := super._agency_prepare(id, a)
		var im: IntentionManager = a["intentions"]
		var candidates := ActionRegistry.get_available_actions(_build_actor_view(id, a), world)
		candidates.append(DecisionEngine._do_nothing())
		var current := im.matching_candidate(candidates) if im.has_intention() else {}
		var best := 0.0
		for c in candidates: best = maxf(best, float(c["utility"]))
		utility_records[id] = {}
		if not current.is_empty():
			utility_records[id] = {"tick": tick, "actor_id": id, "action": current["action"],
				"stored": im.current_intention.get("utility", 0.0), "current": current["utility"], "best": best}
		return result
	func _plan_execution_on_decision(id: String, a: Dictionary, decision: Dictionary) -> void:
		super._plan_execution_on_decision(id, a, decision)
		var r: Dictionary = utility_records[id]
		if r.is_empty() or boundaries.back()["phase"] != "INTENTION_CONTINUE": return
		if float(r["best"]) - float(r["stored"]) <= 0.35 and float(r["best"]) - float(r["current"]) > 0.35:
			stale_bypasses += 1
			if examples.size() < 6: examples.append(r)

func _make_observed(mq, seed: int, configs: Array) -> ObservedSimulation:
	return UtilityObserved.new(mq, seed, configs)

func _extra_summary(observed) -> Dictionary:
	var result := {"stale_urgency_bypasses": observed.stale_bypasses, "examples": observed.examples}
	print("UTILITY_AUDIT " + JSON.stringify(result))
	return result
