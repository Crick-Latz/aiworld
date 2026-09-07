extends SceneTree
## P1.7 内生社会生态验收：地点评价/关系→空间/资源压过厌恶/跨空间寻人
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/p1_7_ecology.gd

var passed := 0
var failed := 0
var _started := false
var _finished := false

func _initialize() -> void:
	print("P1.7 ecology harness: deferred")

func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _finished

func _run() -> void:
	_test_o_relationship_shapes_space()
	_test_p_resource_overrides_dislike()
	_test_q_epistemic_cross_space()
	_test_rs_feedback_directions()
	await _test_sim_encounter_graph()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	_finished = true
	quit(0 if failed == 0 else 1)

func _check(n: String, c: bool, d: String = "") -> void:
	if c: passed += 1; print("PASS %s" % n)
	else: failed += 1; print("FAIL %s  %s" % [n, d])

func _actor(id: String, traits: Dictionary) -> Dictionary:
	return {
		"id": id, "personality": PersonalityProfile.new(traits, {}),
		"needs": {"hunger": 300, "thirst": 300, "energy": 900, "social": 100},
		"physical": {"sick": false, "injured": false, "wet": false},
		"inventory": {"food": 0, "wood": 0, "shells": 0},
		"tom": TheoryOfMind.new(), "beliefs": BeliefStore.new(),
		"norms": {"personal": {"sharing": 0.5, "self_reliance": 0.5, "reciprocity": 0.5},
			"descriptive": {"sharing": 0.5}, "injunctive": {"sharing": 0.5}},
		"memories": [], "visited_tiles": {}, "social_stance": {}, "grudges": {},
		"sensitivities": {}, "open_questions": [], "observing": {}, "claims_received": [],
		"place_beliefs": PlaceBelief.new(), "base": Vector2i(10, 10),
		"tile": Vector2i(10, 10), "display_name": id, "display_names": {},
	}

# ── O. 关系塑造空间偏好：喜欢之地 > 恐惧之地（权重非规则）──
func _test_o_relationship_shapes_space() -> void:
	var a := _actor("npc_a", {"empathy": 0.5, "sociability": 0.6})
	var rs := RelationshipStore.new()
	rs.adjust("npc_a", "npc_b", "benevolence", 500)   # A 喜欢 B
	rs.adjust("npc_a", "npc_c", "fear", 600)           # A 怕 C
	a["_relationships_hint"] = rs
	var place_b := {"tile": Vector2i(12, 10), "resources": [], "safety": 0.6, "familiarity": 0.3}
	var place_c := {"tile": Vector2i(12, 10), "resources": [], "safety": 0.6, "familiarity": 0.3}
	var v_b: float = PlaceBelief.evaluate_place(a, place_b, ["npc_b"], rs)
	var v_c: float = PlaceBelief.evaluate_place(a, place_c, ["npc_c"], rs)
	_check("o_liked_place_preferred", v_b > v_c + 0.1, "B地=%f C地=%f" % [v_b, v_c])

# ── P. 资源压过厌恶：极度口渴时，唯一水源（讨厌的人守着）仍是正分 ──
func _test_p_resource_overrides_dislike() -> void:
	var a := _actor("npc_a", {"empathy": 0.5, "sociability": 0.4})
	a["needs"]["thirst"] = 900
	var rs := RelationshipStore.new()
	rs.adjust("npc_a", "npc_b", "benevolence", -400)  # 讨厌 B
	a["_relationships_hint"] = rs
	var well := {"tile": Vector2i(15, 10), "resources": ["water"], "safety": 0.6, "familiarity": 0.3}
	var v: float = PlaceBelief.evaluate_place(a, well, ["npc_b"], rs)
	_check("p_water_beats_dislike", v > 0.0, "v=%f（厌恶在场但极度缺水→仍愿去）" % v)
	# 对照：不渴时，同地同人在场 → 厌恶主导
	a["needs"]["thirst"] = 100
	var v2: float = PlaceBelief.evaluate_place(a, well, ["npc_b"], rs)
	_check("p_dislike_without_need", v2 < v - 0.15, "不渴时=%f 应显著低于渴时=%f" % [v2, v])

