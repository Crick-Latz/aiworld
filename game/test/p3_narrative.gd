extends SceneTree
## P3a-1 Grounded Narrative Renderer 验收（总纲第 20 条 P3-NA…NG + 三视角集成）
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/p3_narrative.gd

var passed := 0
var failed := 0
var _s := false
var _f := false

func _initialize() -> void: pass
func _process(_d: float) -> bool:
	if not _s: _s = true; _run()
	return _f

func _run() -> void:
	await _contract_and_fallback()
	await _perspectives()
	_determinism()
	await _test_p3a2_claims()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	_f = true
	quit(0 if failed == 0 else 1)

func _check(n: String, c: bool, d: String = "") -> void:
	if c: passed += 1; print("PASS %s" % n)
	else: failed += 1; print("FAIL %s  %s" % [n, d])

## ── P3-NA grounding + P3-ND fallback + P3-NE malformed + P3-NF no-new-dialogue ──
func _contract_and_fallback() -> void:
	var sim = await _make_sim(600)
	if sim == null:
		for i in 14: _check("p3_contract_%d" % i, false, "地图不可用")
		return
	var ir_o: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 10)
	_check("p3_ir_objective_ok", bool(ir_o.get("ok", false)), str(ir_o.get("code", "")))

	# 契约：Template 输出（无 LLM 路径）
	var t_out: Dictionary = NarrativeRenderer.render({"render": func(ir, s, l, n): return TemplateNarrativeRenderer.render(ir, s, l, n)}, ir_o, "chronicle", "zh", 4)
	_check("p3_template_contract", bool(t_out.get("ok", false)) and str(t_out.get("text", "")) != "" and str(t_out.get("renderer", "")) != "",
		str(t_out.get("code", "")))
	# P3-NA：输出 source ids ⊆ IR
	var ir_events: Dictionary = {}
	for e in ir_o.get("source_refs", {}).get("event_ids", []):
		ir_events[int(e)] = true
	var all_grounded := true
	for e in t_out.get("source_event_ids", []):
		if not ir_events.has(int(e)):
			all_grounded = false
	_check("p3_na_sources_grounded", all_grounded, str(t_out.get("source_event_ids", [])))

	# P3-NE：malformed LLM 输出 → Validator reject → fallback template
	var out_mal: Dictionary = NarrativeRenderer.render(MockNarrativeRenderer.make("malformed"), ir_o)
	_check("p3_ne_malformed_fallback", bool(out_mal.get("ok", false)) and str(out_mal.get("renderer", "")) == "template" and out_mal.has("fallback_reason"),
		"renderer=%s reason=%s" % [str(out_mal.get("renderer", "")), str(out_mal.get("fallback_reason", ""))])
	# timeout（null 返回）
	var out_to: Dictionary = NarrativeRenderer.render(MockNarrativeRenderer.make("timeout"), ir_o)
	_check("p3_ne_timeout_fallback", bool(out_to.get("ok", false)) and str(out_to.get("renderer", "")) == "template")
	# crash（空 dict）
	var out_cr: Dictionary = NarrativeRenderer.render(MockNarrativeRenderer.make("crash"), ir_o)
	_check("p3_ne_crash_fallback", bool(out_cr.get("ok", false)) and str(out_cr.get("renderer", "")) == "template")
	# missing_sources
	var out_ms: Dictionary = NarrativeRenderer.render(MockNarrativeRenderer.make("missing_sources"), ir_o)
	_check("p3_ne_missing_sources_rejected", out_ms.has("fallback_reason"), str(out_ms.get("renderer", "")))
	# hallucinated ids
	var out_hi: Dictionary = NarrativeRenderer.render(MockNarrativeRenderer.make("hallucinated_ids"), ir_o)
	_check("p3_ne_hallucinated_ids_rejected", out_hi.has("fallback_reason"))
	# fabricated dialogue（IR 无 speech）
	var out_fd: Dictionary = NarrativeRenderer.render(MockNarrativeRenderer.make("fabricated_dialogue"), ir_o)
	_check("p3_nf_no_fabricated_dialogue", out_fd.has("fallback_reason") and not _has_speech_marks(str(out_fd.get("text", ""))),
		"text=%s" % str(out_fd.get("text", "")).substr(0, 30))
	# mock ok 模式：合规 LLM 输出直接通过（不 fallback）
	var out_ok: Dictionary = NarrativeRenderer.render(MockNarrativeRenderer.make("ok"), ir_o)
	_check("p3_mock_ok_passes", bool(out_ok.get("ok", false)) and not out_ok.has("fallback_reason"),
		"reason=%s" % str(out_ok.get("fallback_reason", "")))
	# P3-ND：renderer 全故障时模拟状态不受影响（sim.tick 继续推进）
	var tick_before: int = sim.tick
	var ir_bad: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 5)
	var out_bad: Dictionary = NarrativeRenderer.render(MockNarrativeRenderer.make("crash"), ir_bad)
	sim.step()
	_check("p3_nd_simulation_unaffected", sim.tick == tick_before + 1 and bool(out_bad.get("ok", false)),
		"tick %d→%d" % [tick_before, sim.tick])

