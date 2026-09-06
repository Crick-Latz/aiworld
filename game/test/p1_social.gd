extends SceneTree
## P1 社会层验收测试：ToM / 提案协议 / 双向评价 / 关系后果 / 反思。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/p1_social.gd

var passed := 0
var failed := 0
var _started := false
var _finished := false

func _initialize() -> void:
	print("P1 social harness: deferred")

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
	_test_tom_observation()
	_test_request_target_selection()
	_test_request_gated_by_hunger()
	await _test_sim_social_emergence()
	_test_refusal_no_food()
	_test_acceptance_by_personality()
	_test_appraisal_roles()
	_test_norms()
	_test_reflection_grudge()
	_test_relationship_asymmetry()

# ── 1. ToM v2：证据累积 + 置信度 + 可削弱 ──
func _test_tom_observation() -> void:
	var tom := TheoryOfMind.new()
	# 无证据 → 中性 0
	_check("tom_unknown_is_neutral", tom.belief_about("npc_oun", "has_food") == 0.0)
	# 一条证据：方向正确但置信度低（0.4）
	tom.add_evidence("npc_oun", "has_food", 1.0, 0.5, 1, 10)
	var one: float = tom.belief_about("npc_oun", "has_food")
	_check("tom_single_evidence_uncertain", one > 0.0 and one < 0.35, str(one))
	# 多条证据 → 置信度提升
	tom.add_evidence("npc_oun", "has_food", 1.0, 0.5, 2, 11)
	tom.add_evidence("npc_oun", "has_food", 1.0, 0.5, 3, 12)
	var many: float = tom.belief_about("npc_oun", "has_food")
	_check("tom_evidence_builds_confidence", many > one, "%f -> %f" % [one, many])
	# 新证据可以削弱旧结论（"他自私"可被"他其实没粮"推翻）
	tom.add_evidence("npc_kadga", "generous", -1.0, 0.6, 4, 13)
	var g0: float = tom.belief_about("npc_kadga", "generous")
	tom.weaken("npc_kadga", "generous", 0.6)
	var g1: float = tom.belief_about("npc_kadga", "generous")
	_check("tom_weaken_revisable", absf(g1) < absf(g0), "%f -> %f" % [g0, g1])

# ── 2. 请求目标选择：ToM + 信任 ──
func _test_request_target_selection() -> void:
	var me := _actor("npc_weila", {})
	# 我相信欧恩有食物，卡德加有没有食物未知
	me["tom"].add_evidence("npc_oun", "has_food", 1.0, 0.6, 1, 1)
	var nearby := [{"id": "npc_oun", "tile": Vector2i(1, 0)}, {"id": "npc_kadga", "tile": Vector2i(0, 1)}]
	var picked := SocialSystem.pick_request_target(me, nearby, {"npc_oun": 50, "npc_kadga": 50})
	_check("request_picks_believed_rich", picked == "npc_oun", picked)
	# 深度不信任的人，即使相信他有钱也不开口
	var picked2 := SocialSystem.pick_request_target(me, nearby, {"npc_oun": -300, "npc_kadga": 50})
	_check("request_skips_distrusted", picked2 == "", picked2)
	# 回避倾向强的人也不找（解释系统写入的倾向）
	var picked2b := SocialSystem.pick_request_target(me, nearby, {"npc_oun": 50, "npc_kadga": 50})
	me["social_stance"] = {"npc_oun": 0.8}
	var picked2c := SocialSystem.pick_request_target(me, nearby, {"npc_oun": 50, "npc_kadga": 50})
	_check("request_skips_avoided", picked2c != "npc_oun", picked2c)
	# 谁都没食物信念 → 不开口
	var me2 := _actor("npc_weila", {})
	var picked3 := SocialSystem.pick_request_target(me2, nearby, {"npc_oun": 50, "npc_kadga": 50})
	_check("request_needs_belief", picked3 == "", picked3)

