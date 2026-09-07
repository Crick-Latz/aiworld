extends SceneTree
## P4.2 Gate C 补充：L2 拒绝原因直方图（区分生态稀缺 vs 社会权重过紧）
var _f := false
var _s := false
func _initialize() -> void: pass
func _process(_d: float) -> bool:
	if not _s: _s = true; _run()
	return _f

func _run() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var spot = mq.get_poi_tile("post_house")
	var configs: Array = []
	for ac in scenario.get("actors", []):
		var cfg = ac.duplicate(); cfg["spawn"] = spot; configs.append(cfg)

	var hist := {}
	var hard_gate := 0
	var by_object := {}
	for seed in [50000, 50001, 50002, 50003, 50015]:
		var sim := IslandSimulation.new(mq, seed, configs)
		for i in 1500: sim.step()
		for e in sim.events:
			var t := str(e.get("type", ""))
			if t.ends_with("_request_refused"):
				var txt := str(e.get("text", ""))
				var reason := ""
				var idx := txt.find("：")
				var idx2 := txt.find("——")
				if idx >= 0 and idx2 > idx:
					reason = txt.substr(idx + 1, idx2 - idx - 1)
				else:
					reason = "PARSE_FAIL"
				hist[reason] = int(hist.get(reason, 0)) + 1
				var obj := "food"
				if t.begins_with("water"): obj = "water"
				elif t.begins_with("tool"): obj = "tool"
				by_object[obj] = int(by_object.get(obj, 0)) + 1
				if reason == "自己也不够吃":
					hard_gate += 1
	print("L2_REASON_HIST %s" % str(hist))
	print("L2_BY_OBJECT %s" % str(by_object))
	print("L2_HARD_GATE_FRAC %d/%d" % [hard_gate, hist.values().reduce(func(a, b): return int(a) + int(b), 0)])
	_f = true
	quit(0)
