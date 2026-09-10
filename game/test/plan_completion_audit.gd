extends "res://test/intention_revalidation_probe.gd"
## Read-only diagnosis: distinguish not selected, failed result, and missing identity.
class CompletionObserved extends ObservedSimulation:
	var completion_counts := {}
	var location_counts := {}
	var completion_examples: Array = []
	func _plan_execution_on_complete(id: String, a: Dictionary, action: Dictionary, segment: Array) -> void:
		var rec := {}
		for i in range(boundaries.size() - 1, -1, -1):
			if boundaries[i]["actor_id"] == id:
				rec = boundaries[i]
				break
		var matched := false
		for candidate in rec.get("step_candidates", []):
			if candidate["key"] == AgencyActionBridge.candidate_key(action): matched = true
		var before := agency_plan_run(id).duplicate(true)
		var identity: Dictionary = a.get("_plan_exec_inflight", {}).duplicate(true)
		var events_seen: Array = []
		var success := false
		var expected := str(PlanStepActionAdapter.MAIN_SUCCESS_EVENTS.get(action.get("action", ""), ""))
		if rec.get("step", {}).get("kind", "") == "CRAFT": expected = "crafted"
		for e in segment:
			events_seen.append({"seq": e.get("seq", -1), "type": e.get("type", ""), "actor_id": e.get("actor_id", "")})
			if e.get("actor_id", "") == id and expected != "" and e.get("type", "") == expected: success = true
		super._plan_execution_on_complete(id, a, action, segment)
		if not matched: return
		var target = action.get("target")
		var location := "no_tile_target"
		if typeof(target) == TYPE_VECTOR2I:
			location = "at_target" if a["tile"] == target else "before_arrival"
		var location_key := str(action.get("action", "")) + "/" + location + "/" + ("success" if success else "no_success")
		location_counts[location_key] = int(location_counts.get(location_key, 0)) + 1
		var key := "%s/%s/%s" % [rec.get("phase", "UNKNOWN"), "identity" if not identity.is_empty() else "no_identity", "success_event" if success else "no_success_event"]
		completion_counts[key] = int(completion_counts.get(key, 0)) + 1
		if completion_examples.size() < 12:
			completion_examples.append({"tick": tick, "actor_id": id, "tile_at_completion": a["tile"], "action": action.duplicate(true),
				"boundary_tick": rec.get("tick"), "phase": rec.get("phase"), "step": rec.get("step"),
				"identity": identity, "events": events_seen, "category": key,
				"run_before": _run_view(before), "run_after": _run_view(agency_plan_run(id))})

func _make_observed(mq, seed: int, configs: Array) -> ObservedSimulation:
	return CompletionObserved.new(mq, seed, configs)

func _extra_summary(observed) -> Dictionary:
	var result := {"counts": observed.completion_counts, "location_counts": observed.location_counts, "examples": observed.completion_examples}
	print("COMPLETION_AUDIT " + JSON.stringify({"counts": observed.completion_counts}))
	return result
