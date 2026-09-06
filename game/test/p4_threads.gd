extends SceneTree
## P4 Long-Horizon Story Threads 验收测试 TA-TL
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/p4_threads.gd

var passed := 0
var failed := 0
var _s := false
var _f := false
func _initialize() -> void: pass
func _process(_d: float) -> bool:
	if not _s: _s = true; _run()
	return _f
func _run() -> void:
	await _all_tests()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	_f = true
	quit(0 if failed == 0 else 1)
func _check(n: String, c: bool, d: String = "") -> void:
	if c: passed += 1; print("PASS %s" % n)
	else: failed += 1; print("FAIL %s  %s" % [n, d])

func _all_tests() -> void:
	await _ta_promise_long_gap()
	await _tb_temporal_not_thread()
	await _tc_dormancy()
	_te_resolution_evidence()
	await _th_no_sim_effect()
	await _ti_determinism()
	await _test_p41_episode_identity()

## TA：承诺跨天——Day 1 promise → Day 20 fulfilled → 同 thread RESOLVED
func _ta_promise_long_gap() -> void:
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
	var sim := IslandSimulation.new(mq, 44001, configs)
	# Day 1: promise made
	sim._emit("promise_made", "npc_oun", "欧恩承诺回报卡德加", {"to_id": "npc_kadga"})
	# 中间 400 tick（~17 天）——大量无关事件
	for i in 400: sim.step()
	# Day ~18: promise kept
	sim._emit("promise_kept", "npc_oun", "欧恩兑现了承诺", {"to_id": "npc_kadga"})
	var te := ThreadEngine.new()
	te.process(sim)
	var stats: Dictionary = te.engine.stats()
	_check("ta_threads_created", stats["opened"] > 0, str(stats))
	var promise_resolved := false
	var same_id := false
	for th in te.engine.threads:
		if str(th.get("thread_type", "")) == "PROMISE_THREAD":
			if str(th.get("status", "")) == "RESOLVED" and str(th.get("resolution", "")) == "FULFILLED":
				promise_resolved = true
				# 同一线程包含两个事件（opening + resolution）
				same_id = (th.get("source_event_ids", []) as Array).size() >= 2
	_check("ta_promise_resolved_fulfilled", promise_resolved)
	_check("ta_same_thread_across_gap", same_id, "跨 17 天仍同一线程")

## TB：时间邻近 ≠ 线程——相邻 tick 事件无结构链接
func _tb_temporal_not_thread() -> void:
	var te := ThreadEngine.new()
	var st := te.engine
	# 两个无关事件，tick 相邻
	st.open_thread("PROMISE_THREAD", ["npc_oun", "npc_kadga"], 100, 100, {"promisor": "npc_oun", "promisee": "npc_kadga"})
	# 事件 101：完全无关（天气）
	var e_irrelevant := {"type": "weather_storm", "actor_id": "", "seq": 101, "tick": 101}
	te.engine.ingest_event(e_irrelevant, [])
	var th: Dictionary = te.engine.threads[0]
	_check("tb_irrelevant_not_added", (th.get("source_event_ids", []) as Array).size() == 1,
		"nodes=%d（天气不入承诺线程）" % (th.get("source_event_ids", []) as Array).size())

## TC：休眠——长时间无事件 → DORMANT，线程保留
func _tc_dormancy() -> void:
	var te := ThreadEngine.new()
	te.engine.open_thread("PROMISE_THREAD", ["npc_oun", "npc_kadga"], 100, 100, {"promisor": "npc_oun", "promisee": "npc_kadga"})
	te.engine.threads[0]["status"] = "ACTIVE"
	te.engine.update_threads(100 + StoryThread.DORMANT_AFTER_TICKS + 10)
	_check("tc_dormant_after_idle", str(te.engine.threads[0]["status"]) == "DORMANT")
	_check("tc_thread_persists", te.engine.threads.size() == 1)
	# TD：休眠后激活——同 thread_id
	te.engine.ingest_event({"type": "promise_kept", "actor_id": "npc_oun", "to_id": "npc_kadga", "seq": 500, "tick": 500}, [])
	_check("td_reactivated", str(te.engine.threads[0]["status"]) == "RESOLVED")

## TE：无证据不 RESOLVED——即使 10000 tick
func _te_resolution_evidence() -> void:
	var te := ThreadEngine.new()
	te.engine.open_thread("PROMISE_THREAD", ["npc_oun", "npc_kadga"], 100, 100, {"promisor": "npc_oun", "promisee": "npc_kadga"})
	te.engine.threads[0]["status"] = "ACTIVE"
	te.engine.update_threads(10100)
	_check("te_no_timeout_resolution", str(te.engine.threads[0]["status"]) == "DORMANT",
		"status=%s（10000 tick 后仍 DORMANT 非 RESOLVED）" % str(te.engine.threads[0]["status"]))

## TH：ThreadEngine ON/OFF 不影响模拟
func _th_no_sim_effect() -> void:
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
	# Run A：无 ThreadEngine
	var sim_a := IslandSimulation.new(mq, 44002, configs)
	for i in 300: sim_a.step()
	# Run B：有 ThreadEngine（只读处理）
	var sim_b := IslandSimulation.new(mq, 44002, configs)
	var te := ThreadEngine.new()
	for i in 300:
		sim_b.step()
		if i % 50 == 0:
			te.process(sim_b)  # 读但不写
	var hash_a := _sim_hash(sim_a)
	var hash_b := _sim_hash(sim_b)
	_check("th_no_sim_effect", str(hash_a) == str(hash_b),
		"hash match=%s" % str(hash_a == hash_b))

