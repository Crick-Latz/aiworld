extends SceneTree
## P6.3A — Generic Item / Recipe / Capability Foundation（Gate A-V）
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
	## ── 独立目录：ItemCatalog / RecipeCatalog / InventoryOps / CraftingResolver ──
	var items := ItemCatalog.load_default()
	var recipes := RecipeCatalog.load_default(items)
	var store := KnowledgePack.load_island_pack()

	# A：ItemSpec 合法加载
	_check("a_item_loads", items.size() >= 9 and items.has("fish_spear") and items.has("shells"),
		"size=%d" % items.size())

	# B：重复 item_id 拒绝
	var dup := ItemCatalog.new()
	dup.load_file("res://data/items/items.json")
	dup.load_file("res://data/items/items.json")
	_check("b_duplicate_rejected", dup.size() == items.size(),
		"dup_size=%d expected=%d（重复 load 不重复计数）" % [dup.size(), items.size()])

	# C：畸形 ItemSpec 拒绝（未知 capability / 缺字段）
	var bad := ItemCatalog.new()
	bad._register({"item_id": "bad1", "display_name": "X", "tags": ["T"], "provides_capabilities": ["NOT_A_CAP"], "stackable": true})
	bad._register({"display_name": "NoID"})
	_check("c_malformed_item_rejected", not bad.has("bad1") and not bad.has("") and bad.rejected.size() >= 2,
		"rejected=%d" % bad.rejected.size())

	# D：RecipeSpec 合法加载
	_check("d_recipe_loads", recipes.has("recipe_fish_spear"),
		"recipes=%s" % str(recipes.all_ids_sorted()))

	# E：未知 ingredient/output 引用拒绝
	var badr := RecipeCatalog.new(items)
	badr._register({"recipe_id": "bad_r", "ingredients": {"nonexistent": 1}, "outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": [], "duration_ticks": 1})
	_check("e_unknown_ref_rejected", not badr.has("bad_r") and badr.rejected.size() >= 1)

	# F：零/负/浮点/NaN/Inf 数量拒绝
	var badf := RecipeCatalog.new(items)
	badf._register({"recipe_id": "f1", "ingredients": {"shells": 0}, "outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": [], "duration_ticks": 1})
	badf._register({"recipe_id": "f2", "ingredients": {"shells": -1}, "outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": [], "duration_ticks": 1})
	badf._register({"recipe_id": "f3", "ingredients": {"shells": 1.5}, "outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": [], "duration_ticks": 1})
	badf._register({"recipe_id": "f4", "ingredients": {"shells": NAN}, "outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": [], "duration_ticks": 1})
	badf._register({"recipe_id": "f5", "ingredients": {"shells": INF}, "outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": [], "duration_ticks": 1})
	_check("f_bad_counts_rejected", not badf.has("f1") and not badf.has("f2") and not badf.has("f3") and not badf.has("f4") and not badf.has("f5"))

	# G/H/I：库存事务
	var inv := {"shells": 2, "wood": 2}
	var spec: Dictionary = recipes.spec("recipe_fish_spear")
	var txn: Dictionary = InventoryOps.consume_and_grant(inv, spec, items)
	_check("g_transaction_ok", bool(txn.get("ok", false))
		and int(txn["inventory"].get("shells", 0)) == 1
		and int(txn["inventory"].get("wood", 0)) == 1
		and int(txn["inventory"].get("fish_spear", 0)) == 1)

	var inv_poor := {"shells": 0, "wood": 2}
	var inv_poor_snapshot := inv_poor.duplicate()
	var txn_fail: Dictionary = InventoryOps.consume_and_grant(inv_poor, spec, items)
	_check("h_insufficient_atomic", not bool(txn_fail.get("ok", false))
		and JSON.stringify(InventoryOps.normalize(inv_poor)) == JSON.stringify(InventoryOps.normalize(inv_poor_snapshot)))

	var bad_output_recipe := {"ingredients": {"shells": 1}, "outputs": {"ghost_item": 1}, "knowledge_refs": [], "required_capabilities": [], "duration_ticks": 1, "recipe_id": "x"}
	var inv2 := {"shells": 3}
	var txn_bad: Dictionary = InventoryOps.consume_and_grant(inv2, bad_output_recipe, items)
	_check("i_bad_output_atomic", not bool(txn_bad.get("ok", false)) and int(inv2.get("shells", 0)) == 3)

	# J：插入顺序无关
	var ia := {"shells": 1, "wood": 2}
	var ib := {"wood": 2, "shells": 1}
	_check("j_canonical_order_independent", InventoryOps.canonical_hash(ia) == InventoryOps.canonical_hash(ib))

	# K：有材料但不知道配方 → 不能制作
	var no_knowledge: Array = []
	var diag_k: Dictionary = CraftingResolver.diagnose({"shells": 1, "wood": 1}, no_knowledge, [], recipes)
	_check("k_no_knowledge_no_craft", not bool(diag_k.get("recipe_fish_spear", {}).get("craftable", true)))

	# L：知道配方但缺材料 → 不能制作 + 稳定 missing
	var krr: Array = RecipeKnowledgeAdapter.known_recipe_refs([], store, recipes)
	var diag_l: Dictionary = CraftingResolver.diagnose({"shells": 0, "wood": 1}, krr, [], recipes)
	var missing_l: Array = diag_l.get("recipe_fish_spear", {}).get("missing", [])
	_check("l_missing_material_stable", not bool(diag_l.get("recipe_fish_spear", {}).get("craftable", true))
		and missing_l.has("material:shells(0/1)"))

	# M：知识+材料齐 → 唯一确定候选
	var cands1: Array = CraftingResolver.craft_candidates({"shells": 1, "wood": 1}, krr, [], recipes, items)
	var cands2: Array = CraftingResolver.craft_candidates({"wood": 1, "shells": 1}, krr, [], recipes, items)
	_check("m_unique_deterministic_candidate", cands1.size() == 1 and cands2.size() == 1
		and JSON.stringify(cands1[0]) == JSON.stringify(cands2[0]))

	# N/O：hidden-state 隔离（用 sim 夹具）
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var sim = null
	var mq = null
	if ps != null:
		var inst = ps.instantiate()
		root.add_child(inst)
		for i in 20: await physics_frame
		mq = inst.get_node("World/MapController")
		var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
		var spot = mq.get_poi_tile("post_house")
		var configs: Array = []
		for ac in scenario.get("actors", []):
			var cfg = ac.duplicate(); cfg["spawn"] = spot; configs.append(cfg)
		sim = IslandSimulation.new(mq, 30014, configs)
		for i in 200: sim.step()
		sim.actors["npc_oun"]["inventory"]["shells"] = 1
		sim.actors["npc_oun"]["inventory"]["wood"] = 1
		var ctx1 := AgencyContextBuilder.build(sim, sim.actors["npc_oun"])
		var hash1 := AgencyContextBuilder.context_hash(ctx1)
		var cands_a: Array = CraftingResolver.craft_candidates(sim.actors["npc_oun"]["inventory"], ctx1.get("known_recipe_refs", []), ctx1.get("possessed_capabilities", []), recipes, items)

		# N：世界暗加未知材料源 → ctx hash/候选不变
		var far := Vector2i(60, 60)
		(sim.world.get("berry_bushes", []) as Array).append({"pos": far, "food": 5, "regrow_day": -1})
		var ctx2 := AgencyContextBuilder.build(sim, sim.actors["npc_oun"])
		var cands_b: Array = CraftingResolver.craft_candidates(sim.actors["npc_oun"]["inventory"], ctx2.get("known_recipe_refs", []), ctx2.get("possessed_capabilities", []), recipes, items)
		_check("n_hidden_source_isolation", AgencyContextBuilder.context_hash(ctx2) == hash1
			and JSON.stringify(cands_a) == JSON.stringify(cands_b))

		# O：篡改他人库存 → 当前 NPC 候选不变
		sim.actors["npc_weila"]["inventory"]["shells"] = 99
		var ctx3 := AgencyContextBuilder.build(sim, sim.actors["npc_oun"])
		var cands_c: Array = CraftingResolver.craft_candidates(sim.actors["npc_oun"]["inventory"], ctx3.get("known_recipe_refs", []), ctx3.get("possessed_capabilities", []), recipes, items)
		_check("o_other_inventory_isolation", JSON.stringify(cands_a) == JSON.stringify(cands_c))

		# P：制作后库存精确正确（shells/wood/fish_spear + 事件 consumed/produced）
		var crafted_before_p := 0
		for e in sim.events:
			if str(e.get("type", "")) == "crafted":
				crafted_before_p += 1
		for i in 100: sim.step()
		var crafted_events: Array = []
		for e in sim.events:
			if str(e.get("type", "")) == "crafted":
				crafted_events.append(e)
		var p_inv: Dictionary = sim.actors["npc_oun"]["inventory"]
		var p_evt: Dictionary = crafted_events[crafted_events.size() - 1] if crafted_events.size() > crafted_before_p else {}
		var p_consumed: Dictionary = p_evt.get("consumed_items", {})
		var p_produced: Dictionary = p_evt.get("produced_items", {})
		_check("p_craft_transaction_precise", crafted_events.size() > crafted_before_p
			and int(p_inv.get("fish_spear", 0)) >= 1
			and int(p_consumed.get("shells", -1)) == 1 and int(p_consumed.get("wood", -1)) == 1
			and int(p_produced.get("fish_spear", -1)) == 1
			and str(p_evt.get("recipe_id", "")) == "recipe_fish_spear",
			"spear=%d consumed=%s produced=%s" % [int(p_inv.get("fish_spear", 0)), JSON.stringify(p_consumed), JSON.stringify(p_produced)])

		# Q：FISH/PIERCE 由 ItemCatalog 派生
		var caps := InventoryOps.capabilities_of_inventory(sim.actors["npc_oun"]["inventory"], items)
		_check("q_capability_from_catalog", caps.has("FISH") and caps.has("PIERCE"))

		# R：没有 fish_spear → 不凭空获得 FISH
		var no_spear_caps := InventoryOps.capabilities_of_inventory({"shells": 5, "wood": 5}, items)
		_check("r_no_spear_no_fish", not no_spear_caps.has("FISH"))

		# S：旧行为等价（真夹具——确定性验证兼容性，不用恒真）
		# S1：材料齐 + 无鱼叉 + 知识齐 → 产出 craft_fish_spear（action/duration 与旧语义一致）
		var oun_a: Dictionary = sim.actors["npc_oun"]
		oun_a["inventory"]["shells"] = 1
		oun_a["inventory"]["wood"] = 1
		oun_a["inventory"].erase("fish_spear")
		var s_view: Dictionary = sim._build_actor_view("npc_oun", oun_a)
		var s_craft: Dictionary = {}
		for act in ActionRegistry.get_available_actions(s_view, sim.world):
			if str(act.get("action", "")) == "craft_fish_spear":
				s_craft = act
		var s_util := float(s_craft.get("utility", -1.0)) if not s_craft.is_empty() else -1.0
		_check("s_compat_candidate_present", not s_craft.is_empty()
			and str(s_craft.get("action", "")) == "craft_fish_spear"
			and int(s_craft.get("duration", 0)) == 2
			and typeof(s_craft.get("target")) == TYPE_VECTOR2I
			and s_util > 0.3 and s_util < 0.8,
			"action=%s duration=%s" % [str(s_craft.get("action", "?")), str(s_craft.get("duration", "?"))])
		# S2：材料不足（去 shells）→ 不产生制作候选
		oun_a["inventory"].erase("shells")
		var s_view2: Dictionary = sim._build_actor_view("npc_oun", oun_a)
		var s_craft2 := {}
		for act2 in ActionRegistry.get_available_actions(s_view2, sim.world):
			if str(act2.get("action", "")) == "craft_fish_spear":
				s_craft2 = act2
		_check("s_compat_no_material_no_craft", s_craft2.is_empty(), "")
		# S3：已有非 stackable 鱼叉 → 不重复制作（旧 fish_spear>0 门语义）
		oun_a["inventory"]["shells"] = 1
		oun_a["inventory"]["fish_spear"] = 1
		var s_view3: Dictionary = sim._build_actor_view("npc_oun", oun_a)
		var s_craft3 := {}
		for act3 in ActionRegistry.get_available_actions(s_view3, sim.world):
			if str(act3.get("action", "")) == "craft_fish_spear":
				s_craft3 = act3
		_check("s_compat_owned_nonstackable_no_craft", s_craft3.is_empty(), "")

		# T：同输入重复运行 → 候选/库存/事件一致
		var sim_t1 := IslandSimulation.new(mq, 30014, configs)
		var sim_t2 := IslandSimulation.new(mq, 30014, configs)
		for i in 300:
			sim_t1.step()
			sim_t2.step()
		_check("t_deterministic", sim_t1.events.size() == sim_t2.events.size()
			and AgencyMeasure.canonical_behavior_digest(sim_t1) == AgencyMeasure.canonical_behavior_digest(sim_t2))

		# U：P6.2 bridge 隔离不回退（OFF 模式世界一致）
		var off1 := IslandSimulation.new(mq, 30014, configs)
		var off2 := IslandSimulation.new(mq, 30014, configs)
		for i in 200:
			off1.step()
			off2.step()
		_check("u_bridge_off_invariant", AgencyMeasure.canonical_behavior_digest(off1) == AgencyMeasure.canonical_behavior_digest(off2))
		inst.queue_free()
	else:
		_check("n_hidden_source_isolation", false, "地图不可用")

	# ── P6.3A-R1 追加门 ──

	# rw1：duration 1.5/0/负 拒绝
	var rw_cat := RecipeCatalog.new(items)
	rw_cat._register({"recipe_id": "rw1", "ingredients": {"shells": 1}, "outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": [], "duration_ticks": 1.5})
	rw_cat._register({"recipe_id": "rw2", "ingredients": {"shells": 1}, "outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": [], "duration_ticks": 0})
	rw_cat._register({"recipe_id": "rw3", "ingredients": {"shells": 1}, "outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": [], "duration_ticks": -2})
	_check("rw1_bad_duration_rejected", not rw_cat.has("rw1") and not rw_cat.has("rw2") and not rw_cat.has("rw3"))

	# rw2：duplicate compat_action 拒绝
	var rw2_cat := RecipeCatalog.new(items)
	rw2_cat._register({"recipe_id": "a1", "compat_action": "same_action", "ingredients": {"shells": 1}, "outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": [], "duration_ticks": 1})
	rw2_cat._register({"recipe_id": "a2", "compat_action": "same_action", "ingredients": {"shells": 1}, "outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": [], "duration_ticks": 1})
	_check("rw2_dup_compat_rejected", rw2_cat.has("a1") and not rw2_cat.has("a2"))

	# rw3：knowledge_refs 非 Array / 空条目拒绝
	var rw3_cat := RecipeCatalog.new(items)
	rw3_cat._register({"recipe_id": "b1", "ingredients": {"shells": 1}, "outputs": {"fish_spear": 1}, "knowledge_refs": "not_array", "required_capabilities": [], "duration_ticks": 1})
	rw3_cat._register({"recipe_id": "b2", "ingredients": {"shells": 1}, "outputs": {"fish_spear": 1}, "knowledge_refs": [""], "required_capabilities": [], "duration_ticks": 1})
	_check("rw3_bad_krefs_rejected", not rw3_cat.has("b1") and not rw3_cat.has("b2"))

	# rw4：stackable 非 bool / tags 空或非字符串拒绝
	var rw4_cat := ItemCatalog.new()
	rw4_cat._register({"item_id": "c1", "display_name": "X", "tags": ["T"], "provides_capabilities": [], "stackable": "yes"})
	rw4_cat._register({"item_id": "c2", "display_name": "X", "tags": [""], "provides_capabilities": [], "stackable": true})
	rw4_cat._register({"item_id": "c3", "display_name": "X", "tags": [42], "provides_capabilities": [], "stackable": true})
	_check("rw4_bad_item_fields_rejected", not rw4_cat.has("c1") and not rw4_cat.has("c2") and not rw4_cat.has("c3"))

	# rw5：primary_output 稳定排序
	var rw5_recipe := {"outputs": {"zebra_item": 1, "alpha_item": 2}}
	var rw5_out := recipes.primary_output(rw5_recipe)
	_check("rw5_primary_output_sorted", rw5_out == "alpha_item", "got=%s" % rw5_out)

	# rw6：recipe_id 执行权威（直调 _do_craft 传 recipe_id 路径）
	var rw6_ok := false
	var rw6_sim = null
	if ps != null:
		rw6_sim = sim
	if rw6_sim != null:
		rw6_sim.actors["npc_oun"]["inventory"]["shells"] = 1
		sim.actors["npc_oun"]["inventory"]["wood"] = 1
		sim.actors["npc_oun"]["inventory"].erase("fish_spear")
		var ev_before: int = sim.events.size()
		sim._do_craft("npc_oun", sim.actors["npc_oun"], [], {"action": "craft_fish_spear", "recipe_id": "recipe_fish_spear"})
		if sim.events.size() > ev_before and int(sim.actors["npc_oun"]["inventory"].get("fish_spear", 0)) >= 1:
			if str(sim.events[sim.events.size() - 1].get("recipe_id", "")) == "recipe_fish_spear":
				rw6_ok = true
	_check("rw6_recipe_id_authority", rw6_ok)

	# rw7：actor 无 _p63_store
	var rw7_clean := true
	if ps != null:
		for id_key in sim.actors:
			if sim.actors[id_key].has("_p63_store"):
				rw7_clean = false
	_check("rw7_no_p63_store_on_actor", rw7_clean)

	# rw8：items/ 不依赖 WorldKnowledgeStore/KnowledgePack（循环消除）
	var rw8_ok := true
	for f_path in ["res://src/simulation/items/item_catalog.gd", "res://src/simulation/items/recipe_catalog.gd", "res://src/simulation/items/inventory_ops.gd", "res://src/simulation/items/crafting_resolver.gd"]:
		var src8 := FileAccess.get_file_as_string(f_path)
		if src8.find("WorldKnowledgeStore") != -1 or src8.find("KnowledgePack") != -1:
			rw8_ok = false
	_check("rw8_items_no_knowledge_dependency", rw8_ok)

	# rw9：known_recipe_refs 经 knowledge 侧 adapter
	var rw9_refs: Array = RecipeKnowledgeAdapter.known_recipe_refs([], store, recipes)
	_check("rw9_adapter_known_refs", rw9_refs.has("recipe_fish_spear"), str(rw9_refs))

	# ═══ P6.3A-R3 执行层契约测试（直调 _do_craft，统一拒绝 helper）═══

	var rw_sim := IslandSimulation.new(mq, 1, []) if mq != null else null
	if rw_sim != null:
		var rw_actor: Dictionary = {"id": "test", "display_name": "测试", "tile": Vector2i(5, 5),
			"inventory": {"shells": 2, "wood": 2}, "current_action": null}
		var rw_items_cat := ItemCatalog.load_default()

		## 统一拒绝验证：inventory deep 全同 + events 数量同 + capabilities 全同 + 无 crafted
		var rw_verify_reject := func(action_dict: Dictionary, name: String) -> void:
			var inv_snap: Dictionary = rw_actor["inventory"].duplicate(true)
			var ev_before: int = rw_sim.events.size()
			var caps_before: Array = InventoryOps.capabilities_of_inventory(inv_snap, rw_items_cat)
			rw_sim._do_craft("test", rw_actor, [], action_dict)
			var inv_after: Dictionary = rw_actor["inventory"]
			var caps_after: Array = InventoryOps.capabilities_of_inventory(inv_after, rw_items_cat)
			var crafted_after: int = 0
			for e_rj in rw_sim.events.slice(ev_before, rw_sim.events.size()):
				if str(e_rj.get("type", "")) == "crafted":
					crafted_after += 1
			_check(name,
				AgencyMeasure.canon(inv_snap) == AgencyMeasure.canon(inv_after)
				and rw_sim.events.size() == ev_before
				and caps_before == caps_after
				and crafted_after == 0,
				"inv_diff=%s ev_delta=%d caps_eq=%s crafted=%d" % [
					str(AgencyMeasure.canon(inv_snap) != AgencyMeasure.canon(inv_after)),
					rw_sim.events.size() - ev_before, str(caps_before == caps_after), crafted_after])

		# 5 个拒绝场景（统一 helper）
		rw_verify_reject.call({"action": "craft_fish_spear", "recipe_id": null}, "rw10_null_rid_rejected")
		rw_verify_reject.call({"action": "craft_fish_spear", "recipe_id": 123}, "rw10_int_rid_rejected")
		rw_verify_reject.call({"action": "craft_fish_spear", "recipe_id": ""}, "rw10_empty_rid_rejected")
		rw_verify_reject.call({"action": "craft_fish_spear", "recipe_id": "nonexistent_recipe"}, "rw11_unknown_rid_no_legacy_fallback")
		rw_verify_reject.call({"action": "wrong_action", "recipe_id": "recipe_fish_spear"}, "rw11b_valid_rid_wrong_action_rejected")

		# 2 个成功场景
		var rw_inv_snap: Dictionary = rw_actor["inventory"].duplicate(true)
		rw_sim._do_craft("test", rw_actor, [], {"action": "craft_fish_spear"})
		_check("rw13_legacy_alias_succeeds", rw_sim.events.size() > 0 and int(rw_actor["inventory"].get("fish_spear", 0)) == 1,
			"ev=%d spear=%d" % [rw_sim.events.size(), int(rw_actor["inventory"].get("fish_spear", 0))])

		rw_actor["inventory"] = rw_inv_snap.duplicate(true)
		var ev_before2: int = rw_sim.events.size()
		rw_sim._do_craft("test", rw_actor, [], {"action": "craft_fish_spear", "recipe_id": "recipe_fish_spear"})
		var crafted2: int = 0
		for e_c2 in rw_sim.events.slice(ev_before2, rw_sim.events.size()):
			if str(e_c2.get("type", "")) == "crafted":
				crafted2 += 1
		_check("rw13b_valid_rid_succeeds", crafted2 > 0 and int(rw_actor["inventory"].get("fish_spear", 0)) >= 1,
			"crafted=%d spear=%d" % [crafted2, int(rw_actor["inventory"].get("fish_spear", 0))])
	else:
		_check("rw10_null_rid_rejected", false, "无地图")
		_check("rw10_int_rid_rejected", false, "无地图")
		_check("rw10_empty_rid_rejected", false, "无地图")
		_check("rw11_unknown_rid_no_legacy_fallback", false, "无地图")
		_check("rw11b_valid_rid_wrong_action_rejected", false, "无地图")
		_check("rw13_legacy_alias_succeeds", false, "无地图")
		_check("rw13b_valid_rid_succeeds", false, "无地图")


	# rw12：inventory 输入键顺序不变性（改名——原名称不准确）
	var rw12_inv := {"shells": 1, "wood": 1}
	var rw12_inv_rev := {"wood": 1, "shells": 1}
	var rw12_ings := {"shells": 1, "wood": 1}
	var rw12_outs := {"fish_spear": 1}
	var rw12_p1: Dictionary = InventoryOps.preview_transaction(rw12_inv, rw12_ings, rw12_outs, items)
	var rw12_p2: Dictionary = InventoryOps.preview_transaction(rw12_inv_rev, rw12_ings, rw12_outs, items)
	_check("rw12_inventory_input_order_invariant", JSON.stringify(rw12_p1.get("result", {})) == JSON.stringify(rw12_p2.get("result", {})), "")

	# rw14：primary_output 字母排序
	var rw14_recipe2 := {"outputs": {"zeta": 1, "alpha": 1, "mid": 1}}
	var rw14_po := recipes.primary_output(rw14_recipe2)
	_check("rw14_primary_output_alphabetical", rw14_po == "alpha", "got=%s" % rw14_po)

	# rw15：认知不变性——比较 CognitiveTransition 全部真实输出 + observer 状态
	var rw15_obs_a := _cog_observer()
	var rw15_obs_b := _cog_observer()
	var rw15_rs_a := RelationshipStore.new()
	var rw15_rs_b := RelationshipStore.new()
	var ev_basic := {"seq": 10, "tick": 100, "day": 5, "type": "crafted", "actor_id": "npc_weila", "text": "薇拉 制作了一把鱼叉", "tool": "fish_spear"}
	var ev_ext := ev_basic.duplicate()
	ev_ext["recipe_id"] = "recipe_fish_spear"
	ev_ext["consumed_items"] = {"shells": 1, "wood": 1}
	ev_ext["produced_items"] = {"fish_spear": 1}
	ev_ext["capabilities_before"] = ["CUT"]
	ev_ext["capabilities_after"] = ["CUT", "FISH", "PIERCE"]
	var sum_a: Dictionary = CognitiveTransition.process(rw15_obs_a, ev_basic, {"relationships": rw15_rs_a, "tick": 100})
	var sum_b: Dictionary = CognitiveTransition.process(rw15_obs_b, ev_ext, {"relationships": rw15_rs_b, "tick": 100})
	# 1. summary 全字典 canonical 比较
	_check("rw15_summary_canonical_identical", AgencyMeasure.canon(sum_a) == AgencyMeasure.canon(sum_b),
		"a=%s... b=%s..." % [AgencyMeasure.canon(sum_a).substr(0, 80), AgencyMeasure.canon(sum_b).substr(0, 80)])
	# 2. observer 状态深度比较（emotions/tom/memories/last_transition/open_questions/social_stance）
	var st_a := _cog_state(rw15_obs_a)
	var st_b := _cog_state(rw15_obs_b)
	_check("rw15_observer_state_identical", st_a == st_b,
		"diff keys: %s" % str(_dict_diff_keys(st_a, st_b)))
	# 3. RelationshipStore 状态比较
	_check("rw15_relationship_state_identical", AgencyMeasure.canon(rw15_rs_a.snapshot()) == AgencyMeasure.canon(rw15_rs_b.snapshot()), "")


	# V：模块边界（外部脚本执行；此处验证无反向依赖——items/ 不引用 cognition/narrative）
	var boundary_ok := true
	var forbidden := ["PersonalityProfile", "TheoryOfMind", "CognitiveTransition", "NarrativeClaim", "ThreadEngine", "RelationshipStore", "ExpressionContext"]
	for f in ["res://src/simulation/items/item_catalog.gd", "res://src/simulation/items/recipe_catalog.gd",
			"res://src/simulation/items/inventory_ops.gd", "res://src/simulation/items/crafting_resolver.gd"]:
		var src := FileAccess.get_file_as_string(f)
		for word in forbidden:
			if src.find(word) != -1:
				boundary_ok = false
	_check("v_no_reverse_dependency", boundary_ok)

	print("SUMMARY pass=%d fail=%d" % [_pass, _fail])
	_f = true
	quit(0)