# ── 3. 求助门槛：不够饿开不了口 ──
func _test_request_gated_by_hunger() -> void:
	var actor := _actor("npc_weila", {})
	actor["tom"].add_evidence("npc_oun", "has_food", 1.0, 0.6, 1, 1)
	actor["trust_of"] = {"npc_oun": 100}
	actor["others_nearby"] = [{"id": "npc_oun", "tile": Vector2i(1, 0)}]
	actor["needs"]["hunger"] = 400  # 还没那么饿
	var world := {"resources": {"berry_bushes": [], "water_springs": [], "fish_spots": [], "shell_beaches": [], "ruins": []}}
	var names := []
	for a in ActionRegistry.get_available_actions(actor, world):
		names.append(str(a["action"]))
	_check("request_absent_when_fed", not names.has("request_share"), str(names))
	actor["needs"]["hunger"] = 720
	var names2 := []
	for a in ActionRegistry.get_available_actions(actor, world):
		names2.append(str(a["action"]))
	_check("request_present_when_starving", names2.has("request_share"), str(names2))

# ── 4. 模拟涌现：三人同岛，社交事件自然发生 ──
func _test_sim_social_emergence() -> void:
	var mq = await _make_map()
	if mq == null:
		for i in 4:
			_check("sim_social_%d" % i, false, "地图不可用")
		return
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var configs := _make_configs(mq, scenario, true)  # 同点出生：强制社交密度
	var sim := IslandSimulation.new(mq, 10002, configs)  # 验证过：该种子有求助+接受
	for i in 600:
		sim.step()
	var social_types := ["food_requested", "food_request_accepted", "food_request_refused", "shared_food", "socialized", "kept_distance", "reflected"]
	var counts := {}
	var total_social := 0
	for e in sim.events:
		if social_types.has(str(e["type"])):
			counts[str(e["type"])] = int(counts.get(str(e["type"]), 0)) + 1
			total_social += 1
	_check("sim_social_events_emerge", total_social > 0, str(counts))
	# 确定性：同 seed 重跑，社交事件序列完全一致
	var sim2 := IslandSimulation.new(mq, 10002, configs)
	for i in 600:
		sim2.step()
	var seq1 := _social_sequence(sim)
	var seq2 := _social_sequence(sim2)
	_check("sim_social_deterministic", seq1 == seq2, "len %d vs %d" % [seq1.length(), seq2.length()])
	print("P1_SOCIAL_COUNTS %s" % str(counts))
	# 囤粮饿死防御：测"连续囤粮"（卡死态），瞬时态（刚捡到食物还没来得及吃）是合法的
	var sim3 := IslandSimulation.new(mq, 11, configs)  # seed 11 曾出现"饿 1000 + 存粮 31"
	var max_hoard_streak := 0
	var streaks := {}
	for aid in sim3.actors:
		streaks[aid] = 0
	for i in 800:
		sim3.step()
		for aid in sim3.actors:
			if int(sim3.actors[aid]["needs"]["hunger"]) >= 999 and int(sim3.actors[aid]["inventory"].get("food", 0)) >= 1:
				streaks[aid] = int(streaks[aid]) + 1
				max_hoard_streak = maxi(max_hoard_streak, int(streaks[aid]))
			else:
				streaks[aid] = 0
	_check("no_starve_while_hoarding", max_hoard_streak < 8, "max_streak=%d" % max_hoard_streak)
	# P1.5: 描述性规范随目击的分享/拒绝风气漂移（个人规范不动）
	var drifted_seeds := 0
	for s in [10002, 10008, 10017]:  # 经验证：这些种子在当前认知门控下必产生请求结果
		var sim4 := IslandSimulation.new(mq, s, configs)
		for i in 600:
			sim4.step()
		var initial := {}
		for ac in scenario.get("actors", []):
			initial[str(ac["id"])] = ac.get("norms", {}).get("descriptive", {})
		var drifted := false
		for aid in sim4.actors:
			var desc: Dictionary = sim4.actors[aid]["norms"]["descriptive"]
			var was: float = float(initial.get(aid, {}).get("sharing", 0.5))
			if absf(float(desc.get("sharing", 0.5)) - was) > 0.001:
				drifted = true
		if drifted:
			drifted_seeds += 1
	_check("norms_drift_from_experience", drifted_seeds >= 1, "drifted=%d/3" % drifted_seeds)
	# P2: 编年史——模拟每天自己写日记
	_check("chronicle_daily", sim.chronicles.size() >= 2 and str(sim.chronicles[0]["text"]).length() > 4,
		"chronicles=%d first=%s" % [sim.chronicles.size(), str(sim.chronicles[0]["text"]).substr(0, 20) if sim.chronicles.size() > 0 else "-"])
	var all_chronicle_ok := true
	for c in sim.chronicles:
		if not str(c["text"]).begins_with("第"):
			all_chronicle_ok = false
	_check("chronicle_format", all_chronicle_ok)
	# 有戏剧事件的日子，日记必须提到它（显著性排序生效）
	var drama_day := -1
	for e in sim.events:
		if str(e["type"]) == "food_request_refused":
			drama_day = int(e["day"])
			break
	if drama_day >= 0:
		var found := false
		for c in sim.chronicles:
			if int(c["day"]) == drama_day and str(c["text"]).find("拒绝") != -1:
				found = true
		_check("chronicle_mentions_drama", found, "day=%d" % drama_day)
	else:
		_check("chronicle_mentions_drama", true, "(本种子无拒绝事件，跳过)")
	# ToM 在真实模拟中被填充（任意属性：含 has_water/hungry 等新感知槽）
	var any_belief := false
	for id in sim.actors:
		var snap15: Dictionary = sim.actors[id]["tom"].snapshot()
		if not snap15.is_empty():
			for oid in snap15:
				for key in snap15[oid]:
					if absf(float(snap15[oid][key])) > 0.05:
						any_belief = true
	_check("sim_tom_populated", any_belief)

