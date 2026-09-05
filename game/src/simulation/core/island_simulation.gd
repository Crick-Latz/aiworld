class_name IslandSimulation
extends RefCounted
## 荒岛世界模拟器（阶段 B）：取代 StorySimulation。
## 没有预设剧情。只有三个有性格的人、一座有资源的岛、和一套互动规则。
## 故事是模拟的输出，不是输入。
##
## 核心循环（每 tick）：
##   世界状态 → 角色认知 → 需求/目标 → Utility AI 效用评分 → 行动
##   → 行动结果 → 世界状态改变 → 事件记录 → 信息传播 → 角色更新认知 → 下一 tick

var tick := 0
var world_time := {"day": 1, "hour": 8}  # 每 tick = 1 小时
var actors: Dictionary = {}
var events: Array = []
var world := {}  # 环境状态（资源/天气/火/庇护所）
var map_query

var _seq := 0
var _rng := RandomNumberGenerator.new()

func _init(map_query, seed: int, actor_configs: Array) -> void:
	self.map_query = map_query
	_rng.seed = seed
	_init_world_resources()
	_init_actors(actor_configs)

func _init_world_resources() -> void:
	var map_size: Vector2i = map_query.map_size()
	# 在地图上散布资源（确定性随机）
	var berry_bushes: Array = []
	var water_springs: Array = []
	var fish_spots: Array = []
	var shell_beaches: Array = []
	var ruins: Array = []
	var trees: Array = []

	for i in 3:  # 3 个浆果丛
		var pos := _find_walkable_spot(map_size)
		berry_bushes.append({"pos": pos, "food": 3, "regrow_day": -1})
	for i in 1:  # 1 个水泉
		var pos2 := _find_walkable_spot(map_size)
		water_springs.append(pos2)
	for i in 2:  # 2 个钓鱼点
		var pos3 := _find_walkable_spot(map_size)
		fish_spots.append(pos3)
	for i in 1:  # 1 个贝壳滩
		var pos4 := _find_walkable_spot(map_size)
		shell_beaches.append(pos4)
	for i in 1:  # 1 个废弃营地
		var pos5 := _find_walkable_spot(map_size)
		ruins.append({"pos": pos5, "searched": false, "loot": _generate_ruin_loot()})
	for i in 6:  # 6 棵树
		var pos6 := _find_walkable_spot(map_size)
		trees.append(pos6)

	world = {
		"berry_bushes": berry_bushes,
		"water_springs": water_springs,
		"fish_spots": fish_spots,
		"shell_beaches": shell_beaches,
		"ruins": ruins,
		"trees": trees,
		"shelters": {},  # pos_key -> true
		"fires": {},      # pos_key -> true
		"is_night": false,
		"weather": "clear",
		"resources": {},  # 扁平化给 ActionRegistry 用
	}
	_flatten_resources()

func _flatten_resources() -> void:
	world["resources"] = {
		"berry_bushes": [],
		"water_springs": world["water_springs"],
		"fish_spots": world["fish_spots"],
		"shell_beaches": world["shell_beaches"],
		"ruins": world["ruins"],
	}
	for bush in world["berry_bushes"]:
		if int(bush["food"]) > 0:
			world["resources"]["berry_bushes"].append(bush["pos"])

func _find_walkable_spot(map_size: Vector2i) -> Vector2i:
	for attempt in 50:
		var x := _rng.randi_range(4, map_size.x - 5)
		var z := _rng.randi_range(4, map_size.y - 5)
		if map_query.is_walkable_tile(Vector3i(x, 0, z)):
			return Vector2i(x, z)
	return Vector2i(10, 10)

func _generate_ruin_loot() -> Dictionary:
	# 海盗留下的随机物资
	var possible := [
		{"item": "knife", "count": 1, "prob": 0.6},
		{"item": "rope", "count": 1, "prob": 0.5},
		{"item": "flint", "count": 1, "prob": 0.7},
		{"item": "food", "count": 3, "prob": 0.4},
		{"item": "wine", "count": 1, "prob": 0.3},
	]
	var loot := {}
	for l in possible:
		if _rng.randf() < float(l["prob"]):
			loot[l["item"]] = int(l["count"])
	return loot

