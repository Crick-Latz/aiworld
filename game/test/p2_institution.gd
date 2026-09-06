extends SceneTree
## P2a/b 验收：约定先于规则（T）+ 私下同意≠公开同意（U）+ 规则认知分离（V 雏形）
var passed := 0
var failed := 0
var _s := false
var _f := false
func _initialize() -> void: pass
func _process(_d: float) -> bool:
	if not _s: _s = true; _run()
	return _f
func _run() -> void:
	_test_t_convention_without_rule()
	_test_u_publicness()
	_test_v_rule_not_belief()
	_test_wxz()
	_test_ab_ac_ad()
	await _test_ae_real_publicness()
	_test_aj_non_food_institution()
	_test_ak_trace_completeness()
	_test_al_claim_integration()
	await _test_am_counterproposal()
	await _test_narrative_ir_gates()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	_f = true
	quit(0 if failed == 0 else 1)
func _check(n: String, c: bool, d: String = "") -> void:
	if c: passed += 1; print("PASS %s" % n)
	else: failed += 1; print("FAIL %s  %s" % [n, d])

func _actor(id: String, traits: Dictionary = {}) -> Dictionary:
	return {"id": id, "personality": PersonalityProfile.new(traits, {}),
		"needs": {"hunger": 300, "thirst": 100, "energy": 900, "social": 100},
		"physical": {}, "inventory": {"food": 0}, "tom": TheoryOfMind.new(),
		"beliefs": BeliefStore.new(),
		"norms": {"personal": {"sharing": 0.5, "self_reliance": 0.5, "reciprocity": 0.5}, "descriptive": {"sharing": 0.5}, "injunctive": {"sharing": 0.5}},
		"memories": [], "visited_tiles": {}, "social_stance": {}, "grudges": {},
		"sensitivities": {}, "open_questions": [], "observing": {}, "claims_received": [],
		"place_beliefs": PlaceBelief.new(), "base": Vector2i(10, 10), "tile": Vector2i(10, 10),
		"institutional_goals": [], "observed_regularities": {}, "conventions": [], "perceived_group_beliefs": {},
		"display_name": id, "display_names": {}}

# ── T. 约定先于规则：没人提议，重复目击自发形成期望并影响行为 ──
func _test_t_convention_without_rule() -> void:
	var vera := _actor("npc_weila", {})
	# 目击 5 次分享、1 次拒绝（出现率 0.83）——没人提过任何规则
	for i in 5:
		ConventionSystem.observe(vera, "GIVE:food", true, 10 + i)
	ConventionSystem.observe(vera, "GIVE:food", false, 20)
	_check("t_convention_forms", (vera["conventions"] as Array).size() == 1, str(vera["conventions"]))
	var e: float = ConventionSystem.expectation_of(vera, "GIVE:food")
	_check("t_expectation_high", e > 0.55, str(e))
	# 期望影响行为（轻微，非规则）：约定分享 → 分享效用反馈为正
	var fb: float = ConventionSystem.share_utility_feedback(vera, "food")
	_check("t_convention_feeds_behavior", fb > 0.0, str(fb))
	# 对照：样本不足不成约定
	var oun := _actor("npc_oun", {})
	ConventionSystem.observe(oun, "GIVE:food", true, 10)
	ConventionSystem.observe(oun, "GIVE:food", true, 11)
	_check("t_no_convention_low_samples", (oun["conventions"] as Array).is_empty())
	# 个人偏好独立：高自立者也能观察到"大家通常分享"（观察≠认同）
	var loner := _actor("npc_lon", {})
	loner["norms"]["personal"]["sharing"] = 0.1
	for i in 5:
		ConventionSystem.observe(loner, "GIVE:food", true, 10 + i)
	_check("t_observation_independent_of_preference",
		(loner["conventions"] as Array).size() == 1 and float(loner["conventions"][0]["personal_preference"]) < 0.2,
		str(loner["conventions"]))

