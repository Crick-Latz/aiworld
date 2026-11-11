extends SceneTree
## UI-R2 Targeted Tests：大脑 ViewModel 语义 + 无副作用 + 守卫扫描。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path game --script res://test/ui_r2_brain_view_model.gd
## 覆盖：needs 映射与 energy→fatigue 反转、关系/ToM 分离、动态 has_item 谓词、
## 记忆推导（day/derived_importance）、承诺过滤、why chain provenance、
## 缺失可选字段 fail-soft、build 前后模拟状态零变化、私有 tracker 访问扫描、mutation 调用扫描。

var passed := 0
var failed := 0
var _started := false
var _finished := false
var _inst: Node = null

func _initialize() -> void:
	print("UI-R2 brain view model harness: deferred to first frame")

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _finished

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("PASS %s" % name)
	else:
		failed += 1
		print("FAIL %s  %s" % [name, detail])

func _run() -> void:
	await _run_all_tests()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	_finished = true
	quit(0 if failed == 0 else 1)

func _steps(n: int) -> void:
	for i in n:
		await physics_frame

func _run_all_tests() -> void:
	# 起真实 observer（island 模式默认）
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null:
		_check("observer_loads", false, "场景不可加载")
		return
	_inst = ps.instantiate()
	root.add_child(_inst)
	await _steps(20)
	var sim = _inst.island_sim
	_check("observer_island_boots", sim != null)

	# 推进若干 tick 产生决策留痕/记忆/关系数据
	for i in 40:
		sim.step()
	var actor_id := "npc_weila"
	var a: Dictionary = sim.actors[actor_id]

	# —— 1. 无副作用：build 前后关键状态 hash 一致（强制项 §59）——
	var before := _state_hash(sim, actor_id)
	var brain: Dictionary = NpcBrainViewModel.build(sim, actor_id)
	var after := _state_hash(sim, actor_id)
	_check("build_zero_mutation", before == after,
		"before=%s after=%s" % [before.substr(0, 48), after.substr(0, 48)])
	_check("brain_not_empty", not brain.is_empty() and str(brain.get("display_name", "")) == "薇拉")

	# —— 2. needs 映射 + energy→fatigue 反转 ——
	var rows: Array = brain["needs"]["rows"]
	var by_key := {}
	for row in rows:
		by_key[str(row["key"])] = row
	_check("needs_four_rows", rows.size() == 4)
	var energy_val: int = int(a["needs"].get("energy", 1000))
	_check("needs_fatigue_inversion", int(by_key["fatigue"]["value"]) == 1000 - energy_val,
		"fatigue=%d energy=%d" % [int(by_key["fatigue"]["value"]), energy_val])
	_check("needs_fatigue_marked_derived", str(by_key["fatigue"]["provenance"]) == "derived")
	_check("needs_hunger_objective", str(by_key["hunger"]["provenance"]) == "objective")
	_check("needs_sorted_by_urgency", float(rows[0]["frac"]) >= float(rows[rows.size() - 1]["frac"]))

	# —— 3. 关系 / ToM 分离 ——
	var rel_rows: Array = brain["relationships"]["rows"]
	_check("relationship_rows_present", not rel_rows.is_empty())
	var r0: Dictionary = rel_rows[0]
	_check("relationship_has_real_dims", r0.has("benevolence") and r0.has("reliability") \
		and r0.has("obligation") and r0.has("fear") and r0.has("trust"))
	var expected_b: int = sim.relationships.get_dim(actor_id, str(r0["other_id"]), "benevolence")
	_check("relationship_dims_from_store", int(r0["benevolence"]) == expected_b)
	_check("tom_separate_from_relationship", r0.has("tom") and str(r0["provenance"]) == "objective")

	# —— 4. 动态 has_item 谓词（测试注入证据后可枚举）——
	var tom: TheoryOfMind = a["tom"]
	tom.add_evidence("npc_kadga", TheoryOfMind.possession_predicate("shells"), 1.0, 0.5, 900, 905)
	tom.add_evidence("npc_kadga", TheoryOfMind.possession_predicate("shells"), 1.0, 0.4, 901, 906)
	var brain2: Dictionary = NpcBrainViewModel.build(sim, actor_id)
	var found_holder := false
	var holder_row := {}
	for subject in brain2["mind"]["tom_subjects"]:
		if str(subject["other_id"]) != "npc_kadga":
			continue
		for row in subject["rows"]:
			if str(row["predicate"]) == "has_item:shells":
				found_holder = true
				holder_row = row
	_check("dynamic_has_item_predicate_enumerated", found_holder)
	if found_holder:
		_check("holder_label_readable", str(holder_row["label"]) == "持有 shells")
		_check("holder_confidence_present", float(holder_row["confidence"]) > 0.0)
		_check("holder_evidence_tick_present", int(holder_row["last_evidence_tick"]) >= 905)
		_check("holder_row_subjective", str(holder_row["provenance"]) == "subjective")
	# 再验无副作用（第二次 build 前重取 hash——上一步测试自身注入过证据）
	var before_second := _state_hash(sim, actor_id)
	var _brain2b: Dictionary = NpcBrainViewModel.build(sim, actor_id)
	_check("build_zero_mutation_second", _state_hash(sim, actor_id) == before_second)

	# —— 5. 记忆推导 ——
	var mems: Array = a.get("memories", [])
	if not mems.is_empty():
		var mrows: Array = brain2["memories"]["rows"]
		_check("memory_rows_present", not mrows.is_empty())
		var last_real: Dictionary = mems[mems.size() - 1]
		_check("memory_day_derived_from_tick", int(mrows[0]["day"]) == int(last_real.get("tick", 0)) / 24 + 1,
			"day=%d tick=%d" % [int(mrows[0]["day"]), int(last_real.get("tick", 0))])
		_check("memory_importance_derived", absf(float(mrows[0]["derived_importance"]) -
			absf(float(last_real.get("appraisal_goal_congruence", 0.0)))) < 0.0001)
	else:
		_check("memory_rows_fail_soft", (brain2["memories"]["rows"] as Array).is_empty())

	# —— 6. 承诺过滤（测试注入一条承诺记录）——
	sim.obligations.append({
		"commitment_id": "c_test", "debtor_id": actor_id, "creditor_id": "npc_kadga",
		"object_id": "shell", "quantity": 2, "status": "ACTIVE", "due_tick": 420,
		"source_request_id": "req_test"})
	var brain3: Dictionary = NpcBrainViewModel.build(sim, actor_id)
	var found_commitment := false
	for c in brain3["social"]["commitments"]:
		if str(c["commitment_id"]) == "c_test":
			found_commitment = true
			_check("commitment_direction_debtor", str(c["direction"]) == "我欠")
			_check("commitment_fields", str(c["object"]) == "shell" and int(c["quantity"]) == 2)
	_check("commitment_filtered_by_actor", found_commitment)
	sim.obligations.erase(sim.obligations[sim.obligations.size() - 1])

	# —— 7. why（fail-closed：整体 derived；决策理由优先；无“升高”措辞）——
	var why: Dictionary = brain3["why"]
	_check("why_overall_derived", str(why.get("provenance", "")) == "derived")
	_check("why_not_empty", not (why.get("nodes", []) as Array).is_empty())
	var why_all_sourced := true
	for node in why.get("nodes", []):
		if not (node.has("provenance") and node.has("source_kind") and node.has("source_ref")):
			why_all_sourced = false
	for link in why.get("links", []):
		if not (link.has("provenance") and link.has("source_kind") and str(link.get("source_ref", "")) != ""):
			why_all_sourced = false
	_check("why_nodes_and_links_sourced", why_all_sourced)
	_check("why_no_fake_rising_word", not JSON.stringify(why).contains("升高"))
	var live_reason: String = str((a.get("last_decision_trace", {}) as Dictionary).get("reason", ""))
	if live_reason != "":
		_check("why_uses_trace_reason", str((why.get("decision_reason", {}) as Dictionary).get("text", "")) == live_reason)
	else:
		_check("why_reason_absent_when_trace_lacks_it", (why.get("decision_reason", {}) as Dictionary).is_empty())

	# —— 8. 缺失可选字段 fail-soft（清空 trace 的 actor）——
	var saved_trace: Dictionary = a.get("last_decision_trace", {}).duplicate(true)
	a["last_decision_trace"] = {}
	var brain4: Dictionary = NpcBrainViewModel.build(sim, actor_id)
	_check("no_trace_fail_soft", (brain4["decision"]["candidates"] as Array).is_empty() \
		and str(brain4["decision"]["chosen"]) == "")
	_check("no_trace_still_builds", not brain4.is_empty() and not (brain4["plan"]["nodes"] as Array).is_empty())
	a["last_decision_trace"] = saved_trace

	# —— 9. 真实 trace 候选（若 sim 已产生决策）——
	var brain5: Dictionary = NpcBrainViewModel.build(sim, actor_id)
	var live_trace: Dictionary = a.get("last_decision_trace", {})
	if live_trace.has("top_candidates") and not (live_trace["top_candidates"] as Dictionary).is_empty():
		var live_candidates: Array = brain5["decision"]["candidates"]
		_check("live_candidates_rendered", not live_candidates.is_empty())
		var any_chosen := false
		for c in live_candidates:
			if bool(c.get("chosen", false)):
				any_chosen = true
		_check("live_candidates_chosen_marked", any_chosen)
	else:
		_check("live_candidates_gap_when_empty", true) # 空留痕 → 空候选为合法

	# —— 9b. runtime schema 0.3（真实 observer runtime + preview 一致）——
	var main_src := FileAccess.get_file_as_string("res://scenes/observer/observer_main.gd")
	_check("runtime_schema_03",
		main_src.contains('"view_schema_version": "0.3"') and not main_src.contains('"view_schema_version": "0.2"'))
	var pv_script: GDScript = load("res://scenes/ui/ui_preview.gd")
	_check("preview_schema_03", str(pv_script.fixture_model()["view_schema_version"]) == "0.3")

	# —— 9c. LIVE plan / info goal：公开 accessor（FakeSim shim 受控验证）——
	var fs := FakeSim.new()
	fs.plan_run = {"run_id": "npc_weila#1", "actor_id": "npc_weila", "plan_id": "plan_2",
		"root_goal": "SHELTER", "plan_snapshot": {},
		"steps": [{"step_id": "s1"}, {"step_id": "s2"}, {"step_id": "s3"}],
		"current_step_id": "s2", "state": "ACTIVE", "started_tick": 10,
		"last_progress_tick": 12, "reason_code": ""}
	fs.info_goal = {"query_kind": "HOLDER", "state": "ACTIVE", "item_id": "wood",
		"information_goal_id": "g1", "parent_run_id": "npc_weila#1", "blocker_step_id": "s2"}
	var fb := NpcBrainViewModel.build(fs, "npc_weila")
	var lr: Dictionary = fb["plan"]["live_run"]
	_check("live_plan_uses_public_agency_plan_run",
		str(lr.get("run_id", "")) == "npc_weila#1" and str(lr.get("current_step_id", "")) == "s2"
		and str(lr.get("state", "")) == "ACTIVE")
	var srows: Array = lr.get("steps", [])
	_check("live_plan_steps_current_and_unknown",
		srows.size() == 3 and bool(srows[1].get("is_current", false))
		and str(srows[0].get("status", "")) == "UNKNOWN" and str(srows[2].get("status", "")) == "UNKNOWN")
	var node_kinds: Array = []
	for n in fb["plan"]["nodes"]:
		node_kinds.append(str(n["kind"]))
	_check("live_plan_nodes_present", node_kinds.has("RUN") and node_kinds.count("STEP") == 3)
	# live 信息目标：真实字段 state（无 status 字段也必须读出 ACTIVE）
	var subgoal := {}
	for n in fb["plan"]["nodes"]:
		if str(n["kind"]) == "SUBGOAL":
			subgoal = n
	_check("live_information_goal_uses_public_accessor",
		not subgoal.is_empty() and str(subgoal.get("source_kind", "")) == "LIVE_ACCESSOR"
		and str(subgoal.get("status", "")) == "ACTIVE" and str(subgoal.get("label", "")).contains("HOLDER"))
	_check("holder_goal_state_reads_state_not_status",
		not fs.info_goal.has("status") and str(subgoal.get("value", "")) == "状态 ACTIVE")
	_check("why_live_info_goal_state", str((fb["why"]["nodes"] as Array).filter(func(n): return str(n.get("label", "")).contains("信息目标"))[0].get("label", "")).contains("ACTIVE"))

	# —— 9d. fixture 兼容回退：goal 只有 status（旧 mock）时仍可读 ——
	var fs2 := FakeSim.new()
	fs2.actors["npc_weila"]["last_decision_trace"] = {"goal_desc": "守夜", "reason": "营地需要警戒",
		"tick": 40, "agency_information": {"goal": {"kind": "SOURCE", "status": "ACTIVE"}}}
	var fb2 := NpcBrainViewModel.build(fs2, "npc_weila")
	var sub2 := {}
	for n in fb2["plan"]["nodes"]:
		if str(n["kind"]) == "SUBGOAL":
			sub2 = n
	_check("fixture_goal_status_fallback", not sub2.is_empty() and str(sub2.get("status", "")) == "ACTIVE")

	# —— 9e. why fail-closed（FakeSim：hunger=900 但 trace 不涉及 hunger）——
	var fs3 := FakeSim.new()
	fs3.actors["npc_weila"]["needs"] = {"hunger": 900, "thirst": 100, "energy": 950, "social": 50}
	fs3.actors["npc_weila"]["last_decision_trace"] = {"goal_desc": "守夜", "reason": "营地需要警戒",
		"tick": 40, "agency_execution": {"step_id": "s9", "blocker_reason": "", "decision_tick": 40}}
	var fb3 := NpcBrainViewModel.build(fs3, "npc_weila")
	var need_in_chain := false
	for n in fb3["why"]["nodes"]:
		if str(n.get("source_ref", "")).begins_with("needs."):
			need_in_chain = true
	for l in fb3["why"]["links"]:
		if str(l.get("source_ref", "")).begins_with("needs."):
			need_in_chain = true
	_check("why_no_fake_need_causality", not need_in_chain)
	var ctx_has_need := false
	for row in fb3["why"]["context"]:
		if str(row.get("label", "")).contains("饥饿 900"):
			ctx_has_need = true
	_check("why_need_lives_in_context_only", ctx_has_need)
	_check("why_fake_sim_reason_used",
		str((fb3["why"]["decision_reason"] as Dictionary).get("text", "")) == "营地需要警戒")

	# —— 9c2. R1.1：Plan LIVE/snapshot 真分区 + 信息目标身份校验 ——
	# A：trace root=HUNGER、live run root=SHELTER → LIVE 区只显示 SHELTER；HUNGER 只在快照区
	var fsp := FakeSim.new()
	fsp.actors["npc_weila"]["last_decision_trace"] = {"goal_desc": "觅食", "active_goal": "HUNGER",
		"goal_priority": 0.5, "tick": 30}
	fsp.plan_run = {"run_id": "run#9", "plan_id": "plan_7", "root_goal": "SHELTER",
		"steps": [{"step_id": "s1"}], "current_step_id": "s1", "state": "ACTIVE"}
	var fbp := NpcBrainViewModel.build(fsp, "npc_weila")
	var live_labels: Array = []
	var snapshot_labels: Array = []
	for n in fbp["plan"]["nodes"]:
		if str(n.get("section", "")) == "live":
			live_labels.append(str(n.get("label", "")))
		elif str(n.get("section", "")) == "snapshot":
			snapshot_labels.append(str(n.get("label", "")))
	var live_has_shelter := false
	var live_has_hunger := false
	for l in live_labels:
		if l.contains("SHELTER"):
			live_has_shelter = true
		if l.contains("觅食") or l.contains("HUNGER"):
			live_has_hunger = true
	var snapshot_has_hunger := false
	for l in snapshot_labels:
		if l.contains("觅食") or l.contains("HUNGER"):
			snapshot_has_hunger = true
	_check("plan_live_snapshot_separated",
		live_has_shelter and not live_has_hunger and snapshot_has_hunger)
	# B：parent_run_id 不匹配 → 不附着（独立显示，无箭头接入）
	var fsm := FakeSim.new()
	fsm.plan_run = {"run_id": "run#9", "plan_id": "plan_7", "root_goal": "SHELTER",
		"steps": [{"step_id": "s1"}], "current_step_id": "s1", "state": "ACTIVE"}
	fsm.info_goal = {"query_kind": "HOLDER", "state": "ACTIVE", "parent_run_id": "run#OTHER"}
	var fbm := NpcBrainViewModel.build(fsm, "npc_weila")
	var independent_goal := {}
	for n in fbm["plan"]["nodes"]:
		if str(n["kind"]) == "SUBGOAL":
			independent_goal = n
	_check("plan_goal_attach_identity_mismatch",
		(fbm["plan"]["live"]["attached_information_goal"] as Dictionary).is_empty()
		and not independent_goal.is_empty() and bool(independent_goal.get("no_arrow_in", false))
		and str(independent_goal.get("label", "")).contains("当前信息目标"))
	# C：parent_run_id 匹配（+blocker_step_id 匹配 current）→ 附着在 run 流内
	var fsa := FakeSim.new()
	fsa.plan_run = {"run_id": "run#9", "plan_id": "plan_7", "root_goal": "SHELTER",
		"steps": [{"step_id": "s1"}, {"step_id": "s2"}], "current_step_id": "s2", "state": "ACTIVE"}
	fsa.info_goal = {"query_kind": "HOLDER", "state": "ACTIVE",
		"parent_run_id": "run#9", "blocker_step_id": "s2"}
	var fba := NpcBrainViewModel.build(fsa, "npc_weila")
	var attached_goal := {}
	for n in fba["plan"]["nodes"]:
		if str(n["kind"]) == "SUBGOAL" and str(n.get("section", "")) == "live":
			attached_goal = n
	_check("plan_goal_attach_identity_match",
		not (fba["plan"]["live"]["attached_information_goal"] as Dictionary).is_empty()
		and not attached_goal.is_empty() and not bool(attached_goal.get("no_arrow_in", true))
		and str(attached_goal.get("label", "")).contains("信息目标"))
	# D：无 live run → 决策快照作为主计划（snapshot section 正常）
	var fsd := FakeSim.new()
	fsd.actors["npc_weila"]["last_decision_trace"] = {"goal_desc": "觅食", "active_goal": "HUNGER",
		"goal_priority": 0.5, "tick": 30}
	var fbd := NpcBrainViewModel.build(fsd, "npc_weila")
	var snapshot_nodes := 0
	for n in fbd["plan"]["nodes"]:
		if str(n.get("section", "")) == "snapshot":
			snapshot_nodes += 1
	_check("plan_snapshot_fallback_without_live_run", snapshot_nodes > 0 and (fbd["plan"]["live"] as Dictionary).is_empty())

	# —— 9c3. R1.2：无 live run 但有当前 live 信息目标——绝不落入 snapshot 区 ——
	var fsn := FakeSim.new()
	fsn.actors["npc_weila"]["last_decision_trace"] = {"goal_desc": "旧的觅食目标", "active_goal": "HUNGER",
		"goal_priority": 0.5, "tick": 30,
		"agency_execution": {"plan_id": "plan_old", "step_id": "step_old",
			"blocker_reason": "", "selected": false, "decision_tick": 30}}
	fsn.info_goal = {"query_kind": "HOLDER", "state": "ACTIVE",
		"information_goal_id": "INFO:npc_weila:3", "parent_run_id": "", "item_id": "shell"}
	var fbn := NpcBrainViewModel.build(fsn, "npc_weila")
	var live_info_node := {}
	var snapshot_kinds: Array = []
	for n in fbn["plan"]["nodes"]:
		if str(n.get("section", "")) == "snapshot":
			snapshot_kinds.append(str(n.get("kind", "")))
		if str(n["kind"]) == "SUBGOAL" and str(n.get("source_kind", "")) == "LIVE_ACCESSOR":
			live_info_node = n
	_check("live_goal_without_live_run_is_not_snapshot",
		not live_info_node.is_empty() and str(live_info_node.get("section", "")) != "snapshot")
	_check("live_goal_without_live_run_is_live_info",
		not live_info_node.is_empty() and str(live_info_node.get("section", "")) == "live_info")
	_check("live_goal_without_live_run_has_no_arrow_in",
		not live_info_node.is_empty() and bool(live_info_node.get("no_arrow_in", false)))
	# 有 live run 但身份不匹配 → 也必须是 live_info 独立区
	var live_goal_sections: Array = []
	for n in fbm["plan"]["nodes"]:
		if str(n["kind"]) == "SUBGOAL" and str(n.get("source_kind", "")) == "LIVE_ACCESSOR":
			live_goal_sections.append(str(n.get("section", "")))
	_check("live_goal_mismatched_run_uses_live_info_section",
		not live_goal_sections.is_empty() and live_goal_sections.has("live_info")
		and not live_goal_sections.has("snapshot"))
	# 匹配时仍附着 live run（现有 C 例复核 + section==live）
	var attach_sections: Array = []
	for n in fba["plan"]["nodes"]:
		if str(n["kind"]) == "SUBGOAL" and str(n.get("section", "")) == "live":
			attach_sections.append(str(n.get("source_kind", "")))
	_check("matched_live_goal_stays_attached_to_live_run", attach_sections.has("LIVE_ACCESSOR"))
	# 决策快照内的旧信息目标仍留在 snapshot 区
	var fss := FakeSim.new()
	fss.actors["npc_weila"]["last_decision_trace"] = {"goal_desc": "旧的觅食目标",
		"agency_information": {"goal": {"kind": "SOURCE", "status": "ACTIVE"}}}
	var fbs := NpcBrainViewModel.build(fss, "npc_weila")
	var snap_sub := {}
	for n in fbs["plan"]["nodes"]:
		if str(n["kind"]) == "SUBGOAL" and str(n.get("source_kind", "")) == "DECISION_TRACE":
			snap_sub = n
	_check("snapshot_information_goal_stays_snapshot",
		not snap_sub.is_empty() and str(snap_sub.get("section", "")) == "snapshot")
	# 不变量：LIVE_ACCESSOR 节点绝不允许出现在 snapshot 区（扫全部已构建案例）
	var live_in_snapshot := 0
	for built_model in [fbn, fbm, fba, fbs, fbd, fbp]:
		for n in built_model["plan"]["nodes"]:
			if str(n.get("source_kind", "")) == "LIVE_ACCESSOR" and str(n.get("section", "")) == "snapshot":
				live_in_snapshot += 1
	_check("no_live_accessor_node_in_snapshot", live_in_snapshot == 0,
		"violations=%d" % live_in_snapshot)

	# —— 9e2. R1.1：Why 边全部为 presentation 自建 [推导] ——
	var all_links_derived := true
	for l in fb3["why"]["links"]:
		if str(l.get("provenance", "")) != "derived" or str(l.get("source_kind", "")) != "PRESENTATION_LINK" \
				or str(l.get("source_ref", "")) == "":
			all_links_derived = false
	_check("why_all_links_derived", all_links_derived)
	if not (fb3["why"]["decision_reason"] as Dictionary).is_empty():
		_check("why_decision_reason_stays_subjective",
			str(fb3["why"]["decision_reason"].get("provenance", "")) == "subjective")

	# —— 9f. primary question / dominant emotion ——
	var fs4 := FakeSim.new()
	fs4.actors["npc_weila"]["open_questions"] = [
		{"about": "npc_kadga", "kind": "why_refused", "entropy": 0.8, "stakes": 0.3,
			"tick": 260, "source_event_ids": [38]},
		{"about": "wood", "kind": "where_to_find", "entropy": 0.5, "stakes": 0.9,
			"tick": 240, "source_event_ids": [22]}]
	var fb4 := NpcBrainViewModel.build(fs4, "npc_weila")
	var pq: Dictionary = fb4["mind"]["primary_question"]
	_check("primary_question_semantics",
		str(pq.get("about", "")) == "wood" and str(pq.get("provenance", "")) == "derived")
	_check("dominant_emotion_derived",
		str(brain3["emotions"]["dominant"]["provenance"]) == "derived")

	# —— 9g. 社会页事件过滤（真实 sim 注入事件后 build）——
	var ev_base: int = sim.events.size()
	sim.events.append({"seq": 900001, "tick": sim.tick, "day": 2, "type": "MATERIAL_REQUEST_CREATED",
		"actor_id": "npc_oun", "requester_id": "npc_oun", "target_id": "npc_kadga",
		"text": "欧恩 向 卡德加 请求（与薇拉无关）", "request_id": "rA"})
	sim.events.append({"seq": 900002, "tick": sim.tick, "day": 2, "type": "holder_information_shared",
		"actor_id": "npc_kadga", "to_id": "npc_weila", "target_id": "npc_weila", "reporter_id": "npc_kadga",
		"reported_holder_id": "npc_oun", "text": "卡德加 回答 薇拉 的持有询问"})
	sim.events.append({"seq": 900003, "tick": sim.tick, "day": 2, "type": "holder_information_shared",
		"actor_id": "npc_kadga", "to_id": "npc_oun", "target_id": "npc_oun", "reporter_id": "npc_kadga",
		"reported_holder_id": "npc_weila", "text": "卡德加 回答 欧恩（谈论薇拉，她未参与）"})
	sim.events.append({"seq": 900004, "tick": sim.tick, "day": 2, "type": "MATERIAL_REQUEST_CREATED",
		"actor_id": "npc_weila", "requester_id": "npc_weila", "target_id": "npc_kadga",
		"text": "薇拉 向 卡德加 请求", "request_id": "rD1"})
	sim.events.append({"seq": 900005, "tick": sim.tick, "day": 2, "type": "COMMITMENT_CREATED",
		"actor_id": "npc_oun", "debtor_id": "npc_weila", "to_id": "npc_kadga",
		"text": "薇拉 的承诺事件", "commitment_id": "cD2"})
	sim.events.append({"seq": 900006, "tick": sim.tick, "day": 2, "type": "source_information_shared",
		"actor_id": "npc_oun", "to_id": "npc_weila", "target_id": "npc_weila",
		"text": "欧恩 告诉 薇拉：北滩有浮木来源"})
	sim.events.append({"seq": 900007, "tick": sim.tick, "day": 2, "type": "source_information_shared",
		"actor_id": "npc_oun", "to_id": "npc_kadga", "target_id": "npc_kadga",
		"text": "欧恩 告诉 卡德加（与薇拉无关）"})
	var fsocial := NpcBrainViewModel.build(sim, actor_id)
	var req_seqs: Array = []
	var holder_seqs: Array = []
	var source_seqs: Array = []
	var all_seqs: Array = []
	for row in fsocial["social"]["recent_requests"]:
		req_seqs.append(int(row["seq"]))
	for row in fsocial["social"]["holder_events"]:
		holder_seqs.append(int(row["seq"]))
	for row in fsocial["social"]["source_information_events"]:
		source_seqs.append(int(row["seq"]))
	for bucket in ["recent_requests", "holder_events", "source_information_events", "recent_social_events"]:
		for row in fsocial["social"][bucket]:
			all_seqs.append(int(row["seq"]))
	_check("unrelated_social_event_filtered", not all_seqs.has(900001))
	_check("selected_target_social_event_included", holder_seqs.has(900002))
	_check("lowercase_holder_information_recognized", holder_seqs.has(900002))
	_check("reported_holder_alone_not_direct_participant", not all_seqs.has(900003))
	_check("social_relevance_fields_recognized",
		req_seqs.has(900004) and all_seqs.has(900005))
	# R1.1：holder（谁持有）与 source（哪里有）分桶，互不混入；无关 source 事件被过滤
	_check("social_holder_source_separated",
		holder_seqs.has(900002) and not holder_seqs.has(900006)
		and source_seqs.has(900006) and not source_seqs.has(900002))
	_check("social_unrelated_source_filtered", not all_seqs.has(900007))
	sim.events.resize(ev_base)

	# —— 10. 守卫扫描：私有 tracker 访问（§57）——
	var guard_dirs := ["res://src/presentation/", "res://scenes/ui/", "res://scenes/observer/observer_hud.gd"]
	var private_tokens := ["._plan_tracker", "._material_request_runtime",
		"._information_tracker_state", "._commitment_runtime"]
	var private_hits: Array = []
	for target in guard_dirs:
		var files: Array = []
		if target.ends_with(".gd"):
			files = [target]
		else:
			files = _list_gd_recursive(target)
		for f in files:
			var text := FileAccess.get_file_as_string(f)
			for token in private_tokens:
				if text.contains(token):
					private_hits.append("%s 含 %s" % [f, token])
	_check("no_private_tracker_access", private_hits.is_empty(), "; ".join(private_hits))

	# —— 11. 守卫扫描：UI 侧 mutation 调用（§56，启发式非完备）——
	var mutation_tokens := [".adjust(", ".add_evidence(", ".add_reported_evidence(", ".weaken(",
		".open_request(", ".respond(", ".transfer(", ".fulfill(", ".cancel_holder(",
		".set_intention(", ".decay("]
	var mutation_hits: Array = []
	for target in guard_dirs:
		var files2: Array = []
		if target.ends_with(".gd"):
			files2 = [target]
		else:
			files2 = _list_gd_recursive(target)
		for f in files2:
			var text2 := FileAccess.get_file_as_string(f)
			for token in mutation_tokens:
				if text2.contains(token):
					mutation_hits.append("%s 含 %s" % [f, token])
	_check("no_ui_mutation_calls", mutation_hits.is_empty(), "; ".join(mutation_hits))

	root.remove_child(_inst)
	_inst.free()

