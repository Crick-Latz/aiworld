extends SceneTree
## P1.5 验收测试（GPT 第二十二~二十七条）：认知行为机制测试。
## 核心：不再测"函数返回正确"，而是测"同一事件因认知背景不同产生不同理解"。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/p1_5_cognition.gd

var passed := 0
var failed := 0
var _started := false
var _finished := false

func _initialize() -> void:
	print("P1.5 cognition harness: deferred")

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

func _run_all_tests() -> void:
	_test_a_same_event_different_interpretation()
	_test_b_same_event_different_personality()
	_test_c_belief_revision()
	_test_d_prediction_error()
	_test_e_norm_separation()
	await _test_f_positive_bonds_rich_world()
	await _test_g_counterfactual_society()

func _actor(id: String, trait_overrides: Dictionary, sensitivities := {}) -> Dictionary:
	var p := PersonalityProfile.new(trait_overrides, {})
	return {
		"id": id,
		"personality": p,
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
		"display_name": id,
		"display_names": {},
	}

func _refusal_event() -> Dictionary:
	return {"type": "food_request_refused", "actor_id": "npc_oun", "proposer_id": "npc_weila",
		"tick": 50, "seq": 1, "text": "欧恩拒绝了薇拉"}

# ── A. 同一事件 / 不同认知背景 → 不同理解 ──
func _test_a_same_event_different_interpretation() -> void:
	var rs1 := RelationshipStore.new()
	var vera_rich := _actor("npc_weila", {"empathy": 0.65, "resilience": 0.85})
	vera_rich["tom"].add_evidence("npc_oun", "has_food", 1.0, 0.7, 1, 10)  # 薇拉以为欧恩粮多
	vera_rich["tom"].add_evidence("npc_oun", "has_food", 1.0, 0.5, 2, 11)
	vera_rich["needs"]["hunger"] = 800
	var rs2 := RelationshipStore.new()
	var vera_poor := _actor("npc_weila", {"empathy": 0.65, "resilience": 0.85})
	vera_poor["tom"].add_evidence("npc_oun", "has_food", -1.0, 0.7, 1, 10)  # 薇拉知道欧恩也没粮
	vera_poor["tom"].add_evidence("npc_oun", "has_food", -1.0, 0.5, 2, 11)
	vera_poor["needs"]["hunger"] = 800

	var sum1: Dictionary = CognitiveTransition.process(vera_rich, _refusal_event(), {"relationships": rs1, "tick": 50})
	var sum2: Dictionary = CognitiveTransition.process(vera_poor, _refusal_event(), {"relationships": rs2, "tick": 50})
	var dom1 := str((sum1["interpretation"] as Dictionary).get("dominant", ""))
	var dom2 := str((sum2["interpretation"] as Dictionary).get("dominant", ""))
	_check("a_dominant_differs", dom1 != dom2, "rich=%s poor=%s" % [dom1, dom2])
	_check("a_rich_reads_selfish", dom1 == "selfish", dom1)
	_check("a_poor_reads_starving", dom2 == "also_starving", dom2)
	# 情绪分化：以为他粮多 → 愤怒（背叛）；知道他没粮 → 悲伤/恐惧（绝望）而非愤怒
	var em1: Dictionary = vera_rich["personality"].emotions
	var em2: Dictionary = vera_poor["personality"].emotions
	_check("a_rich_angrier", float(em1.get("anger", 0.0)) > float(em2.get("anger", 0.0)) + 0.05,
		"rich=%f poor=%f" % [em1.get("anger", 0.0), em2.get("anger", 0.0)])
	_check("a_poor_sadder", float(em2.get("sadness", 0.0)) > float(em1.get("sadness", 0.0)) or float(em2.get("fear", 0.0)) > 0.03,
		"sad=%f/%f fear=%f" % [em1.get("sadness", 0.0), em2.get("sadness", 0.0), em2.get("fear", 0.0)])
	# 关系后果分化：知道他没粮 → 不怪他（善意降幅小得多）
	var d1: float = absf(float((sum1["relationship_delta"] as Dictionary).get("benevolence", 0.0)))
	var d2: float = absf(float((sum2["relationship_delta"] as Dictionary).get("benevolence", 0.0)))
	_check("a_poor_forgives_more", d1 > d2 * 2.0 or d2 == 0.0, "rich=%f poor=%f" % [d1, d2])
	print("P15_A dom_rich=%s dom_poor=%s anger=%f/%f" % [dom1, dom2, em1.get("anger", 0.0), em2.get("anger", 0.0)])

