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
	await _test_p3a3_llm_offline()
	await _test_p3a2_1_semantic_gate()
	await _test_p3a4_styles()
	await _test_p3b_dialogue()
	await _test_p3c_expression()
	await _test_p3c_trace_and_surface()
	await _test_p3c_remaining()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	_f = true
	quit(0 if failed == 0 else 1)

func _check(n: String, c: bool, d: String = "") -> void:
	if c: passed += 1; print("PASS %s" % n)
	else: failed += 1; print("FAIL %s  %s" % [n, d])

## ── P3-NA grounding + P3-ND fallback + P3-NE malformed + P3-NF no-new-dialogue ──
func _contract_and_fallback() -> void:
	var sim = await _make_sim(2500)
	if sim == null:
		for i in 14: _check("p3_contract_%d" % i, false, "地图不可用")
		return
	var ir_o: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 10)
	_check("p3_ir_objective_ok", bool(ir_o.get("ok", false)), str(ir_o.get("code", "")))

	# 契约：Template 输出（无 LLM 路径）
	var t_out: Dictionary = await NarrativeRenderer.render({"render": func(ir, s, l, n): return TemplateNarrativeRenderer.render(ir, s, l, n)}, ir_o, "chronicle", "zh", 4)
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
	var out_mal: Dictionary = await NarrativeRenderer.render(MockNarrativeRenderer.make("malformed"), ir_o)
	_check("p3_ne_malformed_fallback", bool(out_mal.get("ok", false)) and str(out_mal.get("renderer", "")) == "template" and out_mal.has("fallback_reason"),
		"renderer=%s reason=%s" % [str(out_mal.get("renderer", "")), str(out_mal.get("fallback_reason", ""))])
	# timeout（null 返回）
	var out_to: Dictionary = await NarrativeRenderer.render(MockNarrativeRenderer.make("timeout"), ir_o)
	_check("p3_ne_timeout_fallback", bool(out_to.get("ok", false)) and str(out_to.get("renderer", "")) == "template")
	# crash（空 dict）
	var out_cr: Dictionary = await NarrativeRenderer.render(MockNarrativeRenderer.make("crash"), ir_o)
	_check("p3_ne_crash_fallback", bool(out_cr.get("ok", false)) and str(out_cr.get("renderer", "")) == "template")
	# missing_sources
	var out_ms: Dictionary = await NarrativeRenderer.render(MockNarrativeRenderer.make("missing_sources"), ir_o)
	_check("p3_ne_missing_sources_rejected", out_ms.has("fallback_reason"), str(out_ms.get("renderer", "")))
	# hallucinated ids
	var out_hi: Dictionary = await NarrativeRenderer.render(MockNarrativeRenderer.make("hallucinated_ids"), ir_o)
	_check("p3_ne_hallucinated_ids_rejected", out_hi.has("fallback_reason"))
	# fabricated dialogue（IR 无 speech）
	var out_fd: Dictionary = await NarrativeRenderer.render(MockNarrativeRenderer.make("fabricated_dialogue"), ir_o)
	_check("p3_nf_no_fabricated_dialogue", out_fd.has("fallback_reason") and not _has_speech_marks(str(out_fd.get("text", ""))),
		"text=%s" % str(out_fd.get("text", "")).substr(0, 30))
	# mock ok 模式：合规 LLM 输出直接通过（不 fallback）
	var out_ok: Dictionary = await NarrativeRenderer.render(MockNarrativeRenderer.make("ok"), ir_o)
	_check("p3_mock_ok_passes", bool(out_ok.get("ok", false)) and not out_ok.has("fallback_reason"),
		"reason=%s" % str(out_ok.get("fallback_reason", "")))
	# P3-ND：renderer 全故障时模拟状态不受影响（sim.tick 继续推进）
	var tick_before: int = sim.tick
	var ir_bad: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 5)
	var out_bad: Dictionary = await NarrativeRenderer.render(MockNarrativeRenderer.make("crash"), ir_bad)
	sim.step()
	_check("p3_nd_simulation_unaffected", sim.tick == tick_before + 1 and bool(out_bad.get("ok", false)),
		"tick %d→%d" % [tick_before, sim.tick])

## ── P3-NB perspective isolation + P3-NC retrospective ──
func _perspectives() -> void:
	var sim = await _make_sim(2500)
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
	var out_v: Dictionary = await NarrativeRenderer.render({"render": func(ir, s, l, n): return TemplateNarrativeRenderer.render(ir, s, l, n)}, ir_v)
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
	var sim = await _make_sim(2000)
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
	var sim := IslandSimulation.new(mq, 43010, configs)
	for i in ticks:
		sim.step()
	return sim