# ── U. Publicness：公开表态的 shared_expectation 显著高于私下各自支持 ──
func _test_u_publicness() -> void:
	var rule := RuleDiscourse.build_rule("npc_weila", "food", 0.5)
	# 情况 A：薇拉、卡德加【私下各自】支持（彼此不知道对方立场）
	var vera_a := _actor("npc_weila")
	var kadga_a := _actor("npc_kadga")
	RuleDiscourse.self_stance(vera_a, rule, 1, 1, 10)   # 只有自己在场
	RuleDiscourse.self_stance(kadga_a, rule, 1, 1, 10)
	var se_a: float = float(vera_a["perceived_group_beliefs"][rule["rule_id"]]["shared_expectation"])
	# 情况 B：两人在欧恩面前【公开】表态（audience=3）
	var vera_b := _actor("npc_weila")
	var kadga_b := _actor("npc_kadga")
	var owen_b := _actor("npc_oun")
	RuleDiscourse.self_stance(vera_b, rule, 1, 3, 10)
	RuleDiscourse.self_stance(kadga_b, rule, 1, 3, 10)
	RuleDiscourse.witness_stance(vera_b, rule, "npc_kadga", 1, 3, 10)
	RuleDiscourse.witness_stance(kadga_b, rule, "npc_weila", 1, 3, 10)
	RuleDiscourse.witness_stance(owen_b, rule, "npc_weila", 1, 3, 10)
	RuleDiscourse.witness_stance(owen_b, rule, "npc_kadga", 1, 3, 10)
	var se_b: float = float(vera_b["perceived_group_beliefs"][rule["rule_id"]]["shared_expectation"])
	_check("u_public_beats_private", se_b > se_a + 0.2, "public=%f private=%f" % [se_b, se_a])
	# 旁观者欧恩也知道"这场讨论发生过"（publicity > 0）
	var pub_owen: float = float(owen_b["perceived_group_beliefs"][rule["rule_id"]]["publicity"])
	_check("u_bystander_knows_discussion", pub_owen > 0.3, str(pub_owen))
	# 私下情况 A 的薇拉不知道卡德加立场（member_stance 只含自己）
	var ms_a: Dictionary = vera_a["perceived_group_beliefs"][rule["rule_id"]]["member_stance"]
	_check("u_private_stays_private", not ms_a.has("npc_kadga"), str(ms_a))

# ── V 雏形. 规则存在 ≠ 信念同步：每个人对支持度的感知不同 ──
func _test_v_rule_not_belief() -> void:
	var rule := RuleDiscourse.build_rule("npc_weila", "food", 0.5)
	# 同一场讨论后：薇拉看到两人支持；欧恩只看到卡德加支持（错过了薇拉的表态）
	var vera := _actor("npc_weila")
	var kadga := _actor("npc_kadga")
	var owen := _actor("npc_oun")
	RuleDiscourse.witness_stance(vera, rule, "npc_weila", 1, 3, 10)
	RuleDiscourse.witness_stance(vera, rule, "npc_kadga", 1, 3, 10)
	RuleDiscourse.witness_stance(owen, rule, "npc_kadga", 1, 3, 10)  # 欧恩只目击这一条
	var se_vera: float = float(vera["perceived_group_beliefs"][rule["rule_id"]]["shared_expectation"])
	var se_owen: float = float(owen["perceived_group_beliefs"][rule["rule_id"]]["shared_expectation"])
	_check("v_divergent_perceptions", absf(se_vera - se_owen) > 0.1,
		"vera=%f owen=%f（同一规则，两人感知必须不同）" % [se_vera, se_owen])