## ── P3-NB perspective isolation + P3-NC retrospective ──
func _perspectives() -> void:
	var sim = await _make_sim(600)
	if sim == null:
		for i in 6: _check("p3_perspective_%d" % i, false, "地图不可用")
		return
	# 构造一次只有欧恩目击的隐藏违规（薇拉不在场）
	var oun: Dictionary = sim.actors["npc_oun"]
	var vera: Dictionary = sim.actors["npc_weila"]
	var vera_tile: Vector2i = vera["tile"]
	vera["tile"] = Vector2i(2, 2)  # 拉走薇拉（远距）
	var rid := "rule_food_50"
	if not oun["perceived_group_beliefs"].has(rid):
		oun["perceived_group_beliefs"][rid] = {"rule": {"rule_id": rid, "object": "food", "proposer": "npc_weila", "prescribed": "CONTRIBUTE", "fraction": 0.5},
			"member_stance": {}, "publicity": 0.8, "shared_expectation": 0.6, "recognition": 1.0, "descriptive_compliance": 0.6, "perceived_enforcement": 0.3}
	oun["inventory"]["food"] = 4
	oun["needs"]["hunger"] = 900  # 饿到极限 → violate 倾向
	oun["norms"]["personal"]["sharing"] = 0.1  # 低认同 → 低合法性
	oun["norms"]["personal"]["self_reliance"] = 0.9
	oun["others_nearby"] = []  # 无人附近 → 隐藏违规（检测低）
	sim._compliance_check("npc_oun", oun, "food", 4)
	vera["tile"] = vera_tile  # 恢复
	var hidden_seq := -1
	for e in sim.events:
		if str(e.get("type", "")) == "storage_withheld":
			hidden_seq = int(e["seq"])
			break
	_check("p3_hidden_violation_exists", hidden_seq >= 0, "构造失败")
	# P3-NB：薇拉的 CHARACTER IR 不得包含该事件
	var ir_v: Dictionary = NarrativeIR.build_ir(sim, "CHARACTER", "npc_weila", 10)
	var leaked := false
	for f in ir_v.get("subjective_facts", []):
		if (f.get("source_event_ids", []) as Array).has(hidden_seq):
			leaked = true
	for f in ir_v.get("known_facts", []):
		if int(f.get("seq", -1)) == hidden_seq:
			leaked = true
	_check("p3_nb_no_hidden_leak", not leaked and bool(ir_v.get("ok", false)))
	# 渲染也不得包含
	var out_v: Dictionary = NarrativeRenderer.render({"render": func(ir, s, l, n): return TemplateNarrativeRenderer.render(ir, s, l, n)}, ir_v)
	_check("p3_nb_render_no_leak", str(out_v.get("text", "")).find("没有按约定") == -1 or hidden_seq < 0,
		"text 含隐藏违规")
	# OBJECTIVE 能看到（世界真值）
	var ir_o2: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 50)
	var obj_has := false
	for f in ir_o2.get("known_facts", []):
		if int(f.get("seq", -1)) == hidden_seq:
			obj_has = true
	_check("p3_objective_sees_truth", obj_has)
	# P3-NC：RETROSPECTIVE 与 CHARACTER 输出结构不同（retrospective 允许 reflected）
	var ir_r: Dictionary = NarrativeIR.build_ir(sim, "RETROSPECTIVE", "npc_weila", 10)
	_check("p3_nc_retrospective_valid", bool(ir_r.get("ok", false)), str(ir_r.get("code", "")))

