extends SceneTree
## P6.2 §1 — Divergence 诊断探针（只读）：把 READY 方案与实际行为的分歧逐条归为互斥 8 类。
## 依据：决策时刻的 last_decision_trace（considered/ignored/selected 是决策时真值）
##      + current_action（BETWEEN/IN_PROGRESS/PERSISTED）。
## 分类优先级：BETWEEN_ACTIONS > ACTION_IN_PROGRESS > INTENTION_PERSISTED >
##            (selected=同行动 → MATCHED) > CONSIDERED_NOT_SELECTED >
##            IGNORED_BY_CONSIDERATION > ACTION_GAP（近似：用观察时 ActionRegistry 重建）。
var _natural := 20
var _camp := 10
var _ticks := 3000
var _started := false
var _done := false

const RULE_TO_ACTION := {
	"berry_patch_food": "forage_berries",
	"spring_water": "drink_water",
	"build_shelter": "build_shelter",
	"fish_food": "fish",
	"wood_structure": "gather_wood",
}

func _initialize() -> void:
	print("P62DIAG_CONFIG natural=%d camp=%d ticks=%d" % [_natural, _camp, _ticks])

func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done

func _run() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var camp_spot = mq.get_poi_tile("post_house")
	var spots := [mq.get_poi_tile("post_house"), mq.get_poi_tile("tide_market"), mq.get_poi_tile("old_lighthouse")]
	var store := KnowledgePack.load_island_pack()
	var counts := {}
	var by_problem := {}
	var by_action := {}
	for cohort in ["natural", "camp"]:
		var count := _natural if cohort == "natural" else _camp
		for s in range(count):
			var seed := 50000 + s
			var configs: Array = []
			for ac in scenario.get("actors", []):
				var cfg = ac.duplicate()
				cfg["spawn"] = camp_spot if cohort == "camp" else spots[configs.size() % spots.size()]
				configs.append(cfg)
			var sim := IslandSimulation.new(mq, seed, configs)
			var runner := AgencyShadowRunner.new()
			for i in _ticks:
				sim.step()
				runner.observe(sim)
				_classify_tick(sim, runner, store, counts, by_problem, by_action)
	# 汇总
	var total_ready := 0
	for k in counts:
		total_ready += int(counts[k])
	var out := {"total_ready_proposals": total_ready, "categories": counts,
		"by_problem": by_problem, "by_action": by_action}
	print("P62DIAG_AGG " + JSON.stringify(out))
	_done = true
	quit(0)

## 观察后对最新一条记录分类（runner.records 尾部；只处理本 tick 的新记录）
func _classify_tick(sim, runner: AgencyShadowRunner, store: WorldKnowledgeStore,
		counts: Dictionary, by_problem: Dictionary, by_action: Dictionary) -> void:
	if runner.records.is_empty():
		return
	var r: Dictionary = runner.records[runner.records.size() - 1]
	if int(r.get("tick", -1)) != sim.tick:
		return
	var actor_id := str(r.get("actor_id", ""))
	if not sim.actors.has(actor_id):
		return
	var actor: Dictionary = sim.actors[actor_id]
	var cur = actor.get("current_action", {})
	var cur_action := ""
	if typeof(cur) == TYPE_DICTIONARY:
		cur_action = str(cur.get("action", ""))
	var trace: Dictionary = actor.get("last_decision_trace", {})
	var considered: Array = trace.get("considered_actions", [])
	var ignored: Array = trace.get("ignored_actions", [])
	var selected := str(trace.get("selected", ""))
	var trace_tick := int(trace.get("tick", -1))
	for p in r.get("proposals_cache", []):
		if str(p.get("status", "")) != "READY":
			continue
		var action := str(RULE_TO_ACTION.get(str(p.get("via_rule", "")), ""))
		if action == "":
			_bump(counts, "NO_EQUIVALENT_EXECUTION")
			_bump_nested(by_problem, str(p.get("root_goal", "")), "NO_EQUIVALENT_EXECUTION")
			_bump_nested(by_action, "(none)", "NO_EQUIVALENT_EXECUTION")
			continue
		var cat := ""
		if typeof(cur) != TYPE_DICTIONARY:
			cat = "BETWEEN_ACTIONS"
		elif cur_action == action:
			cat = "ACTION_IN_PROGRESS"
		elif trace_tick < sim.tick and cur_action != "":
			cat = "INTENTION_PERSISTED"
		elif selected == action:
			cat = "MATCHED_SELECTED"
		elif considered.has(action):
			cat = "CONSIDERED_NOT_SELECTED"
		elif ignored.has(action):
			cat = "IGNORED_BY_CONSIDERATION"
		else:
			# 决策时既不在 considered 也不在 ignored → 不在该次 all_actions
			cat = "ACTION_GAP"
		_bump(counts, cat)
		_bump_nested(by_problem, str(p.get("root_goal", "")), cat)
		_bump_nested(by_action, action, cat)

func _bump(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1

func _bump_nested(d: Dictionary, key: String, cat: String) -> void:
	var slot: Dictionary = d.get(key, {})
	slot[cat] = int(slot.get(cat, 0)) + 1
	d[key] = slot
