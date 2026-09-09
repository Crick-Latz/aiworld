extends SceneTree
## P6.3B-0-R2 §六 — 真实 A-Q 门禁（每扇门可反向破坏）
var _f := false
var _s := false
var _pass := 0
var _fail := 0
func _initialize() -> void: pass
func _process(_d: float) -> bool:
	if not _s: _s = true; _run()
	return _f
func _check(name: String, ok: bool, info: String = "") -> void:
	if ok: _pass += 1; print("PASS " + name)
	else: _fail += 1; print("FAIL " + name + "  " + info)

func _run() -> void:
	var items := ItemCatalog.load_default()
	var recipes := RecipeCatalog.load_default(items)
	var store := KnowledgePack.load_island_pack()
	# 真实 item_id（非大写标签）：RecipeCatalog ingredients 用 wood/shells
	var krr: Array = RecipeKnowledgeAdapter.known_recipe_refs([], store, recipes)
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")

	# ── A：合法 13 字段 PlanStep 通过 ──
	var a := PlanStepSpec.make("ACQUIRE", "ACQUIRE:item:wood", "PENDING", "", "wood", 1, "", "", ["wood"], [], ["kf_x"], ["known_source:y"], "get wood")
	_check("a_valid_13_fields", PlanStepSpec.validate(a), str(a.keys().size()))

	# ── B：畸形拒绝（缺字段/错类型/refs 畸形/kind 不变量）──
	var b1 := {"step_id": "x"} # 缺 12 个字段
	var b2 := PlanStepSpec.make("ACQUIRE", "x", "PENDING", "", "wood", 1, "", "", [], [], [], [], "")
	b2.erase("capability") # 删一个字段
	var b3 := PlanStepSpec.make("CRAFT", "x", "PENDING", "", "", 1, "recipe_fish_spear", "FISH", [], [], [], [], "")
	b3["knowledge_refs"] = [42] # 手动注入 int（validate 必须拒绝——不经 make 洗白）
	var b4 := PlanStepSpec.make("ACQUIRE", "x", "PENDING", "", "", 0, "", "", [], [], [], [], "") # ACQUIRE quantity=0
	var b5 := PlanStepSpec.make("CRAFT", "x", "PENDING", "", "", 1, "", "FISH", [], [], [], [], "") # CRAFT recipe_id 空
	var b6 := PlanStepSpec.make("MAIN", "x", "PENDING", "", "", 0, "", "", [], [], [], [], "") # MAIN action_name 空
	var b7 := PlanStepSpec.make("USE", "x", "PENDING", "", "", 0, "", "", [], [], [], [], "") # USE capability 空
	var b_results := [PlanStepSpec.validate(b1), PlanStepSpec.validate(b2), PlanStepSpec.validate(b3), PlanStepSpec.validate(b4), PlanStepSpec.validate(b5), PlanStepSpec.validate(b6), PlanStepSpec.validate(b7)]
	for bi in range(b_results.size()):
		if b_results[bi]:
			print("B_DEBUG b" + str(bi + 1) + " PASSED (should FAIL)")
	_check("b_malformed_rejected", not b_results.has(true), str(b_results))

	# ── VB（R4 §二）：validate_blocker——四种 reason 合法通过 + 畸形/不变量违反拒绝 ──
	var vb_valid := [RecipePlanAdapter.make_blocker("UNKNOWN_RECIPE", "", "FISH", 0),
		RecipePlanAdapter.make_blocker("UNKNOWN_SOURCE", "wood", "", 2),
		RecipePlanAdapter.make_blocker("MISSING_CAPABILITY", "", "TRAP", 0),
		RecipePlanAdapter.make_blocker("INVALID_PLAN_STEPS", "", "", 0)]
	var vb_inv1 := RecipePlanAdapter.make_blocker("UNKNOWN_SOURCE", "wood", "", 0) # qty 必须 >0
	var vb_inv2 := RecipePlanAdapter.make_blocker("UNKNOWN_RECIPE", "wood", "", 0) # item_id 必须空
	var vb_inv3 := RecipePlanAdapter.make_blocker("MISSING_CAPABILITY", "", "", 0) # capability 必须非空
	var vb_inv4 := {"reason_code": "UNKNOWN_RECIPE"} # 缺字段
	var vb_inv5 := RecipePlanAdapter.make_blocker("NO_SUCH_REASON", "", "X", 0) # 未知 reason
	var vb_all_valid := true
	for v in vb_valid:
		if not RecipePlanAdapter.validate_blocker(v): vb_all_valid = false
	var vb_none_invalid := RecipePlanAdapter.validate_blocker(vb_inv1) or RecipePlanAdapter.validate_blocker(vb_inv2) \
		or RecipePlanAdapter.validate_blocker(vb_inv3) or RecipePlanAdapter.validate_blocker(vb_inv4) \
		or RecipePlanAdapter.validate_blocker(vb_inv5)
	_check("vb_validate_blocker_invariants", vb_all_valid and not vb_none_invalid, "")

	# ── C：step_id 非空/唯一/双跑一致 ──
	var c_ctx := _full_ctx(krr, {"wood": 1, "shells": 1})
	var c_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, c_ctx, recipes, items)
	var c_ok := c_plans.size() > 0
	var c_ids: Array = []
	for plan in c_plans:
		for st in plan.get("steps", []):
			var sid := str((st as Dictionary).get("step_id", ""))
			if sid == "" or c_ids.has(sid):
				c_ok = false
			c_ids.append(sid)
	# 双跑
	var c_plans2: Array = MeansEndsPlanner.propose_plans("HUNGER", store, c_ctx, recipes, items)
	_check("c_step_ids_unique_deterministic", c_ok and JSON.stringify(c_plans) == JSON.stringify(c_plans2),
		"plans=%d ids=%d" % [c_plans.size(), c_ids.size()])

	# ── D：输入 Dictionary 插入顺序不同 → 计划逐位相同 ──
	var d1 := _full_ctx(krr, {"wood": 1, "shells": 1})
	var d2 := _full_ctx(krr, {"shells": 1, "wood": 1}) # 顺序不同
	var d1_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, d1, recipes, items)
	var d2_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, d2, recipes, items)
	_check("d_input_order_same_output", JSON.stringify(d1_plans) == JSON.stringify(d2_plans), "")

	# ── E：capability → recipe 数据驱动（查 RecipeCatalog）──
	var e_recipe: Dictionary = RecipePlanAdapter.find_recipe_for_capability("PIERCE", krr, recipes, items)
	_check("e_adapter_finds_recipe", not e_recipe.is_empty() and recipes.has(str(e_recipe.get("recipe_id", ""))),
		str(e_recipe.get("recipe_id", "?")))

	# ── F：知道配方且材料齐全 → CRAFT 无 ACQUIRE，plan READY ──
	var f_ctx := _full_ctx(krr, {"wood": 1, "shells": 1})
	var f_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, f_ctx, recipes, items)
	var f_craft := 0
	var f_acquire := 0
	var f_ready := false
	for plan in f_plans:
		if str(plan.get("via_rule", "")) != "animal_food_raw":
			continue
		for st in plan.get("steps", []):
			var k := str((st as Dictionary).get("kind", ""))
			if k == "CRAFT": f_craft += 1
			if k == "ACQUIRE": f_acquire += 1
		f_ready = str(plan.get("status", "")) == "READY"
	_check("f_materials_ok_craft_ready", f_craft > 0 and f_acquire == 0 and f_ready,
		"craft=%d acquire=%d ready=%s" % [f_craft, f_acquire, str(f_ready)])

	# ── G：known_recipe_refs=[] → 无 CRAFT，BLOCKED，UNKNOWN_RECIPE blocker ──
	var g_ctx := _full_ctx([], {"wood": 1, "shells": 1})
	var g_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, g_ctx, recipes, items)
	var g_craft := 0
	var g_blocked := false
	var g_unknown_recipe := false
	for plan in g_plans:
		for st in plan.get("steps", []):
			if str((st as Dictionary).get("kind", "")) == "CRAFT": g_craft += 1
		if str(plan.get("status", "")) == "BLOCKED_PLAN":
			g_blocked = true
			# R4 §五：门禁读结构化 blockers（不解析 missing_requirements 前缀字符串）
			for blk in plan.get("blockers", []):
				if RecipePlanAdapter.validate_blocker(blk) and str((blk as Dictionary).get("reason_code", "")) == "UNKNOWN_RECIPE":
					g_unknown_recipe = true
	_check("g_no_recipe_blocked", g_craft == 0 and g_blocked and g_unknown_recipe,
		"craft=%d blocked=%s unknown=%s" % [g_craft, str(g_blocked), str(g_unknown_recipe)])

	# ── H：A/B 仅 known_recipe_refs 不同 → 输出差异 ──
	var h_a_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, _full_ctx(krr, {"wood": 1, "shells": 1}), recipes, items)
	var h_b_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, _full_ctx([], {"wood": 1, "shells": 1}), recipes, items)
	var h_a_craft := 0
	var h_b_craft := 0
	for plan in h_a_plans:
		for st in plan.get("steps", []):
			if str((st as Dictionary).get("kind", "")) == "CRAFT": h_a_craft += 1
	for plan in h_b_plans:
		for st in plan.get("steps", []):
			if str((st as Dictionary).get("kind", "")) == "CRAFT": h_b_craft += 1
	_check("h_knowledge_isolation", h_a_craft > 0 and h_b_craft == 0,
		"a=%d b=%d" % [h_a_craft, h_b_craft])

	# ── I：材料足够时 ACQUIRE == 0 ──
	var i_ctx := _full_ctx(krr, {"wood": 1, "shells": 1})
	var i_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, i_ctx, recipes, items)
	var i_acquire := 0
	for plan in i_plans:
		for st in plan.get("steps", []):
			if str((st as Dictionary).get("kind", "")) == "ACQUIRE": i_acquire += 1
	_check("i_owned_no_acquire", i_acquire == 0, "acquire=%d" % i_acquire)

	# ── J：缺 wood 且有来源 → ACQUIRE item_id=wood quantity=1 belief_ref ──
	var j_ctx := _full_ctx(krr, {"shells": 1}) # 无 wood
	j_ctx["known_sources"].append({"tag": "WOOD", "source_id": "src_wood", "belief_ref": "known_source:wood", "last_seen_tick": 1, "confidence": 1.0})
	var j_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, j_ctx, recipes, items)
	var j_ok := false
	for plan in j_plans:
		for st in plan.get("steps", []):
			if str((st as Dictionary).get("kind", "")) == "ACQUIRE" and str((st as Dictionary).get("item_id", "")) == "wood":
				var qty := int((st as Dictionary).get("quantity", 0))
				var brefs: Array = (st as Dictionary).get("belief_refs", [])
				if qty == 1 and brefs.size() > 0:
					j_ok = true
	_check("j_gap_acquire_with_belief", j_ok, "")

	# ── K：缺 wood 无来源 → 无 ACQUIRE，BLOCKED/SUBGOAL ──
	var k_ctx := _full_ctx(krr, {"shells": 1})
	k_ctx["known_sources"] = [] # 无 wood 来源
	k_ctx["known_source_tags"] = ["ANIMAL"] # 只有动物
	var k_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, k_ctx, recipes, items)
	var k_acquire := 0
	var k_blocked := false
	for plan in k_plans:
		for st in plan.get("steps", []):
			if str((st as Dictionary).get("kind", "")) == "ACQUIRE" and str((st as Dictionary).get("item_id", "")) == "wood":
				k_acquire += 1
		if str(plan.get("status", "")) == "BLOCKED_PLAN":
			k_blocked = true
	_check("k_no_source_blocked", k_acquire == 0 and k_blocked, "acquire=%d blocked=%s" % [k_acquire, str(k_blocked)])

	# ── L：真实双角色反事实——只改 B 库存，A 的 ctx hash/plans 不变 ──
	if ps != null:
		var l_inst = ps.instantiate()
		root.add_child(l_inst)
		for i2 in 20: await physics_frame
		var l_mq = l_inst.get_node("World/MapController")
		var l_scen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
		var l_spot = l_mq.get_poi_tile("post_house")
		var l_cfgs: Array = []
		for ac in l_scen.get("actors", []):
			var cf = ac.duplicate(); cf["spawn"] = l_spot; l_cfgs.append(cf)
		var l_sim := IslandSimulation.new(l_mq, 30014, l_cfgs)
		for i3 in 100: l_sim.step()
		var actor_a: Dictionary = l_sim.actors["npc_oun"]
		var actor_b: Dictionary = l_sim.actors["npc_weila"]
		var A_before := AgencyContextBuilder.build(l_sim, actor_a)
		var A_before_hash := AgencyContextBuilder.context_hash(A_before)
		var A_before_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, A_before, recipes, items)
		var B_before_inv: Dictionary = actor_b["inventory"].duplicate()
		actor_b["inventory"]["wood"] = 99
		actor_b["inventory"]["shells"] = 99
		var B_changed := InventoryOps.canonical_hash(actor_b["inventory"]) != InventoryOps.canonical_hash(B_before_inv)
		var A_after := AgencyContextBuilder.build(l_sim, actor_a)
		var A_after_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, A_after, recipes, items)
		_check("l_other_inventory_isolated", B_changed
			and AgencyContextBuilder.context_hash(A_after) == A_before_hash
			and JSON.stringify(A_after_plans) == JSON.stringify(A_before_plans),
			"B_changed=%s hash_eq=%s plans_eq=%s" % [str(B_changed), str(AgencyContextBuilder.context_hash(A_after) == A_before_hash), str(JSON.stringify(A_after_plans) == JSON.stringify(A_before_plans))])
		l_inst.queue_free()
	else:
		_check("l_other_inventory_isolated", false, "no map")

	# ── M：所有 CRAFT 的 recipe_id 在 RecipeCatalog ──
	var m_ok := true
	for plan in c_plans:
		for st in plan.get("steps", []):
			if str((st as Dictionary).get("kind", "")) == "CRAFT":
				var rid := str((st as Dictionary).get("recipe_id", ""))
				if rid == "" or not recipes.has(rid):
					m_ok = false
	_check("m_craft_recipe_exists_in_catalog", m_ok, "")

	# ── N：future_subgoal 非空、结构化、无旧字段 ──
	# R3 §二：使用真实可映射 via_rule（fish_food → fish）确保 future_subgoals 非空
	var n_blocked := {"plan_id": "PLAN_N", "root_goal": "HUNGER", "via_rule": "fish_food", "status": "BLOCKED_PLAN",
		"missing_requirements": ["UNKNOWN_RECIPE:FISH"],
		"knowledge_refs": ["recipe_fish_spear"], "belief_refs": [],
		"blockers": [RecipePlanAdapter.make_blocker("UNKNOWN_RECIPE", "", "FISH", 0, ["recipe_fish_spear"], [])],
		"steps": []}
	var n_fish_action := {"action": "fish", "target": Vector2i(5, 5), "utility": 0.5, "desc": "去捕鱼", "duration": 2}
	var n_ground := AgencyActionBridge.ground([n_blocked], [n_fish_action], 1, "test")
	var n_futures: Array = n_ground.get("future_subgoals", [])
	var n_structured := n_futures.size() > 0
	for fsg in n_futures:
		if not fsg.has("step_kind"): n_structured = false
		if fsg.has("capability_or_requirement"): n_structured = false
		# R3 §三：UNKNOWN_RECIPE blocker → item_id 空、capability=目标能力
		# R4 §三：能力缺口无物品量 → future quantity 精确为 0（禁止 maxi(1,·) 伪造）
		if str(fsg.get("reason_code", "")) == "UNKNOWN_RECIPE":
			if str(fsg.get("item_id", "?")) != "": n_structured = false
			if str(fsg.get("capability", "?")) != "FISH": n_structured = false
			if int(fsg.get("quantity", -1)) != 0: n_structured = false
		if str(fsg.get("item_id", "?")) != "" and str(fsg.get("capability", "?")) != "": n_structured = false
	_check("n_future_subgoal_structured_nonempty", n_structured, "futures=%d rc=%s" % [n_futures.size(), str(n_futures[0].get("reason_code", "?")) if n_futures.size() > 0 else "empty"])

	# ── n2（R4 §四）：production chain——真实 Planner→Bridge，UNKNOWN_SOURCE 带精确缺口量 ──
	# 自定义配方需 wood×3（gap=3 > 1，才能分辨数量是否被中途篡改/丢失）
	var n2_items := ItemCatalog.load_default()
	var n2_recipes := RecipeCatalog.new(n2_items)
	n2_recipes._register({"recipe_id": "recipe_r4_gap", "ingredients": {"wood": 3},
		"outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": [],
		"duration_ticks": 2})
	var n2_ctx := _full_ctx(["recipe_r4_gap"], {}) # 无 wood、无 WOOD 来源（来源仅为 possessed 建档）
	var n2_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, n2_ctx, n2_recipes, n2_items)
	# Planner 侧：blocker 携带精确缺口量 3
	var n2_planner_ok := false
	var n2_blocked_plan := false
	for plan in n2_plans:
		if str(plan.get("status", "")) == "BLOCKED_PLAN":
			n2_blocked_plan = true
		for blk in plan.get("blockers", []):
			if RecipePlanAdapter.validate_blocker(blk) \
					and str((blk as Dictionary).get("reason_code", "")) == "UNKNOWN_SOURCE" \
					and str((blk as Dictionary).get("item_id", "")) == "wood" \
					and int((blk as Dictionary).get("quantity", 0)) == 3:
				n2_planner_ok = true
	# Bridge 侧：future_subgoal 精确复制 quantity（不 clamp 不伪造）
	var n2_ground := AgencyActionBridge.ground(n2_plans, [n_fish_action], 1, "test")
	var n2_futures: Array = n2_ground.get("future_subgoals", [])
	var n2_ok := n2_planner_ok and n2_blocked_plan and n2_futures.size() > 0
	for fsg2 in n2_futures:
		if str(fsg2.get("reason_code", "")) == "UNKNOWN_SOURCE" and str(fsg2.get("item_id", "?")) == "wood":
			if int(fsg2.get("quantity", 0)) != 3: n2_ok = false
			if str(fsg2.get("capability", "?")) != "": n2_ok = false
	_check("n2_unknown_source_blocker_structured", n2_ok,
		"plans=%d futures=%d planner_ok=%s" % [n2_plans.size(), n2_futures.size(), str(n2_planner_ok)])

	# ── S（R4 §五）：畸形 blocker → Bridge fail-closed 跳过；合法 blocker 正常产出 ──
	var s_bad1 := RecipePlanAdapter.make_blocker("UNKNOWN_SOURCE", "wood", "", 1)
	s_bad1.erase("knowledge_refs") # 缺字段
	var s_bad2 := RecipePlanAdapter.make_blocker("UNKNOWN_RECIPE", "", "FISH", 0)
	s_bad2["capability"] = "" # reason 不变量违反（UNKNOWN_RECIPE 必须有 capability）
	var s_good := RecipePlanAdapter.make_blocker("MISSING_CAPABILITY", "", "TRAP", 0)
	var s_plan := {"plan_id": "PLAN_S", "root_goal": "HUNGER", "via_rule": "fish_food",
		"status": "BLOCKED_PLAN", "missing_requirements": [], "knowledge_refs": [], "belief_refs": [],
		"blockers": [s_bad1, s_bad2, 42, s_good], "steps": []}
	var s_ground := AgencyActionBridge.ground([s_plan], [n_fish_action], 1, "test")
	var s_futures: Array = s_ground.get("future_subgoals", [])
	var s_ok := s_futures.size() == 1
	if s_ok:
		s_ok = str(s_futures[0].get("reason_code", "")) == "MISSING_CAPABILITY" \
			and str(s_futures[0].get("capability", "")) == "TRAP"
	_check("s_malformed_blocker_fail_closed", s_ok, "futures=%d" % s_futures.size())

	# ── T（R4 §五）：重复 step_id（非 ACQUIRE）→ Planner fail-closed：BLOCKED + INVALID_PLAN_STEPS ──
	var t_store := WorldKnowledgeStore.new()
	t_store.load_pack({"pack_id": "r4_dup", "facts": [], "affordances": [{
		"id": "r4_dup_rule", "affordance": "TEST", "subject_tags": ["WOOD"],
		"produces": ["FOOD"], "provides_capabilities": [],
		"requirements": ["BUILD_BASIC", "BUILD_BASIC"], "risks": [],
		"knowledge_required": [], "estimated_effort": 1.0}]})
	var t_ctx := _full_ctx([], {})
	t_ctx["possessed_capabilities"] = ["BUILD_BASIC"] # 两个 USE 同 step_id → 重复
	var t_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", t_store, t_ctx)
	var t_status := ""
	var t_invalid_blk := false
	var t_use_count := 0
	for plan in t_plans:
		if str(plan.get("via_rule", "")) == "r4_dup_rule":
			t_status = str(plan.get("status", ""))
			for st in plan.get("steps", []):
				if str((st as Dictionary).get("kind", "")) == "USE": t_use_count += 1
			for blk in plan.get("blockers", []):
				if str((blk as Dictionary).get("reason_code", "")) == "INVALID_PLAN_STEPS": t_invalid_blk = true
	_check("t_duplicate_step_id_blocked", t_status == "BLOCKED_PLAN" and t_invalid_blk and t_use_count == 2,
		"status=%s use=%d invalid=%s" % [t_status, t_use_count, str(t_invalid_blk)])

	# ── AG（R4 §六）：ACQUIRE 聚合合并全部四个 refs 数组并排序 ──
	var ag_a := PlanStepSpec.make("ACQUIRE", "ACQUIRE:item:wood", "PENDING", "", "wood", 2, "", "", ["wood"], [], ["k1"], ["b2"])
	var ag_b := PlanStepSpec.make("ACQUIRE", "ACQUIRE:item:wood", "PENDING", "", "wood", 3, "", "", ["plank"], ["craft"], ["k0"], ["b1"])
	var ag_merged: Array = MeansEndsPlanner._aggregate_acquires([ag_a, ag_b])
	var ag_ok := ag_merged.size() == 1
	if ag_ok:
		var m0: Dictionary = ag_merged[0]
		ag_ok = int(m0["quantity"]) == 5 \
			and JSON.stringify(m0["requires"]) == JSON.stringify(["plank", "wood"]) \
			and JSON.stringify(m0["provides"]) == JSON.stringify(["craft"]) \
			and JSON.stringify(m0["knowledge_refs"]) == JSON.stringify(["k0", "k1"]) \
			and JSON.stringify(m0["belief_refs"]) == JSON.stringify(["b1", "b2"])
	_check("ag_aggregate_merges_sorts_all_refs", ag_ok, JSON.stringify(ag_merged))

	# ── O/P：SHADOW/OFF 行为一致 + 库存一致 ──
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
		var off := IslandSimulation.new(mq, 30014, configs)
		var sh := IslandSimulation.new(mq, 30014, configs)
		sh.agency_mode = "SHADOW"
		var o_ok := true
		for i in 200:
			off.step()
			sh.step()
			if AgencyMeasure.canonical_behavior_digest(off) != AgencyMeasure.canonical_behavior_digest(sh):
				o_ok = false
				break
		_check("o_shadow_off_digest", o_ok, "")
		# P：逐 actor 比较 inventory canonical + 事件数
		var p_ok := off.events.size() == sh.events.size()
		for id in off.actors:
			var ia := InventoryOps.canonical_hash(off.actors[id]["inventory"])
			var ib := InventoryOps.canonical_hash(sh.actors[id]["inventory"])
			if ia != ib: p_ok = false
		_check("p_inventory_events_identical", p_ok, "events=%d/%d" % [off.events.size(), sh.events.size()])
		inst.queue_free()
	else:
		_check("o_shadow_off_digest", false, "no map")
		_check("p_inventory_events_identical", false, "no map")

	# ── Q：同输入双跑逐位一致 ──
	var q1: Array = MeansEndsPlanner.propose_plans("HUNGER", store, c_ctx, recipes, items)
	var q2: Array = MeansEndsPlanner.propose_plans("HUNGER", store, c_ctx, recipes, items)
	_check("q_deterministic", JSON.stringify(q1) == JSON.stringify(q2), "")

	# ── R2 §四：ctx hash 含数量 ──
	var r1 := _full_ctx(krr, {"wood": 1})
	var r2 := _full_ctx(krr, {"wood": 2}) # 同键不同量
	var r3 := _full_ctx(krr, {"wood": 1})
	_check("r_hash_includes_quantity",
		AgencyContextBuilder.context_hash(r1) != AgencyContextBuilder.context_hash(r2)
		and AgencyContextBuilder.context_hash(r1) == AgencyContextBuilder.context_hash(r3), "")

	print("SUMMARY pass=%d fail=%d" % [_pass, _fail])
	_f = true
	quit(0)

func _full_ctx(refs: Array, possessed: Dictionary) -> Dictionary:
	var sources: Array = []
	for item_id in possessed:
		sources.append({"tag": "WOOD" if item_id == "wood" else "SHELL", "source_id": "src_" + item_id, "belief_ref": "known_source:" + item_id, "last_seen_tick": 1, "confidence": 1.0})
	sources.append({"tag": "ANIMAL", "source_id": "src_animal", "belief_ref": "known_source:animal", "last_seen_tick": 1, "confidence": 1.0})
	return {
		"known_source_tags": ["ANIMAL", "WOOD", "SHELL"],
		"known_sources": sources,
		"possessed_items": possessed,
		"possessed_tags": ["WOOD", "SHELL", "ANIMAL"],
		"possessed_capabilities": [],
		"expertise_tags": [],
		"known_peers": [],
		"known_recipe_refs": refs,
	}