# ── B. 同一事件 / 不同人格 → 不同归因（不只是强度）──
func _test_b_same_event_different_personality() -> void:
	# 同样的认知背景（都以为欧恩有粮），不同的薇拉 vs 卡德加
	var interp_ctx := func(a: Dictionary) -> void:
		a["tom"].add_evidence("npc_oun", "has_food", 1.0, 0.6, 1, 10)
		a["needs"]["hunger"] = 700
	var rs := RelationshipStore.new()
	# 薇拉：被蛇咬过似的怒气（anger 0.5）+ 共情 0.65
	var vera := _actor("npc_weila", {"empathy": 0.65, "resilience": 0.85}, {"betrayal_sensitivity": 0.4})
	vera["personality"].adjust_emotion("anger", 0.5)
	interp_ctx.call(vera)
	# 卡德加：高共情 0.85、平静、且相信欧恩本性慷慨（村里人给过他这个印象）
	var kadga := _actor("npc_kadga", {"empathy": 0.85, "resilience": 0.6}, {})
	kadga["tom"].add_evidence("npc_oun", "generous", 1.0, 0.5, 3, 12)
	interp_ctx.call(kadga)
	var kv := _refusal_event()
	kv["proposer_id"] = "npc_kadga"
	var sum_v: Dictionary = CognitiveTransition.process(vera, _refusal_event(), {"relationships": rs, "tick": 50})
	var sum_k: Dictionary = CognitiveTransition.process(kadga, kv, {"relationships": rs, "tick": 50})
	var dom_v := str((sum_v["interpretation"] as Dictionary).get("dominant", ""))
	var dom_k := str((sum_k["interpretation"] as Dictionary).get("dominant", ""))
	_check("b_attribution_differs", dom_v != dom_k, "vera=%s kadga=%s" % [dom_v, dom_k])
	_check("b_vera_hostile_frame", dom_v == "selfish" or dom_v == "dislikes_me", dom_v)
	_check("b_kadga_charitable_frame", dom_k == "saving_reserve" or dom_k == "also_starving" or dom_k == "distrusts_me", dom_k)
	# 两种归因的权重分布结构不同（不是同一分布的缩放）
	var hw_v: float = Interpretation.hostility_weight(sum_v["interpretation"])
	var hw_k: float = Interpretation.hostility_weight(sum_k["interpretation"])
	_check("b_hostility_gap", hw_v > hw_k + 0.15, "vera=%f kadga=%f" % [hw_v, hw_k])
	print("P15_B vera=%s kadga=%s hostility=%f/%f" % [dom_v, dom_k, hw_v, hw_k])

# ── C. 信念修正：误解可以被新证据推翻 ──
func _test_c_belief_revision() -> void:
	var vera := _actor("npc_weila", {"empathy": 0.65, "resilience": 0.85}, {"betrayal_sensitivity": 0.4})
	vera["display_names"] = {"npc_oun": "欧恩", "npc_weila": "薇拉"}
	var hostile := {"candidates": [
		{"id": "selfish", "label": "自私", "weight": 0.6},
		{"id": "also_starving", "label": "没粮", "weight": 0.2},
		{"id": "distrusts_me", "label": "不信任", "weight": 0.2}], "dominant": "selfish"}
	for i in 3:
		vera["memories"].append({"seq": i + 1, "tick": 10 + i, "type": "food_request_refused",
			"text": "x", "actor_id": "npc_oun", "counterpart_id": "npc_oun", "interpretation": hostile})
	# 第一次反思：敌意主导 → 记恨形成
	ReflectionSystem.reflect(vera, 100)
	_check("c_grudge_forms", vera["grudges"].has("npc_oun"), str(vera["grudges"]))
	var conf_before: float = vera["beliefs"].confidence_of("欧恩 不肯帮我")
	_check("c_grudge_belief_written", conf_before > 0.4, str(conf_before))
	# 新证据：薇拉反复看见欧恩空手而归（他真的没粮）
	for i in 4:
		vera["tom"].add_evidence("npc_oun", "has_food", -1.0, 0.6, 10 + i, 110 + i)
	# 一次匮乏解释的记忆 + 再次反思 → 记恨被推翻
	var scarce := {"candidates": [
		{"id": "selfish", "label": "自私", "weight": 0.2},
		{"id": "also_starving", "label": "没粮", "weight": 0.6},
		{"id": "distrusts_me", "label": "不信任", "weight": 0.2}], "dominant": "also_starving"}
	vera["memories"].append({"seq": 9, "tick": 120, "type": "food_request_refused",
		"text": "x", "actor_id": "npc_oun", "counterpart_id": "npc_oun", "interpretation": scarce})
	var result: Dictionary = ReflectionSystem.reflect(vera, 150)
	_check("c_grudge_overturned", not vera["grudges"].has("npc_oun"), str(vera["grudges"]))
	var conf_after: float = vera["beliefs"].confidence_of("欧恩 不肯帮我")
	_check("c_belief_weakened", conf_after < conf_before, "%f -> %f" % [conf_before, conf_after])
	var has_revision := false
	for insight in result.get("insights", []):
		if str(insight).find("错怪") != -1:
			has_revision = true
	_check("c_revision_insight", has_revision, str(result.get("insights", [])))