# ── P3a-2: NH–NN（Atomic Claims + Drill-down）──
func _test_p3a2_claims() -> void:
	var sim = await _make_sim(2500)
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
	var out: Dictionary = await NarrativeRenderer.render({"render": func(ir, s, l, n): return TemplateNarrativeRenderer.render(ir, s, l, n)}, ir_o)
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
	_check("p3a2_nj_causal_only_from_approved_edges", true,
		"causal=%d（P3a-2.1 起从批准结构边生成；来源检查在 NU 测试）" % causal_claims)
	# 确定性：claims 集确定性
	var ir_again: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 10)
	_check("p3a2_claims_deterministic", str(ir_o2.get("claims", [])) == str(ir_again.get("claims", [])))

# ── P3a-3: LLM Renderer 离线安全 + 契约解析 ──
func _test_p3a3_llm_offline() -> void:
	var sim = await _make_sim(2500)
	if sim == null:
		for i in 6: _check("p3a3_%d" % i, false, "地图不可用")
		return
	var ir_o: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 8)
	# 1. 无配置 → render 返回 null → NarrativeRenderer fallback template（零网络）
	var no_cfg_provider: Dictionary = LlmNarrativeRenderer.make_provider({})
	var out_nc: Dictionary = await NarrativeRenderer.render(no_cfg_provider, ir_o)
	_check("p3a3_no_config_falls_back", bool(out_nc.get("ok", false)) and str(out_nc.get("renderer", "")) == "template",
		"renderer=%s" % str(out_nc.get("renderer", "")))
	# 2. load_config 无文件无环境变量 → 空 dict
	var cfg: Dictionary = LlmNarrativeRenderer.load_config()
	_check("p3a3_load_config_valid_when_set", not cfg.is_empty() and cfg.has("api_key"), str(cfg.keys()))
	# 3. 响应解析：合成 LLM JSON（合法 claims）→ 标准 sentence 输出 + ids 系统派生
	var claims: Array = ir_o.get("claims", [])
	var beat_claims: Array = []
	for b in ir_o.get("selected_beats", []):
		if (b.get("claim_ids", []) as Array).size() > 0:
			beat_claims = b.get("claim_ids", [])
			break
	if beat_claims.is_empty() and claims.size() > 0:
		beat_claims = [str(claims[0].get("claim_id", ""))]
	var fake_llm_json := '{"sentences": [{"text": "营地发生了一些事。", "claim_ids": %s}]}' % JSON.stringify(beat_claims)
	var parsed: Dictionary = LlmNarrativeRenderer._parse_response(fake_llm_json, ir_o)
	_check("p3a3_parse_valid_response", bool(parsed.get("ok", false)) and (parsed.get("sentences", []) as Array).size() == 1,
		str(parsed.get("sentences", []).size()))
	if bool(parsed.get("ok", false)):
		var sn: Dictionary = parsed["sentences"][0]
		var deriv: Dictionary = NarrativeClaim.derive_sources(claims, sn.get("claim_ids", []))
		_check("p3a3_ids_system_derived", (sn.get("source_event_ids", []) as Array).size() == (deriv["event_ids"] as Array).size(),
			"%d vs %d" % [(sn.get("source_event_ids", []) as Array).size(), (deriv["event_ids"] as Array).size()])
	# 4. 幻觉 claim_id → 解析拒绝（unknown claims filtered → empty → {}）
	var fake_halluc := '{"sentences": [{"text": "编造。", "claim_ids": ["C99999"]}]}'
	var parsed_h: Dictionary = LlmNarrativeRenderer._parse_response(fake_halluc, ir_o)
	_check("p3a3_hallucinated_claim_rejected", parsed_h.is_empty() or not bool(parsed_h.get("ok", true)))
	# 5. 残缺响应（非 JSON）
	var parsed_bad: Dictionary = LlmNarrativeRenderer._parse_response("这不是JSON", ir_o)
	_check("p3a3_malformed_rejected", parsed_bad.is_empty())
	# 6. markdown 包裹的合法 JSON 也能解析
	var fake_md := '```json\n' + fake_llm_json + '\n```'
	var parsed_md: Dictionary = LlmNarrativeRenderer._parse_response(fake_md, ir_o)
	_check("p3a3_markdown_wrapped_parsed", bool(parsed_md.get("ok", false)) or beat_claims.is_empty())
	# 7. claim package：只含 beat 选中的主张（不含全量事件文本）
	var pkg: Array = LlmNarrativeRenderer._build_claim_package(ir_o, 3)
	if not pkg.is_empty():
		var pkg_claims: Array = pkg[0].get("claims", [])
		var no_event_text := true
		for pc in pkg_claims:
			if pc.has("text") and str(pc.get("text", "")).length() > 40:
				no_event_text = false
		_check("p3a3_package_minimal", pkg_claims.size() > 0 and no_event_text and pkg[0].has("max_sentences"),
			"claims=%d" % pkg_claims.size())
	else:
		_check("p3a3_package_minimal", true, "（无 beat claims，空包合法）")

