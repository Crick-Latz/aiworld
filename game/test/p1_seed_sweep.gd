extends SceneTree
## P1 种子多样性大扫描（一次性验收工具，不在常规回归里）：
## 200 个种子 × 600 tick，验证没有任何剧本的情况下，
## 社交剧情的形态分布——合作、破裂、记恨、感念各自涌现。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/p1_seed_sweep.gd

const SEED_COUNT := 200
const TICKS := 600

var _started := false
var _finished := false

func _initialize() -> void:
	print("P1 seed sweep: %d seeds x %d ticks" % [SEED_COUNT, TICKS])

func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _finished

func _run() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null:
		print("SWEEP_FAIL map_unavailable")
		_finished = true
		quit(1)
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var spots := [mq.get_poi_tile("post_house"), mq.get_poi_tile("tide_market"), mq.get_poi_tile("old_lighthouse")]
	var configs: Array = []
	for ac in scenario.get("actors", []):
		var cfg = ac.duplicate()
		cfg["spawn"] = spots[configs.size() % spots.size()]  # 正常出生分布
		configs.append(cfg)

	var t0 := Time.get_ticks_msec()
	var stats := {
		"crashes": 0, "any_social": 0, "requests": 0, "accepted": 0, "refused": 0, "shared": 0,
		"full_arc": 0, "trust_collapse": 0, "strong_bond": 0, "reflected": 0,
	}
	var fingerprints := {}
	var stories := []  # 每个种子一行摘要
	for s in range(1, SEED_COUNT + 1):
		var sim := IslandSimulation.new(mq, 10000 + s, configs)
		var c := {}
		for i in TICKS:
			sim.step()
		for e in sim.events:
			var t := str(e["type"])
			if ["food_requested", "food_request_accepted", "food_request_refused", "shared_food", "reflected"].has(t):
				c[t] = int(c.get(t, 0)) + 1
		var edge_min := 0
		var edge_max := 0
		var snap: Dictionary = sim.relationships.snapshot()
		for key in snap:
			edge_min = mini(edge_min, int(snap[key]["trust"]))
			edge_max = maxi(edge_max, int(snap[key]["trust"]))
		var fp := "%d/%d/%d/%d/%d" % [c.get("food_requested", 0), c.get("food_request_accepted", 0),
			c.get("food_request_refused", 0), c.get("shared_food", 0), c.get("reflected", 0)]
		fingerprints[fp] = true
		var total_social: int = int(c.get("food_requested", 0)) + int(c.get("food_request_accepted", 0)) \
			+ int(c.get("food_request_refused", 0)) + int(c.get("shared_food", 0))
		if total_social > 0: stats["any_social"] += 1
		if c.get("food_requested", 0) >= 2 and c.get("food_request_refused", 0) >= 2 and c.get("reflected", 0) >= 1:
			stats["full_arc"] += 1
			if stories.size() < 12:
				stories.append("seed=%d req=%d acc=%d ref=%d shared=%d trust[%d..%d]" % [10000 + s,
					c.get("food_requested", 0), c.get("food_request_accepted", 0),
					c.get("food_request_refused", 0), c.get("shared_food", 0), edge_min, edge_max])
		if edge_min <= -200: stats["trust_collapse"] += 1
		if edge_max >= 200: stats["strong_bond"] += 1
		stats["requests"] += c.get("food_requested", 0)
		stats["accepted"] += c.get("food_request_accepted", 0)
		stats["refused"] += c.get("food_request_refused", 0)
		stats["shared"] += c.get("shared_food", 0)
		stats["reflected"] += c.get("reflected", 0)
	var ms := Time.get_ticks_msec() - t0
	print("SWEEP_SUMMARY seeds=%d ticks=%d duration_ms=%d" % [SEED_COUNT, TICKS, ms])
	print("SWEEP any_social=%d/%d unique_fingerprints=%d" % [stats["any_social"], SEED_COUNT, fingerprints.size()])
	print("SWEEP totals requests=%d accepted=%d refused=%d shared=%d reflected=%d" % [
		stats["requests"], stats["accepted"], stats["refused"], stats["shared"], stats["reflected"]])
	print("SWEEP full_arc(req>=2,ref>=2,reflected)=%d trust_collapse(<=-200)=%d strong_bond(>=200)=%d" % [
		stats["full_arc"], stats["trust_collapse"], stats["strong_bond"]])
	for st in stories:
		print("STORY %s" % st)
	_finished = true
	quit(0)
