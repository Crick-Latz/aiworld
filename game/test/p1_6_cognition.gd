extends SceneTree
## P1.6 验收测试：主动认知与通用社会推理（Phase 1）
## H 认识行动涌现 / I 不确定容忍分化 / J 隐状态隔离 / M 声明≠事实
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/p1_6_cognition.gd

var passed := 0
var failed := 0
var _started := false
var _finished := false

func _initialize() -> void:
	print("P1.6 cognition harness: deferred")

func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _finished

func _run() -> void:
	await _run_all_tests()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	_finished = true
	quit(0 if failed == 0 else 1)

func _check(n: String, c: bool, d: String = "") -> void:
	if c: passed += 1; print("PASS %s" % n)
	else: failed += 1; print("FAIL %s  %s" % [n, d])

func _actor(id: String, trait_overrides: Dictionary, sensitivities := {}) -> Dictionary:
	return {
		"id": id,
		"personality": PersonalityProfile.new(trait_overrides, {}),
		"needs": {"hunger": 300, "thirst": 100, "energy": 900, "social": 100},
		"physical": {"sick": false, "injured": false, "wet": false},
		"inventory": {"food": 0, "wood": 0, "shells": 0},
		"tom": TheoryOfMind.new(),
		"beliefs": BeliefStore.new(),
		"norms": {
			"personal": {"sharing": 0.8, "self_reliance": 0.3, "reciprocity": 0.6},
			"descriptive": {"sharing": 0.5, "reciprocity": 0.5},
			"injunctive": {"sharing": 0.6},
		},
		"memories": [],
		"visited_tiles": {},
		"social_stance": {},
		"grudges": {},
		"sensitivities": sensitivities,
		"open_questions": [],
		"observing": {},
		"claims_received": [],
		"display_name": id,
		"display_names": {},
	}

# ── J. 隐状态隔离：percept 不变 → 决策不变（隐藏真值改变不得影响观察者）──
func _test_j_hidden_state_isolation() -> void:
	# 决策者（欧恩）的 ToM 里对薇拉没有任何 hungry 感知证据
	var decider := _actor("npc_oun", {"altruism": 0.6, "empathy": 0.6})
	decider["inventory"]["food"] = 4
	# 两个提议者：真实饥饿天差地别，但对欧恩不可见（没开口要过、没被看见）
	var proposer_fine := _actor("npc_weila", {})
	proposer_fine["needs"]["hunger"] = 150
	var proposer_starving := _actor("npc_weila", {})
	proposer_starving["needs"]["hunger"] = 950
	var rng1 := RandomNumberGenerator.new(); rng1.seed = 11
	var rng2 := RandomNumberGenerator.new(); rng2.seed = 11
	var seq1 := ""
	var seq2 := ""
	for i in 30:
		var r1: Dictionary = SocialSystem.evaluate_food_request(decider, proposer_fine, 0, rng1)
		var r2: Dictionary = SocialSystem.evaluate_food_request(decider, proposer_starving, 0, rng2)
		seq1 += "1" if bool(r1["accepted"]) else "0"
		seq2 += "1" if bool(r2["accepted"]) else "0"
	_check("j_hidden_hunger_invisible", seq1 == seq2, "%s vs %s" % [seq1, seq2])
	# 对照：一旦薇拉开口要过食物（percept 出现），感知应当影响决策
	var decider2 := _actor("npc_oun", {"altruism": 0.6, "empathy": 0.6})
	decider2["inventory"]["food"] = 4
	decider2["tom"].add_evidence("npc_weila", "hungry", 1.0, 0.6, 1, 10)
	var rng3 := RandomNumberGenerator.new(); rng3.seed = 11
	var accepts_with_percept := 0
	for i in 30:
		if bool(SocialSystem.evaluate_food_request(decider2, proposer_starving, 0, rng3)["accepted"]):
			accepts_with_percept += 1
	var rng4 := RandomNumberGenerator.new(); rng4.seed = 11
	var accepts_blind := 0
	for i in 30:
		if bool(SocialSystem.evaluate_food_request(decider, proposer_starving, 0, rng4)["accepted"]):
			accepts_blind += 1
	_check("j_percept_changes_decision", accepts_with_percept > accepts_blind,
		"with=%d blind=%d" % [accepts_with_percept, accepts_blind])