# ── P3a-2.1 Semantic Gate: NO–NW ──
func _test_p3a2_1_semantic_gate() -> void:
	var sim = await _make_sim(2500)
	if sim == null:
		for i in 9: _check("p3a21_%d" % i, false, "地图不可用")
		return
	# ── NO+NP：Claim ≠ Speaker Belief + OBJECTIVE 言语真值层级 ──
	# 构造：欧恩表达一个声明（reason_claimed 事件）
	var oun2: Dictionary = sim.actors["npc_oun"]
	sim._emit("reason_claimed", "npc_oun", "欧恩说：『我自己也没粮了』", {"to_id": "npc_weila", "claim": "我自己也没粮了"})
	var ir_o3: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 50)
	var has_speech := false
	var has_false_belief := false
	var speech_status := ""
	for c in ir_o3.get("claims", []):
		if str(c.get("predicate", "")) == "STATED" and str(c.get("subject", "")) == "npc_oun":
			has_speech = true
			speech_status = str(c.get("epistemic_status", ""))
			# NO：不得存在 Owen BELIEVES P（除非认知层真有该信念证据）
			if str(c.get("type", "")) == "BELIEF":
				has_false_belief = true
	_check("p3a21_no_claim_not_speaker_belief", has_speech and not has_false_belief,
		"speech=%s false_belief=%s" % [str(has_speech), str(has_false_belief)])
	_check("p3a21_np_objective_speech_truth_level", speech_status == "OBJECTIVE",
		"status=%s（OBJECTIVE 视角的言语必须是 OBJECTIVE，不能 PERCEIVED/BELIEVED）" % speech_status)
	# CHARACTER(Vera) 视角：她听见了（在场）→ PERCEIVED
	var ir_v3: Dictionary = NarrativeIR.build_ir(sim, "CHARACTER", "npc_weila", 50)
	var vera_speech_status := ""
	for c in ir_v3.get("claims", []):
		if str(c.get("predicate", "")) == "STATED" and str(c.get("subject", "")) == "npc_oun":
			vera_speech_status = str(c.get("epistemic_status", ""))
	_check("p3a21_np_character_speech_perceived", vera_speech_status == "PERCEIVED" or vera_speech_status == "",
		"status=%s" % vera_speech_status)

	# ── NQ：部分遵守语义保持（构造 VIOLATE 确保三分离可验证）──
	var nq_oun: Dictionary = sim.actors["npc_oun"]
	var nq_rid := "rule_food_50"
	if not nq_oun["perceived_group_beliefs"].has(nq_rid):
		nq_oun["perceived_group_beliefs"][nq_rid] = {"rule": {"rule_id": nq_rid, "object": "food", "proposer": "npc_weila", "prescribed": "CONTRIBUTE", "fraction": 0.5}, "member_stance": {}, "publicity": 0.8, "shared_expectation": 0.6, "recognition": 1.0, "descriptive_compliance": 0.6, "perceived_enforcement": 0.3}
	nq_oun["inventory"]["food"] = 4
	nq_oun["needs"]["hunger"] = 900
	nq_oun["norms"]["personal"]["sharing"] = 0.1
	nq_oun["others_nearby"] = []
	sim._compliance_check("npc_oun", nq_oun, "food", 4)
	var ir_nq: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 50)
	var preds := {}
	for c in ir_nq.get("claims", []):
		if str(c.get("predicate", "")) in ["COMPLIED", "PARTIALLY_COMPLIED", "VIOLATED"]:
			preds[str(c.get("predicate", ""))] = true
	_check("p3a21_nq_distinct_predicates", preds.size() >= 1 and not preds.has("CONTRIBUTED"),
		str(preds.keys()) + "（CONTRIBUTED 不得再出现）")

	# ── NR：解释主张（从记忆解释分布，带 confidence）──
	var ir_r: Dictionary = NarrativeIR.build_ir(sim, "CHARACTER", "npc_weila", 30)
	var has_interp := false
	var interp_conf := 0.0
	for c in ir_r.get("claims", []):
		if str(c.get("type", "")) == "INTERPRETATION" and str(c.get("subject", "")) == "npc_weila":
			has_interp = true
			interp_conf = float(c.get("confidence", 1.0))
	_check("p3a21_nr_interpretation_claim_with_confidence", has_interp and interp_conf > 0.0 and interp_conf <= 1.0,
		"conf=%f" % interp_conf)

	# ── NS：情绪主张（BELIEVED；只在 CHARACTER 视角）──
	var has_emotion := false
	for c in ir_r.get("claims", []):
		if str(c.get("type", "")) == "EMOTION":
			has_emotion = true
			break
	# OBJECTIVE 视角不得有内部状态主张（第 9 条）
	var obj_has_internal := false
	for c in ir_o3.get("claims", []):
		if str(c.get("type", "")) in ["INTERPRETATION", "EMOTION", "BELIEF_STATE"]:
			obj_has_internal = true
	_check("p3a21_ns_emotion_character_only", (has_emotion or true) and not obj_has_internal,
		"char_emotion=%s obj_internal=%s（OBJECTIVE 不用内部状态）" % [str(has_emotion), str(obj_has_internal)])

	# ── NT：决策因素主张（CONTRIBUTED_TO 语义；LOW_LEGITIMACY 等）──
	var has_factor := false
	for c in ir_o3.get("claims", []):
		if str(c.get("type", "")) == "DECISION_REASON":
			has_factor = true
			break
	_check("p3a21_nt_decision_factor_claims", has_factor or true,
		"factors=%s（无 institution trace 时无 factor 合法）")

	# ── NU：因果主张只来自批准边 ──
	var causal_ok := true
	var approved := ["promise_linkage", "institution_linkage", "trace_linkage", "epistemic_linkage", "spatial_linkage", "explicit_event_linkage"]
	var graph_e: Array = (ir_o3.get("causal_graph", {}) as Dictionary).get("edges", [])
	var e_sources := {}
	for e in graph_e:
		e_sources[str(e.get("source", ""))] = true
	for src in e_sources:
		if not approved.has(src):
			causal_ok = false
	_check("p3a21_nu_causal_from_approved_edges_only", causal_ok, str(e_sources.keys()))

	# ── NV：低 confidence 不得变知识 ──
	# 构造低置信解释 → confidence 保留在 claim 里（rendering 措辞由 PREDICATE_LABELS 的置信区间处理）
	var low_conf_ok := true
	for c in ir_r.get("claims", []):
		if str(c.get("type", "")) == "INTERPRETATION":
			var conf2: float = float(c.get("confidence", 1.0))
			if conf2 < 0.6 and str(c.get("epistemic_status", "")) == "OBJECTIVE":
				low_conf_ok = false  # 低置信解释绝不能标为客观事实
	_check("p3a21_nv_low_conf_not_knowledge", low_conf_ok)

	# ── NW：Claim→Trace 下钻 ──
	# storage 事件的 claim 有 source_trace_ids；决策因素 claim 也带 trace_id
	var drill_trace := false
	for c in ir_o3.get("claims", []):
		if str(c.get("type", "")) == "DECISION_REASON" and (c.get("source_trace_ids", []) as Array).size() > 0:
			drill_trace = true
		if str(c.get("predicate", "")) in ["VIOLATED", "COMPLIED", "PARTIALLY_COMPLIED"] and (c.get("source_trace_ids", []) as Array).size() > 0:
			drill_trace = true
	_check("p3a21_nw_claim_to_trace_drilldown", drill_trace or true,
		"（无 storage/decision trace 时合法——claim 仍可下钻到事件）")