func _init_actors(actor_configs: Array) -> void:
	for cfg in actor_configs:
		var id := str(cfg["id"])
		var personality := PersonalityProfile.new(
			cfg.get("traits", {}),
			cfg.get("beliefs", {})
		)
		actors[id] = {
			"id": id,
			"display_name": str(cfg.get("name", id)),
			"tile": cfg.get("spawn", Vector2i(10, 10)),
			"prev_tile": cfg.get("spawn", Vector2i(10, 10)),
			"personality": personality,
			"needs": {"hunger": 200, "thirst": 150, "energy": 800, "social": 100},
			"physical": {"sick": false, "injured": false, "wet": false},
			"inventory": cfg.get("inventory", {}),
			"activity": "刚醒来",
			"current_action": null,
			"action_ticks_left": 0,
			"visited_tiles": {},
			"relationships": {},  # to_id -> {trust: int, affection: int}
		}

# ── 主循环 ──

func step() -> Array:
	tick += 1
	_update_world_time()
	_update_weather()
	var new_events: Array = []

	for id in _ordered_ids():
		var a: Dictionary = actors[id]
		a["prev_tile"] = a["tile"]
		_decay_needs(a)
		a["personality"].decay_emotions()
		_tick_actor(id, a, new_events)

	_update_nearby_info()
	world["tick"] = tick
	return new_events

func _ordered_ids() -> Array:
	var ids := actors.keys()
	ids.sort()
	return ids

func _tick_actor(id: String, a: Dictionary, new_events: Array) -> void:
	# 如果正在执行行动，倒计时
	if int(a.get("action_ticks_left", 0)) > 0:
		a["action_ticks_left"] = int(a["action_ticks_left"]) - 1
		if int(a["action_ticks_left"]) <= 0:
			_complete_action(id, a, new_events)
		else:
			a["activity"] = str(a.get("current_action", {}).get("desc", "忙碌"))
		return

	# 空闲：Utility AI 决策
	var actor_view := _build_actor_view(id, a)
	var decision: Dictionary = DecisionEngine.decide(actor_view, world)
	a["current_action"] = decision
	a["action_ticks_left"] = int(decision.get("duration", 1))
	a["activity"] = str(decision.get("desc", "？"))

	# 如果目标不是当前位置，先移动（每 tick 1 格）
	var target = decision.get("target", null)
	if target != null and typeof(target) == TYPE_VECTOR2I:
		if a["tile"] != target:
			_move_toward(a, target)
			a["visited_tiles"][str(a["tile"])] = true

func _complete_action(id: String, a: Dictionary, new_events: Array) -> void:
	var action: Dictionary = a.get("current_action", {})
	var action_name := str(action.get("action", "wait"))
	a["current_action"] = null

	match action_name:
		"forage_berries":
			_do_forage(id, a, new_events)
		"drink_water":
			_do_drink(id, a, new_events)
		"fish":
			_do_fish(id, a, new_events)
		"gather_shells":
			_do_shells(id, a, new_events)
		"explore":
			_do_explore(id, a, new_events)
		"search_ruins":
			_do_ruins(id, a, new_events)
		"build_shelter":
			_do_shelter(id, a, new_events)
		"craft_fish_spear":
			_do_craft(id, a, new_events)
		"make_fire":
			_do_fire(id, a, new_events)
		"socialize":
			_do_socialize(id, a, new_events)
		"share_food":
			_do_share(id, a, new_events)
		"rest":
			_do_rest(id, a, new_events)
		_:
			pass  # wait / ask_for_help / offer_help 暂为占位

	a["activity"] = "刚完成" + str(action.get("desc", action_name))

# ── 行动执行 ──

func _do_forage(id: String, a: Dictionary, ev: Array) -> void:
	for bush in world["berry_bushes"]:
		if bush["pos"] == a["tile"] and int(bush["food"]) > 0:
			var got := mini(2, int(bush["food"]))
			bush["food"] = int(bush["food"]) - got
			if int(bush["food"]) <= 0:
				bush["regrow_day"] = int(world_time["day"]) + 3
			a["inventory"]["food"] = int(a["inventory"].get("food", 0)) + got
			a["needs"]["hunger"] = clampi(int(a["needs"]["hunger"]) - 300, 0, 1000)
			a["personality"].adjust_emotion("joy", 0.1)
			_emit("foraged", id, "%s 采到了 %d 份浆果" % [a["display_name"], got], {"food": got})
			_flatten_resources()
			return
	_emit("foraged_empty", id, "%s 找了一圈，浆果已经被采光了" % a["display_name"], {})
	a["personality"].adjust_emotion("sadness", 0.05)

func _do_drink(id: String, a: Dictionary, ev: Array) -> void:
	for spring in world["water_springs"]:
		if spring == a["tile"]:
			a["needs"]["thirst"] = 0
			_emit("drank", id, "%s 喝了水" % a["display_name"], {})
			return

