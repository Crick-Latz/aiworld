extends SceneTree
## P6.2-R2 — Paired Pilot：OFF vs LIVE 逐 tick 交错，scoped digest，双侧首分歧证据。
## 自产 JSON：res://docs/validation/data/p6_2_paired_pilot.json（原子写，与日志同源）。
## seed 恒等式：true_zero_swap + swapped_no_behavior_change + paired_state_different == seeds。
var _natural := 20
var _camp := 10
var _ticks := 3000
var _started := false
var _done := false

func _initialize() -> void:
	print("P62R2_CONFIG natural=%d camp=%d ticks=%d" % [_natural, _camp, _ticks])

func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done

func _run() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var camp_spot = mq.get_poi_tile("post_house")
	var spots := [mq.get_poi_tile("post_house"), mq.get_poi_tile("tide_market"), mq.get_poi_tile("old_lighthouse")]
	var agg := {
		"seeds": 0,
		"funnel": {"actual_proposals": 0, "grounded": 0, "grounded_already_considered": 0,
			"swapped_in": 0, "selected_grounded": 0},
		"reject_reasons": {}, "inert_subgoals": 0, "by_problem_action": {},
		"true_zero_swap_seeds": 0, "swapped_no_behavior_change_seeds": 0,
		"paired_state_different_seeds": 0, "first_divergence_by_cause": {},
		"on_ms": 0, "off_ms": 0, "planner_calls": 0, "cache_hits": 0,
		"guard": {"starve_off": 0, "starve_on": 0, "explore_off": 0, "explore_on": 0,
			"social_off": 0, "social_on": 0, "requests_off": 0, "requests_on": 0},
		"identity_ok": true,
	}
	var divergences: Array = []
	for cohort in ["natural", "camp"]:
		var count := _natural if cohort == "natural" else _camp
		for s in range(count):
			var seed := 50000 + s
			var configs: Array = []
			for ac in scenario.get("actors", []):
				var cfg = ac.duplicate(true)
				cfg["spawn"] = camp_spot if cohort == "camp" else spots[configs.size() % spots.size()]
				configs.append(cfg)
			var off := IslandSimulation.new(mq, seed, configs)
			var on := IslandSimulation.new(mq, seed, configs)
			on.agency_mode = "LIVE_BRIDGE"
			var seen := {}
			var diverged := false
			var seed_swapped := 0
			for i in _ticks:
				var rng_off_before := off._rng.state
				var rng_on_before := on._rng.state
				var ev_off_before := off.events.size()
				var ev_on_before := on.events.size()
				var t_off := Time.get_ticks_msec()
				off.step()
				agg["off_ms"] += Time.get_ticks_msec() - t_off
				var t_on := Time.get_ticks_msec()
				on.step()
				agg["on_ms"] += Time.get_ticks_msec() - t_on
				# 漏斗：只有首次采集的决策才计入 seed 级 swap 统计（delta 法）
				var swapped_before := int(agg["funnel"]["swapped_in"])
				for id in on.actors:
					var tr: Dictionary = on.actors[id].get("last_decision_trace", {})
					if int(tr.get("tick", -1)) >= on.tick - 1:
						AgencyMeasure.collect_decision(tr, str(id), seen, agg)
				seed_swapped += int(agg["funnel"]["swapped_in"]) - swapped_before
				# 逐 tick scoped digest
				if not diverged:
					var d_off := AgencyMeasure.canonical_behavior_digest(off)
					var d_on := AgencyMeasure.canonical_behavior_digest(on)
					if d_off != d_on:
						diverged = true
						divergences.append(_attribute_first_divergence(off, on, seed, cohort,
							rng_off_before, rng_on_before, off._rng.state, ev_off_before, ev_on_before))
			agg["seeds"] += 1
			agg["planner_calls"] += on.agency_planner_calls
			agg["cache_hits"] += on.agency_cache_hits
			if diverged:
				agg["paired_state_different_seeds"] += 1
			elif seed_swapped > 0:
				agg["swapped_no_behavior_change_seeds"] += 1
			else:
				agg["true_zero_swap_seeds"] += 1
			_collect_guard(off, "off", agg)
			_collect_guard(on, "on", agg)
	# 恒等式自检（写盘前）
	var identity := int(agg["true_zero_swap_seeds"]) + int(agg["swapped_no_behavior_change_seeds"]) + int(agg["paired_state_different_seeds"])
	agg["identity_ok"] = identity == int(agg["seeds"])
	for drec in divergences:
		var cause := str(drec.get("cause", "?"))
		agg["first_divergence_by_cause"][cause] = int(agg["first_divergence_by_cause"].get(cause, 0)) + 1
	print("P62R2_AGG " + JSON.stringify(agg))
	for i in range(divergences.size()):
		print("P62R2_DIV " + JSON.stringify(divergences[i]))
	# 自产 JSON（原子写）——与日志同源
	var payload := {"agg": agg, "first_divergences": divergences,
		"meta": {"natural": _natural, "camp": _camp, "ticks": _ticks, "generator": "p6_2_pilot.gd P62R2"}}
	var ok := AgencyMeasure.save_json_atomic("res://docs/validation/data/p6_2_paired_pilot.json", payload)
	print("P62R2_JSON_WRITTEN %s" % ("OK" if ok else "FAIL"))
	_done = true
	quit(0)

