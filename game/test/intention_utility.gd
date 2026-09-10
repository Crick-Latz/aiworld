extends SceneTree
var passed := 0
var failed := 0
func _initialize() -> void:
	call_deferred("_run")
func _check(label: String, ok: bool) -> void:
	if ok: passed += 1; print("PASS " + label)
	else: failed += 1; print("FAIL " + label)
func _run() -> void:
	var p := PersonalityProfile.new({}, {})
	var world := {"tick": 20, "fires": {}, "shelters": {}}
	var old_rest: Dictionary = ActionRegistry._rest(p, {"energy": 100})
	var new_rest: Dictionary = ActionRegistry._rest(p, {"energy": 1000})
	_check("actual_rest_value_drops", float(old_rest["utility"]) - float(new_rest["utility"]) > 0.35)
	var fresh_all := true
	var stable_persisted := 0
	var stable_payload := true
	for seed in range(32):
		var im := IntentionManager.new()
		var actor := {"id": "fixture", "personality": p, "tile": Vector2i(10, 10),
			"needs": {"energy": 1000, "hunger": 0, "thirst": 950, "social": 0},
			"physical": {}, "inventory": {}, "intentions": im,
			"known_resources": {"water_springs": [Vector2i(10, 10)]}}
		im.set_intention(old_rest, 1)
		var rng := RandomNumberGenerator.new(); rng.seed = seed
		DecisionEngine.decide(actor, world, rng)
		fresh_all = fresh_all and actor.get("last_decision_trace", {}).get("tick", -1) == 20
		# No new winning action mandated: only the existing urgency guard must run.
		actor["needs"]["energy"] = 100
		actor["needs"]["thirst"] = 0
		actor.erase("last_decision_trace")
		im.set_intention(old_rest, 1)
		var continued := DecisionEngine.decide(actor, world, rng)
		if not actor.has("last_decision_trace"):
			stable_persisted += 1
			stable_payload = stable_payload and continued.get("duration") == 3 and continued.get("started_tick") == 1
	_check("current_urgency_forces_reconsideration", fresh_all)
	_check("stable_value_preserves_commitment", stable_persisted > 0 and stable_payload)
	var manager := IntentionManager.new()
	manager.set_intention(old_rest, 1)
	var returned := manager.continue_action(new_rest)
	_check("continued_score_is_current", returned["utility"] == new_rest["utility"] and manager.current_intention["utility"] == new_rest["utility"])
	_check("commitment_metadata_preserved", returned["started_tick"] == 1 and is_equal_approx(returned["commitment"], 0.85))
	returned["utility"] = -999.0
	_check("utility_snapshot_isolated", manager.current_intention["utility"] != -999.0)
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