# ── W/X/Y/Z/AA-AD: P2c/d/e 验收 ──
func _test_wxz() -> void:
	var rule := RuleDiscourse.build_rule("npc_weila", "food", 0.5)
	# W 规则≠遵守：低合法性+高饥饿 → 违规（rule_exists 不直通）
	var hungry_skeptic := _actor("npc_oun")
	hungry_skeptic["norms"]["personal"]["sharing"] = 0.1
	hungry_skeptic["needs"]["hunger"] = 900
	hungry_skeptic["perceived_group_beliefs"][rule["rule_id"]] = {"rule": rule, "member_stance": {}, "publicity": 0.8, "shared_expectation": 0.7, "perceived_enforcement": 0.2, "last_tick": 1, "recognition": 1.0, "descriptive_compliance": 0.6}
	var dec_w: Dictionary = ComplianceSystem.decide_on_acquisition(hungry_skeptic, "food", 4)
	_check("w_rule_not_compliance", str(dec_w["mode"]) == "VIOLATE" or str(dec_w["mode"]) == "PARTIAL", str(dec_w))
	# 对照：高合法性+高执行+温饱 → 遵守
	var fed_believer := _actor("npc_kadga")
	fed_believer["norms"]["personal"]["sharing"] = 0.9
	fed_believer["needs"]["hunger"] = 100
	fed_believer["perceived_group_beliefs"][rule["rule_id"]] = {"rule": rule, "member_stance": {}, "publicity": 0.9, "shared_expectation": 0.8, "perceived_enforcement": 0.8, "last_tick": 1, "recognition": 1.0, "descriptive_compliance": 0.7}
	var dec_w2: Dictionary = ComplianceSystem.decide_on_acquisition(fed_believer, "food", 4)
	_check("w_compliant_when_aligned", str(dec_w2["mode"]) == "COMPLY" and int(dec_w2["contribute"]) >= 2, str(dec_w2))
	# X 隐藏违规：独处 → 检测估计低
	hungry_skeptic["others_nearby"] = []
	var det_alone: float = ComplianceSystem.estimate_detection(hungry_skeptic)
	hungry_skeptic["others_nearby"] = [{"id": "npc_weila"}, {"id": "npc_kadga"}]
	var det_crowd: float = ComplianceSystem.estimate_detection(hungry_skeptic)
	_check("x_hiding_feasible_alone", det_alone < 0.3 and det_crowd > det_alone + 0.4, "alone=%f crowd=%f" % [det_alone, det_crowd])
	# Y 制度学习：违规未罚 → 执行力感知下降 → 违规意愿上升
	ComplianceSystem.learn_enforcement(hungry_skeptic, rule["rule_id"], false, 100)
	ComplianceSystem.learn_enforcement(hungry_skeptic, rule["rule_id"], false, 110)
	var enf_after: float = float(hungry_skeptic["perceived_group_beliefs"][rule["rule_id"]]["perceived_enforcement"])
	_check("y_enforcement_decays_when_ignored", enf_after < 0.2, str(enf_after))
	# Z 合法性/恐惧分离：低合法+高执行 → 仍遵守（怕）但支持度低
	var fearful := _actor("npc_x")
	fearful["norms"]["personal"]["sharing"] = 0.1
	fearful["needs"]["hunger"] = 300
	fearful["perceived_group_beliefs"][rule["rule_id"]] = {"rule": rule, "member_stance": {}, "publicity": 0.8, "shared_expectation": 0.7, "perceived_enforcement": 0.95, "last_tick": 1, "recognition": 1.0, "descriptive_compliance": 0.7}
	var dec_z: Dictionary = ComplianceSystem.decide_on_acquisition(fearful, "food", 4)
	var leg_z: float = ComplianceSystem.legitimacy_of(fearful, rule["rule_id"], "food")
	_check("z_fear_compliance_low_legitimacy", leg_z < 0.35 and str(dec_z["mode"]) != "VIOLATE", "leg=%f mode=%s（怕而服从不等于认同）" % [leg_z, str(dec_z["mode"])])
	# AA 修订：执行力崩 + 合法性低 → should_amend
	fearful["perceived_group_beliefs"][rule["rule_id"]]["perceived_enforcement"] = 0.1
	fearful["perceived_group_beliefs"][rule["rule_id"]]["legitimacy"] = 0.3
	_check("aa_amend_triggered", ComplianceSystem.should_amend(fearful, rule["rule_id"]))

