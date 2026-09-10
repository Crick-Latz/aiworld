extends SceneTree
## P6.1 — Subjective Agency Runtime Bridge · Shadow Mode（RA-RO）
## RA 无世界读取 · RB 缺源 fail-closed · RC 伙伴专长隔离 · RD 同世界不同认知 ·
## RE belief_refs 有据 · RF ON/OFF 不变 · RG 确定性 · RH 不执行 · RI 既有行动标注 ·
## RJ 未来能力惰性 · RK 饿+浆果 · RL 隐藏浆果反事实 · RM 渴+泉 · RN 庇护所能力门 · RO 缓存
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

	# ── 基础 sim：跑到有人知道浆果/泉 ──
	var sim := IslandSimulation.new(mq, 30014, configs)
	for i in 400: sim.step()
	var ctx_store := {}
	var berry_owner := ""
	var berry_count_total := 0
	for id in sim.actors:
		var ctx := AgencyContextBuilder.build(sim, sim.actors[id])
		ctx_store[id] = ctx
		for s in ctx.get("known_sources", []):
			if str(s.get("tag", "")) == "BERRY":
				berry_owner = str(id)
	if berry_owner != "":
		var owner_ctx: Dictionary = ctx_store[berry_owner]
		var n_berry := 0
		for s in owner_ctx.get("known_sources", []):
			if str(s.get("tag", "")) == "BERRY":
				n_berry += 1
		var world_berries: int = (sim.world.get("berry_bushes", []) as Array).size()
		# RA/RD：ctx 只含自己见过的来源，且少于世界总量（主观派生，非真值）
		_check("ra_subjective_sources_only", n_berry >= 1 and n_berry <= world_berries,
			"actor=%s known=%d world=%d" % [berry_owner, n_berry, world_berries])
		# RD：显式不同的主观观察，不假设同点出生的人必然见到不同浆果。
		var other := ""
		for id in sim.actors:
			if str(id) != berry_owner:
				other = str(id)
				break
		var rd_a: Dictionary = sim.actors[berry_owner].duplicate(true)
		var rd_b: Dictionary = sim.actors[other].duplicate(true)
		rd_a["spatial"] = SpatialBeliefMap.new()
		rd_b["spatial"] = SpatialBeliefMap.new()
		rd_a["spatial"].observe_resource("berry", Vector2i(10, 11), true, false, 1)
		rd_b["spatial"].observe_resource("berry", Vector2i(20, 21), true, false, 1)
		var rd_world := AgencyMeasure.canon(sim.world)
		var rd_a_before := AgencyContextBuilder.build(sim, rd_a)
		var rd_b_before := AgencyContextBuilder.build(sim, rd_b)
		rd_b["spatial"].observe_resource("berry", Vector2i(22, 23), true, false, 2)
		var rd_a_after := AgencyContextBuilder.build(sim, rd_a)
		var rd_b_after := AgencyContextBuilder.build(sim, rd_b)
		_check("rd_same_world_different_knowledge",
			_source_ids(rd_a_before, "BERRY") == ["berry|10,11"]
			and _source_ids(rd_b_before, "BERRY") == ["berry|20,21"]
			and _source_ids(rd_b_after, "BERRY") == ["berry|20,21", "berry|22,23"]
			and AgencyMeasure.canon(rd_a_before) == AgencyMeasure.canon(rd_a_after)
			and AgencyMeasure.canon(sim.world) == rd_world,
			"explicit observations; changing B must not change A or world")
	else:
		_check("ra_subjective_sources_only", false, "400 ticks 无人见浆果——延长跑")
		_check("rd_same_world_different_knowledge", false, "同上")

	# RB：无空间信念 → fail-closed（不回退世界）
	var no_belief_actor := {"id": "x", "inventory": {"knife": 1}, "needs": {"hunger": 500}, "life_history": LifeHistory.new([])}
	var rb_ctx := AgencyContextBuilder.build(sim, no_belief_actor)
	_check("rb_missing_context_fail_closed",
		(rb_ctx.get("known_sources", []) as Array).is_empty()
		and (rb_ctx.get("flags", []) as Array).has("CONTEXT_SOURCE_MISSING"),
		"flags=%s" % str(rb_ctx.get("flags", [])))

	# RC：改伙伴真值专长 → 计划不变（适配器只读自己的证据）
	var sim_rc := IslandSimulation.new(mq, 30014, configs)
	for i in 400: sim_rc.step()
	var rc_actor: Dictionary = sim_rc.actors["npc_oun"]
	rc_actor["needs"]["hunger"] = 600
	var rc_ctx_a := AgencyContextBuilder.build(sim_rc, rc_actor)
	var store := KnowledgePack.load_island_pack()
	var plans_a: Array = MeansEndsPlanner.propose_plans("HUNGER", store, rc_ctx_a)
	# 篡改世界真值：Khadga 的 LifeHistory（Owen 不该感知到）
	var kad_life = sim_rc.actors["npc_kadga"].get("life_history", null)
	if kad_life != null:
		kad_life.events.append({"age": 9, "type": "expertise", "desc": "修船建房航海样样精通"})
	var plans_b: Array = MeansEndsPlanner.propose_plans("HUNGER", store, rc_ctx_a)
	_check("rc_peer_expertise_isolation", JSON.stringify(plans_a) == JSON.stringify(plans_b), "")

	# RE：用到的提案必须带 belief_ref
	var re_ok := true
	for p in plans_a:
		if str(p.get("via_rule", "")) in ["berry_patch_food", "spring_water"] and (p.get("belief_refs", []) as Array).is_empty():
			re_ok = false
	_check("re_belief_refs_grounded", re_ok, "")

	# RF/RH：Shadow ON/OFF 世界完全一致 + 无执行副作用
	var sim_off := IslandSimulation.new(mq, 30014, configs)
	var sim_on := IslandSimulation.new(mq, 30014, configs)
	var runner := AgencyShadowRunner.new()
	for i in 300:
		sim_off.step()
		sim_on.step()
		runner.observe(sim_on)
	_check("rf_shadow_onoff_invariance", _sim_hash(sim_off) == _sim_hash(sim_on), "")
	# RH：ON 侧无计划导致的事件（无 craft/hunt 新事件类型，事件数一致由 RF 保证）
	_check("rh_no_execution", sim_on.events.size() == sim_off.events.size()
		and not _has_event_type(sim_on, "crafted_spear") and not _has_event_type(sim_on, "hunt"),
		"events %d/%d" % [sim_on.events.size(), sim_off.events.size()])

	# RG：同 seed shadow 双跑记录一致
	var r1 := AgencyShadowRunner.new()
	var r2 := AgencyShadowRunner.new()
	var sg1 := IslandSimulation.new(mq, 30014, configs)
	var sg2 := IslandSimulation.new(mq, 30014, configs)
	for i in 200:
		sg1.step(); sg2.step()
		r1.observe(sg1); r2.observe(sg2)
	_check("rg_runtime_determinism", JSON.stringify(r1.records) == JSON.stringify(r2.records),
		"records %d/%d" % [r1.records.size(), r2.records.size()])

	# RK：饿 + 已知浆果 → READY forage + belief_ref 指向自己的来源
	var rk_ok := false
	var rk_ref_ok := false
	for r in r1.records:
		if (r.get("problems", []) as Array).has("HUNGER") and int(r.get("ready_count", 0)) > 0:
			for p in r.get("proposals_cache", []):
				if str(p.get("via_rule", "")) == "berry_patch_food" and str(p.get("status", "")) == "READY":
					rk_ok = true
					if (p.get("belief_refs", []) as Array).size() > 0:
						rk_ref_ok = true
	_check("rk_hunger_known_berry", rk_ok and rk_ref_ok, "ready_forage=%s ref=%s" % [str(rk_ok), str(rk_ref_ok)])

	# RM：渴 + 已知泉 → DRINK 候选（确定性夹具：泉移至出生点旁，30 tick 感知可见）
	var sim_rm := IslandSimulation.new(mq, 30014, configs)
	var springs: Array = sim_rm.world.get("water_springs", [])
	if not springs.is_empty():
		springs[0] = spot + Vector2i(3, 0)
	for i in 30:
		sim_rm.step()
	var rm_actor: Dictionary = sim_rm.actors["npc_weila"]
	rm_actor["needs"]["thirst"] = 600
	var rm_runner := AgencyShadowRunner.new()
	rm_runner.observe(sim_rm)
	var rm_ok := false
	for r in rm_runner.records:
		if str(r.get("actor_id", "")) == "npc_weila" and (r.get("problems", []) as Array).has("THIRST"):
			for p in r.get("proposals_cache", []):
				if str(p.get("via_rule", "")) == "spring_water" and str(p.get("status", "")) == "READY":
					rm_ok = true
	_check("rm_thirst_known_spring", rm_ok, "")
	# RI/RJ：步骤标注——浆果=EXISTING_ACTION(forage_berries)；craft_spear=FUTURE_CAPABILITY 且惰性
	var ri_ok := false
	var rj_ok := true
	for r in r1.records:
		for p in r.get("proposals_cache", []):
			for st in p.get("steps", []):
				if str(p.get("via_rule", "")) == "berry_patch_food" and str(st.get("kind", "")) == "MAIN":
					if str(st.get("step_execution_status", "")) == "EXISTING_ACTION" and str(st.get("existing_action", "")) == "forage_berries":
						ri_ok = true
				if str(st.get("description", "")).find("craft_spear") != -1:
					if str(st.get("step_execution_status", "")) != "FUTURE_CAPABILITY":
						rj_ok = false
	_check("ri_existing_action_annotation", ri_ok, "")
	_check("rj_future_capability_inert", rj_ok, "")

	# RL：隐藏浆果反事实——世界多处一个未见浆果 → ctx hash 与计划不变
	var sim_l := IslandSimulation.new(mq, 30014, configs)
	for i in 400: sim_l.step()
	var target_id := berry_owner if berry_owner != "" else "npc_weila"
	var t_actor: Dictionary = sim_l.actors[target_id]
	var ctx_l1 := AgencyContextBuilder.build(sim_l, t_actor)
	var plans_l1: Array = MeansEndsPlanner.propose_plans("HUNGER", store, ctx_l1)
	var hash_l1 := AgencyContextBuilder.context_hash(ctx_l1)
	# 世界真值加一个远处的浆果（不在任何人视野内）
	var far := _far_hidden_tile(sim_l, mq)
	(sim_l.world.get("berry_bushes", []) as Array).append({"pos": far, "food": 2, "regrow_day": -1})
	var ctx_l2 := AgencyContextBuilder.build(sim_l, t_actor)
	var plans_l2: Array = MeansEndsPlanner.propose_plans("HUNGER", store, ctx_l2)
	_check("rl_hidden_berry_counterfactual",
		AgencyContextBuilder.context_hash(ctx_l2) == hash_l1 and JSON.stringify(plans_l2) == JSON.stringify(plans_l1), "")

	# RN：庇护所能力门——知 WOOD + 无 BUILD_BASIC → BLOCKED；给 BUILD_BASIC → READY；不因 Khadga 会木工而放行
	var rn_ctx := {"known_source_tags": ["WOOD"], "possessed_tags": [], "possessed_capabilities": [],
		"expertise_tags": [], "known_peers": [{"id": "npc_kadga", "expertise_tags": ["WOODWORKING"], "trust": 0.5}]}
	var rn_blocked: Array = MeansEndsPlanner.propose_plans("LACK_OF_SHELTER", store, rn_ctx)
	var rn_b := _find_by_rule(rn_blocked, "build_shelter")
	var rn_ok1 := not rn_b.is_empty() and str(rn_b.get("status", "")) == "BLOCKED_PLAN"
	var rn_ctx2 := rn_ctx.duplicate()
	rn_ctx2["possessed_capabilities"] = ["BUILD_BASIC"]
	var rn_ready: Array = MeansEndsPlanner.propose_plans("LACK_OF_SHELTER", store, rn_ctx2)
	var rn_r := _find_by_rule(rn_ready, "build_shelter")
	var rn_ok2 := not rn_r.is_empty() and str(rn_r.get("status", "")) == "READY"
	_check("rn_shelter_capability_gate", rn_ok1 and rn_ok2, "blocked=%s ready=%s" % [str(rn_ok1), str(rn_ok2)])

	# RO：缓存确定性——同 context 重复观察 → cache_hits 增长且 planner_calls 受限
	var ro_runner := AgencyShadowRunner.new()
	var sim_ro := IslandSimulation.new(mq, 30014, configs)
	for i in 60:
		sim_ro.step()
		ro_runner.observe(sim_ro)
	var st: Dictionary = ro_runner.stats()
	_check("ro_cache_deterministic", int(st["cache_hits"]) > 0 and int(st["planner_calls"]) < 60 * 3,
		"calls=%d hits=%d" % [int(st["planner_calls"]), int(st["cache_hits"])])

	print("SUMMARY pass=%d fail=%d" % [_pass, _fail])
	_f = true
	quit(0 if _fail == 0 else 1)

