extends SceneTree
## P4.2 后续审计
## Gate D: Reciprocity episode 分类（dyad 合并 vs episode 隔离）
## Gate E: Epistemic resolution funnel（open→answered→resolved）
## Gate F: 跨线程双挂载 + PROMISE episode 串线检查
## Gate G: 合成场景——同 dyad 双 promise 反序兑现（episode identity 压力测试）
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

	# ── Gate D: Reciprocity episode 分类 ──
	print("═══ GATE D: Reciprocity Episode Classification ═══")
	var sim := IslandSimulation.new(mq, 50000, configs)
	for i in 2000: sim.step()
	var te := ThreadEngine.new()
	te.process(sim)
	var threads: Array = te.engine.threads
	var rec_threads: Array = []
	for th in threads:
		if str(th.get("thread_type", "")) == "RECIPROCITY_THREAD":
			rec_threads.append(th)
	print("D_TOTAL_RECIPROCITY %d" % rec_threads.size())
	# 按 dyad 分组
	var by_dyad := {}
	for th in rec_threads:
		var idt: Dictionary = th.get("identity", {})
		var key := "%s->%s" % [str(idt.get("helper", "")), str(idt.get("receiver", ""))]
		if not by_dyad.has(key):
			by_dyad[key] = []
		(by_dyad[key] as Array).append(th)
	for dyad in by_dyad.keys():
		var group: Array = by_dyad[dyad]
		var node_counts := []
		var ekeys := {}
		var tier1_count := 0
		for th in group:
			node_counts.append((th.get("source_event_ids", []) as Array).size())
			ekeys[str(th.get("episode_key", ""))] = true
			for att in th.get("attachments", []):
				if str(att.get("tier", "")) == "TIER_1_DYAD_FALLBACK" or str(att.get("tier", "")) == "TIER_1_EXPLICIT_ID":
					tier1_count += 1
		print("D_DYAD %s threads=%d nodes=%s unique_episode_keys=%d tier1_atts=%d" % [
			dyad, group.size(), str(node_counts), ekeys.size(), tier1_count])

	# ── Gate E: Epistemic resolution funnel ──
	print("═══ GATE E: Epistemic Funnel ═══")
	var epi_status := {"OPEN": 0, "ACTIVE": 0, "DORMANT": 0, "RESOLVED": 0, "SUPERSEDED": 0}
	var epi_resolved_with_evidence := 0
	for th in threads:
		if str(th.get("thread_type", "")) == "EPISTEMIC_THREAD":
			var st := str(th.get("status", ""))
			epi_status[st] = int(epi_status.get(st, 0)) + 1
			if st == "RESOLVED":
				var has_evidence := false
				for seq in th.get("source_event_ids", []):
					for e in sim.events:
						if int(e.get("seq", -1)) == int(seq) and str(e.get("type", "")) in ["reason_claimed", "reflected", "reason_deflected"]:
							has_evidence = true
							break
					if has_evidence:
						break
				if has_evidence:
					epi_resolved_with_evidence += 1
	print("E_STATUS %s" % str(epi_status))
	print("E_RESOLVED_WITH_EVIDENCE %d" % epi_resolved_with_evidence)

	# ── Gate F: 双挂载 + promise 串线 ──
	print("═══ GATE F: Double-Attach / Promise Cross-Wiring ═══")
	var seq_owner := {}
	for th in threads:
		for seq in th.get("source_event_ids", []):
			seq_owner[int(seq)] = int(seq_owner.get(int(seq), 0)) + 1
	var multi := 0
	for seq in seq_owner.keys():
		if int(seq_owner[seq]) > 1:
			multi += 1
	print("F_MULTI_OWNED_NODES %d of %d" % [multi, seq_owner.keys().size()])
	# seed 50015 双 promise 串线复检
	var sim15 := IslandSimulation.new(mq, 50015, configs)
	for i in 2000: sim15.step()
	var te15 := ThreadEngine.new()
	te15.process(sim15)
	for th in te15.engine.threads:
		if str(th.get("thread_type", "")) == "PROMISE_THREAD":
			var seed_node: int = int((th.get("source_event_ids", []) as Array)[0])
			print("F_PROMISE_THREAD %s status=%s nodes=%d seed_seq=%d nodes=%s" % [
				str(th.get("thread_id", "")), str(th.get("status", "")),
				(th.get("source_event_ids", []) as Array).size(), seed_node,
				str(th.get("source_event_ids", []))])

	# ── Gate G: 合成压力测试——同 dyad 双 promise，反序兑现 ──
	print("═══ GATE G: Episode Identity Stress Test ═══")
	var stg := StoryThread.new()
	stg.open_thread("PROMISE_THREAD", ["oun", "kadga"], 100, 100,
		{"promisor": "oun", "promisee": "kadga"}, "promise|oun|kadga|100")
	stg.open_thread("PROMISE_THREAD", ["oun", "kadga"], 200, 150,
		{"promisor": "oun", "promisee": "kadga"}, "promise|oun|kadga|200")
	# promise_kept 指向第二笔（seq 200），先于第一笔兑现
	var kept2 := {"type": "promise_kept", "actor_id": "oun", "to_id": "kadga",
		"seq": 250, "tick": 200, "source_event_ids": [200]}
	stg.ingest_event(kept2, [])
	var t1: Dictionary = stg.threads[0]
	var t2: Dictionary = stg.threads[1]
	print("G_T1_RESOLVED_BY_KEPT2 %s (expect false)" % str(t1.get("status", "") == "RESOLVED"))
	print("G_T2_RESOLVED_BY_KEPT2 %s (expect true)" % str(t2.get("status", "") == "RESOLVED"))

	print("SUMMARY gates=D,E,F,G")
	_f = true
	quit(0)