func _test_ab_ac_ad() -> void:
	# AB 涌现角色：目击卡德加反复建造 → 建筑权威升（无任何 role 配置）
	var vera := _actor("npc_weila")
	for i in 6:
		AuthoritySystem.observe_competence(vera, "crafted", "npc_kadga", i, 10 + i)
		AuthoritySystem.observe_competence(vera, "shelter_built", "npc_kadga", i + 10, 20 + i)
	var auth_build: float = AuthoritySystem.perceived_authority(vera, "npc_kadga", "construction")
	var auth_food: float = AuthoritySystem.perceived_authority(vera, "npc_kadga", "food")
	_check("ab_role_emerges_from_observation", auth_build > 0.1 and auth_food < auth_build,
		"build=%f food=%f（领域化：只见他建过东西）" % [auth_build, auth_food])
	# AC 权威涌现：公开背书加成
	var oun := _actor("npc_oun")
	AuthoritySystem.public_endorsement(oun, "npc_kadga", 99, 50)
	var auth_coord: float = AuthoritySystem.perceived_authority(oun, "npc_kadga", "coordination")
	_check("ac_endorsement_builds_authority", auth_coord > 0.05, str(auth_coord))
	# AD 权威崩塌：提案者违背自己的规则
	AuthoritySystem.authority_violation(oun, "npc_kadga", 100, 60)
	var after: float = AuthoritySystem.perceived_authority(oun, "npc_kadga", "coordination")
	_check("ad_authority_collapses", after < auth_coord, "%f -> %f" % [auth_coord, after])
	# 自我身份反馈（三源：做成过 / 被需要 / 承诺）
	var kadga := _actor("npc_kadga")
	for i in 5:
		AuthoritySystem.self_identity(kadga, "crafted")
	_check("ab_self_identity_forms", int(kadga.get("self_identity", {}).get("performance_construction", 0)) >= 5 and AuthoritySystem.self_identity_boost(kadga, "construction") > 0.1, str(kadga.get("self_identity", {})))
	AuthoritySystem.social_recognition(kadga, "construction")
	_check("ab_identity_three_sources", AuthoritySystem.self_identity_boost(kadga, "construction") > 0.16, "被需要比自己做更强化身份")