func _source_ids(ctx: Dictionary, tag: String) -> Array:
	var out: Array = []
	for s in ctx.get("known_sources", []):
		if str(s.get("tag", "")) == tag:
			out.append(str(s.get("source_id", "")))
	out.sort()
	return out

func _find_by_rule(plans: Array, rule_id: String) -> Dictionary:
	for p in plans:
		if str(p.get("via_rule", "")) == rule_id:
			return p
	return {}

func _has_event_type(sim, t: String) -> bool:
	for e in sim.events:
		if str(e.get("type", "")) == t:
			return true
	return false

func _far_hidden_tile(sim, mq) -> Vector2i:
	# 找一个离所有 actor 都 >25 格的可走格（保证不在任何视野内）
	var rect: Rect2i = mq.get_map_rect()
	for z in range(2, rect.size.y - 2):
		for x in range(2, rect.size.x - 2):
			var t := Vector2i(x, z)
			if not mq.is_walkable_tile(Vector3i(x, 0, z)):
				continue
			var far_enough := true
			for id in sim.actors:
				var at: Vector2i = sim.actors[id]["tile"]
				if absi(at.x - x) + absi(at.y - z) <= 25:
					far_enough = false
					break
			if far_enough:
				return t
	return Vector2i(2, 2)

func _sim_hash(sim) -> String:
	var h := str(sim.tick) + ":" + str(sim.events.size())
	for id in sim.actors:
		var a: Dictionary = sim.actors[id]
		h += "|" + id + str(a["tile"]) + str(int(a["needs"]["hunger"])) + str(int(a["needs"]["thirst"]))
	return h
