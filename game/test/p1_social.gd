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
	_test_reflection_grudge()
	_test_relationship_asymmetry()

# ── 1. ToM：观察更新主观模型 ──
func _test_tom_observation() -> void:
	var tom := TheoryOfMind.new()
	TheoryOfMind.observe(tom, {"type": "foraged", "actor_id": "npc_oun", "tick": 10})
	_check("tom_forage_implies_food", tom.belief_about("npc_oun", "has_food") > 0.3,
		str(tom.belief_about("npc_oun", "has_food")))
	TheoryOfMind.observe(tom, {"type": "shared_food", "actor_id": "npc_oun", "tick": 11})
	_check("tom_share_implies_generous", tom.belief_about("npc_oun", "generous") > 0.3,
		str(tom.belief_about("npc_oun", "generous")))
	TheoryOfMind.observe(tom, {"type": "food_request_refused", "actor_id": "npc_oun", "tick": 12})
	var g: float = tom.belief_about("npc_oun", "generous")
	_check("tom_refusal_lowers_generous", g > 0.0 and g < 0.4, str(g))
	# 未知他人 = 中性 0（不是善意也不是恶意）
	_check("tom_unknown_is_neutral", tom.belief_about("npc_stranger", "has_food") == 0.0)

# ── 2. 请求目标选择：ToM + 信任 ──
func _test_request_target_selection() -> void:
	var me := _actor("npc_weila", {})
	# 我相信欧恩有食物，卡德加有没有食物未知
	me["tom"].update("npc_oun", "has_food", 0.7, 1)
	var nearby := [{"id": "npc_oun", "tile": Vector2i(1, 0)}, {"id": "npc_kadga", "tile": Vector2i(0, 1)}]
	var picked := SocialSystem.pick_request_target(me, nearby, {"npc_oun": 50, "npc_kadga": 50})
	_check("request_picks_believed_rich", picked == "npc_oun", picked)
	# 深度不信任的人，即使相信他有钱也不开口
	var picked2 := SocialSystem.pick_request_target(me, nearby, {"npc_oun": -300, "npc_kadga": 50})
	_check("request_skips_distrusted", picked2 == "", picked2)
	# 谁都没食物信念 → 不开口
	var me2 := _actor("npc_weila", {})
	var picked3 := SocialSystem.pick_request_target(me2, nearby, {"npc_oun": 50, "npc_kadga": 50})
	_check("request_needs_belief", picked3 == "", picked3)

# ── 3. 求助门槛：不够饿开不了口 ──
func _test_request_gated_by_hunger() -> void:
	var actor := _actor("npc_weila", {})
	actor["tom"].update("npc_oun", "has_food", 0.7, 1)
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
	var sim := IslandSimulation.new(mq, 20260906, configs)
	for i in 600:
		sim.step()
	var social_types := ["food_requested", "food_request_accepted", "food_request_refused", "shared_food", "socialize"]
	var counts := {}
	var total_social := 0
	for e in sim.events:
		if social_types.has(str(e["type"])):
			counts[str(e["type"])] = int(counts.get(str(e["type"]), 0)) + 1
			total_social += 1
	_check("sim_social_events_emerge", total_social > 0, str(counts))
	# 确定性：同 seed 重跑，社交事件序列完全一致
	var sim2 := IslandSimulation.new(mq, 20260906, configs)
	for i in 600:
		sim2.step()
	var seq1 := _social_sequence(sim)
	var seq2 := _social_sequence(sim2)
	_check("sim_social_deterministic", seq1 == seq2, "len %d vs %d" % [seq1.length(), seq2.length()])
	print("P1_SOCIAL_COUNTS %s" % str(counts))
	# 囤粮饿死防御：饿到极点还揣着存粮的 tick 不应存在（吃存粮是可选项）
	var sim3 := IslandSimulation.new(mq, 11, configs)  # seed 11 曾出现"饿 1000 + 存粮 31"
	var hoard_ticks := 0
	for i in 800:
		sim3.step()
		for aid in sim3.actors:
			if int(sim3.actors[aid]["needs"]["hunger"]) >= 999 and int(sim3.actors[aid]["inventory"].get("food", 0)) >= 1:
				hoard_ticks += 1
	_check("no_starve_while_hoarding", hoard_ticks == 0, "hoard_ticks=%d" % hoard_ticks)
	# ToM 在真实模拟中被填充
	var any_belief := false
	for id in sim.actors:
		var tom: TheoryOfMind = sim.actors[id]["tom"]
		for key in ["has_food", "generous", "reliable"]:
			if absf(tom.belief_about(_other_of(sim, id), key)) > 0.1:
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