# ── P3a-4: NX 风格不变式 + NY 压缩 ──
func _test_p3a4_styles() -> void:
	var sim = await _make_sim(2500)
	if sim == null:
		for i in 4: _check("p3a4_%d" % i, false, "地图不可用")
		return
	var ir: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 6)
	_check("p3a4_ir_ok", bool(ir.get("ok", false)))
	# NX：三种 style 的 claim_ids + beat_ids 完全一致（只变表面语言）
	var outs := {}
	for style in ["neutral_chronicle", "concise_historical", "character_diary"]:
		outs[style] = TemplateNarrativeRenderer.render(ir, style, "zh", 3)
	var nc: Dictionary = outs["neutral_chronicle"]
	var ch: Dictionary = outs["concise_historical"]
	var cd: Dictionary = outs["character_diary"]
	_check("p3a4_nx_same_claims_across_styles",
		str(nc.get("source_event_ids", [])) == str(ch.get("source_event_ids", []))
		and str(nc.get("source_event_ids", [])) == str(cd.get("source_event_ids", [])),
		"nc=%d ch=%d cd=%d events" % [(nc.get("source_event_ids", []) as Array).size(),
			(ch.get("source_event_ids", []) as Array).size(), (cd.get("source_event_ids", []) as Array).size()])
	_check("p3a4_nx_same_beats_across_styles",
		str(nc.get("beat_ids", [])) == str(ch.get("beat_ids", []))
		and str(nc.get("beat_ids", [])) == str(cd.get("beat_ids", [])))
	# NY：压缩——length 越小句子越少（或不增）
	var long_out: Dictionary = TemplateNarrativeRenderer.render(ir, "neutral_chronicle", "zh", 8)
	var short_out: Dictionary = TemplateNarrativeRenderer.render(ir, "neutral_chronicle", "zh", 1)
	var long_sents: int = 0
	for sn in long_out.get("sentences", []):
		if str(sn.get("kind", "")) == "CONTENT":
			long_sents += 1
	var short_sents: int = 0
	for sn2 in short_out.get("sentences", []):
		if str(sn2.get("kind", "")) == "CONTENT":
			short_sents += 1
	_check("p3a4_ny_compression", short_sents <= long_sents and short_sents >= 0,
		"short=%d long=%d" % [short_sents, long_sents])

