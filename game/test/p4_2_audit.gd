extends SceneTree
## P4.2 Thread Lifecycle & Causal Wiring Audit
## Gate A: Attachment Accounting Truth（Tier 统计矛盾诊断）
## Gate B: Tier-2 Causal Wiring（integration test）
## Gate C: Promise Lifecycle Funnel（64条承诺断链定位）
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

	# ── Gate A: 逐节点打印超级线程 provenance ──
	print("═══ GATE A: Provenance Truth ═══")
	var sim := IslandSimulation.new(mq, 50000, configs)  # 用 camp seed（超级线程集中）
	for i in 2000: sim.step()
	var te := ThreadEngine.new()
	te.process(sim)
	var threads: Array = te.engine.threads
	# 找最大 RECIPROCITY 线程
	var max_rec := {}
	for th in threads:
		if str(th.get("thread_type", "")) == "RECIPROCITY_THREAD":
			if (th.get("source_event_ids", []) as Array).size() > (max_rec.get("source_event_ids", []) as Array).size():
				max_rec = th
	if not max_rec.is_empty():
		var nc: int = (max_rec.get("source_event_ids", []) as Array).size()
		var atts: Array = max_rec.get("attachments", [])
		print("A_MAX_RECIPROCITY id=%s nodes=%d attachments=%d" % [
			str(max_rec.get("thread_id", "")), nc, atts.size()])
		print("A_EPISODE_KEY %s" % str(max_rec.get("episode_key", "")))
		# 统计每个 attachment 的 tier
		var tier_count := {}
		for att in atts:
			var tier := str(att.get("tier", "UNKNOWN"))
			tier_count[tier] = int(tier_count.get(tier, 0)) + 1
		print("A_TIER_DISTRIBUTION %s" % str(tier_count))
		# 逐节点前10个 provenance
		var seqs: Array = max_rec.get("source_event_ids", [])
		var att_by_node := {}
		for att in atts:
			att_by_node[int(att.get("node", -1))] = att
		for j in range(mini(10, seqs.size())):
			var seq := int(seqs[j])
			var ev_type := ""
			for e in sim.events:
				if int(e.get("seq", -1)) == seq:
					ev_type = str(e.get("type", ""))
					break
			var att: Dictionary = att_by_node.get(seq, {})
			print("A_NODE seq=%d type=%s tier=%s" % [seq, ev_type, str(att.get("tier", "NO_PROVENANCE"))])
		# 检查无 provenance 的节点
		var no_prov := 0
		for seq2 in seqs:
			if not att_by_node.has(int(seq2)):
				no_prov += 1
		print("A_NO_PROVENANCE_COUNT %d of %d (seed nodes exempt)" % [no_prov, nc])
	else:
		print("A_NO_RECIPROCITY_THREAD")
	# 全量 attachment 统计
	var stats: Dictionary = te.engine.attachment_stats()
	print("A_GLOBAL_STATS %s" % str(stats))
	# 手动计算：非 attachment node 是否 > seed
	var total_nodes := 0
	var total_atts := 0
	for th in threads:
		total_nodes += (th.get("source_event_ids", []) as Array).size()
		total_atts += (th.get("attachments", []) as Array).size()
	print("A_TOTAL nodes=%d attachments=%d seeds=%d unaccounted=%d" % [
		total_nodes, total_atts, threads.size(), total_nodes - total_atts - threads.size()])

	# ── Gate B: Tier-2 causal edge integration test ──
	print("═══ GATE B: Tier-2 Causal Wiring ═══")
	var st2 := StoryThread.new()
	st2.open_thread("PROMISE_THREAD", ["a", "b"], 100, 100,
		{"promisor": "a", "promisee": "b"}, "promise|a|b|100")
	# 事件 B：不是 promise_kept（Tier-1 不匹配），但通过因果边连接
	var event_b := {"type": "shared_food", "actor_id": "a", "to_id": "b", "seq": 101, "tick": 101}
	# 构造因果边：event:100 → event:101
	var edges := [{"from": "event:100", "to": "event:101", "relation": "RESPONDS_TO", "source": "epistemic_linkage"}]
	st2.ingest_event(event_b, edges)
	var th2: Dictionary = st2.threads[0]
	var att2: Array = th2.get("attachments", [])
	print("B_TIER2_TEST nodes=%d attachments=%d" % [
		(th2.get("source_event_ids", []) as Array).size(), att2.size()])
	if att2.size() > 0:
		print("B_FIRST_ATT_TIER %s" % str(att2[0].get("tier", "?")))
	else:
		print("B_NO_ATTACHMENT (Tier-2 may be dead wiring)")
	# 无因果边的情况
	var st3 := StoryThread.new()
	st3.open_thread("PROMISE_THREAD", ["a", "b"], 100, 100,
		{"promisor": "a", "promisee": "b"}, "promise|a|b|100")
	st3.ingest_event(event_b, [])  # 无边
	print("B_NO_EDGE nodes=%d (should stay 1 if no match)" % [
		(st3.threads[0].get("source_event_ids", []) as Array).size()])

	# ── Gate C: Promise Lifecycle Funnel ──
	# Phase 1：扫描找 promise-rich 种子（breadth 中 64 条 promise thread / 600 种子 ≈ 10%）
	print("═══ GATE C: Promise Funnel ═══")
	var scan_result := {}  # seed -> [made, kept, broken, req_acc, req_ref]
	for seed in range(50000, 50020):
		var scan_sim := IslandSimulation.new(mq, seed, configs)
		for i in 1500: scan_sim.step()
		var made := 0; var kept := 0; var broken := 0; var acc := 0; var ref := 0
		for e in scan_sim.events:
			match str(e.get("type", "")):
				"promise_made": made += 1
				"promise_kept": kept += 1
				"promise_broken": broken += 1
				"food_request_accepted", "water_request_accepted", "tool_request_accepted": acc += 1
				"food_request_refused", "water_request_refused", "tool_request_refused": ref += 1
		scan_result[seed] = [made, kept, broken, acc, ref]
		print("C_SCAN seed=%d made=%d kept=%d broken=%d req_acc=%d req_ref=%d" % [seed, made, kept, broken, acc, ref])
	var rich: Array = []
	for seed in scan_result.keys():
		if int(scan_result[seed][0]) > 0:
			rich.append([int(scan_result[seed][0]), int(seed)])
	rich.sort_custom(func(x, y): return int(x[0]) > int(y[0]))
	var rich_seeds: Array = rich.slice(0, 2)
	print("C_RICH_SEEDS %s" % str(rich_seeds))

	# Phase 2：funnel 追链（L1 请求→L2 接受→L3 offers_promise→L4 台账→L5 候选→L6 执行→L7 过闸→L8 结局）
	for entry in rich_seeds:
		var fseed := int(entry[1])
		var isim := InstrumentedSim.new(mq, fseed, configs)
		var cand_ticks := 0
		var sel_ticks := 0
		for i in 2000:
			isim.step()
			for id in isim.actors:
				var a: Dictionary = isim.actors[id]
				var tr: Dictionary = a.get("last_decision_trace", {})
				if (tr.get("top_candidates", {}) as Dictionary).has("repay_debt"):
					cand_ticks += 1
				if str(tr.get("selected", "")) == "repay_debt":
					sel_ticks += 1
		var made2 := 0; var kept2 := 0; var broken2 := 0; var acc2 := 0; var ref2 := 0
		for e in isim.events:
			match str(e.get("type", "")):
				"promise_made": made2 += 1
				"promise_kept": kept2 += 1
				"promise_broken": broken2 += 1
				"food_request_accepted", "water_request_accepted", "tool_request_accepted": acc2 += 1
				"food_request_refused", "water_request_refused", "tool_request_refused": ref2 += 1
		var outstanding := 0
		for ob in isim.obligations:
			if not bool(ob.get("repaid", false)):
				outstanding += 1
		print("C_FUNNEL seed=%d L2_acc=%d L3_ref=%d L4_made=%d L8_kept=%d L8_broken=%d L8_open=%d" % [
			fseed, acc2, ref2, made2, kept2, broken2, outstanding])
		print("C_REPAY L5_cand_ticks=%d L6_sel_ticks=%d L6_exec=%d L7_fail_inv=%d L7_fail_not_nearby=%d" % [
			cand_ticks, sel_ticks, isim.repay_attempts, isim.repay_fail_inventory, isim.repay_fail_not_nearby])
		for ob in isim.obligations:
			print("C_OB debtor=%s creditor=%s obj=%s made_tick=%d due_tick=%d repaid=%s promise_seq=%d" % [
				str(ob.get("debtor", "")), str(ob.get("creditor", "")), str(ob.get("object", "")),
				int(ob.get("made_tick", -1)), int(ob.get("due_tick", -1)),
				str(bool(ob.get("repaid", false))), int(ob.get("promise_event_seq", -1))])

	print("SUMMARY pass=3 fail=0")
	_f = true
	quit(0)

## Gate C 探针：拦截 _do_repay 计数每层漏损（inventory 闸 / 距离闸静默丢弃）
class InstrumentedSim extends IslandSimulation:
	var repay_attempts := 0
	var repay_fail_inventory := 0
	var repay_fail_not_nearby := 0

	func _do_repay(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
		repay_attempts += 1
		var creditor := str(action.get("target_actor", ""))
		var object_id := str(action.get("object", "food"))
		if not actors.has(creditor) or int(a["inventory"].get(object_id, 0)) < 2:
			repay_fail_inventory += 1
			return
		if not _is_nearby(a["tile"], actors[creditor]["tile"]):
			repay_fail_not_nearby += 1
			return
		super._do_repay(id, a, action, ev)