func _state_hash(sim, actor_id: String) -> String:
	var a: Dictionary = sim.actors[actor_id]
	var tom: TheoryOfMind = a["tom"]
	return "|".join([
		JSON.stringify(a["inventory"]),
		JSON.stringify(a["needs"]),
		JSON.stringify(a.get("memories", [])),
		JSON.stringify(tom.snapshot()),
		JSON.stringify(tom.last_seen_of("npc_kadga")),
		JSON.stringify(a.get("open_questions", [])),
		str(sim.relationships.get_trust(actor_id, "npc_kadga")),
		str(sim.relationships.get_dim(actor_id, "npc_kadga", "benevolence")),
		JSON.stringify(sim.obligations),
		JSON.stringify(a.get("last_decision_trace", {})),
	])

func _list_gd_recursive(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path + name
		if dir.current_is_dir() and not name.begins_with("."):
			out.append_array(_list_gd_recursive(full + "/"))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out

## FakeSim：受控 shim——只暴露 NpcBrainViewModel.build 需要的公开面（含 live accessors）。
## 测试通过直接改 actors["npc_weila"] / plan_run / info_goal 控制场景。
class FakeSim:
	extends RefCounted
	var actors := {}
	var events: Array = []
	var obligations: Array = []
	var relationships: FakeRels = null
	var plan_run := {}
	var info_goal := {}

	func _init() -> void:
		relationships = FakeRels.new()
		actors = {"npc_weila": {
			"display_name": "薇拉", "tile": Vector2i(7, 37), "activity": "砍伐树木",
			"inventory": {"wood": 2},
			"needs": {"hunger": 200, "thirst": 150, "energy": 800, "social": 50},
			"memories": [], "open_questions": [],
			"personality": null, "intentions": null, "tom": null,
			"last_decision_trace": {}}}

	func agency_plan_run(_actor_id: String) -> Dictionary:
		return plan_run.duplicate(true)

	func agency_information_goal(_actor_id: String) -> Dictionary:
		return info_goal.duplicate(true)

class FakeRels:
	extends RefCounted
	func get_trust(_a: String, _b: String) -> int:
		return 0

	func get_dim(_a: String, _b: String, _dim: String) -> int:
		return 0
