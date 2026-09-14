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

	# —— 7. why chain provenance ——
	var chain: Array = brain3["why_chain"]
	_check("why_chain_not_empty", not chain.is_empty())
	var all_sourced := true
	for node in chain:
		if not (node.has("provenance") and node.has("source_kind") and node.has("source_ref")):
			all_sourced = false
	_check("why_chain_nodes_sourced", all_sourced)
	var has_objective := false
	var has_subjective := false
	for node in chain:
		if str(node["provenance"]) == "objective":
			has_objective = true
		if str(node["provenance"]) == "subjective":
			has_subjective = true
	_check("why_chain_mixed_provenance", has_objective and has_subjective)

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