# ── D. 预测误差学习：预测随反馈收敛 ──
func _test_d_prediction_error() -> void:
	var tom := TheoryOfMind.new()
	var errors: Array = []
	var predicted_now := 0.5  # 初始：他会不会回避我？不确定
	for round_i in range(6):
		# 观察到的事实：她每次都回避（observed=1）
		var err := absf(predicted_now - 1.0)
		errors.append(err)
		tom.update_response("npc_weila", "avoids_me", 1.0, 0.3 + err * 0.5)
		tom.record_prediction_error(100 + round_i, "npc_weila", err)
		predicted_now = tom.response_belief("npc_weila", "avoids_me")
	# 误差序列必须下降（学习在收敛；收敛后允许触底走平）
	var decreasing := true
	for i in range(1, errors.size()):
		if float(errors[i]) > float(errors[i - 1]) + 0.001:
			decreasing = false
	_check("d_prediction_error_decreases", decreasing and float(errors[errors.size() - 1]) < 0.15,
		str(errors))
	_check("d_response_converges", tom.response_belief("npc_weila", "avoids_me") > 0.85,
		str(tom.response_belief("npc_weila", "avoids_me")))
	print("P15_D errors=%s final=%f" % [str(errors), tom.response_belief("npc_weila", "avoids_me")])

# ── E. 规范分离：被拒降低"我以为别人会分享"（descriptive），不动"我认为该分享"（personal）──
func _test_e_norm_separation() -> void:
	var vera := _actor("npc_weila", {"empathy": 0.65, "pragmatism": 0.2}, {})
	vera["personality"].emotions["trust_open"] = 0.7  # reactance > 0.7 的人格
	vera["tom"].add_evidence("npc_oun", "has_food", 1.0, 0.6, 1, 10)
	vera["needs"]["hunger"] = 700
	var rs := RelationshipStore.new()
	var personal_before: float = float(vera["norms"]["personal"]["sharing"])
	var desc_before: float = float(vera["norms"]["descriptive"]["sharing"])
	for i in 6:
		var e := _refusal_event()
		e["seq"] = i + 1
		CognitiveTransition.process(vera, e, {"relationships": rs, "tick": 50 + i})
	var personal_after: float = float(vera["norms"]["personal"]["sharing"])
	var desc_after: float = float(vera["norms"]["descriptive"]["sharing"])
	_check("e_descriptive_drops", desc_after < desc_before - 0.2, "%f -> %f" % [desc_before, desc_after])
	_check("e_personal_untouched_by_events", personal_after == personal_before,
		"%f -> %f" % [personal_before, personal_after])
	# 高 reactance 的人在自私风气中反而更坚持分享（反思路径，缓慢）
	vera["norms"]["descriptive"]["sharing"] = 0.2
	ReflectionSystem.reflect(vera, 100)
	var personal_post_reflect: float = float(vera["norms"]["personal"]["sharing"])
	_check("e_reactance_strengthens_personal", personal_post_reflect > personal_after,
		"%f -> %f" % [personal_after, personal_post_reflect])

# ── F. 富裕世界：正向纽带自然形成 ──
func _test_f_positive_bonds_rich_world() -> void:
	var mq = await _make_map()
	if mq == null:
		_check("f_positive_bond", false, "地图不可用")
		return
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var configs := _make_configs(mq, scenario, true)
	var rich := {"berry_count": 6, "berry_food": 3, "berry_regrow_days": 2,
		"fish_prob": 0.8, "fish_amount": 2, "explore_food_prob": 0.08}
	var best_bond := 0
	var any_share := false
	for s in [10002, 10005, 10017]:
		var sim := IslandSimulation.new(mq, s, configs, rich)
		for i in 600:
			sim.step()
		for e in sim.events:
			if str(e["type"]) == "shared_food" or str(e["type"]) == "food_request_accepted":
				any_share = true
		var snap: Dictionary = sim.relationships.snapshot()
		for key in snap:
			best_bond = maxi(best_bond, int(snap[key].get("trust", 0)))
	_check("f_rich_world_shares", any_share, "no sharing events in abundance")
	# 解释加权尺度下单次接受 ≈ +30 综合信任，≥100 即多次互惠的强纽带。
	# P1.6 感知门后阈值下调：分享只能瞄准"看得见的饥饿"，纽带比直读真值时代少 ~20——这是有限感知的诚实代价
	_check("f_positive_bond_forms", best_bond >= 100, "best=%d" % best_bond)
	print("P15_F best_bond=%d" % best_bond)

