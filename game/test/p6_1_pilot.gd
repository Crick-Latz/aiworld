extends SceneTree
## P6.1 Pilot — Shadow 观察统计（20 natural + 10 camp × 3000）
var _natural := 20
var _camp := 10
var _ticks := 3000
var _started := false
var _done := false

func _initialize() -> void:
	print("P61PILOT_CONFIG natural=%d camp=%d ticks=%d" % [_natural, _camp, _ticks])

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
	var agg := {"by_problem": {}, "top_missing": {}, "records": 0, "planner_calls": 0, "cache_hits": 0,
		"plans": 0, "divergence": 0, "ms": 0}
	var divergence_cases: Array = []
	var blocked_cases: Array = []
	for cohort in ["natural", "camp"]:
		var count := _natural if cohort == "natural" else _camp
		for s in range(count):
			var seed := 40000 + s
			var configs: Array = []
			for ac in scenario.get("actors", []):
				var cfg = ac.duplicate()
				cfg["spawn"] = camp_spot if cohort == "camp" else spots[configs.size() % spots.size()]
				configs.append(cfg)
			var sim := IslandSimulation.new(mq, seed, configs)
			var runner := AgencyShadowRunner.new()
			var t0 := Time.get_ticks_msec()
			for i in _ticks:
				sim.step()
				runner.observe(sim)
			agg["ms"] += Time.get_ticks_msec() - t0
			var st: Dictionary = runner.stats()
			agg["records"] += int(st["records"])
			agg["planner_calls"] += int(st["planner_calls"])
			agg["cache_hits"] += int(st["cache_hits"])
			agg["plans"] += int(st["shadow_plans_generated"])
			agg["divergence"] += int(st["divergence_count"])
			for p in st["by_problem"]:
				var slot: Dictionary = agg["by_problem"].get(p, {"ready": 0, "blocked": 0, "no_plan": 0})
				var s2: Dictionary = st["by_problem"][p]
				slot["ready"] += int(s2["ready"]); slot["blocked"] += int(s2["blocked"]); slot["no_plan"] += int(s2["no_plan"])
				agg["by_problem"][p] = slot
			for m in st["top_missing"]:
				agg["top_missing"][m] = int(agg["top_missing"].get(m, 0)) + int(st["top_missing"][m])
			# 案例 extraction（每 seed 最多 2+2）
			var div_n := 0
			var blk_n := 0
			for r in runner.records:
				if div_n < 2 and int(r.get("ready_count", 0)) > 0 and str(r.get("actual_selected_action", "")) in ["explore", "rest", "do_nothing", ""]:
					divergence_cases.append({"seed": seed, "cohort": cohort, "tick": r.get("tick"), "actor": r.get("actor_id"),
						"problems": r.get("problems"), "ready": r.get("ready_count"),
						"proposals": (r.get("proposals_cache", []) as Array).map(func(p): return {"via": p.get("via_rule"), "status": p.get("status")}),
						"actual": r.get("actual_selected_action")})
					div_n += 1
				if blk_n < 2 and int(r.get("blocked_count", 0)) > 0 and (r.get("missing_requirements", []) as Array).size() > 0:
					blocked_cases.append({"seed": seed, "cohort": cohort, "tick": r.get("tick"), "actor": r.get("actor_id"),
						"problems": r.get("problems"), "missing": r.get("missing_requirements")})
					blk_n += 1
	print("P61PILOT_AGG " + JSON.stringify(agg))
	print("P61PILOT_DIVERGENCE_N=%d" % divergence_cases.size())
	for i in range(mini(20, divergence_cases.size())):
		print("P61DIV " + JSON.stringify(divergence_cases[i]))
	print("P61PILOT_BLOCKED_N=%d" % blocked_cases.size())
	for i in range(mini(20, blocked_cases.size())):
		print("P61BLK " + JSON.stringify(blocked_cases[i]))
	_done = true
	quit(0)