# ── H. 认识行动涌现：高熵+高利害 → NPC 会去问/看，而不是立刻下结论 ──
func _test_h_epistemic_action_emergence() -> void:
	# 薇拉被拒且解释分布高熵（她不知道欧恩为什么拒绝）
	var vera := _actor("npc_weila", {"empathy": 0.65, "curiosity": 0.75, "conflict_avoidance": 0.3, "expressiveness": 0.85})
	vera["needs"]["hunger"] = 700
	vera["open_questions"] = [{"about": "npc_oun", "kind": "why_refused", "entropy": 0.95, "stakes": 0.75, "tick": 50, "expires": 200}]
	vera["others_visible"] = [{"id": "npc_oun", "tile": Vector2i(3, 0)}, {"id": "npc_kadga", "tile": Vector2i(0, 3)}]
	var world := {"tick": 60, "resources": {"berry_bushes": [], "water_springs": [], "fish_spots": [], "shell_beaches": [], "ruins": []}, "fires": {}}
	var names: Array = []
	for act in ActionRegistry.get_available_actions(vera, world):
		names.append(str(act["action"]))
	_check("h_epistemic_actions_available",
		names.has("ask_reason") and names.has("observe_person") and names.has("ask_third_party"), str(names))
	# Softmax 下认识行动应被真实选中（不是只有Availability）
	var rng := RandomNumberGenerator.new(); rng.seed = 42
	var epistemic_picks := 0
	for i in 40:
		vera["intentions"] = IntentionManager.new()  # 每次重新决策
		var d: Dictionary = DecisionEngine.decide(vera, world, rng)
		if ["ask_reason", "observe_person", "ask_third_party"].has(str(d.get("action", ""))):
			epistemic_picks += 1
	_check("h_epistemic_actions_chosen", epistemic_picks >= 3, "picks=%d/40" % epistemic_picks)
	# 高熵解释不应立刻形成记恨（不确定延迟结论）
	var hostile_interp := {"candidates": [
		{"id": "selfish", "label": "自私", "weight": 0.28},
		{"id": "also_starving", "label": "没粮", "weight": 0.26},
		{"id": "distrusts_me", "label": "不信任", "weight": 0.24},
		{"id": "saving_reserve", "label": "存粮", "weight": 0.22}], "dominant": "selfish"}
	_check("h_entropy_quantified", absf(Interpretation.entropy(hostile_interp) - 1.0) < 0.1,
		str(Interpretation.entropy(hostile_interp)))
	var certain := {"candidates": [
		{"id": "selfish", "label": "自私", "weight": 0.9},
		{"id": "also_starving", "label": "没粮", "weight": 0.1}], "dominant": "selfish"}
	_check("h_certainty_low_entropy", Interpretation.entropy(certain) < 0.5, str(Interpretation.entropy(certain)))
	print("P16_H epistemic_picks=%d/40" % epistemic_picks)