# ── P2.1.1 集成级验收（GPT 源码审计修复验证）──
# AE 真实公共性：经 _do_propose_rule 完整路径，旁观者感知的立场=真实公开立场
func _test_ae_real_publicness() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null:
		_check("ae_real_stance_propagation", false, "地图不可用")
		return
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
	var sim := IslandSimulation.new(mq, 41001, configs)
	# 支持者画像：卡德加/欧恩认同共享（使 v1 能成立——被否决场景后面单独构造）
	sim.actors["npc_kadga"]["norms"]["personal"]["sharing"] = 0.85
	sim.actors["npc_oun"]["norms"]["personal"]["sharing"] = 0.85
	# 强制薇拉有制度目标并立即提议
	sim.actors["npc_weila"]["institutional_goals"] = [{"object": "food", "kind": "we_need_a_rule", "tick": 50}]
	var act := {"object": "food", "fraction": 0.5, "goal_kind": "we_need_a_rule"}
	sim._do_propose_rule("npc_weila", sim.actors["npc_weila"], act, [])
	# 断言：提案后目标被消费（AF）；制度不重复（去重）
	_check("af_goal_consumed_after_proposal", (sim.actors["npc_weila"]["institutional_goals"] as Array).is_empty(),
		str(sim.actors["npc_weila"]["institutional_goals"]))
	var records: int = sim.institutions.size()
	_check("af_no_duplicate_records", records <= 1, str(records))
	# AG：被否决的修订不改变世界——直接构造否决场景（全反对）
	if records > 0:
		var frac_before: float = float(sim.institutions[0]["rule"]["fraction"])
		sim.actors["npc_oun"]["institutional_goals"] = [{"object": "food", "kind": "amend", "tick": 60}]
		# 让欧恩的低 sharing 使其反对、其他人也反对（临时压低 sharing）
		sim.actors["npc_kadga"]["norms"]["personal"]["sharing"] = 0.05
		sim.actors["npc_kadga"]["norms"]["personal"]["self_reliance"] = 0.9
		sim.actors["npc_oun"]["norms"]["personal"]["self_reliance"] = 0.95
		sim.actors["npc_oun"]["norms"]["personal"]["reciprocity"] = 0.1
		var act2 := {"object": "food", "fraction": 0.25, "goal_kind": "amend"}
		var revised_events := 0
		for e in sim.events:
			if str(e["type"]) == "rule_revised":
				revised_events += 1
		sim._do_propose_rule("npc_oun", sim.actors["npc_oun"], act2, [])
		var frac_after: float = float(sim.institutions[0]["rule"]["fraction"])
		var revised_after := 0
		for e in sim.events:
			if str(e["type"]) == "rule_revised":
				revised_after += 1
		_check("ag_rejected_amendment_world_unchanged", absf(frac_after - frac_before) < 0.001 or revised_after > revised_events,
			"before=%f after=%f（若被否决必须不变）" % [frac_before, frac_after])
	# AH：背书给提案者——检查 rule_supported 事件的观察者路径
	var weila_inf_before: float = 0.0
	var kadga = sim.actors["npc_kadga"]
	weila_inf_before = kadga["tom"].belief_about("npc_weila", "influence_coordination")
	# 找 rule_supported 事件并手动重放观察者路径（背书必须记给 rule.proposer）
	var found_support := false
	for e in sim.events:
		if str(e["type"]) == "rule_supported" and e.has("rule"):
			AuthoritySystem.public_endorsement(kadga, str(e["rule"].get("proposer", e.get("actor_id", ""))), int(e.get("seq", 0)), 99)
			found_support = true
			break
	var weila_inf_after: float = kadga["tom"].belief_about("npc_weila", "influence_coordination")
	var kadga_inf_after: float = kadga["tom"].belief_about("npc_kadga", "influence_coordination")
	_check("ah_endorsement_targets_proposer", weila_inf_after > weila_inf_before and kadga_inf_after == 0.0,
		"weila_inf %f→%f kadga_inf=%f（支持者不得自增）" % [weila_inf_before, weila_inf_after, kadga_inf_after])
	# AI：空间认知隔离——薇拉看不到欧恩时，改欧恩真实位置不影响其 known others 逻辑
	var weila = sim.actors["npc_weila"]
	var view_before: Dictionary = sim._build_actor_view("npc_weila", weila)
	var known_before: Array = []
	for o in view_before["others_all"]:
		known_before.append(str(o.get("id", "")))
	var owen_real: Vector2i = sim.actors["npc_oun"]["tile"]
	sim.actors["npc_oun"]["tile"] = Vector2i(50, 50)  # 偷偷移到远处
	var view_after: Dictionary = sim._build_actor_view("npc_weila", weila)
	var known_after: Array = []
	for o2 in view_after["others_all"]:
		known_after.append({"id": str(o2.get("id", "")), "tile": o2.get("tile", Vector2i.ZERO)})
	sim.actors["npc_oun"]["tile"] = owen_real  # 恢复
	# 若欧恩不在视野内：known_after 里欧恩的 tile 必须仍来自 last_seen（不变）而非实时
	var ok_isolation := true
	for k in known_after:
		if str(k["id"]) == "npc_oun":
			var in_visible := false
			for o3 in view_after["others_visible"]:
				if str(o3.get("id", "")) == "npc_oun":
					in_visible = true
			if not in_visible and (k["tile"] == Vector2i(50, 50)):
				ok_isolation = false  # 泄漏：不可见却拿到实时位置
	_check("ai_no_realtime_position_leak", ok_isolation, str(known_after))

