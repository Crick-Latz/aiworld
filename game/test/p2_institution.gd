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