# ── I. 不确定容忍：三个人用三种方式弄清楚（直问/暗看/打听）──
func _test_i_uncertainty_tolerance() -> void:
	var mk := func(traits: Dictionary, id: String) -> Dictionary:
		var a := _actor(id, traits)
		a["needs"]["hunger"] = 650
		a["open_questions"] = [{"about": "npc_oun", "kind": "why_refused", "entropy": 0.9, "stakes": 0.7, "tick": 50, "expires": 300}]
		a["others_visible"] = [{"id": "npc_oun", "tile": Vector2i(3, 0)}, {"id": "npc_kadga", "tile": Vector2i(0, 3)}]
		return a
	# 官方人设：薇拉=好奇+敢问；欧恩=多疑+怕冲突；卡德加=圆融+高社交
	var vera: Dictionary = mk.call({"empathy": 0.65, "curiosity": 0.75, "conflict_avoidance": 0.3, "expressiveness": 0.85, "pragmatism": 0.5, "sociability": 0.6}, "npc_weila")
	var oun: Dictionary = mk.call({"empathy": 0.4, "curiosity": 0.15, "conflict_avoidance": 0.7, "expressiveness": 0.15, "pragmatism": 0.9, "caution": 0.85, "sociability": 0.2}, "npc_oun2")
	oun["sensitivities"] = {"betrayal_sensitivity": 0.5}  # 真实欧恩的 life_history 派生
	var kadga: Dictionary = mk.call({"empathy": 0.8, "curiosity": 0.4, "conflict_avoidance": 0.85, "expressiveness": 0.6, "pragmatism": 0.55, "sociability": 0.85}, "npc_kadga2")
	var world := {"tick": 60, "resources": {"berry_bushes": [], "water_springs": [], "fish_spots": [], "shell_beaches": [], "ruins": []}, "fires": {}}
	var utils_of := func(a: Dictionary) -> Dictionary:
		var out := {}
		for act in ActionRegistry.get_available_actions(a, world):
			var n := str(act["action"])
			if ["ask_reason", "observe_person", "ask_third_party"].has(n):
				out[n] = float(act["utility"])
		return out
	var uv: Dictionary = utils_of.call(vera)
	var uo: Dictionary = utils_of.call(oun)
	var uk: Dictionary = utils_of.call(kadga)
	var best_of := func(u: Dictionary) -> String:
		var best := ""
		var bv := -1.0
		for k in u:
			if float(u[k]) > bv:
				bv = float(u[k])
				best = str(k)
		return best
	_check("i_vera_asks_directly", best_of.call(uv) == "ask_reason", str(uv))
	_check("i_oun_observes_secretly", best_of.call(uo) == "observe_person", str(uo))
	_check("i_kadga_asks_third_party", best_of.call(uk) == "ask_third_party", str(uk))
	# 务实到不在乎的人：根本不产生认识行动（「不弄清楚」是合法选择）
	var pragmatist: Dictionary = mk.call({"pragmatism": 1.0, "curiosity": 0.1, "conflict_avoidance": 0.5, "expressiveness": 0.3, "sociability": 0.3}, "npc_prag")
	var up: Dictionary = utils_of.call(pragmatist)
	_check("i_pragmatist_does_not_care", up.is_empty(), str(up))
	print("P16_I vera=%s oun=%s kadga=%s pragmatist=%s" % [str(uv), str(uo), str(uk), str(up)])

# ── M. 声明≠事实：说「我没粮」不等于真没粮，听者只按可靠度部分采信 ──
func _test_m_claim_not_truth() -> void:
	var vera := _actor("npc_weila", {"empathy": 0.65})
	var rs := RelationshipStore.new()
	# 欧恩其实有粮（inv=4），却声称「我自己也没粮了」
	var oun_inv := 4
	var claim_prop := {"subject": "npc_oun", "predicate": "has_food", "value": -0.8, "label": "我自己也没粮了"}
	var claim := Claim.build("npc_oun", claim_prop, 60)
	var result: Dictionary = Claim.listen(vera, claim, rs)
	# 薇拉不能直接知道他撒谎：信念只是部分移动，绝不是确信他没粮
	var after: float = vera["tom"].raw_belief("npc_oun", "has_food")
	_check("m_claim_partial_belief", after > -0.6 and after < 0.0,
		"after=%f (真实inv=%d)" % [after, oun_inv])
	_check("m_claim_weight_bounded", float(result["weight"]) <= 0.9 and float(result["weight"]) >= 0.05,
		str(result["weight"]))
	# 声明被归档且真诚度未知——未来可被反证推翻
	var archived: Array = vera["claims_received"]
	_check("m_claim_archived", archived.size() == 1 and bool(archived[0].get("weight", 0) > 0), str(archived))
	# 说话者可靠度高 → 采信权重更大（对比）
	var vera2 := _actor("npc_weila", {})
	vera2["tom"].add_evidence("npc_kadga", "reliable", 1.0, 0.6, 1, 10)
	vera2["tom"].add_evidence("npc_kadga", "reliable", 1.0, 0.6, 2, 11)
	var claim2 := Claim.build("npc_kadga", {"subject": "npc_oun", "predicate": "has_food", "value": -0.8, "label": "他没粮"}, 61)
	var result2: Dictionary = Claim.listen(vera2, claim2, rs)
	_check("m_reliable_speaker_weighed_more", float(result2["weight"]) > float(result["weight"]),
		"reliable=%f stranger=%f" % [float(result2["weight"]), float(result["weight"])])

func _run_all_tests() -> void:
	_test_j_hidden_state_isolation()
	_test_h_epistemic_action_emergence()
	_test_i_uncertainty_tolerance()
	_test_m_claim_not_truth()