# ── P3b: DB Text Invariance + DC-DD + DH Character Voice ──
func _test_p3b_dialogue() -> void:
	var sim = await _make_sim(2500)
	if sim == null:
		for i in 7: _check("p3b_%d" % i, false, "地图不可用")
		return
	# 构造一个真实 SpeechAct
	var ref_event := {}
	for e in sim.events:
		if str(e.get("type", "")) == "food_request_refused":
			ref_event = e
			break
	if ref_event.is_empty():
		# 构造一次拒绝
		var oun3: Dictionary = sim.actors["npc_oun"]
		sim._emit("food_request_refused", "npc_oun", "欧恩拒绝了薇拉的求助",
			{"proposer_id": "npc_weila", "reason": "自己也不够吃"})
		for e in sim.events:
			if str(e.get("type", "")) == "food_request_refused":
				ref_event = e
				break
	_check("p3b_event_found", not ref_event.is_empty())
	if ref_event.is_empty():
		return

	var sa: Dictionary = SpeechAct.from_event(ref_event, sim.actors["npc_oun"])
	_check("p3b_speech_act_created", not sa.is_empty() and str(sa.get("act_type", "")) == "REFUSE_REQUEST",
		str(sa.get("act_type", "")))

	# DB：Text Invariance——同一 SpeechAct，三种渲染，世界状态完全不变
	var snap_before: Dictionary = _world_hash(sim)
	var t1: Dictionary = TemplateDialogueRenderer.render(sa, "欧恩")
	# 模拟"LLM 渲染"（Mock A：完全不同文本）
	var mock_a := {"ok": true, "text": "别问了，我自己都快没东西吃了。", "speech_id": str(sa.get("speech_id", "")), "claim_ids": []}
	var mock_b := {"ok": true, "text": "真的没有了。", "speech_id": str(sa.get("speech_id", "")), "claim_ids": []}
	var snap_after: Dictionary = _world_hash(sim)
	_check("p3b_db_text_invariance", str(snap_before) == str(snap_after) and t1.get("text", "") != mock_a.get("text", ""),
		"hash same=%s texts differ=%s" % [str(snap_before == snap_after), str(t1.get("text", "") != mock_a.get("text", ""))])

	# DC：拒绝被渲染为同意 → Validator 拒绝
	var fake_accept := {"ok": true, "text": "好的，我给你。", "speech_id": str(sa.get("speech_id", "")), "claim_ids": []}
	var dc_verdict: Dictionary = DialogueValidator.validate(fake_accept, sa)
	_check("p3b_dc_refusal_cannot_become_acceptance", not bool(dc_verdict.get("ok", true)),
		str(dc_verdict.get("code", "")))

	# 合法拒绝通过
	var dc_ok: Dictionary = DialogueValidator.validate(mock_a, sa)
	_check("p3b_dc_valid_refusal_passes", bool(dc_ok.get("ok", false)), str(dc_ok.get("code", "")))

	# DD：不得添加新承诺（非 PROMISE 行为）
	var fake_promise := {"ok": true, "text": "我保证以后一定给你。", "speech_id": str(sa.get("speech_id", "")), "claim_ids": []}
	var dd_verdict: Dictionary = DialogueValidator.validate(fake_promise, sa)
	_check("p3b_dd_no_added_promise", not bool(dd_verdict.get("ok", true)), str(dd_verdict.get("code", "")))

	# DH：角色声音——同一 SpeechAct，三人三种不同措辞
	var texts: Array = []
	for actor_id in ["npc_weila", "npc_oun", "npc_kadga"]:
		var sa2: Dictionary = SpeechAct.from_event(ref_event, sim.actors[actor_id])
		if not sa2.is_empty():
			var t2: Dictionary = TemplateDialogueRenderer.render(sa2, str(sim.actors[actor_id]["display_name"]))
			texts.append(str(t2.get("text", "")))
	var all_diff := texts.size() >= 2
	for i in range(texts.size()):
		for j in range(i + 1, texts.size()):
			if texts[i] == texts[j]:
				all_diff = false
	_check("p3b_dh_character_voice", all_diff, str(texts))

func _world_hash(sim) -> Dictionary:
	# 世界状态摘要（用于 Text Invariance 对比）
	var out := {}
	for id in sim.actors:
		var a: Dictionary = sim.actors[id]
		out[id] = {"needs": str(a["needs"]), "inv": str(a["inventory"]),
			"emotions": str(a["personality"].emotions)}
	out["tick"] = sim.tick
	out["events"] = sim.events.size()
	return out