# ── 7. 同一拒绝事件，两种立场，两种情绪 ──
func _test_appraisal_roles() -> void:
	var event := {"type": "food_request_refused", "actor_id": "npc_oun", "proposer_id": "npc_weila", "tick": 50}
	var weila := _actor("npc_weila", {"empathy": 0.5})
	var oun := _actor("npc_oun", {"empathy": 0.9})
	var ap_w: Dictionary = AppraisalSystem.appraise(event, weila)
	var ap_o: Dictionary = AppraisalSystem.appraise(event, oun)
	var em_w: Dictionary = AppraisalSystem.appraisal_to_emotions(ap_w, weila["personality"])
	var em_o: Dictionary = AppraisalSystem.appraisal_to_emotions(ap_o, oun["personality"])
	# 被拒者：悲伤/愤怒
	_check("refused_feels_hurt", float(em_w.get("sadness", 0.0)) > 0.05 or float(em_w.get("anger", 0.0)) > 0.05, str(em_w))
	# 拒绝者（高共情）：内疚
	_check("refuser_feels_guilt", float(em_o.get("guilt", 0.0)) > 0.05, str(em_o))
	# 同一事件，评价不同
	_check("appraisal_role_differs", absf(float(ap_w["goal_congruence"]) - float(ap_o["goal_congruence"])) > 0.3,
		"w=%s o=%s" % [str(ap_w["goal_congruence"]), str(ap_o["goal_congruence"])])

# ── 8. 反思：重复拒绝 → 记恨（ToM↓ + 信念写入） ──
func _test_reflection_grudge() -> void:
	var weila := _actor("npc_weila", {})
	weila["display_names"] = {"npc_oun": "欧恩", "npc_weila": "薇拉"}
	weila["memories"] = [
		{"seq": 1, "tick": 10, "type": "food_request_refused", "text": "x", "actor_id": "npc_oun", "counterpart_id": "npc_oun"},
		{"seq": 2, "tick": 20, "type": "food_request_refused", "text": "x", "actor_id": "npc_oun", "counterpart_id": "npc_oun"},
		{"seq": 3, "tick": 30, "type": "i_refused_request", "text": "x", "actor_id": "npc_weila", "counterpart_id": "npc_kadga"},
	]
	var result: Dictionary = ReflectionSystem.reflect(weila, 100)
	var tom: TheoryOfMind = weila["tom"]
	_check("reflection_grudge_lowers_tom", tom.belief_about("npc_oun", "reliable") < -0.1,
		str(tom.belief_about("npc_oun", "reliable")))
	_check("reflection_writes_belief", weila["beliefs"].confidence_of("欧恩 不肯帮我") > 0.4,
		str(weila["beliefs"].confidence_of("欧恩 不肯帮我")))
	_check("reflection_has_insight", (result.get("insights", []) as Array).size() > 0)
	# 自己拒绝别人的记忆不构成记恨
	_check("no_grudge_from_own_refusals", tom.belief_about("npc_kadga", "reliable") == 0.0)

# ── 9. 关系有向性：A 信 B ≠ B 信 A ──
func _test_relationship_asymmetry() -> void:
	var rs := RelationshipStore.new()
	rs.on_help_accepted("npc_oun", "npc_weila")  # 欧恩帮了薇拉
	_check("trust_is_directed", rs.get_trust("npc_weila", "npc_oun") > rs.get_trust("npc_oun", "npc_weila"),
		"w→o=%d o→w=%d" % [rs.get_trust("npc_weila", "npc_oun"), rs.get_trust("npc_oun", "npc_weila")])
	# 一次恩惠(+100)能盖过一次拒绝(-80)——记恨需要重复，这是设计
	var rs2 := RelationshipStore.new()
	rs2.on_help_declined("npc_oun", "npc_weila")  # 从零开始：欧恩拒绝了薇拉
	_check("refusal_drops_trust", rs2.get_trust("npc_weila", "npc_oun") < 0,
		str(rs2.get_trust("npc_weila", "npc_oun")))

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
		"memories": [],
		"visited_tiles": {},
		"display_name": id,
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