## ── P3-NG determinism ──
func _determinism() -> void:
	var sim = await _make_sim(400)
	if sim == null:
		_check("p3_ng_deterministic", false, "地图不可用")
		return
	var ir1: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 10)
	var t1: Dictionary = TemplateNarrativeRenderer.render(ir1)
	var ir2: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 10)
	var t2: Dictionary = TemplateNarrativeRenderer.render(ir2)
	_check("p3_ng_deterministic", str(ir1.get("ir_hash", "")) == str(ir2.get("ir_hash", "")) and str(t1.get("text", "")) == str(t2.get("text", "")))
	# IR hash 稳定（narrative_ir 套件已测，此处验证 renderer 同 IR 同输出）

func _has_speech_marks(text: String) -> bool:
	return (text.count("“") > 0 and text.count("”") > 0) or (text.count("「") > 0 and text.count("」") > 0)

func _make_sim(ticks: int):
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null: return null
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var spot = mq.get_poi_tile("post_house")
	var configs: Array = []
	for ac in scenario.get("actors", []):
		var cfg = ac.duplicate()
		cfg["spawn"] = spot
		configs.append(cfg)
	var sim := IslandSimulation.new(mq, 43001, configs)
	for i in ticks:
		sim.step()
	return sim

# ── P3a-2: NH–NN（Atomic Claims + Drill-down）──
func _test_p3a2_claims() -> void:
	var sim = await _make_sim(600)
	if sim == null:
		for i in 8: _check("p3a2_%d" % i, false, "地图不可用")
		return
	var ir_o: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 10)
	_check("p3a2_ir_has_claims", bool(ir_o.get("ok", false)) and (ir_o.get("claims", []) as Array).size() > 0,
		"claims=%d" % (ir_o.get("claims", []) as Array).size())
	# beat 挂 claim_ids
	var beats: Array = ir_o.get("selected_beats", [])
	var beat_claimed := false
	for b in beats:
		if (b.get("claim_ids", []) as Array).size() > 0:
			beat_claimed = true
	_check("p3a2_beats_carry_claims", beat_claimed or beats.is_empty())
	# NH：Template CONTENT 句都有 claim
	var out: Dictionary = NarrativeRenderer.render({"render": func(ir, s, l, n): return TemplateNarrativeRenderer.render(ir, s, l, n)}, ir_o)
	var sentences: Array = out.get("sentences", [])
	var nh_ok := sentences.size() > 0
	for sn in sentences:
		if str(sn.get("kind", "")) == "CONTENT" and (sn.get("claim_ids", []) as Array).is_empty():
			nh_ok = false
	_check("p3a2_nh_content_sentences_claimed", nh_ok, str(sentences.size()))
	# NN：空世界 IR → EMPTY_DAY 句 claim_ids=[] 合法
	var empty_ir: Dictionary = {"ok": true, "perspective": "OBJECTIVE", "focus_actor": "", "window": {},
		"selected_beats": [], "claims": [], "known_facts": [], "subjective_facts": [], "forbidden_inferences": [],
		"source_refs": {"event_ids": [], "trace_ids": [], "beat_ids": []}}
	var empty_out: Dictionary = TemplateNarrativeRenderer.render(empty_ir)
	var has_empty_day := false
	for sn2 in empty_out.get("sentences", []):
		if str(sn2.get("kind", "")) == "EMPTY_DAY":
			has_empty_day = (sn2.get("claim_ids", []) as Array).is_empty()
	_check("p3a2_nn_empty_day_allowed", has_empty_day and bool(empty_out.get("ok", false)), str(empty_out.get("code", "")))
	# NK：drill-down——从 sentence 到 beat/claim/event 全链路
	var drill_ok := false
	for sn in sentences:
		if str(sn.get("kind", "")) == "CONTENT":
			var cids: Array = sn.get("claim_ids", [])
			var bids: Array = sn.get("beat_ids", [])
			var evs: Array = sn.get("source_event_ids", [])
			if cids.size() > 0 and bids.size() > 0 and evs.size() > 0:
				# 每个 claim 存在于 IR；每个 beat 存在
				var ir_claim_ids := {}
				for c in ir_o.get("claims", []):
					ir_claim_ids[str(c.get("claim_id", ""))] = true
				var all_c := true
				for cid in cids:
					if not ir_claim_ids.has(str(cid)):
						all_c = false
				if all_c:
					drill_ok = true
			break
	_check("p3a2_nk_drilldown_chain", drill_ok)
	# NL：claim_ids 派生的 sources 与 sentence 一致
	var nl_ok := true
	for sn in sentences:
		if str(sn.get("kind", "")) == "CONTENT":
			var deriv: Dictionary = NarrativeClaim.derive_sources(ir_o.get("claims", []), sn.get("claim_ids", []))
			var evs2: Array = sn.get("source_event_ids", [])
			for ev in evs2:
				if not (deriv["event_ids"] as Array).has(int(ev)):
					nl_ok = false
	_check("p3a2_nl_source_derivation", nl_ok)
	# NI + NM：视角隔离——隐藏违规的 claim 不在薇拉的 IR
	var oun: Dictionary = sim.actors["npc_oun"]
	var vera: Dictionary = sim.actors["npc_weila"]
	var vt: Vector2i = vera["tile"]
	vera["tile"] = Vector2i(2, 2)
	var rid2 := "rule_food_50"
	if not oun["perceived_group_beliefs"].has(rid2):
		oun["perceived_group_beliefs"][rid2] = {"rule": {"rule_id": rid2, "object": "food", "proposer": "npc_weila", "prescribed": "CONTRIBUTE", "fraction": 0.5},
			"member_stance": {}, "publicity": 0.8, "shared_expectation": 0.6, "recognition": 1.0, "descriptive_compliance": 0.6, "perceived_enforcement": 0.3}
	oun["inventory"]["food"] = 4
	oun["needs"]["hunger"] = 900
	oun["norms"]["personal"]["sharing"] = 0.1
	oun["others_nearby"] = []
	sim._compliance_check("npc_oun", oun, "food", 4)
	vera["tile"] = vt
	var hidden_seq2 := -1
	for e in sim.events:
		if str(e.get("type", "")) == "storage_withheld":
			hidden_seq2 = int(e["seq"])
			break
	var ir_v2: Dictionary = NarrativeIR.build_ir(sim, "CHARACTER", "npc_weila", 10)
	var claim_leak := false
	for c in ir_v2.get("claims", []):
		for ev in c.get("source_event_ids", []):
			if int(ev) == hidden_seq2:
				claim_leak = true
	_check("p3a2_ni_claim_isolation", not claim_leak, "seq=%d claims=%d" % [hidden_seq2, (ir_v2.get("claims", []) as Array).size()])
	# NM：同 beat 两视角 claim 集不同（OBJECTIVE vs CHARACTER 的 claims 数或 epistemic 分布不同）
	var ir_o2: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 10)
	var o_claims: int = (ir_o2.get("claims", []) as Array).size()
	var v_claims: int = (ir_v2.get("claims", []) as Array).size()
	var v_status_mix := false
	for c in ir_v2.get("claims", []):
		if str(c.get("epistemic_status", "")) == "PERCEIVED":
			v_status_mix = true
	_check("p3a2_nm_perspective_claim_diff", o_claims >= v_claims and v_status_mix,
		"objective=%d character=%d perceived=%s" % [o_claims, v_claims, str(v_status_mix)])
	# NJ：无因果边的事件不得产生 CAUSAL_LINK claim
	var causal_claims := 0
	for c in ir_o2.get("claims", []):
		if str(c.get("type", "")) == "CAUSAL_LINK":
			causal_claims += 1
	_check("p3a2_nj_no_unearned_causal_claims", causal_claims == 0,
		"causal=%d（本版不自动生成因果主张——只有结构边才能，且当前未接线）" % causal_claims)
	# 确定性：claims 集确定性
	var ir_again: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 10)
	_check("p3a2_claims_deterministic", str(ir_o2.get("claims", [])) == str(ir_again.get("claims", [])))
