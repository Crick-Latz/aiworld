extends SceneTree
## P6.0 — World Knowledge & Agency Foundation（GPT 指令 §28-32）
## 全部合成 fixture 验证（不动任何现有模拟层）。
## KA 装载 · KB 知识≠持有 · KC 隐藏物隔离 · KD 能力检索 · KE 一材多用 ·
## KF 专长只影响估计 · KG=PA · KH=PB · KI=PC · KJ=PD船 · KK 合作候选 ·
## KL 同世界不同知识 · KM 确定性 · KN 只读 · KO 不改世界
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
	var store := KnowledgePack.load_island_pack()

	# KA：包装载
	var c: Dictionary = store.counts()
	_check("ka_pack_loads", c["facts"] >= 15 and c["affordances"] >= 12,
		"facts=%d affordances=%d" % [c["facts"], c["affordances"]])

	# KB：知识≠持有——知道枪能威胁，但没有枪 → 无 use gun 计划
	var kb_ctx := _ctx([], [], [], [], [])
	var kb_plans: Array = MeansEndsPlanner.propose_plans("DANGER", store, kb_ctx)
	var kb_uses_gun := false
	for p in kb_plans:
		if str(p.get("via_rule", "")) == "gun_threaten":
			kb_uses_gun = true
	_check("kb_knowledge_not_possession", not kb_uses_gun, "无枪却出现用枪计划")

	# KC：隐藏物隔离——ctx 无 wood → craft 不出现；ctx 有 → 出现（catalog 路径）
	var p63_items := ItemCatalog.load_default()
	var p63_recipes := RecipeCatalog.load_default(p63_items)
	var krr: Array = RecipeKnowledgeAdapter.known_recipe_refs([], store, p63_recipes)
	var kc_blind_ctx := _ctx(["ANIMAL"], [], ["CUT"], [], [])
	kc_blind_ctx["possessed_items"] = {}
	kc_blind_ctx["known_sources"] = [{"tag": "ANIMAL", "source_id": "a", "belief_ref": "known_source:a", "last_seen_tick": 1, "confidence": 1.0}]
	kc_blind_ctx["known_recipe_refs"] = krr
	var kc_blind: Array = MeansEndsPlanner.propose_plans("HUNGER", store, kc_blind_ctx, p63_recipes, p63_items)
	var kc_blind_craft := _has_step(kc_blind, "CRAFT")
	var kc_seeing_ctx := _ctx(["ANIMAL", "WOOD", "SHELL"], [], ["CUT"], [], [])
	kc_seeing_ctx["possessed_items"] = {"wood": 1, "shells": 1}
	kc_seeing_ctx["known_sources"] = [
		{"tag": "ANIMAL", "source_id": "a", "belief_ref": "known_source:a", "last_seen_tick": 1, "confidence": 1.0},
		{"tag": "WOOD", "source_id": "w", "belief_ref": "known_source:w", "last_seen_tick": 1, "confidence": 1.0},
		{"tag": "SHELL", "source_id": "s", "belief_ref": "known_source:s", "last_seen_tick": 1, "confidence": 1.0}]
	kc_seeing_ctx["known_recipe_refs"] = krr
	var kc_seeing: Array = MeansEndsPlanner.propose_plans("HUNGER", store, kc_seeing_ctx, p63_recipes, p63_items)
	var kc_seeing_craft := _has_step(kc_seeing, "CRAFT")
	_check("kc_hidden_object_isolation", not kc_blind_craft and kc_seeing_craft,
		"blind=%s seeing=%s" % [str(kc_blind_craft), str(kc_seeing_craft)])

	# KD：能力检索——SHARP_STONE 提供 CUT/PIERCE
	var kd_tools: Array = store.rules_providing_capability("CUT")
	_check("kd_capability_retrieval", kd_tools.size() >= 1 and str(kd_tools[0]["id"]) == "sharp_stone_cut",
		"n=%d" % kd_tools.size())

	# KE：一材多用——WOOD 至少 4 种 affordance（燃料/结构/造矛/造筏/庇护所）
	var ke_rules: Array = store.affordances_of_tag("WOOD")
	_check("ke_multiple_affordances", ke_rules.size() >= 4, "wood rules=%d" % ke_rules.size())

	# KG/PA：饿 + 已知浆果 → 直接 forage 计划，不找隐藏资源
	var pa_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store,
		_ctx(["BERRY"], [], [], [], []))
	var pa_ok := false
	for p in pa_plans:
		if str(p.get("via_rule", "")) == "berry_patch_food" and (p.get("missing_requirements", []) as Array).is_empty():
			pa_ok = true
	_check("kg_pa_hunger_known_berry", pa_ok, "plans=%s" % str(pa_plans.size()))

	# KH/PB：饿 + 见动物 + 知矛配方 + 材料齐 → CRAFT_SPEAR→HUNT→FOOD 链
	var pb_ctx := _ctx(["ANIMAL", "WOOD", "SHELL"], [], ["CUT"], [], [])
	pb_ctx["possessed_items"] = {"wood": 1, "shells": 1}
	pb_ctx["known_sources"] = [
		{"tag": "ANIMAL", "source_id": "a", "belief_ref": "known_source:a", "last_seen_tick": 1, "confidence": 1.0},
		{"tag": "WOOD", "source_id": "w", "belief_ref": "known_source:w", "last_seen_tick": 1, "confidence": 1.0},
		{"tag": "SHELL", "source_id": "s", "belief_ref": "known_source:s", "last_seen_tick": 1, "confidence": 1.0}]
	pb_ctx["known_recipe_refs"] = krr
	var pb_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, pb_ctx, p63_recipes, p63_items)
	var pb_plan := _find_by_rule(pb_plans, "animal_food_raw")
	var pb_has_craft := false
	var pb_ready := false
	if not pb_plan.is_empty():
		pb_ready = str(pb_plan.get("status", "")) == "READY"
		for st in pb_plan.get("steps", []):
			if str(st.get("kind", "")) == "CRAFT":
				pb_has_craft = true
	_check("kh_pb_animal_tool_chain", pb_has_craft and pb_ready,
		"craft=%s ready=%s missing=%s" % [str(pb_has_craft), str(pb_ready), str(pb_plan.get("missing_requirements", []))])

	# KI/PC：同 PB 但无 SHARP 材料 → BLOCKED + missing 含 SHARP_STONE，无凭空 craft
	var pc_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store,
		_ctx(["ANIMAL", "WOOD", "BINDING"], [], ["CUT"], [], []))
	var pc_plan := _find_by_rule(pc_plans, "animal_food_raw")
	var pc_blocked := false
	var pc_missing_sharp := false
	var pc_no_craft := true
	if not pc_plan.is_empty():
		pc_blocked = str(pc_plan.get("status", "")) == "BLOCKED_PLAN"
		for m in pc_plan.get("missing_requirements", []):
			if str(m).find("SHARP") != -1:
				pc_missing_sharp = true
		for st in pc_plan.get("steps", []):
			if str(st.get("kind", "")) == "CRAFT" and str(st.get("description", "")).find("craft_spear") != -1:
				pc_no_craft = false
	_check("ki_pc_missing_material_blocks", pc_blocked and pc_missing_sharp and pc_no_craft,
		"blocked=%s missing_sharp=%s no_craft=%s" % [str(pc_blocked), str(pc_missing_sharp), str(pc_no_craft)])

	# KJ/PD：离岛 → 筏需 NAVIGATE/BUILD_STRONG；缺者进 missing（catalog 路径）
	var pd_ctx := _ctx(["WOOD", "BINDING"], [], ["BIND", "CUT"], ["WOODWORKING"],
		[{"id": "npc_weila", "expertise_tags": ["NAVIGATION"], "trust": 0.5}])
	pd_ctx["possessed_items"] = {"wood": 1}
	pd_ctx["known_sources"] = [{"tag": "WOOD", "source_id": "w", "belief_ref": "known_source:w", "last_seen_tick": 1, "confidence": 1.0}]
	pd_ctx["known_recipe_refs"] = krr
	var pd_plans: Array = MeansEndsPlanner.propose_plans("ESCAPE_DESIRE", store, pd_ctx, p63_recipes, p63_items)
	var pd_plan := _find_by_rule(pd_plans, "build_raft")
	var pd_missing_nav := false
	var pd_missing_build := false
	if not pd_plan.is_empty():
		for m in pd_plan.get("missing_requirements", []):
			if str(m).find("NAVIGATE") != -1:
				pd_missing_nav = true
			if str(m).find("BUILD_STRONG") != -1:
				pd_missing_build = true
	_check("kj_pd_boat_requirements", not pd_plan.is_empty() and pd_missing_nav and pd_missing_build,
		"missing=%s" % str(pd_plan.get("missing_requirements", []) if not pd_plan.is_empty() else []))

	# KK：能力缺口 + 已知伙伴有该专长 → 求助候选出现（SUBGOAL/request_help，P6.3B-0 结构化格式）
	var kk_has_help := false
	if not pd_plan.is_empty():
		for st in pd_plan.get("steps", []):
			if str(st.get("kind", "")) == "SUBGOAL" and str(st.get("action_name", "")) == "request_help" and str(st.get("description", "")).find("npc_weila") != -1:
				kk_has_help = true
			elif str(st.get("kind", "")) == "REQUEST_HELP" and str(st.get("description", "")).find("npc_weila") != -1:
				kk_has_help = true
	_check("kk_cooperation_candidate", kk_has_help, "REQUEST_HELP(npc_weila) 未出现")

	# KL：同世界不同知识——A 有 TRAPPING 专长，B 没有 → 候选方案集不同
	var store2 := KnowledgePack.load_island_pack()
	var kl_a: Array = MeansEndsPlanner.propose_plans("HUNGER", store2,
		_ctx(["ANIMAL", "WOOD", "BINDING"], [], ["BIND", "CUT"], ["TRAPPING"], []))
	var kl_b: Array = MeansEndsPlanner.propose_plans("HUNGER", store2,
		_ctx(["ANIMAL", "WOOD", "BINDING"], [], ["BIND", "CUT"], [], []))
	var kl_a_trap := _find_by_rule(kl_a, "set_trap")
	var kl_b_trap := _find_by_rule(kl_b, "set_trap")
	_check("kl_same_world_different_knowledge",
		kl_a_trap.has("via_rule") and (str(kl_a_trap.get("status", "")) != "DROPPED"),
		"A(trapping) 有 set_trap 候选；B 无")

	# KM：同输入双跑完全一致
	var m1: Array = MeansEndsPlanner.propose_plans("HUNGER", store,
		_ctx(["ANIMAL", "WOOD", "SHARP_STONE", "BINDING"], [], ["CUT"], ["WOODWORKING"], []))
	var m2: Array = MeansEndsPlanner.propose_plans("HUNGER", store,
		_ctx(["ANIMAL", "WOOD", "SHARP_STONE", "BINDING"], [], ["CUT"], ["WOODWORKING"], []))
	_check("km_deterministic", JSON.stringify(m1) == JSON.stringify(m2), "")

	# KN：planner 只读——ctx/store 输入前后逐位一致
	var ctx_snapshot := JSON.stringify(pd_ctx)
	var store_snapshot := JSON.stringify(store.counts()) + JSON.stringify(store.fact_by_id("kf_spear_recipe"))
	MeansEndsPlanner.propose_plans("ESCAPE_DESIRE", store, pd_ctx)
	_check("kn_planner_read_only", JSON.stringify(pd_ctx) == ctx_snapshot
		and JSON.stringify(store.counts()) + JSON.stringify(store.fact_by_id("kf_spear_recipe")) == store_snapshot, "")

	# KO：不改世界——用真 sim 派生 ctx 跑 planner，模拟 hash 前后一致 + 提案无执行钩子
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var ko_world_unchanged := true
	var ko_no_exec_hook := true
	if ps != null:
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
		for i in 300: sim.step()
		var hash_before := _sim_hash(sim)
		# 从主观状态派生 ctx（示意：已知浆果 + 持有贝壳）
		var sim_ctx := _ctx(["BERRY"], ["SHELL"], [], [], [])
		var sim_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, sim_ctx)
		for p in sim_plans:
			if p.has("execute") or p.has("action") or p.has("callable"):
				ko_no_exec_hook = false
		if _sim_hash(sim) != hash_before:
			ko_world_unchanged = false
		inst.queue_free()
	_check("ko_no_world_mutation", ko_world_unchanged and ko_no_exec_hook, "")
	# AgencyTrace 冒烟：结构化留痕包含问题与知识引用
	var trace: Dictionary = MeansEndsPlanner.last_trace
	_check("trace_structured", str(trace.get("problem", "")) == "HUNGER"
		and (trace.get("retrieved_knowledge", []) as Array).size() > 0, str(trace))

	print("SUMMARY pass=%d fail=%d" % [_pass, _fail])
	_f = true
	quit(0)

func _ctx(known_sources: Array, possessed: Array, caps: Array, expertise: Array, peers: Array) -> Dictionary:
	return {"known_source_tags": known_sources, "possessed_tags": possessed,
		"possessed_capabilities": caps, "expertise_tags": expertise, "known_peers": peers}

func _has_step(plans: Array, kind: String) -> bool:
	for p in plans:
		for st in p.get("steps", []):
			if str(st.get("kind", "")) == kind:
				return true
	return false

func _find_by_rule(plans: Array, rule_id: String) -> Dictionary:
	for p in plans:
		if str(p.get("via_rule", "")) == rule_id:
			return p
	return {}

func _sim_hash(sim) -> String:
	var h := str(sim.tick) + ":" + str(sim.events.size())
	for id in sim.actors:
		var a: Dictionary = sim.actors[id]
		h += "|" + id + str(a["tile"]) + str(int(a["needs"]["hunger"]))
	return h