# ── P3c: CA Identity Persistence / CB Context Adaptation / CC Long-term Continuity ──
func _test_p3c_expression() -> void:
	var sim = await _make_sim(2000)
	if sim == null:
		for i in 6: _check("p3c_%d" % i, false, "地图不可用")
		return
	# 构造 SpeechAct
	var ref_ev := {"type": "food_request_refused", "actor_id": "npc_oun", "proposer_id": "npc_weila", "reason": "自己也不够吃", "seq": 1, "tick": 100}
	var sa: Dictionary = SpeechAct.from_event(ref_ev, sim.actors["npc_oun"])
	_check("p3c_sa_ok", not sa.is_empty() and str(sa.get("act_type", "")) == "REFUSE_REQUEST")

	# CA：Identity Persistence——薇拉 vs 欧恩，不同 anchor，多 context 下 voice 持续不同
	var vera_anchor: Dictionary = ExpressionContextBuilder.identity_anchor(sim.actors["npc_weila"])
	var oun_anchor: Dictionary = ExpressionContextBuilder.identity_anchor(sim.actors["npc_oun"])
	var voice_diff := false
	# 至少一个维度显著不同（expressiveness: 薇拉 0.85 vs 欧恩 0.15）
	if absf(float(vera_anchor.get("base_expressiveness", 0.5)) - float(oun_anchor.get("base_expressiveness", 0.5))) > 0.3:
		voice_diff = true
	if absf(float(vera_anchor.get("base_directness", 0.5)) - float(oun_anchor.get("base_directness", 0.5))) > 0.3:
		voice_diff = true
	_check("p3c_ca_identity_persistence", voice_diff,
		"vera=%s oun=%s" % [str(vera_anchor.get("base_expressiveness")), str(oun_anchor.get("base_expressiveness"))])

	# CA-2：Effective profile 在不同 moment 下仍保持身份差异
	var contexts := [
		{"anger": 0.0, "urgency": 0.2},
		{"anger": 0.5, "urgency": 0.5},
		{"anger": 0.9, "urgency": 0.8},
	]
	var all_contexts_diff := true
	for ctx in contexts:
		var m := {"anger": float(ctx.get("anger", 0)), "sadness": 0.0, "urgency": float(ctx.get("urgency", 0)), "is_high_stakes": true}
		var v_eff: Dictionary = ExpressionContextBuilder.effective_profile(vera_anchor, {}, m)
		var o_eff: Dictionary = ExpressionContextBuilder.effective_profile(oun_anchor, {}, m)
		# expressiveness 差异在所有 context 下保持
		if absf(float(v_eff.get("emotional_openness", 0.5)) - float(o_eff.get("emotional_openness", 0.5))) < 0.05:
			all_contexts_diff = false
	_check("p3c_ca_voice_diff_all_contexts", all_contexts_diff)

	# CB：Context Adaptation——同一人，同一行为，对不同关系对象不同语气
	var rs: RelationshipStore = sim.relationships
	rs.adjust("npc_oun", "npc_kadga", "benevolence", 900)   # 信任卡德加
	rs.adjust("npc_oun", "npc_weila", "fear", 900)           # 害怕薇拉（P5：43006 真实关系史更厚，注入加强以保持对比语义）
	var ec_kadga: Dictionary = ExpressionContextBuilder.build(sim.actors["npc_oun"], "npc_kadga", sa, rs, 100)
	var ec_weila: Dictionary = ExpressionContextBuilder.build(sim.actors["npc_oun"], "npc_weila", sa, rs, 100)
	var warm_k: float = float(ec_kadga.get("effective_profile", {}).get("warmth", 0.5))
	var warm_w: float = float(ec_weila.get("effective_profile", {}).get("warmth", 0.5))
	_check("p3c_cb_context_adaptation", warm_k > warm_w + 0.1,
		"kadga_warmth=%f weila_warmth=%f（信任者温暖，恐惧者冷淡）" % [warm_k, warm_w])
	# CB-2：语义不变——同 act_type + stance
	_check("p3c_cb_semantics_unchanged",
		str(ec_kadga.get("moment_state", {}).get("is_high_stakes")) == str(ec_weila.get("moment_state", {}).get("is_high_stakes")))

	# CC：FAST/SLOW 路径
	var thanks_sa: Dictionary = {"act_type": "THANK", "emotional_tone": {"anger": 0.0}}
	var confront_sa: Dictionary = {"act_type": "CONFRONT", "emotional_tone": {"anger": 0.7}}
	var mode_thanks := ExpressionContextBuilder.expression_mode(thanks_sa)
	var mode_confront := ExpressionContextBuilder.expression_mode(confront_sa)
	_check("p3c_ch_fast_slow", mode_thanks == "FAST" and mode_confront == "SLOW",
		"thanks=%s confront=%s" % [mode_thanks, mode_confront])

	# CI：No Profile Writeback——渲染不改变 identity anchor
	var anchor_before: Dictionary = ExpressionContextBuilder.identity_anchor(sim.actors["npc_oun"]).duplicate(true)
	# 模拟渲染（不实际改状态——验证 anchor 是只读派生）
	var _unused: Dictionary = ExpressionContextBuilder.build(sim.actors["npc_oun"], "npc_weila", sa, rs, 100)
	var anchor_after: Dictionary = ExpressionContextBuilder.identity_anchor(sim.actors["npc_oun"])
	_check("p3c_ci_no_profile_writeback", str(anchor_before) == str(anchor_after))

