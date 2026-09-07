extends SceneTree
## P5 Spatial Freeze Gate（GPT SN 指令 第十六节测试清单）
## SA 未知障碍隔离 · SC 迷失人员（last_seen 不追真值）· SD 重捕获
## SE 昼夜视野 · SF LOS 遮挡 · SG 资源知识隔离 · SI 撞墙重规划 · SJ 确定性
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

	# ── SA：导航只吃信念。未知≠回避；不确定性改变路线；同输入同输出 ──
	var belief_a := SpatialBeliefMap.new()
	belief_a.configure(Rect2i(0, 0, 20, 20))
	for x in range(2, 13):
		belief_a.observe_cell(x, 11, SpatialBeliefMap.CELL_FREE, "none", 1)   # 已知绕行南线
	for y in range(10, 13):
		belief_a.observe_cell(2, y, SpatialBeliefMap.CELL_FREE, "none", 1)
		belief_a.observe_cell(12, y, SpatialBeliefMap.CELL_FREE, "none", 1)
	# (3..11, 10) 直线区保持 UNKNOWN——真实世界那里有没有墙，导航根本不知道
	var p_low: Array = SubjectiveNavigator.find_path(belief_a, Vector2i(2, 10), Vector2i(12, 10), 1.2)
	var p_high: Array = SubjectiveNavigator.find_path(belief_a, Vector2i(2, 10), Vector2i(12, 10), 5.5)
	var low_uses_unknown := false
	for p in p_low:
		if belief_a.cell_state(int(p.x), int(p.y)) == SpatialBeliefMap.CELL_UNKNOWN:
			low_uses_unknown = true
	_check("sa_unknown_not_preavoided", p_low.size() > 2 and low_uses_unknown,
		"低不确定成本应直穿未知区（路径=%s）" % str(p_low))
	_check("sa_uncertainty_changes_route", p_high != p_low,
		"高 unknown_cost 应改走已知绕行（low=%d high=%d）" % [p_low.size(), p_high.size()])
	var p_again: Array = SubjectiveNavigator.find_path(belief_a, Vector2i(2, 10), Vector2i(12, 10), 1.2)
	_check("sa_same_input_same_output", str(p_again) == str(p_low), "确定性")

	# ── SF：LOS——同距离，rock 遮挡不可见 ──
	var stub := StubMap.new()
	var clear_pair := SpatialPerception.can_see(stub, 12, "clear", Vector2i(5, 5), Vector2i(9, 9))
	stub.rocks["7,7"] = true
	var blocked_pair := SpatialPerception.can_see(stub, 12, "clear", Vector2i(5, 5), Vector2i(9, 9))
	_check("sf_los_clear_visible", clear_pair, "无遮挡应可见")
	_check("sf_los_rock_blocked", not blocked_pair, "rock 遮挡应不可见")
	_check("sf_night_shrinks_vision", not SpatialPerception.can_see(stub, 23, "clear", Vector2i(5, 5), Vector2i(5, 12)),
		"夜视 4 格内收缩（距离 7 应不可见）")

	# ── SE：真实地图上同距离两人，昼见夜不见 ──
	var sim := IslandSimulation.new(mq, 777, configs)
	var pair := _find_visible_pair(mq, sim, spot)
	if pair.size() == 2:
		sim.actors["npc_weila"]["tile"] = pair[0]
		sim.actors["npc_oun"]["tile"] = pair[1]
		sim.world_time["hour"] = 12
		var view_day := sim._build_actor_view("npc_weila", sim.actors["npc_weila"])
		var day_seen: bool = _visible_has(view_day, "npc_oun")
		sim.world_time["hour"] = 23
		var view_night := sim._build_actor_view("npc_weila", sim.actors["npc_weila"])
		var night_seen: bool = _visible_has(view_night, "npc_oun")
		_check("se_day_visible_night_not", day_seen and not night_seen,
			"day=%s night=%s dist=%d" % [str(day_seen), str(night_seen), absi(pair[0].x - pair[1].x) + absi(pair[0].y - pair[1].y)])
	else:
		_check("se_day_visible_night_not", false, "地图上找不到 8 格 LOS 通畅对")

	# ── SC/SD：追踪目标——视野外用 last_seen，重见才用真值 ──
	var sim2 := IslandSimulation.new(mq, 777, configs)
	var w: Dictionary = sim2.actors["npc_weila"]
	var o: Dictionary = sim2.actors["npc_oun"]
	var home: Vector2i = sim2.actors["npc_weila"]["tile"]
	var north_mem := home + Vector2i(0, -6)                     # 记忆：他上次在北边
	(w["tom"] as TheoryOfMind).see_at("npc_oun", north_mem, 1)
	o["tile"] = home + Vector2i(25, 0)                          # 真实：他在 25 格外的东边（方向相反，可区分）
	w["current_action"] = {"action": "seek_person", "target_actor": "npc_oun", "target": north_mem, "duration": 6}
	w["action_ticks_left"] = 6
	sim2._tick_actor("npc_weila", w, [])
	var step1: Vector2i = w["tile"]
	var d_mem := absi(step1.x - north_mem.x) + absi(step1.y - north_mem.y)
	var d_true := absi(step1.x - (home.x + 25)) + absi(step1.y - home.y)
	_check("sc_pursues_last_seen_not_truth", d_mem <= 5 and d_true >= 25,
		"第一步=%s 记忆距=%d(≤5) 真值距=%d(≥25)——若追真值则记忆距应变大" % [str(step1), d_mem, d_true])
	# SD：目标走进视野（西 5 格，可见）→ 改追真值方向
	o["tile"] = home - Vector2i(5, 0)
	w["tile"] = home
	w["action_ticks_left"] = 6
	sim2._tick_actor("npc_weila", w, [])
	_check("sd_reacquire_updates_target", int(w["tile"].x) == int(home.x) - 1,
		"重捕获后第一步=%s 期望向西=%s" % [str(w["tile"]), str(home + Vector2i(-1, 0))])

	# ── SG：资源知识隔离——没见过水泉就不知道有水 ──
	var p_plain := PersonalityProfile.new({}, {})
	var needs := {"thirst": 900.0}
	var w_world := {"resources": {"water_springs": [Vector2i(3, 3)]}}
	var actor_blind := {"tile": Vector2i(0, 0), "known_resources": {"water_springs": []}}
	var actor_knows := {"tile": Vector2i(0, 0), "known_resources": {"water_springs": [Vector2i(3, 3)]}}
	var drink_blind = ActionRegistry._drink(p_plain, needs, Vector2i(0, 0), w_world, actor_blind)
	var drink_knows = ActionRegistry._drink(p_plain, needs, Vector2i(0, 0), w_world, actor_knows)
	_check("sg_unknown_spring_not_targeted", drink_blind == null, "没见过泉 → 不应产生喝水行动")
	_check("sg_known_spring_targeted", drink_knows != null, "见过泉 → 应产生喝水行动")
	# ── SK：缺失知识 ≠ 全知（P5.1 fail-closed 安全门）──
	# actor view 完全没有 known_resources 键时，绝不得回退 world["resources"]
	var actor_nokr := {"tile": Vector2i(0, 0)}
	var w_forage_world := {"resources": {"berry_bushes": [Vector2i(3, 3)]}}
	var drink_nokr = ActionRegistry._drink(p_plain, needs, Vector2i(0, 0), w_world, actor_nokr)
	var forage_nokr = ActionRegistry._forage(p_plain, {"hunger": 900.0}, {}, Vector2i(0, 0), w_forage_world, actor_nokr)
	var fire_nokr = ActionRegistry._sit_by_fire(p_plain, {"social": 900.0}, Vector2i(0, 0), {"fires": {"(3, 3)": true}}, actor_nokr)
	_check("sk_missing_knowledge_not_omniscience",
		drink_nokr == null and forage_nokr == null and fire_nokr == null,
		"drink=%s forage=%s fire=%s（全应为 null——缺键=不知道，不是全知）" % [
			str(drink_nokr != null), str(forage_nokr != null), str(fire_nokr != null)])
	# 分享的饥饿感知只看自己的 ToM（跨角色聚合泄漏修复）
	var inv_full := {"food": 3}
	var share_needs := {"hunger": 100.0}
	var a_selfhungry := {"inventory": inv_full, "appears_hungry_nearby": true}
	var a_calm := {"inventory": inv_full, "appears_hungry_nearby": false}
	var share_boosted = ActionRegistry._share(p_plain, share_needs, inv_full, Vector2i.ZERO, {}, a_selfhungry)
	var share_plain = ActionRegistry._share(p_plain, share_needs, inv_full, Vector2i.ZERO, {}, a_calm)
	if share_boosted != null and share_plain != null:
		var ratio: float = float(share_boosted["utility"]) / maxf(0.0001, float(share_plain["utility"]))
		_check("sg_hunger_perception_isolated", absf(ratio - 1.5) < 0.01, "效用比=%f 期望 1.5" % ratio)
	else:
		_check("sg_hunger_perception_isolated", false, "share 行动未生成")

	# ── SI：主观可走 + 真实阻塞 → movement_blocked + 信念修正 + 重规划 ──
	var blocked := _find_rock_front(mq)
	if blocked.size() == 2:
		var sim3 := IslandSimulation.new(mq, 777, configs)
		var a3: Dictionary = sim3.actors["npc_weila"]
		var stand: Vector2i = blocked[0]          # 可走格
		var rock: Vector2i = blocked[1]           # 紧邻 rock
		a3["tile"] = stand
		var b3: SpatialBeliefMap = a3["spatial"]
		for k in range(1, 7):                     # 主观认为直线全通（从未观察过）
			var cx := stand.x + k * int(sign(rock.x - stand.x)) if rock.x != stand.x else stand.x
			var cy := stand.y + k * int(sign(rock.y - stand.y)) if rock.y != stand.y else stand.y
			b3.observe_cell(cx, cy, SpatialBeliefMap.CELL_FREE, "none", 1)
		var far: Vector2i = stand + (rock - stand) * 6
		var ev_before := sim3.events.size()
		sim3._move_toward(a3, far)
		var mb := 0
		for e in sim3.events.slice(ev_before, sim3.events.size()):
			if str(e.get("type", "")) == "movement_blocked":
				mb += 1
		var rock_now_blocked: bool = b3.cell_state(rock.x, rock.y) == SpatialBeliefMap.CELL_BLOCKED
		_check("si_blocked_emits_and_corrects_belief", mb == 1 and rock_now_blocked and a3["tile"] == stand,
			"mb=%d belief_fixed=%s stayed=%s" % [mb, str(rock_now_blocked), str(a3["tile"] == stand)])
	else:
		_check("si_blocked_emits_and_corrects_belief", false, "地图上找不到紧邻 rock 的可走格")

	# ── SJ：同 seed 双跑全同（事件流 + 信念 hash）──
	var sim_x := IslandSimulation.new(mq, 777, configs)
	var sim_y := IslandSimulation.new(mq, 777, configs)
	for i in 300:
		sim_x.step()
		sim_y.step()
	var hash_x := ""
	var hash_y := ""
	for id in sim_x.actors:
		hash_x += (sim_x.actors[id]["spatial"] as SpatialBeliefMap).hash_state()
		hash_y += (sim_y.actors[id]["spatial"] as SpatialBeliefMap).hash_state()
	_check("sj_full_determinism", sim_x.events.size() == sim_y.events.size() and hash_x == hash_y,
		"events %d/%d hash_eq=%s" % [sim_x.events.size(), sim_y.events.size(), str(hash_x == hash_y)])

	print("SUMMARY pass=%d fail=%d" % [_pass, _fail])
	_f = true
	quit(0)