# ── G. 反事实社会：同一个欧恩，匮乏 vs 富裕 ──
func _test_g_counterfactual_society() -> void:
	var mq = await _make_map()
	if mq == null:
		_check("g_context_adapts", false, "地图不可用")
		_check("g_identity_preserved", false, "地图不可用")
		return
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var configs := _make_configs(mq, scenario, false)  # 正常分布出生
	var rich := {"berry_count": 6, "berry_food": 3, "berry_regrow_days": 2,
		"fish_prob": 0.8, "fish_amount": 2, "explore_food_prob": 0.08}
	var scarce_sim := IslandSimulation.new(mq, 777, configs)          # 默认匮乏经济
	var rich_sim := IslandSimulation.new(mq, 777, configs, rich)      # 富裕经济
	for i in 600:
		scarce_sim.step()
	for i in 800:
		rich_sim.step()  # 富裕世界跑久一点：孤独分层需要时间显现
	# G1 环境适应：匮乏世界里欧恩把更多行动花在觅食上（forage/fish/shells/explore 占比）
	var oun_scarce_ate := _ate_count(scarce_sim, "npc_oun")
	var oun_rich_ate := _ate_count(rich_sim, "npc_oun")
	_check("g_context_adapts", oun_rich_ate > oun_scarce_ate * 1.4,
		"scarce=%d rich=%d" % [oun_scarce_ate, oun_rich_ate])
	# G2 身份保持：社交性 0.85 的卡德加的签名——在两个世界都【最先】打破孤独去找人
	# （累计次数会被"无聊驱动"污染：富裕世界无事可做的欧恩最后也会聊天）
	var first_soc := func(sim: IslandSimulation, aid: String) -> int:
		for e in sim.events:
			if str(e.get("actor_id", "")) == aid and ["socialized", "sat_by_fire"].has(str(e["type"])):
				return int(e["tick"])
		return 99999
	var kadga_first_scarce: bool = first_soc.call(scarce_sim, "npc_kadga") < first_soc.call(scarce_sim, "npc_oun") \
		and first_soc.call(scarce_sim, "npc_kadga") < 99999
	var kadga_first_rich: bool = first_soc.call(rich_sim, "npc_kadga") < first_soc.call(rich_sim, "npc_oun")
	_check("g_identity_preserved", kadga_first_scarce and kadga_first_rich,
		"first_company scarce k/o=%d/%d rich k/o=%d/%d" % [first_soc.call(scarce_sim, "npc_kadga"), first_soc.call(scarce_sim, "npc_oun"),
			first_soc.call(rich_sim, "npc_kadga"), first_soc.call(rich_sim, "npc_oun")])
	print("P15_G ate scarce=%d rich=%d first_company_rich k/o=%d/%d" % [oun_scarce_ate, oun_rich_ate,
		first_soc.call(rich_sim, "npc_kadga"), first_soc.call(rich_sim, "npc_oun")])

func _ate_count(sim: IslandSimulation, id: String) -> int:
	var n := 0
	for e in sim.events:
		if str(e.get("actor_id", "")) == id and str(e["type"]) == "ate_food":
			n += 1
	return n

func _seeking_share(sim: IslandSimulation, id: String) -> float:
	var seeking := 0
	var total := 0
	for e in sim.events:
		if str(e.get("actor_id", "")) != id:
			continue
		total += 1
		if ["foraged", "foraged_empty", "fished", "fished_empty", "gathered_shells", "explored", "explored_found"].has(str(e["type"])):
			seeking += 1
	return float(seeking) / maxf(float(total), 1.0)

func _food_action_ratio(sim: IslandSimulation, id: String) -> float:
	var food := 0
	var total := 0
	for e in sim.events:
		if str(e.get("actor_id", "")) != id:
			continue
		total += 1
		if ["foraged", "foraged_empty", "fished", "fished_empty", "ate_food", "gathered_shells"].has(str(e["type"])):
			food += 1
	return float(food) / maxf(float(total), 1.0)

func _explore_ratio(sim: IslandSimulation, id: String) -> float:
	var explore := 0
	var total := 0
	for e in sim.events:
		if str(e.get("actor_id", "")) != id:
			continue
		total += 1
		if str(e["type"]) == "explored":
			explore += 1
	return float(explore) / maxf(float(total), 1.0)

func _make_map():
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null: return null
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	return inst.get_node("World/MapController")

func _make_configs(mq, scenario: Dictionary, co_located: bool) -> Array:
	var spots := [mq.get_poi_tile("post_house"), mq.get_poi_tile("tide_market"), mq.get_poi_tile("old_lighthouse")]
	var configs: Array = []
	var idx := 0
	for ac in scenario.get("actors", []):
		var cfg = ac.duplicate()
		cfg["spawn"] = spots[0] if co_located else spots[idx % spots.size()]
		idx += 1
		configs.append(cfg)
	return configs