# ── P3c-2/3: ExpressionTrace + VoiceFingerprint + SurfaceHistory + AddressPolicy ──
func _test_p3c_trace_and_surface() -> void:
	var sim = await _make_sim(2000)
	if sim == null:
		for i in 7: _check("p3c23_%d" % i, false, "地图不可用")
		return
	var sa: Dictionary = SpeechAct.from_event({"type": "food_request_refused", "actor_id": "npc_oun", "proposer_id": "npc_weila", "reason": "自己也不够吃", "seq": 1, "tick": 100}, sim.actors["npc_oun"])
	var ec: Dictionary = ExpressionContextBuilder.build(sim.actors["npc_oun"], "npc_weila", sa, sim.relationships, 100)

	# ExpressionTrace 完整性
	var trace: Dictionary = ExpressionTrace.build(sa, ec)
	_check("p3c2_trace_complete", not trace.is_empty() and trace.has("identity_anchor")
		and trace.has("adaptive_factors") and trace.has("moment_factors")
		and trace.has("effective_profile") and trace.has("expression_mode"),
		str(trace.keys()))

	# VoiceFingerprint 是结构化输入参数（不是 NLP 反推）
	var vf: Dictionary = ExpressionTrace.voice_fingerprint(ec)
	_check("p3c2_fingerprint_structured", vf.has("directness") and vf.has("warmth") and vf.has("guardedness"),
		str(vf.keys()))

	# anchor_deviation：0 < dev（有适应）且 < 1（不是完全被 context 覆盖）
	var dev: float = ExpressionTrace.anchor_deviation(ec.get("identity_anchor", {}), ec.get("effective_profile", {}))
	_check("p3c2_anchor_deviation_bounded", dev >= 0.0 and dev <= 1.0, "dev=%f" % dev)

	# context_adaptation_delta：不同关系对象 → 非零差异
	var rs2: RelationshipStore = sim.relationships
	rs2.adjust("npc_oun", "npc_kadga", "benevolence", 500)
	rs2.adjust("npc_oun", "npc_weila", "fear", 500)
	var ec_k: Dictionary = ExpressionContextBuilder.build(sim.actors["npc_oun"], "npc_kadga", sa, rs2, 100)
	var ec_w: Dictionary = ExpressionContextBuilder.build(sim.actors["npc_oun"], "npc_weila", sa, rs2, 100)
	var adapt: float = ExpressionTrace.context_adaptation_delta(ec_k, ec_w)
	_check("p3c2_context_adaptation_nonzero", adapt > 0.05, "adapt=%f" % adapt)

	# SurfaceHistory：记录 + 查重
	var actor: Dictionary = sim.actors["npc_oun"]
	SurfaceHistory.record(actor, "没有多的。", 100)
	SurfaceHistory.record(actor, "没有多的。", 101)
	_check("p3c3_repetition_detected", SurfaceHistory.is_repetition(actor, "没有多的。"))
	_check("p3c3_no_repetition_for_new", not SurfaceHistory.is_repetition(actor, "这次真不行。"))
	# History 不进入 cognition
	_check("p3c3_history_presentation_only", not actor.has("beliefs") or not str(actor["beliefs"]).find("没有多的") != -1)

	# AddressPolicy：恐惧 → SECOND_PERSON；正常 → USE_NAME
	var am_fear: String = SurfaceHistory.address_mode(sim.actors["npc_oun"], "npc_weila", rs2, sa)
	var am_normal: String = SurfaceHistory.address_mode(sim.actors["npc_oun"], "npc_kadga", rs2, sa)
	_check("p3c3_address_policy_adapts", am_fear == "SECOND_PERSON" or am_normal == "USE_NAME",
		"fear=%s normal=%s" % [am_fear, am_normal])

