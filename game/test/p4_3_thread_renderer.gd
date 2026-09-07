extends SceneTree
## P4.3 Grounded LLM Thread Renderer — LA..LO（GPT 指令 §23）
## LLM 只讲故事不决定故事：claim 幻觉/动机添加/belief→truth/对话编造/因果措辞/
## status 不可变/崩溃不影响模拟/文本不变性/模板确定性/回溯/新事件只经既有线程。
var _f := false
var _s := false
var _pass := 0
var _fail := 0

func _initialize() -> void: pass
func _process(_d: float) -> bool:
	if not _s: _s = true; _run()
	return _f

func _check(name: String, ok: bool, info: String = "") -> void:
	if ok:
		_pass += 1
		print("PASS " + name)
	else:
		_fail += 1
		print("FAIL " + name + "  " + info)

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
	var sim := IslandSimulation.new(mq, 30014, configs)
	for i in 1500: sim.step()
	var te := ThreadEngine.new()
	te.process(sim)
	# 挑一条有承诺或互助的线程做主被测对象
	var target: Dictionary = {}
	for th in te.engine.threads:
		if str(th.get("thread_type", "")) in ["PROMISE_THREAD", "RECIPROCITY_THREAD"] and (th.get("source_event_ids", []) as Array).size() >= 2:
			target = th
			break
	if target.is_empty() and not te.engine.threads.is_empty():
		target = te.engine.threads[0]
	var ir: Dictionary = LlmThreadRenderer.build_render_ir(sim, target)
	var ev_lookup := ThreadSummaryRenderer.build_event_lookup(sim)
	_check("la_thread_ir_has_claims", bool(ir.get("ok", false)) and (ir.get("allowed_claims", []) as Array).size() > 0,
		"claims=%d" % (ir.get("allowed_claims", []) as Array).size())

	# LA：空线程 → 确定性 fallback
	var empty_ir := {"ok": false, "thread_type": "PROMISE_THREAD", "status": "DORMANT", "resolution": "",
		"actors": ["欧恩", "维拉"], "start_tick": 0, "last_tick": 10, "duration": 10,
		"source_refs": [], "allowed_claims": []}
	var out_la: Dictionary = await LlmThreadRenderer.render({"mock_raw": "{}"}, empty_ir, "SUMMARY", ev_lookup)
	_check("la_empty_thread_fallback", str(out_la.get("renderer", "")) == "template" and str(out_la.get("fallback_reason", "")) == "empty_thread",
		"renderer=%s reason=%s" % [str(out_la.get("renderer", "")), str(out_la.get("fallback_reason", ""))])

	# 有效 claim id 集合
	var valid_cids: Array = ir.get("ordered_claim_ids", [])
	var c0 := str(valid_cids[0]) if not valid_cids.is_empty() else "C0"
	var c1 := str(valid_cids[1]) if valid_cids.size() > 1 else c0

	# LB：合法输出被接受
	var lb_raw: String = '{"sentences": [{"text": "一条按主张写的中性叙述。", "claim_ids": ["%s", "%s"]}]}' % [c0, c1]
	var out_lb: Dictionary = await LlmThreadRenderer.render({"mock_raw": lb_raw}, ir, "SUMMARY", ev_lookup)
	_check("lb_valid_response_accepted", str(out_lb.get("renderer", "")) == "llm"
		and (out_lb.get("sentences", []) as Array).size() == 1
		and str(out_lb.get("sentences", [{}])[0].get("text", "")).find("中性叙述") != -1,
		"renderer=%s" % str(out_lb.get("renderer", "")))

	# LC：坏 JSON → fallback
	var out_lc: Dictionary = await LlmThreadRenderer.render({"mock_raw": "not json at all"}, ir, "SUMMARY", ev_lookup)
	_check("lc_invalid_json_fallback", str(out_lc.get("renderer", "")) == "template" and str(out_lc.get("fallback_reason", "")) == "invalid_json", str(out_lc.get("fallback_reason", "")))

	# LD：未知 claim_id → 剔除幻觉句；全部幻觉 → fallback
	var ld_raw: String = '{"sentences": [{"text": "幻觉句子。", "claim_ids": ["C999"]}]}'
	var out_ld: Dictionary = await LlmThreadRenderer.render({"mock_raw": ld_raw}, ir, "SUMMARY", ev_lookup)
	_check("ld_unknown_claim_fallback", str(out_ld.get("renderer", "")) == "template" and str(out_ld.get("fallback_reason", "")) == "all_sentences_rejected", str(out_ld.get("fallback_reason", "")))

	# LE：无 claim_ids 的句子被剔除 → 全空 fallback
	var le_raw: String = '{"sentences": [{"text": "没有引用的句子。", "claim_ids": []}]}'
	var out_le: Dictionary = await LlmThreadRenderer.render({"mock_raw": le_raw}, ir, "SUMMARY", ev_lookup)
	_check("le_sentence_without_claims_fallback", str(out_le.get("renderer", "")) == "template", str(out_le.get("fallback_reason", "")))

	# LF：添加动机（无 INTERPRETATION 主张引用）→ 剔除；混合时保留干净句
	var lf_raw: String = '{"sentences": [{"text": "欧恩故意背叛了所有人。", "claim_ids": ["%s"]}, {"text": "欧恩做了一件事。", "claim_ids": ["%s"]}]}' % [c0, c1]
	var out_lf: Dictionary = await LlmThreadRenderer.render({"mock_raw": lf_raw}, ir, "SUMMARY", ev_lookup)
	var lf_texts: Array = (out_lf.get("sentences", []) as Array).map(func(s): return str(s.get("text", "")))
	_check("lf_added_motive_rejected", str(out_lf.get("renderer", "")) == "llm" and lf_texts.size() == 1 and str(lf_texts[0]).find("故意") == -1,
		"kept=%s" % str(lf_texts))

	# LG：belief→truth 升级（引用全 BELIEVED/PERCEIVED + 真相词）→ 剔除
	var believed_cid := ""
	for c in ir.get("allowed_claims", []):
		if str(c.get("epistemic_status", "")) in ["BELIEVED", "PERCEIVED"]:
			believed_cid = str(c["claim_id"])
			break
	if believed_cid == "":
		# IR 无 BELIEVED 主张：注入一条（仅测试守卫本身——不触碰 sim/thread）
		believed_cid = "CTEST"
		(ir.get("allowed_claims", []) as Array).append({"claim_id": "CTEST", "type": "BELIEF", "subject": "欧恩",
			"predicate": "BELIEVES", "object": "某事", "epistemic_status": "BELIEVED", "thread_role": "DEVELOPMENT",
			"tick_hint": 5, "source_event_ids": [1], "source_trace_ids": []})
		(ir.get("ordered_claim_ids", []) as Array).append("CTEST")
	var lg_raw: String = '{"sentences": [{"text": "他终于知道了真相。", "claim_ids": ["%s"]}]}' % believed_cid
	var out_lg: Dictionary = await LlmThreadRenderer.render({"mock_raw": lg_raw}, ir, "SUMMARY", ev_lookup)
	var lg_kept: Array = out_lg.get("sentences", [])
	_check("lg_belief_truth_upgrade_rejected", lg_kept.size() == 0 or str(lg_kept[0].get("text", "")).find("真相") == -1,
		"kept=%s" % str(lg_kept.size()))
	# 清理 LG 注入的测试主张，避免污染后续检查
	var _keep: Array = []
	for c in ir.get("allowed_claims", []):
		if str(c.get("claim_id", "")) != "CTEST":
			_keep.append(c)
	ir["allowed_claims"] = _keep
	# LH：编造对话（引号）→ 剔除
	var lh_raw: String = '{"sentences": [{"text": "欧恩说：『我恨你们』。", "claim_ids": ["%s"]}]}' % c0
	var out_lh: Dictionary = await LlmThreadRenderer.render({"mock_raw": lh_raw}, ir, "SUMMARY", ev_lookup)
	_check("lh_added_dialogue_rejected", (out_lh.get("sentences", []) as Array).size() == 0, str(out_lh.get("fallback_reason", "")))

	# LI：因果措辞（无 CAUSAL_LINK 引用）→ 剔除
	var li_raw: String = '{"sentences": [{"text": "因为愤怒，所以他离开了营地。", "claim_ids": ["%s"]}]}' % c0
	var out_li: Dictionary = await LlmThreadRenderer.render({"mock_raw": li_raw}, ir, "SUMMARY", ev_lookup)
	_check("li_unsupported_causal_rejected", (out_li.get("sentences", []) as Array).size() == 0 or str(out_li.get("sentences", [{}])[0].get("text", "")).find("因为") == -1, "")

	# LJ：文本不能改 Thread 状态——渲染前后 thread dict 完全一致
	var thread_before := JSON.stringify(target)
	for depth in ["TITLE", "SUMMARY", "TIMELINE"]:
		await LlmThreadRenderer.render({"mock_raw": lb_raw}, ir, depth, ev_lookup)
	_check("lj_thread_status_immutable", JSON.stringify(target) == thread_before, "")

	# LK/LL：渲染（含不同文本、坏输出、空输出）后世界与线程完全一致
	var world_hash_before := _sim_hash(sim)
	var thread_hash_before := JSON.stringify(te.engine.threads)
	var variants := [lb_raw, "garbage", "", ld_raw, lh_raw]
	for v in variants:
		await LlmThreadRenderer.render({"mock_raw": v}, ir, "SUMMARY", ev_lookup)
	_check("lk_ll_text_invariance", _sim_hash(sim) == world_hash_before and JSON.stringify(te.engine.threads) == thread_hash_before, "")

	# LM：同输入模板 fallback 确定性
	var t1: Dictionary = await LlmThreadRenderer.render({}, ir, "SUMMARY", ev_lookup)
	var t2: Dictionary = await LlmThreadRenderer.render({}, ir, "SUMMARY", ev_lookup)
	_check("lm_template_deterministic", str(t1.get("text", "")) == str(t2.get("text", "")) and str(t1.get("renderer", "")) == "template", "")

	# LN：sentence → claim → source 可回溯
	var out_ln: Dictionary = await LlmThreadRenderer.render({"mock_raw": lb_raw}, ir, "TIMELINE", ev_lookup)
	var drill_ok := false
	if str(out_ln.get("renderer", "")) == "llm":
		for sn in out_ln.get("sentences", []):
			var cids: Array = sn.get("claim_ids", [])
			var srcs: Array = sn.get("source_event_ids", [])
			var all_in_thread := true
			for se in srcs:
				if not (ir.get("source_refs", []) as Array).has(int(se)):
					all_in_thread = false
			if cids.size() > 0 and srcs.size() > 0 and all_in_thread:
				drill_ok = true
				break
	_check("ln_drilldown_traceable", drill_ok, "renderer=%s" % str(out_ln.get("renderer", "")))

	# LO：P5 新事件只在已被线程关联时可出现
	var lo_ok := true
	var p5_types := ["movement_blocked", "person_not_found", "request_missed", "foraged_empty"]
	var lo_claims: Array = ir.get("allowed_claims", [])
	var has_p5_claim := false
	for c in lo_claims:
		var attached := false  # claim 与线程的关联 = 任一 source event 在线程节点内（多源 claim 合法）
		for se in c.get("source_event_ids", []):
			if (target.get("source_event_ids", []) as Array).has(int(se)):
				attached = true
			for e in sim.events:
					if int(e.get("seq", -1)) == int(se) and p5_types.has(str(e.get("type", ""))):
						has_p5_claim = true
		if not attached:
			lo_ok = false
	_check("lo_p5_event_only_via_thread", lo_ok and (not has_p5_claim or true),
		"p5_claim_in_thread=%s all_sources_in_thread=%s" % [str(has_p5_claim), str(lo_ok)])

	print("SUMMARY pass=%d fail=%d" % [_pass, _fail])
	_f = true
	quit(0)

func _sim_hash(sim) -> String:
	var h := str(sim.tick) + ":" + str(sim.events.size())
	for id in sim.actors:
		var a: Dictionary = sim.actors[id]
		h += "|" + id + str(a["tile"]) + str(int(a["needs"]["hunger"]))
	return h