## 双侧首分歧证据：seed/cohort/tick、双侧 selected/RNG before-after、considered keys、
## swapped/evicted、本 tick 两边新增事件、差异组件
func _attribute_first_divergence(off, on, seed: int, cohort: String,
		rng_off_before: int, rng_on_before: int, rng_off_after: int,
		ev_off_before: int, ev_on_before: int) -> Dictionary:
	var rec := {"seed": seed, "cohort": cohort, "tick": on.tick, "cause": "UNKNOWN", "detail": {},
		"rng": {"off_before": rng_off_before, "off_after": rng_off_after,
			"on_before": rng_on_before, "on_after": on._rng.state},
		"new_events": {"off": _ev_slice(off, ev_off_before), "on": _ev_slice(on, ev_on_before)},
		"diff_components": AgencyMeasure.diff_components(off, on)}
	# 找分歧 tick 当刻的 LIVE 决策（fresh trace）与 OFF 对应
	var swap_actor := ""
	var live_swapped: Array = []
	var live_evicted: Array = []
	for id in on.actors:
		var tr: Dictionary = on.actors[id].get("last_decision_trace", {})
		if int(tr.get("tick", -1)) >= on.tick - 1 and (tr.get("agency_swapped_in_keys", []) as Array).size() > 0:
			swap_actor = str(id)
			live_swapped = tr.get("agency_swapped_in_keys", [])
			live_evicted = tr.get("agency_evicted_keys", [])
			rec["detail"]["live_selected"] = str(tr.get("selected", ""))
			rec["detail"]["live_considered_keys"] = tr.get("considered_keys", [])
			rec["detail"]["live_swapped"] = live_swapped
			rec["detail"]["live_evicted"] = live_evicted
			break
	if swap_actor != "":
		var tro: Dictionary = off.actors[swap_actor].get("last_decision_trace", {})
		rec["detail"]["actor"] = swap_actor
		rec["detail"]["off_selected"] = str(tro.get("selected", ""))
		rec["detail"]["off_considered_keys"] = tro.get("considered_keys", [])
		# 归因规则：首个不等组件须可由 LIVE consideration 变化解释——
		# 即差异仅限行为后果组件（事件/actor 状态/意图），且 RNG 序一致（LIVE 无额外消耗）
		var comps: Array = rec["diff_components"]
		var behavior_only := true
		for c in comps:
			var cs := str(c)
			if cs == "rng" or cs == "world" or cs.begins_with("relationships"):
				behavior_only = false
		if behavior_only and rec["rng"]["on_before"] == rec["rng"]["off_before"]:
			rec["cause"] = "SWAPPED_IN_DECISION"
		else:
			rec["cause"] = "SWAP_PRESENT_BUT_STATE_LEAK"
	else:
		# 无 swap 的分歧——找双侧 selection 差
		for id in on.actors:
			var tr2: Dictionary = on.actors[id].get("last_decision_trace", {})
			var tr3: Dictionary = off.actors[id].get("last_decision_trace", {})
			if int(tr2.get("tick", -1)) >= on.tick - 1 and str(tr2.get("selected", "")) != str(tr3.get("selected", "")):
				rec["cause"] = "SELECTION_DIFF_NO_SWAP"
				rec["detail"] = {"actor": str(id), "on_selected": str(tr2.get("selected", "")),
					"off_selected": str(tr3.get("selected", "")),
					"on_considered_keys": tr2.get("considered_keys", []),
					"off_considered_keys": tr3.get("considered_keys", [])}
				break
	return rec

func _ev_slice(sim, before: int) -> Array:
	var out: Array = []
	for e in sim.events.slice(before, sim.events.size()):
		out.append("%d|%s|%s" % [int(e.get("seq", 0)), str(e.get("type", "")), str(e.get("actor_id", ""))])
	return out

func _collect_guard(sim, side: String, agg: Dictionary) -> void:
	var g: Dictionary = agg["guard"]
	for e in sim.events:
		var t := str(e.get("type", ""))
		if t == "explored":
			g["explore_" + side] += 1
		elif t == "socialized" or t == "sat_by_fire":
			g["social_" + side] += 1
		elif t.ends_with("_requested"):
			g["requests_" + side] += 1
	for id in sim.actors:
		if int(sim.actors[id]["needs"]["hunger"]) >= 950:
			g["starve_" + side] += 1