## TI：确定性——同历史同线程
func _ti_determinism() -> void:
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
	var sim := IslandSimulation.new(mq, 44003, configs)
	for i in 300: sim.step()
	var te1 := ThreadEngine.new()
	te1.process(sim)
	var te2 := ThreadEngine.new()
	te2.process(sim)
	_check("ti_deterministic", str(te1.engine.threads) == str(te2.engine.threads),
		"threads match=%s" % str(te1.engine.threads.size() == te2.engine.threads.size()))
	# ThreadIR 也确定性
	if te1.engine.threads.size() > 0:
		var ir1 := te1.build_thread_ir(sim, te1.engine.threads[0])
		var ir2 := te2.build_thread_ir(sim, te2.engine.threads[0])
		_check("ti_thread_ir_deterministic", str(ir1) == str(ir2))

func _sim_hash(sim) -> Dictionary:
	var out := {}
	for id in sim.actors:
		var a: Dictionary = sim.actors[id]
		out[id] = {"needs": str(a["needs"]), "inv": str(a["inventory"]),
			"emotions": str(a["personality"].emotions)}
	out["tick"] = sim.tick
	out["events"] = sim.events.size()
	return out

# ── P4.1: TM/TN/TO/TQ — Episode Identity + Purity ──
func _test_p41_episode_identity() -> void:
	# TM：同 dyad 两个承诺 → 两个不同线程
	var te := ThreadEngine.new()
	var st := te.engine
	var tid1 := st.open_thread("PROMISE_THREAD", ["npc_oun", "npc_kadga"], 100, 100,
		{"promisor": "npc_oun", "promisee": "npc_kadga"}, "promise|npc_oun|npc_kadga|100")
	var tid2 := st.open_thread("PROMISE_THREAD", ["npc_oun", "npc_kadga"], 200, 200,
		{"promisor": "npc_oun", "promisee": "npc_kadga"}, "promise|npc_oun|npc_kadga|200")
	_check("p41_tm_two_promises_different_threads", tid1 != tid2,
		"%s vs %s" % [tid1, tid2])

	# TM-2：兑现事件只入对应线程（episode_key 匹配）
	var ev_kept1 := {"type": "promise_kept", "actor_id": "npc_oun", "to_id": "npc_kadga", "seq": 300, "tick": 300}
	st.ingest_event(ev_kept1, [])
	_check("p41_tm_kept_matches_one_thread",
		(st.threads[0].get("source_event_ids", []) as Array).size() + (st.threads[1].get("source_event_ids", []) as Array).size() == 3,
		"t1=%d t2=%d（kept 只入一个线程，另一个保持独立——事件无法区分是哪个承诺）" % [(st.threads[0].get("source_event_ids", []) as Array).size(), (st.threads[1].get("source_event_ids", []) as Array).size()])

	# TN：同 dyad 两个不同疑问 → 两个 EPISTEMIC 线程
	var tn_st := StoryThread.new()
	tn_st.open_thread("EPISTEMIC_THREAD", ["npc_weila", "npc_oun"], 100, 100,
		{"asker": "npc_weila", "subject": "npc_oun"}, "question|npc_weila|npc_oun|100")
	tn_st.open_thread("EPISTEMIC_THREAD", ["npc_weila", "npc_oun"], 150, 150,
		{"asker": "npc_weila", "subject": "npc_oun"}, "question|npc_weila|npc_oun|150")
	_check("p41_tn_two_questions_different_threads", tn_st.threads.size() == 2 and tn_st.threads[0]["thread_id"] != tn_st.threads[1]["thread_id"])

	# TO：已解决的冲突不复活——新冲突创建新线程
	var to_st := StoryThread.new()
	var old_tid := to_st.open_thread("RELATIONSHIP_CONFLICT", ["npc_weila", "npc_oun"], 100, 100,
		{"confronter": "npc_weila", "confronted": "npc_oun"}, "conflict|npc_weila|npc_oun|100")
	to_st.threads[0]["status"] = "RESOLVED"
	to_st.threads[0]["resolved_tick"] = 200
	# 新冲突
	var new_tid := to_st.open_thread("RELATIONSHIP_CONFLICT", ["npc_weila", "npc_oun"], 500, 500,
		{"confronter": "npc_weila", "confronted": "npc_oun"}, "conflict|npc_weila|npc_oun|500")
	_check("p41_to_resolved_not_reopened",
		old_tid != new_tid and str(to_st.threads[0]["status"]) == "RESOLVED" and str(to_st.threads[1]["status"]) == "OPEN")

	# TQ：Thread Purity——无污染
	var pq := StoryThread.new()
	pq.open_thread("PROMISE_THREAD", ["a", "b"], 100, 100, {}, "promise|a|b|100")
	pq.open_thread("PROMISE_THREAD", ["a", "b"], 200, 200, {}, "promise|a|b|200")
	_check("p41_tq_purity_zero_contamination", pq.check_purity() == 0)

	# Attachment provenance 存在
	var prov_ok := true
	for th in te.engine.threads:
		var atts: Array = th.get("attachments", [])
		if (th.get("source_event_ids", []) as Array).size() > 1 and atts.is_empty():
			prov_ok = false
	_check("p41_tp_attachments_have_provenance", prov_ok)
