extends "res://test/p6_3b_execution.gd"

func _run() -> void:
	var scene = load("res://scenes/observer/observer_main.tscn").instantiate()
	root.add_child(scene)
	for i in 20: await physics_frame
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var mq = scene.get_node("World/MapController")
	var sim := _chain_sim(mq, true, "LIVE_BRIDGE", 30071, {"wood": 1})
	sim.step()
	var a: Dictionary = sim.actors["npc_chain"]
	var before := JSON.stringify(sim.agency_plan_run("npc_chain"))
	var inflight_before := JSON.stringify(a.get("_plan_exec_inflight", {}))
	var action: Dictionary = a["current_action"].duplicate(true)
	var run := sim.agency_plan_run("npc_chain")
	var base := {"actor_id": "npc_chain", "decision_tick": sim.tick,
		"run_id": run["run_id"], "step_id": run["current_step_id"], "selected": true,
		"candidate_key": AgencyActionBridge.candidate_key(action),
		"chosen_key": AgencyActionBridge.candidate_key(action), "selection_mode": "INTENTION_CONTINUE"}
	var rejects := true
	for field in ["actor_id", "decision_tick", "run_id", "step_id", "chosen_key", "selection_mode"]:
		var bad := base.duplicate(true)
		bad[field] = -1 if field == "decision_tick" else "wrong"
		a["_execution_receipt"] = bad
		sim._plan_execution_on_decision("npc_chain", a, action)
		rejects = rejects and JSON.stringify(sim.agency_plan_run("npc_chain")) == before
		rejects = rejects and JSON.stringify(a.get("_plan_exec_inflight", {})) == inflight_before
	_check("receipt_invalid_identity_rejected", rejects)
	_check("receipt_consumed_on_rejection", not a.has("_execution_receipt"))
	var rng := RandomNumberGenerator.new()
	var generated := false
	var cognitive_unchanged := true
	var receipt := {}
	var im := IntentionManager.new()
	var p := PersonalityProfile.new({}, {})
	var view := {"id": "u", "personality": p, "tile": Vector2i(0,0), "needs": {"energy":100,"hunger":0,"thirst":0,"social":0},
		"inventory":{}, "physical":{}, "known_resources":{}, "intentions":im}
	var agency := {"mode":"LIVE_BRIDGE", "decision_tick":50, "ctx":{},
		"execution_step":{"run_id":"u#1", "step":{"step_id":"rest", "kind":"MAIN", "action_name":"rest"}}}
	for seed in 32:
		rng.seed = seed
		im.set_intention(ActionRegistry._rest(p,view["needs"]),1)
		view["last_decision_trace"] = {"tick":-1}
		DecisionEngine.decide(view,{"tick":50},rng,agency)
		receipt = view.get("_execution_receipt",{})
		if receipt.get("selection_mode") == "INTENTION_CONTINUE":
			generated = receipt.get("selected",false) and receipt.get("decision_tick") == 50
			cognitive_unchanged = view["last_decision_trace"] == {"tick":-1}
			break
	_check("continuation_fresh_receipt", generated)
	_check("continuation_not_fake_deliberation", generated and cognitive_unchanged)
	DecisionEngine.decide(view,{"tick":51},rng,{})
	_check("off_clears_old_receipt", not view.has("_execution_receipt"))
	# Existing real-world fixture: all action starts with a matching continuation
	# must carry a new identity, never merely reuse a consumed completion.
	var seen := {}
	var unique := true
	var continued := 0
	for i in 180:
		sim.step()
		var ident: Dictionary = a.get("_plan_exec_inflight",{})
		if ident.is_empty(): continue
		var key := str(ident["run_id"]) + ":" + str(ident["attempt_id"])
		if seen.has(key): continue # same action still running
		seen[key] = true
		var current: Dictionary = a.get("current_action",{})
		if current.has("started_tick"):
			continued += 1
			unique = unique and ident.get("actor_id") == "npc_chain" and ident.get("candidate_key") == AgencyActionBridge.candidate_key(current)
	_check("physical_continuation_identified", continued > 0 and unique, "count=%d" % continued)
	scene.queue_free()
	await process_frame
	print("SUMMARY pass=%d fail=%d" % [_pass,_fail])
	quit(0 if _fail == 0 else 1)