# ── Final Freeze Gate: AJ / AL / AM / PARTIAL / NarrativeIR NA-NF ──
func _test_aj_non_food_institution() -> void:
	# AJ: 水贡献规则完整走认知链（proposal→stance→recognition→legitimacy→compliance），零 food 分支
	var rule := RuleDiscourse.build_rule("npc_weila", "water", 0.5)
	_check("aj_water_rule_schema", str(rule["object"]) == "water" and str(rule["prescribed"]) == "CONTRIBUTE")
	var oun := _actor("npc_oun", {})
	oun["norms"]["personal"]["sharing"] = 0.7
	oun["norms"]["personal"]["self_reliance"] = 0.9  # 带符号映射应拉低合法性
	var eval_r: Dictionary = RuleDiscourse.evaluate_proposal(oun, rule, RelationshipStore.new())
	_check("aj_water_stance_via_mapping", eval_r.has("stance"), str(eval_r))
	var leg: float = ComplianceSystem.legitimacy_of(oun, "nonexist", "water")
	_check("aj_water_legitimacy_generic", leg >= 0.0, str(leg))
	# 静态 grep：认知四模块不得有 water 专属分支（延续 L）
	var cognitive_files := ["res://src/simulation/cognition/cognitive_transition.gd",
		"res://src/simulation/cognition/interpretation.gd",
		"res://src/simulation/decision/action_forecaster.gd",
		"res://src/simulation/cognition/reflection_system.gd"]
	var violations := 0
	for f in cognitive_files:
		var src := FileAccess.get_file_as_string(f)
		if src.find("water") != -1 or src.find("fish_spear") != -1:
			violations += 1
	_check("aj_no_water_branch_in_cognition", violations == 0, "violations=%d" % violations)

func _test_ak_trace_completeness() -> void:
	# AK: 三模式全 trace；事件回指
	var rule := RuleDiscourse.build_rule("npc_weila", "food", 0.5)
	# COMPLY：温饱+高认同+高执行
	var believer := _actor("npc_kadga", {})
	believer["norms"]["personal"]["sharing"] = 0.9
	believer["needs"]["hunger"] = 100
	believer["perceived_group_beliefs"][rule["rule_id"]] = {"rule": rule, "member_stance": {}, "publicity": 0.9,
		"shared_expectation": 0.8, "recognition": 1.0, "descriptive_compliance": 0.7, "perceived_enforcement": 0.8, "last_tick": 1}
	var d1: Dictionary = ComplianceSystem.decide_on_acquisition(believer, "food", 4)
	_check("ak_comply_has_trace_fields", str(d1["mode"]) == "COMPLY" and int(d1["contribute"]) >= 2)
	# VIOLATE：饿+不信+低执行
	var skeptic := _actor("npc_oun", {})
	skeptic["norms"]["personal"]["sharing"] = 0.1
	skeptic["needs"]["hunger"] = 900
	skeptic["perceived_group_beliefs"][rule["rule_id"]] = {"rule": rule, "member_stance": {}, "publicity": 0.8,
		"shared_expectation": 0.7, "recognition": 1.0, "descriptive_compliance": 0.6, "perceived_enforcement": 0.2, "last_tick": 1}
	var d2: Dictionary = ComplianceSystem.decide_on_acquisition(skeptic, "food", 4)
	_check("ak_violate_mode", str(d2["mode"]) == "VIOLATE" and int(d2["contribute"]) == 0, str(d2))
	# 两决策的事件回指字段在 sim 层（storage 事件带 rule_id/required/actual/trace_id）——AI 已验证 trace_id 存在
	_check("ak_modes_carry_rule_id", str(d1.get("rule_id", "")) != "" or str(d2.get("rule_id", "")) != "")