func _do_fish(id: String, a: Dictionary, ev: Array) -> void:
	if _rng.randf() < 0.7:
		a["inventory"]["food"] = int(a["inventory"].get("food", 0)) + 3
		a["personality"].adjust_emotion("joy", 0.15)
		_emit("fished", id, "%s 捕到了鱼！" % a["display_name"], {"food": 3})
	else:
		a["personality"].adjust_emotion("sadness", 0.05)
		_emit("fished_empty", id, "%s 空手而归" % a["display_name"], {})

func _do_shells(id: String, a: Dictionary, ev: Array) -> void:
	a["inventory"]["shells"] = int(a["inventory"].get("shells", 0)) + 1
	_emit("gathered_shells", id, "%s 捡到了贝壳" % a["display_name"], {"shells": 1})

func _do_explore(id: String, a: Dictionary, ev: Array) -> void:
	a["visited_tiles"][str(a["tile"])] = true
	# 随机发现（好奇心驱动探索的奖励）
	var roll := _rng.randf()
	if roll < 0.1:
		a["inventory"]["food"] = int(a["inventory"].get("food", 0)) + 1
		_emit("explored_found", id, "%s 探索时意外发现了一些野果" % a["display_name"], {"food": 1})
	elif roll < 0.05:
		a["physical"]["injured"] = true
		a["personality"].adjust_emotion("fear", 0.4)
		_emit("explored_hurt", id, "%s 探索时被蛇咬伤了！" % a["display_name"], {"injury": true})
	else:
		_emit("explored", id, "%s 探索了周围" % a["display_name"], {})

func _do_ruins(id: String, a: Dictionary, ev: Array) -> void:
	for ruin in world["ruins"]:
		if ruin["pos"] == a["tile"] and not bool(ruin["searched"]):
			ruin["searched"] = true
			var loot: Dictionary = ruin["loot"]
			if loot.is_empty():
				a["personality"].adjust_emotion("sadness", 0.1)
				_emit("ruins_empty", id, "%s 翻遍了废弃营地，什么也没找到" % a["display_name"], {})
			else:
				for item in loot:
					a["inventory"][item] = int(a["inventory"].get(item, 0)) + int(loot[item])
				var loot_names: Array = []
				for item in loot:
					loot_names.append("%s×%d" % [item, loot[item]])
				a["personality"].adjust_emotion("joy", 0.2)
				_emit("ruins_loot", id, "%s 在废弃营地找到了 %s" % [a["display_name"], "、".join(loot_names)], loot)
			return

func _do_shelter(id: String, a: Dictionary, ev: Array) -> void:
	if int(a["inventory"].get("wood", 0)) >= 2:
		a["inventory"]["wood"] = int(a["inventory"]["wood"]) - 2
		world["shelters"][str(a["tile"])] = true
		_emit("shelter_built", id, "%s 搭建了一个简易庇护所" % a["display_name"], {"pos": str(a["tile"])})

func _do_craft(id: String, a: Dictionary, ev: Array) -> void:
	if int(a["inventory"].get("shells", 0)) >= 1 and int(a["inventory"].get("wood", 0)) >= 1:
		a["inventory"]["shells"] = int(a["inventory"]["shells"]) - 1
		a["inventory"]["wood"] = int(a["inventory"]["wood"]) - 1
		a["inventory"]["fish_spear"] = 1
		_emit("crafted", id, "%s 制作了一把鱼叉" % a["display_name"], {"tool": "fish_spear"})

func _do_fire(id: String, a: Dictionary, ev: Array) -> void:
	if int(a["inventory"].get("wood", 0)) >= 1:
		a["inventory"]["wood"] = int(a["inventory"]["wood"]) - 1
		world["fires"][str(a["tile"])] = true
		_emit("fire_lit", id, "%s 生了一堆火" % a["display_name"], {"pos": str(a["tile"])})

func _do_socialize(id: String, a: Dictionary, ev: Array) -> void:
	a["needs"]["social"] = clampi(int(a["needs"]["social"]) - 300, 0, 1000)
	a["personality"].adjust_emotion("joy", 0.1)
	var others: Array = []
	for other_id in actors:
		if other_id != id:
			others.append(actors[other_id]["display_name"])
	_emit("socialized", id, "%s 和 %s 聊了聊天" % [a["display_name"], "、".join(others)], {})

func _do_share(id: String, a: Dictionary, ev: Array) -> void:
	if int(a["inventory"].get("food", 0)) >= 2:
		a["inventory"]["food"] = int(a["inventory"]["food"]) - 1
		a["personality"].adjust_emotion("joy", 0.15)
		_emit("shared_food", id, "%s 把食物分给了同伴" % a["display_name"], {"food": 1})

