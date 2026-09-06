extends SceneTree
## P1.5 motif diversity 大扫描（一次性验收，不在常规回归）：
## 200 种子 × 600 tick，统计"社会因果母题"而非事件指纹——
## 互惠/回避/误解修正/合作/预测误差学习 是否自然出现（不人为保证概率）。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/p1_5_sweep.gd

const SEED_COUNT := 200
const TICKS := 600

var _started := false
var _finished := false

func _initialize() -> void:
	print("P1.5 motif sweep: %d seeds x %d ticks" % [SEED_COUNT, TICKS])

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
		cfg["spawn"] = spots[configs.size() % spots.size()]
		configs.append(cfg)

	var t0 := Time.get_ticks_msec()
	var motifs := {
		"requests": 0, "accepted": 0, "refused": 0, "shared": 0,
		"reciprocity": 0,        # A 帮 B 后 B 帮 A
		"avoidance_after_refusal": 0,  # 被拒后 100 tick 内回避拒绝者
		"belief_revision": 0,    # 反思推翻记恨（"错怪"）
		"grudge_formed": 0,      # 记恨形成
		"kept_distance": 0,
		"socialized": 0, "ask_reason": 0, "observe_person": 0, "ask_third_party": 0, "reason_claimed": 0, "reason_deflected": 0,
	}
	var interp_diversity := {}   # 所有出现过的主导解释
	var seeds_with_prediction_learning := 0
	var positive_bond_seeds := 0
	var negative_bond_seeds := 0
	var descriptive_spread_max := 0.0
	var stories := []
	for s in range(1, SEED_COUNT + 1):
		var sim := IslandSimulation.new(mq, 20000 + s, configs)
		for i in TICKS:
			sim.step()
		# 事件母题
		var helped := {}   # "a->b" -> tick
		var refused_at := {}  # "p->r" -> tick
		for e in sim.events:
			var t := str(e["type"])
			if t == "food_request_accepted":
				motifs["accepted"] += 1
				helped["%s->%s" % [str(e["actor_id"]), str(e.get("proposer_id", ""))]] = int(e["tick"])
			elif t == "shared_food":
				motifs["shared"] += 1
				helped["%s->%s" % [str(e["actor_id"]), str(e.get("to_id", ""))]] = int(e["tick"])
			elif t == "food_requested":
				motifs["requests"] += 1
			elif t == "food_request_refused":
				motifs["refused"] += 1
				refused_at["%s->%s" % [str(e.get("proposer_id", "")), str(e["actor_id"])]] = int(e["tick"])
			elif t == "kept_distance":
				motifs["kept_distance"] += 1
				var key := "%s->%s" % [str(e["actor_id"]), str(e.get("avoid_of", ""))]
				if refused_at.has(key) and int(e["tick"]) - int(refused_at[key]) <= 100:
					motifs["avoidance_after_refusal"] += 1
			elif t == "socialized":
				motifs["socialized"] += 1
			elif ["ask_reason", "observing_person", "ask_third_party", "reason_asked", "asked_about"].has(t):
				var key2 = {"ask_reason": "ask_reason", "observing_person": "observe_person", "ask_third_party": "ask_third_party", "reason_asked": "ask_reason", "asked_about": "ask_third_party"}[t]
				motifs[key2] += 1
			elif t == "reason_claimed":
				motifs["reason_claimed"] += 1
			elif t == "reason_deflected":
				motifs["reason_deflected"] += 1
			elif t == "reflected" and str(e.get("text", "")).find("错怪") != -1:
				motifs["belief_revision"] += 1
		# 互惠：双向帮助
		for key in helped:
			var parts: Array = key.split("->")
			if parts.size() == 2 and helped.has("%s->%s" % [parts[1], parts[0]]):
				motifs["reciprocity"] += 1
				break  # 每种子最多记一次
		# 认知内部
		var any_learning := false
		var any_grudge := false
		for id in sim.actors:
			var a: Dictionary = sim.actors[id]
			for g in a.get("grudges", {}):
				any_grudge = true
			if not (a.get("tom") as TheoryOfMind).prediction_errors.is_empty():
				any_learning = true
			for m in a.get("memories", []):
				var interp: Dictionary = m.get("interpretation", {})
				if not interp.is_empty():
					interp_diversity[str(interp.get("dominant", ""))] = true
		if any_learning: seeds_with_prediction_learning += 1
		if any_grudge: motifs["grudge_formed"] += 1
		# 关系两极
		var snap: Dictionary = sim.relationships.snapshot()
		var edge_min := 0
		var edge_max := 0
		for key in snap:
			edge_min = mini(edge_min, int(snap[key].get("trust", 0)))
			edge_max = maxi(edge_max, int(snap[key].get("trust", 0)))
		if edge_max >= 120: positive_bond_seeds += 1
		if edge_min <= -120: negative_bond_seeds += 1
		# 规范分歧（描述性层最大差）
		var descs := []
		for id in sim.actors:
			descs.append(float(sim.actors[id]["norms"]["descriptive"]["sharing"]))
		descs.sort()
		descriptive_spread_max = maxf(descriptive_spread_max, descs[descs.size() - 1] - descs[0])
		if motifs["reciprocity"] > 0 and stories.size() < 8:
			stories.append("seed=%d acc=%d ref=%d shared=%d" % [20000 + s, motifs["accepted"], motifs["refused"], motifs["shared"]])
	var ms := Time.get_ticks_msec() - t0
	print("SWEEP seeds=%d ticks=%d duration_ms=%d" % [SEED_COUNT, TICKS, ms])
	print("MOTIFS %s" % str(motifs))
	print("INTERP_DIVERSITY %s (n=%d)" % [str(interp_diversity.keys()), interp_diversity.size()])
	print("LEARNING seeds_with_prediction_learning=%d/%d" % [seeds_with_prediction_learning, SEED_COUNT])
	print("BONDS positive_seeds=%d negative_seeds=%d descriptive_spread_max=%.2f" % [
		positive_bond_seeds, negative_bond_seeds, descriptive_spread_max])
	_finished = true
	quit(0)