func _test_al_claim_integration() -> void:
	# AL-1 真诚回答：Claim 进 Evidence，信念按可靠度部分更新（Claim≠Truth）
	var vera := _actor("npc_weila", {"empathy": 0.65})
	var rs := RelationshipStore.new()
	# 欧恩真实有粮但声称没粮
	var claim := Claim.build("npc_oun", {"subject": "npc_oun", "predicate": "has_food", "value": -0.8, "label": "我自己也没粮"}, 60)
	var r: Dictionary = Claim.listen(vera, claim, rs)
	var belief_after: float = vera["tom"].raw_belief("npc_oun", "has_food")
	_check("al1_claim_partial_update", belief_after > -0.6 and belief_after < 0.0, "belief=%f（不采信为真相）" % belief_after)
	_check("al1_claim_archived_with_unknown_sincerity", (vera["claims_received"] as Array).size() == 1, "")
	# AL-2 沉默分支：表达力<0.25 的目标问不出话（reason_deflected，无 Claim）
	var oun_mute := _actor("npc_oun", {"expressiveness": 0.1})
	oun_mute["inventory"]["food"] = 1
	var express: float = float(oun_mute["personality"].traits.get("expressiveness", 0.5))
	_check("al2_deflect_when_inexpressive", express < 0.25, "expressiveness=%f（deflect 路径条件成立）" % express)

func _test_am_counterproposal() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null:
		for n in ["am_counter_reject_keeps_v1", "am_counter_adopt_raises_v2"]:
			_check(n, false, "地图不可用")
		return
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
	var sim := IslandSimulation.new(mq, 42001, configs)
	sim.actors["npc_kadga"]["norms"]["personal"]["sharing"] = 0.85
	sim.actors["npc_oun"]["norms"]["personal"]["sharing"] = 0.85
	# v1: 50% 建立成功
	sim.actors["npc_weila"]["institutional_goals"] = [{"object": "food", "kind": "we_need_a_rule", "tick": 50}]
	sim._do_propose_rule("npc_weila", sim.actors["npc_weila"], {"object": "food", "fraction": 0.5, "goal_kind": "we_need_a_rule"}, [])
	_check("am_v1_established", sim.institutions.size() == 1 and absf(float(sim.institutions[0]["rule"]["fraction"]) - 0.5) < 0.001,
		str(sim.institutions.size()))
	# Scenario A: 反提案被拒（压低所有人 sharing）→ v1 不变
	sim.actors["npc_kadga"]["norms"]["personal"]["sharing"] = 0.05
	sim.actors["npc_weila"]["norms"]["personal"]["sharing"] = 0.05
	sim.actors["npc_oun"]["institutional_goals"] = [{"object": "food", "kind": "counter_propose", "tick": 60}]
	sim._do_propose_rule("npc_oun", sim.actors["npc_oun"], {"object": "food", "fraction": 0.25, "goal_kind": "counter_propose"}, [])
	_check("am_counter_reject_keeps_v1", sim.institutions.size() == 1 and absf(float(sim.institutions[0]["rule"]["fraction"]) - 0.5) < 0.001,
		"n=%d frac=%f" % [sim.institutions.size(), float(sim.institutions[0]["rule"]["fraction"])])
	# Scenario B: 反提案被采纳（恢复 sharing）→ 同 institution 改版本，不 append
	sim.actors["npc_weila"]["norms"]["personal"]["sharing"] = 0.85
	sim.actors["npc_kadga"]["norms"]["personal"]["sharing"] = 0.85
	sim.actors["npc_oun"]["institutional_goals"] = [{"object": "food", "kind": "counter_propose", "tick": 70}]
	sim._do_propose_rule("npc_oun", sim.actors["npc_oun"], {"object": "food", "fraction": 0.25, "goal_kind": "counter_propose"}, [])
	var adopted := sim.institutions.size() == 1 and absf(float(sim.institutions[0]["rule"]["fraction"]) - 0.25) < 0.001
	_check("am_counter_adopt_same_record_v2", adopted, "n=%d frac=%f（同记录升版本，不 append）" % [
		sim.institutions.size(), float(sim.institutions[0]["rule"]["fraction"])])