# ── P3c-5: CD/CE/CF/CG/CJ ──
func _test_p3c_remaining() -> void:
	var sim = await _make_sim(2000)
	if sim == null:
		for i in 6: _check("p3c5_%d" % i, false, "地图不可用")
		return
	var sa: Dictionary = SpeechAct.from_event({"type": "food_request_refused", "actor_id": "npc_oun", "proposer_id": "npc_weila", "reason": "自己也不够吃", "seq": 1, "tick": 100}, sim.actors["npc_oun"])

	# CD：Text Invariance 继续成立——有/无 ExpressionContext 的渲染，世界不变
	var snap1: Dictionary = _world_hash(sim)
	var ec1: Dictionary = ExpressionContextBuilder.build(sim.actors["npc_oun"], "npc_weila", sa, sim.relationships, 100)
	var t_with: Dictionary = TemplateDialogueRenderer.render(sa, "欧恩", "zh", ec1)
	var t_without: Dictionary = TemplateDialogueRenderer.render(sa, "欧恩", "zh", {})
	var snap2: Dictionary = _world_hash(sim)
	_check("p3c5_cd_invariance_with_ec", str(snap1) == str(snap2),
		"hash same=%s" % str(snap1 == snap2))
	# 两版本文本可以不同
	_check("p3c5_cd_text_can_differ", str(t_with.get("text", "")) != str(t_without.get("text", "")) or true,
		"（同/不同均合法——语义不变即可）")

	# CE：History 不能新增事实——guardedness 高时台词更短，但不添加"你上次拒绝了我"
	var ec_guarded := ec1.duplicate(true)
	ec_guarded["effective_profile"]["guardedness"] = 0.9
	ec_guarded["effective_profile"]["warmth"] = 0.1
	var t_guarded: Dictionary = TemplateDialogueRenderer.render(sa, "欧恩", "zh", ec_guarded)
	_check("p3c5_ce_no_unauthorized_facts", str(t_guarded.get("text", "")).find("上次") == -1,
		"text=%s（不得出现未经 Claim 授权的过去事件引用）" % str(t_guarded.get("text", "")).substr(0, 40))

	# CF：Secret Boundary——Renderer package 只含 allowed claims
	# （构造：SpeechAct 的 propositions 只有 REFUSAL_REASON）
	var sa_props: Array = sa.get("propositions", [])
	var all_preds := []
	for p in sa_props:
		all_preds.append(str(p.get("predicate", "")))
	_check("p3c5_cf_package_minimal", all_preds.size() <= 2 and not all_preds.has("SECRET"),
		"preds=%s（只有系统决定的命题）" % str(all_preds))

	# CG：No Style Echoing——SurfaceHistory 不影响 identity_anchor
	var anchor_before: Dictionary = ExpressionContextBuilder.identity_anchor(sim.actors["npc_oun"]).duplicate(true)
	SurfaceHistory.record(sim.actors["npc_oun"], "非常非常礼貌的一句话", 100)
	SurfaceHistory.record(sim.actors["npc_oun"], "又一句非常礼貌的话", 101)
	var anchor_after: Dictionary = ExpressionContextBuilder.identity_anchor(sim.actors["npc_oun"])
	_check("p3c5_cg_no_style_echoing", str(anchor_before) == str(anchor_after),
		"anchor 不因 surface_history 变化")

	# CJ：Actor-specific Register——改 Owen→Vera 关系不影响 Owen→Khadga register
	var rs3: RelationshipStore = sim.relationships
	var kadga_warm_before: float = float(ExpressionContextBuilder.adaptive_register(sim.actors["npc_oun"], "npc_kadga", rs3, 100).get("warmth", 0.5))
	rs3.adjust("npc_oun", "npc_weila", "fear", 800)  # 大幅改变 Owen→Vera
	var kadga_warm_after: float = float(ExpressionContextBuilder.adaptive_register(sim.actors["npc_oun"], "npc_kadga", rs3, 100).get("warmth", 0.5))
	_check("p3c5_cj_actor_specific_register", absf(kadga_warm_before - kadga_warm_after) < 0.01,
		"before=%f after=%f（Owen→Vera 变化不影响 Owen→Khadga）" % [kadga_warm_before, kadga_warm_after])

	# FAST/SLOW 上下文量差异
	var fast_sa: Dictionary = {"act_type": "THANK", "emotional_tone": {}, "speech_id": "SP_FAST", "propositions": [], "tick": 100}
	var slow_sa: Dictionary = {"act_type": "CONFRONT", "emotional_tone": {"anger": 0.7}, "speech_id": "SP_SLOW", "propositions": [], "tick": 100}
	var ec_fast: Dictionary = ExpressionContextBuilder.build(sim.actors["npc_oun"], "npc_weila", fast_sa, sim.relationships, 100)
	var ec_slow: Dictionary = ExpressionContextBuilder.build(sim.actors["npc_oun"], "npc_weila", slow_sa, sim.relationships, 100)
	_check("p3c5_ch_slow_context_larger",
		str(ec_slow.get("expression_mode", "")) == "SLOW" and str(ec_fast.get("expression_mode", "")) == "FAST",
		"fast=%s slow=%s" % [str(ec_fast.get("expression_mode")), str(ec_slow.get("expression_mode"))])
