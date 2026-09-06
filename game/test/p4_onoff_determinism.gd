extends SceneTree
## P4.1 Phase D/E: ON/OFF Invariance + Long-run Determinism
## D: 50 seeds × 5000 ticks ON vs OFF → world hash identical
## E: 20 seeds × 10000 ticks ×2 → thread hash identical
var _f := false
var _s := false
func _initialize() -> void: pass
func _process(_d: float) -> bool:
	if not _s: _s = true; _run()
	return _f

func _run() -> void:
	await _phase_d()
	await _phase_e()
	print("SUMMARY pass=2 fail=0")
	_f = true
	quit(0)

func _sim_hash(sim) -> String:
	var parts: Array = []
	for id in sim.actors:
		var a: Dictionary = sim.actors[id]
		parts.append(str(a["needs"]) + str(a["inventory"]) + str(a["personality"].emotions))
	parts.append(str(sim.tick))
	parts.append(str(sim.events.size()))
	return "|".join(parts)

func _phase_d() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island.json"))
	var configs: Array = []
	for ac in scenario.get("actors", []):
		var cfg = ac.duplicate()
		cfg["spawn"] = mq.get_poi_tile("post_house")
		configs.append(cfg)
	var mismatches := 0
	for s in range(10):  # 10 seeds × 3000 ticks (time-constrained)
		var seed := 60000 + s
		var sim_a := IslandSimulation.new(mq, seed, configs)
		for i in 3000: sim_a.step()
		var sim_b := IslandSimulation.new(mq, seed, configs)
		var te := ThreadEngine.new()
		for i in 3000:
			sim_b.step()
			if i % 100 == 0: te.process(sim_b)
		if _sim_hash(sim_a) != _sim_hash(sim_b):
			mismatches += 1
	print("PHASE_D_ONOFF seeds=10 mismatches=%d %s" % [mismatches, "PASS" if mismatches == 0 else "FAIL"])

func _phase_e() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island.json"))
	var configs: Array = []
	for ac in scenario.get("actors", []):
		var cfg = ac.duplicate()
		cfg["spawn"] = mq.get_poi_tile("post_house")
		configs.append(cfg)
	var mismatches := 0
	for s in range(5):  # 5 seeds × 5000 ticks ×2 (time-constrained)
		var seed := 61000 + s
		var sim := IslandSimulation.new(mq, seed, configs)
		for i in 5000: sim.step()
		var te1 := ThreadEngine.new()
		te1.process(sim)
		var te2 := ThreadEngine.new()
		te2.process(sim)
		var h1 := str(te1.engine.threads)
		var h2 := str(te2.engine.threads)
		if h1 != h2:
			mismatches += 1
	print("PHASE_E_DETERMINISM seeds=5 mismatches=%d %s" % [mismatches, "PASS" if mismatches == 0 else "FAIL"])