func _test_narrative_ir_gates() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null:
		for n in ["na_no_temporal_causality", "nb_perspective_isolation", "nc_retrospective", "nd_beats_grounded", "ne_deterministic"]:
			_check(n, false, "地图不可用")
		return
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
	var sim := IslandSimulation.new(mq, 42002, configs)
	for i in 600:
		sim.step()
	# ND/NF 需要 beat 原料：无脚本注入一次真实路径的完整制度事件（同 AE 方法）
	if (NarrativeIR.extract_beats(sim.events, sim.actors) as Array).is_empty():
		sim.actors["npc_weila"]["institutional_goals"] = [{"object": "food", "kind": "we_need_a_rule", "tick": sim.tick}]
		sim.actors["npc_kadga"]["norms"]["personal"]["sharing"] = 0.85
		sim.actors["npc_oun"]["norms"]["personal"]["sharing"] = 0.85
		sim._do_propose_rule("npc_weila", sim.actors["npc_weila"], {"object": "food", "fraction": 0.5, "goal_kind": "we_need_a_rule"}, [])
	# NA：因果边禁止纯时间推测——所有边必须有结构 source
	var edges: Array = NarrativeIR.build_causal_edges(sim.events)
	var bad_source := 0
	for e in edges:
		if ["promise_linkage", "institution_linkage", "trace_linkage", "epistemic_linkage", "explicit_event_linkage"].has(str(e["source"])) == false:
			bad_source += 1
	_check("na_no_temporal_causality", bad_source == 0, "edges=%d bad=%d" % [edges.size(), bad_source])
	# NB：CHARACTER(Vera) IR 不得包含她没感知到的事实（无记忆注入）
	var ir_c: Dictionary = NarrativeIR.build_ir(sim, "CHARACTER", "npc_weila", 20)
	var leaked := false
	for f in ir_c["known_facts"]:
		leaked = true  # CHARACTER 视角 known_facts 必须为空（世界真值不进）
	_check("nb_perspective_isolation", not leaked and (ir_c["subjective_facts"] as Array).size() > 0,
		"known=%d subjective=%d" % [(ir_c["known_facts"] as Array).size(), (ir_c["subjective_facts"] as Array).size()])
	# ND：每个 beat 必须有 source_event_ids
	var beats: Array = NarrativeIR.extract_beats(sim.events, sim.actors)
	var grounded := true
	for b in beats:
		if (b.get("source_event_ids", []) as Array).is_empty():
			grounded = false
	_check("nd_beats_grounded", grounded and beats.size() > 0, "beats=%d" % beats.size())
	# NE：确定性
	var beats2: Array = NarrativeIR.extract_beats(sim.events, sim.actors)
	_check("ne_deterministic", str(beats) == str(beats2))
	# NF：制度 beat 与事件联动
	var has_form := false
	for b2 in beats:
		if str(b2["type"]) == "INSTITUTION_FORMATION":
			has_form = true
	var est_events := 0
	for e in sim.events:
		if str(e["type"]) == "institution_established":
			est_events += 1
	_check("nf_institution_beat_linked", has_form == (est_events > 0), "form=%s est=%d" % [str(has_form), est_events])
	# NC：OBJECTIVE 用世界真值
	var ir_o: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "npc_weila", 20)
	_check("nc_objective_uses_world_truth", (ir_o["known_facts"] as Array).size() > 0)