# ── Q. 认识目标跨空间：人在视野外 + 我记得他在哪 → SEEK_PERSON 产生 ──
func _test_q_epistemic_cross_space() -> void:
	var vera := _actor("npc_weila", {"empathy": 0.65, "curiosity": 0.75, "conflict_avoidance": 0.3, "expressiveness": 0.85, "pragmatism": 0.5, "sociability": 0.6})
	vera["open_questions"] = [{"about": "npc_oun", "kind": "why_refused", "entropy": 0.95, "stakes": 0.8, "tick": 100, "expires": 260}]
	vera["tom"].see_at("npc_oun", Vector2i(3, 7), 95)  # 我记得欧恩在 (3,7)
	vera["others_visible"] = [{"id": "npc_kadga", "tile": Vector2i(9, 9)}]  # 欧恩不在视野
	vera["others_all"] = [{"id": "npc_oun", "tile": Vector2i(3, 7)}, {"id": "npc_kadga", "tile": Vector2i(9, 9)}]
	vera["trust_of"] = {}
	var act = ActionRegistry._seek_person(vera["personality"], vera)
	_check("q_seek_person_generated", act != null and str(act.get("action", "")) == "seek_person" and str(act.get("target_actor", "")) == "npc_oun", str(act))
	# 对照：问题不存在时不产生
	vera["open_questions"] = []
	var act2 = ActionRegistry._seek_person(vera["personality"], vera)
	_check("q_no_question_no_seek", act2 == null or str(act2.get("target_actor", "")) != "npc_oun", str(act2))

# ── R/S. 反馈方向：亏欠→想见（R）；敌意→避开（S）——同为权重 ──
func _test_rs_feedback_directions() -> void:
	var a := _actor("npc_a", {"empathy": 0.5, "sociability": 0.6})
	var rs := RelationshipStore.new()
	rs.adjust("npc_a", "npc_b", "obligation", 600)   # R: 我欠 B
	rs.adjust("npc_a", "npc_c", "benevolence", -500) # S: 记恨 C
	a["_relationships_hint"] = rs
	var place := {"tile": Vector2i(12, 10), "resources": [], "safety": 0.6, "familiarity": 0.3}
	var v_oblig: float = PlaceBelief.evaluate_place(a, place, ["npc_b"], rs)
	var v_grudge: float = PlaceBelief.evaluate_place(a, place, ["npc_c"], rs)
	var v_empty: float = PlaceBelief.evaluate_place(a, place, [], rs)
	_check("r_obligation_attracts", v_oblig > v_empty, "还债对象在=%f 无人=%f" % [v_oblig, v_empty])
	_check("s_grudge_repels", v_grudge < v_empty, "仇人在=%f 无人=%f" % [v_grudge, v_empty])
	# S 的非绝对性：仇人守着水而我快渴死 → 去仍然值得（与 P 一致的困境结构）
	a["needs"]["thirst"] = 950
	place["resources"] = ["water"]
	var v_grudge_water: float = PlaceBelief.evaluate_place(a, place, ["npc_c"], rs)
	_check("s_dependency_overrides_grudge", v_grudge_water > 0.0, "v=%f" % v_grudge_water)

# ── 遭遇图在真实模拟中运转 ──
func _test_sim_encounter_graph() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null:
		_check("encounter_graph_runs", false, "地图不可用")
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
	var sim := IslandSimulation.new(mq, 30001, configs)
	for i in 1500:
		sim.step()
	var g: Dictionary = sim.encounter_graph()
	var total_co := 0
	var any_voluntary := false
	for dyad in g:
		total_co += int(g[dyad]["co_presence"])
		if int(g[dyad]["voluntary"]) > 0:
			any_voluntary = true
	_check("encounter_graph_runs", g.size() >= 2 and total_co > 200, "dyads=%d co=%d" % [g.size(), total_co])
	print("P17_GRAPH %s" % str(g))
	_check("voluntary_encounters_recorded", any_voluntary, "无主动接触记录")