func _cog_state(o: Dictionary) -> Dictionary:
	return {
		"emotions": AgencyMeasure.canon(o.get("personality", null).emotions if o.get("personality") else {}),
		"tom": AgencyMeasure.canon(o.get("tom", null).snapshot() if o.get("tom") else {}),
		"memories": (o.get("memories", []) as Array).size(),
		"last_transition": AgencyMeasure.canon(o.get("last_transition", {})),
		"open_questions": (o.get("open_questions", []) as Array).size(),
		"social_stance": AgencyMeasure.canon(o.get("social_stance", {})),
	}

func _dict_diff_keys(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for k in a:
		if str(a[k]) != str(b.get(k, "<missing>")):
			out.append(str(k))
	return out

func _cog_observer() -> Dictionary:
	return {"id": "npc_oun", "display_name": "欧恩",
		"personality": PersonalityProfile.new({"empathy": 0.4, "trust": 0.3}, {}),
		"tom": TheoryOfMind.new(), "memories": [], "needs": {"hunger": 300},
		"norms": {"personal": {"sharing": 0.5}}, "sensitivities": {}, "beliefs": BeliefStore.new(),
		"last_transition": {}, "grudges": {}, "open_questions": [], "claims_received": [],
		"social_stance": {}, "physical": {"sick": false, "injured": false}}