func _visible_has(view: Dictionary, other_id: String) -> bool:
	for o in view.get("others_visible", []):
		if str(o.get("id", "")) == other_id:
			return true
	return false

## 找一对曼哈顿 8、LOS 通畅的可走格（昼夜视野分界：12 可见 / 4 不可见）
func _find_visible_pair(mq, sim, spot: Vector2i) -> Array:
	var centers: Array = [spot]
	for id in sim.actors:
		centers.append(sim.actors[id]["tile"])
	for c in centers:
		for d in [Vector2i(8, 0), Vector2i(7, 1), Vector2i(6, 2), Vector2i(5, 3), Vector2i(4, 4),
				Vector2i(0, 8), Vector2i(1, 7), Vector2i(2, 6), Vector2i(3, 5),
				Vector2i(-8, 0), Vector2i(-7, -1), Vector2i(-6, -2), Vector2i(-5, -3), Vector2i(-4, -4),
				Vector2i(0, -8), Vector2i(-1, -7), Vector2i(-2, -6), Vector2i(-3, -5)]:
			var t: Vector2i = c + d
			if not mq.is_walkable_tile(Vector3i(t.x, 0, t.y)):
				continue
			if not mq.is_walkable_tile(Vector3i(c.x, 0, c.y)):
				continue
			if SpatialPerception.has_los(mq, c, t):
				return [c, t]
	return []

## 找 可走格+紧邻rock（SI 用）
func _find_rock_front(mq) -> Array:
	var rect: Rect2i = mq.get_map_rect()
	for z in range(2, rect.size.y - 2):
		for x in range(2, rect.size.x - 2):
			if mq.get_obstacle(x, z) != "rock":
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var w2: Vector2i = Vector2i(x, z) + d
				if mq.is_walkable_tile(Vector3i(w2.x, 0, w2.y)):
					return [w2, Vector2i(x, z)]
	return []

class StubMap extends RefCounted:
	var rocks := {}
	func get_obstacle(x: int, z: int) -> String:
		return "rock" if rocks.has("%d,%d" % [x, z]) else "none"
	func is_walkable_tile(t: Vector3i) -> bool:
		return not rocks.has("%d,%d" % [t.x, t.z])
	func get_map_rect() -> Rect2i:
		return Rect2i(0, 0, 40, 40)