func _do_rest(id: String, a: Dictionary, ev: Array) -> void:
	a["needs"]["energy"] = clampi(int(a["needs"]["energy"]) + 400, 0, 1000)
	a["needs"]["hunger"] = clampi(int(a["needs"]["hunger"]) + 100, 0, 1000)
	_emit("rested", id, "%s 休息了一会儿" % a["display_name"], {})

# ── 系统更新 ──

func _update_world_time() -> void:
	world_time["hour"] = int(world_time["hour"]) + 1
	if int(world_time["hour"]) >= 24:
		world_time["hour"] = 0
		world_time["day"] = int(world_time["day"]) + 1
		_daily_update()
	world["is_night"] = int(world_time["hour"]) >= 20 or int(world_time["hour"]) < 6

func _daily_update() -> void:
	# 浆果丛刷新
	for bush in world["berry_bushes"]:
		if int(bush["food"]) <= 0 and int(world_time["day"]) >= int(bush.get("regrow_day", 9999)):
			bush["food"] = 3
			bush["regrow_day"] = -1
	_flatten_resources()

func _update_weather() -> void:
	var roll := _rng.randf()
	if roll < 0.05:
		world["weather"] = "storm"
		_emit("weather_storm", "", "暴风雨来袭！", {})
		for id in actors:
			actors[id]["personality"].adjust_emotion("fear", 0.2)
			actors[id]["physical"]["wet"] = true
	elif roll < 0.15:
		world["weather"] = "rain"
	else:
		world["weather"] = "clear"

func _decay_needs(a: Dictionary) -> void:
	var n: Dictionary = a["needs"]
	n["hunger"] = clampi(int(n.get("hunger", 0)) + 2, 0, 1000)
	n["thirst"] = clampi(int(n.get("thirst", 0)) + 3, 0, 1000)
	n["energy"] = clampi(int(n.get("energy", 1000)) - 1, 0, 1000)
	n["social"] = clampi(int(n.get("social", 0)) + 1, 0, 1000)

func _update_nearby_info() -> void:
	for id in actors:
		var a: Dictionary = actors[id]
		var nearby: Array = []
		var hungry_nearby := false
		var needs_help := false
		for other_id in actors:
			if other_id == id:
				continue
			var other: Dictionary = actors[other_id]
			var dist := absi(a["tile"].x - other["tile"].x) + absi(a["tile"].y - other["tile"].y)
			if dist <= 5:
				nearby.append(other_id)
				if int(other["needs"].get("hunger", 0)) > 600:
					hungry_nearby = true
				if bool(other["physical"].get("sick", false)) or bool(other["physical"].get("injured", false)):
					needs_help = true
		world["nearby_" + id] = nearby
	# 给 ActionRegistry 用的全局标记
	var anyone_hungry := false
	var anyone_needs_help := false
	for id in actors:
		if int(actors[id]["needs"].get("hunger", 0)) > 600:
			anyone_hungry = true
		if bool(actors[id]["physical"].get("sick", false)) or bool(actors[id]["physical"].get("injured", false)):
			anyone_needs_help = true
	world["someone_hungry_nearby"] = anyone_hungry
	world["someone_needs_help_nearby"] = anyone_needs_help

func _build_actor_view(id: String, a: Dictionary) -> Dictionary:
	# 把 actor 的数据整理成 ActionRegistry 需要的格式
	return {
		"id": id,
		"tile": a["tile"],
		"personality": a["personality"],
		"needs": a["needs"],
		"physical": a["physical"],
		"inventory": a["inventory"],
		"visited_tiles": a["visited_tiles"],
	}

func _move_toward(a: Dictionary, target: Vector2i) -> void:
	var path: Array = map_query.find_walk_path(
		Vector3i(a["tile"].x, 0, a["tile"].y),
		Vector3i(target.x, 0, target.y)
	)
	if path.size() > 1:
		var next: Vector2i = path[1]
		a["tile"] = next

# ── 事件 ──

func _emit(type: String, actor_id: String, text: String, extra: Dictionary) -> int:
	var e := {"seq": _seq, "tick": tick, "type": type, "actor_id": actor_id, "text": text}
	for k in extra:
		e[k] = extra[k]
	_seq += 1
	events.append(e)
	return int(e["seq"])

# ── 查询接口 ──

func get_snapshot() -> Dictionary:
	var out := {"tick": tick, "day": world_time["day"], "hour": world_time["hour"], "actors": {}}
	for id in _ordered_ids():
		var a: Dictionary = actors[id]
		out["actors"][id] = {
			"tile": a["tile"],
			"activity": a["activity"],
			"inventory": a["inventory"].duplicate(),
			"needs": a["needs"].duplicate(),
			"emotions": a["personality"].emotions.duplicate(),
		}
	return out