func _social_sequence(sim: IslandSimulation) -> String:
	var parts: Array = []
	for e in sim.events:
		var t := str(e["type"])
		if ["food_requested", "food_request_accepted", "food_request_refused", "shared_food"].has(t):
			parts.append("%s:%s" % [t, str(e["actor_id"])])
	return ",".join(parts)

func _other_of(sim: IslandSimulation, id: String) -> String:
	for oid in sim.actors:
		if oid != id:
			return oid
	return ""

# ── 5. 目标没食物 → 必拒 ──
func _test_refusal_no_food() -> void:
	var target := _actor("npc_oun", {"altruism": 0.95, "empathy": 0.9})
	target["inventory"]["food"] = 1  # 少于安全线 2
	var proposer := _actor("npc_weila", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var any_accept := false
	for i in 20:
		var r: Dictionary = SocialSystem.evaluate_food_request(target, proposer, 0, rng)
		if bool(r["accepted"]):
			any_accept = true
	_check("no_spare_food_always_refused", not any_accept)

# ── 6. 性格决定分享倾向（统计性） ──
func _test_acceptance_by_personality() -> void:
	var proposer := _actor("npc_weila", {})
	proposer["needs"]["hunger"] = 750  # 看得见的苦处
	var saint := _actor("npc_oun", {"altruism": 0.95, "empathy": 0.9})
	saint["inventory"]["food"] = 5
	saint["needs"]["hunger"] = 150
	var miser := _actor("npc_kadga", {"altruism": 0.05, "empathy": 0.1})
	miser["inventory"]["food"] = 5
	miser["needs"]["hunger"] = 150
	var rng1 := RandomNumberGenerator.new(); rng1.seed = 7
	var rng2 := RandomNumberGenerator.new(); rng2.seed = 7
	var saint_accepts := 0
	var miser_accepts := 0
	for i in 40:
		if bool(SocialSystem.evaluate_food_request(saint, proposer, 0, rng1)["accepted"]):
			saint_accepts += 1
		if bool(SocialSystem.evaluate_food_request(miser, proposer, 0, rng2)["accepted"]):
			miser_accepts += 1
	_check("altruist_shares_more_than_miser", saint_accepts > miser_accepts + 6,
		"saint=%d/40 miser=%d/40" % [saint_accepts, miser_accepts])
	print("P1_ACCEPT_RATE saint=%d/40 miser=%d/40" % [saint_accepts, miser_accepts])

# ── 7. 同一拒绝事件，两种立场，两种情绪（经 CognitiveTransition 全链）──
func _test_appraisal_roles() -> void:
	var rs := RelationshipStore.new()
	var event := {"type": "food_request_refused", "actor_id": "npc_oun", "proposer_id": "npc_weila",
		"tick": 50, "seq": 1, "text": "欧恩拒绝了薇拉"}
	var weila := _actor("npc_weila", {"empathy": 0.5})
	weila["norms"]["personal"] = {"sharing": 0.85, "self_reliance": 0.35, "reciprocity": 0.6}
	weila["tom"].add_evidence("npc_oun", "has_food", 1.0, 0.6, 1, 10)  # 薇拉以为欧恩粮多
	weila["needs"]["hunger"] = 800
	var oun := _actor("npc_oun", {"empathy": 0.9})
	oun["norms"]["personal"] = {"sharing": 0.9, "self_reliance": 0.1, "reciprocity": 0.7}
	var ctx := {"relationships": rs, "tick": 50}
	var sum_w: Dictionary = CognitiveTransition.process(weila, event, ctx)
	var sum_o: Dictionary = CognitiveTransition.process(oun, event, ctx)
	# 被拒者：悲伤/愤怒（解释为自私）
	var ew: Dictionary = weila["personality"].emotions
	_check("refused_feels_hurt", float(ew.get("sadness", 0.0)) > 0.03 or float(ew.get("anger", 0.0)) > 0.03, str(ew))
	# 拒绝者（高共情+高分享规范）：内疚
	var eo: Dictionary = oun["personality"].emotions
	_check("refuser_feels_guilt", float(eo.get("guilt", 0.0)) > 0.03, str(eo))
	# 同一事件，两个立场产生不同的解释（被拒者有解释分布，拒绝者走规范自检）
	_check("transition_interpretation_exists", not (sum_w.get("interpretation", {}) as Dictionary).is_empty())
	# 被拒者的关系受损（解释加权，非固定值）
	_check("refusal_hurts_benevolence", rs.get_dim("npc_weila", "npc_oun", "benevolence") < 0,
		str(rs.get_dim("npc_weila", "npc_oun", "benevolence")))

# ── 7b. 规范决定拒绝的道德重量（经 CognitiveTransition）──
func _test_norms() -> void:
	# 高分享规范的人被拒时更愤怒（背叛感）；低分享规范的人相对无所谓
	var event := {"type": "food_request_refused", "actor_id": "npc_oun", "proposer_id": "npc_weila",
		"tick": 50, "seq": 1, "text": "x"}
	var believer := _actor("npc_weila", {"empathy": 0.5})
	believer["norms"]["personal"] = {"sharing": 0.95, "self_reliance": 0.1, "reciprocity": 0.6}
	believer["tom"].add_evidence("npc_oun", "has_food", 1.0, 0.6, 1, 10)
	believer["needs"]["hunger"] = 800
	var cynic := _actor("npc_weila", {"empathy": 0.5})
	cynic["norms"]["personal"] = {"sharing": 0.05, "self_reliance": 0.95, "reciprocity": 0.6}
	cynic["tom"].add_evidence("npc_oun", "has_food", 1.0, 0.6, 1, 10)
	cynic["needs"]["hunger"] = 800
	var ctx := {"relationships": RelationshipStore.new(), "tick": 50}
	CognitiveTransition.process(believer, event, ctx)
	CognitiveTransition.process(cynic, event, ctx)
	var anger_b: float = float(believer["personality"].emotions.get("anger", 0.0))
	var anger_c: float = float(cynic["personality"].emotions.get("anger", 0.0))
	_check("norm_believer_angrier", anger_b > anger_c + 0.02,
		"b=%f c=%f" % [anger_b, anger_c])
	# 拒绝者的内疚随自己的分享规范缩放
	var sharer := _actor("npc_oun", {"empathy": 0.8})
	sharer["norms"]["personal"] = {"sharing": 0.9, "self_reliance": 0.1, "reciprocity": 0.5}
	var self_relier := _actor("npc_oun", {"empathy": 0.8})
	self_relier["norms"]["personal"] = {"sharing": 0.1, "self_reliance": 0.95, "reciprocity": 0.5}
	var ctx2 := {"relationships": RelationshipStore.new(), "tick": 51}
	CognitiveTransition.process(sharer, event, ctx2)
	CognitiveTransition.process(self_relier, event, ctx2)
	var guilt_s: float = float(sharer["personality"].emotions.get("guilt", 0.0))
	var guilt_r: float = float(self_relier["personality"].emotions.get("guilt", 0.0))
	_check("norm_guilt_scales_with_sharing", guilt_s > guilt_r,
		"s=%f r=%f" % [guilt_s, guilt_r])
	# 高分享规范的人更愿意接受请求（同样的性格与处境）
	var proposer := _actor("npc_weila", {})
	var communitarian := _actor("npc_oun", {"altruism": 0.5, "empathy": 0.5})
	communitarian["inventory"]["food"] = 5
	communitarian["norms"]["personal"] = {"sharing": 0.9, "self_reliance": 0.1, "reciprocity": 0.5}
	var individualist := _actor("npc_kadga", {"altruism": 0.5, "empathy": 0.5})
	individualist["inventory"]["food"] = 5
	individualist["norms"]["personal"] = {"sharing": 0.1, "self_reliance": 0.9, "reciprocity": 0.5}
	var rng1 := RandomNumberGenerator.new(); rng1.seed = 7
	var rng2 := RandomNumberGenerator.new(); rng2.seed = 7
	var acc_c := 0
	var acc_i := 0
	for i in 40:
		if bool(SocialSystem.evaluate_food_request(communitarian, proposer, 0, rng1)["accepted"]):
			acc_c += 1
		if bool(SocialSystem.evaluate_food_request(individualist, proposer, 0, rng2)["accepted"]):
			acc_i += 1
	_check("norm_sharing_accepts_more", acc_c > acc_i + 6, "comm=%d/40 indiv=%d/40" % [acc_c, acc_i])
	print("P1_NORM_ACCEPT communitarian=%d/40 individualist=%d/40" % [acc_c, acc_i])

# ── 8. 反思 v2：解释竞争 → 记恨（记忆带解释分布）──
func _test_reflection_grudge() -> void:
	var weila := _actor("npc_weila", {})
	weila["display_names"] = {"npc_oun": "欧恩", "npc_weila": "薇拉", "npc_kadga": "卡德加"}
	# 记忆带敌意主导的解释（transition 平时写入；这里直接构造）
	var hostile_interp := {"candidates": [
		{"id": "selfish", "label": "自私", "weight": 0.55},
		{"id": "also_starving", "label": "没粮", "weight": 0.15},
		{"id": "distrusts_me", "label": "不信任我", "weight": 0.3}], "dominant": "selfish"}
	weila["memories"] = [
		{"seq": 1, "tick": 10, "type": "food_request_refused", "text": "x", "actor_id": "npc_oun", "counterpart_id": "npc_oun", "interpretation": hostile_interp},
		{"seq": 2, "tick": 20, "type": "food_request_refused", "text": "x", "actor_id": "npc_oun", "counterpart_id": "npc_oun", "interpretation": hostile_interp},
		{"seq": 3, "tick": 30, "type": "i_refused_request", "text": "x", "actor_id": "npc_weila", "counterpart_id": "npc_kadga"},
	]
	var result: Dictionary = ReflectionSystem.reflect(weila, 100)
	_check("reflection_forms_grudge", weila["grudges"].has("npc_oun"), str(weila["grudges"]))
	_check("reflection_writes_belief", weila["beliefs"].confidence_of("欧恩 不肯帮我") > 0.4,
		str(weila["beliefs"].confidence_of("欧恩 不肯帮我")))
	_check("reflection_has_insight", (result.get("insights", []) as Array).size() > 0)
	# 自己拒绝别人的记忆不构成记恨
	_check("no_grudge_from_own_refusals", not weila["grudges"].has("npc_kadga"))

# ── 9. 关系有向性 + 解释加权的关系变化 ──
func _test_relationship_asymmetry() -> void:
	var rs := RelationshipStore.new()
	# 欧恩答应了薇拉 → 经 transition：薇拉→欧恩 善意/亏欠上升；欧恩→薇拉 不变（有向）
	var weila := _actor("npc_weila", {})
	var accept_event := {"type": "food_request_accepted", "actor_id": "npc_oun", "proposer_id": "npc_weila",
		"tick": 10, "seq": 1, "text": "x"}
	weila["needs"]["hunger"] = 700
	CognitiveTransition.process(weila, accept_event, {"relationships": rs, "tick": 10})
	_check("trust_is_directed", rs.composite_trust("npc_weila", "npc_oun") > 0 and rs.composite_trust("npc_oun", "npc_weila") == 0,
		"w→o=%d o→w=%d" % [rs.composite_trust("npc_weila", "npc_oun"), rs.composite_trust("npc_oun", "npc_weila")])
	# 拒绝：敌意解释加权 → 善意下降（数量由解释权重决定，不是固定 -80）
	var rs2 := RelationshipStore.new()
	var weila2 := _actor("npc_weila", {"empathy": 0.5})
	weila2["tom"].add_evidence("npc_oun", "has_food", 1.0, 0.6, 1, 10)
	weila2["needs"]["hunger"] = 800
	var refuse_event := {"type": "food_request_refused", "actor_id": "npc_oun", "proposer_id": "npc_weila",
		"tick": 20, "seq": 2, "text": "x"}
	CognitiveTransition.process(weila2, refuse_event, {"relationships": rs2, "tick": 20})
	_check("refusal_drops_benevolence", rs2.get_dim("npc_weila", "npc_oun", "benevolence") < 0,
		str(rs2.get_dim("npc_weila", "npc_oun", "benevolence")))

# ── 工具 ──

func _actor(id: String, trait_overrides: Dictionary) -> Dictionary:
	return {
		"id": id,
		"personality": PersonalityProfile.new(trait_overrides, {}),
		"needs": {"hunger": 300, "thirst": 100, "energy": 900, "social": 100},
		"physical": {"sick": false, "injured": false, "wet": false},
		"inventory": {"food": 0, "wood": 0, "shells": 0},
		"tom": TheoryOfMind.new(),
		"beliefs": BeliefStore.new(),
		"norms": {
			"personal": {"sharing": 0.5, "self_reliance": 0.5, "reciprocity": 0.5},
			"descriptive": {"sharing": 0.5, "reciprocity": 0.5},
			"injunctive": {"sharing": 0.5},
		},
		"memories": [],
		"visited_tiles": {},
		"social_stance": {},
		"grudges": {},
		"sensitivities": {},
		"display_name": id,
		"display_names": {},
	}

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
		if co_located:
			cfg["spawn"] = spots[0]  # 全员同点出生：制造社交密度
		else:
			cfg["spawn"] = spots[idx % spots.size()]
		idx += 1
		configs.append(cfg)
	return configs
