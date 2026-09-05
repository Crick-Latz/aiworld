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
var chronicles: Array = []  # P2: 每日编年史（模拟自己写日记，P3 由 LLM 润色）
var world := {}  # 环境状态（资源/天气/火/庇护所）
var relationships := RelationshipStore.new()  # P1: 有向信任（A 信 B ≠ B 信 A）
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

	for i in 3:  # 3 个浆果丛（1 份/丛，5 天一茬——匮乏驱动社交）
		var pos := _find_walkable_spot(map_size)
		berry_bushes.append({"pos": pos, "food": 1, "regrow_day": -1})
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
		{"item": "food", "count": 2, "prob": 0.25},
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
		# P0: 人生经历 → 派生信念 + 敏感度
		var life := LifeHistory.new(cfg.get("life_history", []))
		var derived := life.derived_beliefs()
		for belief_text in derived:
			personality.add_belief(belief_text, float(derived[belief_text]))
		actors[id] = {
			"id": id,
			"display_name": str(cfg.get("name", id)),
			"tile": cfg.get("spawn", Vector2i(10, 10)),
			"prev_tile": cfg.get("spawn", Vector2i(10, 10)),
			"personality": personality,
			"life_history": life,
			"sensitivities": life.derived_sensitivities(),
			"beliefs": BeliefStore.new(),
			"intentions": IntentionManager.new(),
			"goal_manager": GoalManager.new(),
			"needs": {"hunger": 200, "thirst": 150, "energy": 800, "social": 100},
			"physical": {"sick": false, "injured": false, "wet": false},
			"inventory": (cfg.get("inventory", {}) as Dictionary).duplicate(true),  # 深拷贝：多个模拟实例不得共享可变配置
			"activity": "刚醒来",
			"current_action": null,
			"action_ticks_left": 0,
			"visited_tiles": {},
			"relationships": {},
			"tom": TheoryOfMind.new(),  # P1: 一阶心智模型
			"norms": _init_norms(cfg.get("norms", {})),  # P2: 内化规范（会随经历漂移）
			"last_decision_trace": {},
			"memories": [],
		}
	# P1: 反思系统需要把 id 翻译成名字（信念是人话，不是 id）
	var display_names := {}
	for id in actors:
		display_names[id] = str(actors[id]["display_name"])
	for id in actors:
		actors[id]["display_names"] = display_names

## P2: 规范默认中性，由剧本数据覆盖。规范不是特质——是"人应该怎样"的期待。
func _init_norms(overrides: Dictionary) -> Dictionary:
	var norms := {"sharing": 0.5, "self_reliance": 0.5, "reciprocity": 0.5}
	for k in overrides:
		if norms.has(k):
			norms[k] = clampf(float(overrides[k]), 0.0, 1.0)
	return norms

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

	# P1: 反思——每两天把情景记忆蒸馏成语义信念（延迟领悟）
	if tick % ReflectionSystem.REFLECT_INTERVAL == 0:
		for id in _ordered_ids():
			var result: Dictionary = ReflectionSystem.reflect(actors[id], tick)
			for insight in result.get("insights", []):
				_emit("reflected", id, "%s" % str(insight), {})

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

	# P0: 每次决策前重新生成目标（需求+人格→目标）
	var gm: GoalManager = a.get("goal_manager", null)
	if gm != null:
		a["goal_manager"] = GoalManager.auto_generate(a)

	# P0: DecisionEngine v2（Goal→Intention→Softmax + Trace）
	var actor_view := _build_actor_view(id, a)
	var decision: Dictionary = DecisionEngine.decide(actor_view, world, _rng)
	a["current_action"] = decision
	a["action_ticks_left"] = int(decision.get("duration", 1))
	a["activity"] = str(decision.get("desc", "？"))

	# P0: 把 trace 写回真实 actor（DecisionEngine 只写了 view 副本）
	if actor_view.has("last_decision_trace"):
		a["last_decision_trace"] = actor_view["last_decision_trace"]
	_enrich_trace(a, decision, gm)

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
		"request_share":
			_do_request(id, a, action, new_events)
		"eat_food":
			_do_eat(id, a, new_events)
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
				bush["regrow_day"] = int(world_time["day"]) + 5
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
	# 海里的鱼不多：0.5 概率 1 份——鱼叉有用但不是印钞机
	if _rng.randf() < 0.5:
		a["inventory"]["food"] = int(a["inventory"].get("food", 0)) + 1
		a["personality"].adjust_emotion("joy", 0.15)
		_emit("fished", id, "%s 捕到了一条鱼！" % a["display_name"], {"food": 1})
	else:
		a["personality"].adjust_emotion("sadness", 0.05)
		_emit("fished_empty", id, "%s 空手而归" % a["display_name"], {})

func _do_shells(id: String, a: Dictionary, ev: Array) -> void:
	a["inventory"]["shells"] = int(a["inventory"].get("shells", 0)) + 1
	_emit("gathered_shells", id, "%s 捡到了贝壳" % a["display_name"], {"shells": 1})

func _do_explore(id: String, a: Dictionary, ev: Array) -> void:
	a["visited_tiles"][str(a["tile"])] = true
	# 随机发现（好奇心驱动探索的奖励）——野果稀少，否则探索成了食物印钞机
	var roll := _rng.randf()
	if roll < 0.04:
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
	# P1: 分享是双向互动——找到最近的真实挨饿者，食物给到具体的人
	if int(a["inventory"].get("food", 0)) < 2:
		return
	var hungriest := ""
	var hungriest_v := 600  # 只分给真的饿的人（>600）
	for other_id in actors:
		if other_id == id:
			continue
		var h := int(actors[other_id]["needs"].get("hunger", 0))
		if h > hungriest_v and _is_nearby(a["tile"], actors[other_id]["tile"]):
			hungriest_v = h
			hungriest = other_id
	if hungriest == "":
		return  # 没有具体的对象，分享没有意义（事件流不记——没发生的事）
	a["inventory"]["food"] = int(a["inventory"]["food"]) - 1
	actors[hungriest]["inventory"]["food"] = int(actors[hungriest]["inventory"].get("food", 0)) + 1
	actors[hungriest]["needs"]["hunger"] = clampi(int(actors[hungriest]["needs"]["hunger"]) - 200, 0, 1000)
	a["personality"].adjust_emotion("joy", 0.15)
	relationships.on_transfer_complete(id, hungriest)
	_emit("shared_food", id, "%s 把食物分给了 %s" % [a["display_name"], actors[hungriest]["display_name"]],
		{"to_id": hungriest})

## P1: 请求-回应协议。提议者开口（一次决策），目标独立评估（第二次决策）。
## 接受/拒绝都产生事件 → 双方 Appraisal + ToM 更新 + 记忆 → 关系变化。
func _do_request(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var target_id := str(action.get("target_actor", ""))
	if not actors.has(target_id):
		return
	var target: Dictionary = actors[target_id]
	# 人会走动——决定请求时他在旁边，开口时可能已经走远
	if not _is_nearby(a["tile"], target["tile"]):
		_emit("request_missed", id, "%s 想开口，但 %s 已经走远了" % [a["display_name"], target["display_name"]], {})
		return
	_emit("food_requested", id, "%s 向 %s 开口要食物" % [a["display_name"], target["display_name"]],
		{"target_id": target_id})
	var trust_toward_proposer := relationships.get_trust(target_id, id)
	var result: Dictionary = SocialSystem.evaluate_food_request(target, a, trust_toward_proposer, _rng)
	if bool(result.get("accepted", false)):
		target["inventory"]["food"] = int(target["inventory"].get("food", 0)) - 1
		a["inventory"]["food"] = int(a["inventory"].get("food", 0)) + 1
		a["needs"]["hunger"] = clampi(int(a["needs"]["hunger"]) - 200, 0, 1000)
		relationships.on_help_accepted(target_id, id)
		# P2: 规范漂移——受助让人相信分享是岛上的活法
		_drift_norm(a, "sharing", 0.02)
		_drift_norm(a, "self_reliance", -0.01)
		_emit("food_request_accepted", target_id,
			"%s 把食物分给了 %s" % [target["display_name"], a["display_name"]],
			{"proposer_id": id, "reason": str(result.get("reason", ""))})
	else:
		relationships.on_help_declined(target_id, id)
		# P2: 规范漂移——被拒让人对"同伴该分享"幻灭
		_drift_norm(a, "sharing", -0.03)
		_drift_norm(a, "self_reliance", 0.02)
		_emit("food_request_refused", target_id,
			"%s 摇了摇头：%s——%s 的求助被拒绝了" % [target["display_name"], str(result.get("reason", "")), a["display_name"]],
			{"proposer_id": id, "reason": str(result.get("reason", ""))})

func _drift_norm(a: Dictionary, key: String, delta: float) -> void:
	var norms: Dictionary = a.get("norms", {})
	if norms.has(key):
		norms[key] = clampf(float(norms[key]) + delta, 0.0, 1.0)

func _do_rest(id: String, a: Dictionary, ev: Array) -> void:
	a["needs"]["energy"] = clampi(int(a["needs"]["energy"]) + 400, 0, 1000)
	a["needs"]["hunger"] = clampi(int(a["needs"]["hunger"]) + 100, 0, 1000)
	_emit("rested", id, "%s 休息了一会儿" % a["display_name"], {})

func _do_eat(id: String, a: Dictionary, ev: Array) -> void:
	if int(a["inventory"].get("food", 0)) < 1:
		return
	a["inventory"]["food"] = int(a["inventory"]["food"]) - 1
	a["needs"]["hunger"] = clampi(int(a["needs"]["hunger"]) - 350, 0, 1000)
	_emit("ate_food", id, "%s 吃了些存粮" % a["display_name"], {"food": -1})

# ── 系统更新 ──

func _update_world_time() -> void:
	world_time["hour"] = int(world_time["hour"]) + 1
	if int(world_time["hour"]) >= 24:
		world_time["hour"] = 0
		world_time["day"] = int(world_time["day"]) + 1
		_daily_update()
	world["is_night"] = int(world_time["hour"]) >= 20 or int(world_time["hour"]) < 6

func _daily_update() -> void:
	# 浆果丛刷新（稀疏：5 天一茬，岛上养不活三个人——匮乏驱动社交）
	for bush in world["berry_bushes"]:
		if int(bush["food"]) <= 0 and int(world_time["day"]) >= int(bush.get("regrow_day", 9999)):
			bush["food"] = 1
			bush["regrow_day"] = -1
	_flatten_resources()
	# P1: 对他人的旧印象每天淡忘一点（回到中性）
	for id in actors:
		actors[id]["tom"].decay(tick, 3)
	# P2: 编年史——前一天的事件合成日记（本地模板；P3 换 LLM 润色）
	_compose_chronicle(int(world_time["day"]) - 1)

## P2: 按显著性合成一天的日记。冲突/伤害 > 温暖/收获 > 日常琐碎。
const CHRONICLE_TIER2 := ["food_request_refused", "explored_hurt", "weather_storm", "reflected"]
const CHRONICLE_TIER1 := ["food_request_accepted", "shared_food", "ruins_loot", "fire_lit", "shelter_built", "crafted"]

func _compose_chronicle(day: int) -> void:
	if day < 1:
		return
	var drama: Array = []
	var warmth: Array = []
	var quiet := 0
	for e in events:
		if int(e.get("day", -1)) != day:
			continue
		var t := str(e["type"])
		if CHRONICLE_TIER2.has(t):
			drama.append(str(e["text"]))
		elif CHRONICLE_TIER1.has(t):
			warmth.append(str(e["text"]))
		else:
			quiet += 1
	var parts: Array = []
	parts.append_array(drama)
	var warm_used := 0
	for w in warmth:
		if warm_used >= 2:  # 温暖的事挑两件说，不然日记太长
			break
		parts.append(w)
		warm_used += 1
	var text := ""
	if parts.is_empty():
		text = "第%d天：平静的一天。" % day if quiet > 0 else "第%d天：无事发生。" % day
	else:
		text = "第%d天：%s。" % [day, "；".join(parts)]
	# 关系氛围尾注（有显著恩怨才提）
	var snap: Dictionary = relationships.snapshot()
	var edge_min := 0
	var edge_max := 0
	for key in snap:
		edge_min = mini(edge_min, int(snap[key]["trust"]))
		edge_max = maxi(edge_max, int(snap[key]["trust"]))
	if edge_min <= -150:
		text += "岛上的气氛有些紧张。"
	elif edge_max >= 200:
		text += "同伴之间的信任在加深。"
	chronicles.append({"day": day, "tick": tick, "text": text})

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
			if dist <= 8:  # 喊话/目击范围，与 _is_nearby 一致
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
	# P1: 决策需要的社交信息——ToM、对每人的信任、附近有谁（不含他们的隐私状态）
	var trust_of := {}
	var others_nearby: Array = []
	var others_all: Array = []
	for other_id in actors:
		if other_id == id:
			continue
		trust_of[other_id] = relationships.get_trust(id, other_id)
		others_all.append({"id": other_id, "tile": actors[other_id]["tile"]})
		if other_id in world.get("nearby_" + id, []):
			others_nearby.append({"id": other_id, "tile": actors[other_id]["tile"]})
	return {
		"id": id,
		"tile": a["tile"],
		"personality": a["personality"],
		"needs": a["needs"],
		"physical": a["physical"],
		"inventory": a["inventory"],
		"visited_tiles": a["visited_tiles"],
		"beliefs": a.get("beliefs", BeliefStore.new()),
		"intentions": a.get("intentions", IntentionManager.new()),
		"goal_manager": a.get("goal_manager", GoalManager.new()),
		"sensitivities": a.get("sensitivities", {}),
		"tom": a.get("tom", TheoryOfMind.new()),
		"trust_of": trust_of,
		"others_nearby": others_nearby,
		"others_all": others_all,
		"norms": a.get("norms", {}),
	}

## P0: 丰富 DecisionTrace——把 belief/goal/intention/memories 写入
func _enrich_trace(a: Dictionary, decision: Dictionary, gm: GoalManager) -> void:
	var trace: Dictionary = a.get("last_decision_trace", {})
	if trace.is_empty():
		return
	# 当前最高优先级目标
	if gm != null:
		var top := gm.top_goal()
		if not top.is_empty():
			trace["active_goal"] = str(top["id"])
			trace["goal_desc"] = str(top["desc"])
			trace["goal_priority"] = float(top["priority"])
	# 意图状态
	var im: IntentionManager = a.get("intentions", null)
	if im != null and im.has_intention():
		trace["intention"] = str(im.current_intention.get("action", ""))
		trace["commitment"] = float(im.current_intention.get("commitment", 0))
	# 信念中与当前行动相关的
	var beliefs: Dictionary = a["personality"].beliefs
	if not beliefs.is_empty():
		var relevant := {}
		for b in beliefs:
			relevant[b] = float(beliefs[b]["weight"])
		trace["beliefs"] = relevant
	# 情绪快照
	trace["emotions"] = a["personality"].emotions.duplicate()
	# 记忆量
	trace["memory_count"] = (a.get("memories", []) as Array).size()

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
	var e := {"seq": _seq, "tick": tick, "day": int(world_time["day"]), "type": type, "actor_id": actor_id, "text": text}
	for k in extra:
		e[k] = extra[k]
	_seq += 1
	events.append(e)
	# 阶段 C：事件触发情绪评价（FAtiMA 式），记忆存储
	# P1：目击同时更新一阶心智模型（"我看见欧恩采到果子了→他有食物"）
	for id in actors:
		var a: Dictionary = actors[id]
		var is_witness: bool = id == actor_id or _is_nearby(actors[actor_id]["tile"] if actors.has(actor_id) else Vector2i.ZERO, a["tile"])
		if is_witness:
			_appraise_and_react(e, a)
			_store_memory(a, e)
			if id != actor_id:
				TheoryOfMind.observe(a["tom"], e)
	return int(e["seq"])

func _is_nearby(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) <= 8

func _appraise_and_react(event: Dictionary, actor: Dictionary) -> void:
	var p: PersonalityProfile = actor.get("personality", null)
	if p == null:
		return
	var appraisal: Dictionary = AppraisalSystem.appraise(event, actor)
	if appraisal.is_empty():
		return
	var changes: Dictionary = AppraisalSystem.appraisal_to_emotions(appraisal, p)
	for key in changes:
		p.adjust_emotion(key, float(changes[key]))

func _store_memory(actor: Dictionary, event: Dictionary) -> void:
	var type := str(event.get("type", ""))
	# 只记住重要事件
	var important_types := ["explored_hurt", "explored_found", "ruins_loot", "shared_food",
		"weather_storm", "food_requested", "food_request_accepted", "food_request_refused"]
	if not important_types.has(type):
		return
	# P1: 记忆带"对手方"，并从我的视角归一化类型。
	# 关键区分："我拒绝了他"(i_refused_request) ≠ "他拒绝了我"(food_request_refused)——
	# 反思系统据此统计恩怨，混淆会让拒绝者反过来记恨求助者。
	var me := str(actor.get("id", ""))
	var counterpart := ""
	var my_type := type
	if me == str(event.get("actor_id", "")):
		counterpart = str(event.get("to_id", event.get("proposer_id", event.get("target_id", ""))))
		if type == "shared_food":
			my_type = "i_shared_food"            # 我分给了他
		elif type == "food_request_accepted":
			my_type = "i_shared_on_request"      # 他求我，我答应了
		elif type == "food_request_refused":
			my_type = "i_refused_request"        # 他求我，我拒绝了
	elif me == str(event.get("proposer_id", "")):
		counterpart = str(event.get("actor_id", ""))
		# food_request_accepted → 他帮了我；food_request_refused → 他拒绝了我（类型保留）
	elif me == str(event.get("to_id", "")):
		counterpart = str(event.get("actor_id", ""))
		if type == "shared_food":
			my_type = "shared_food_to_me"  # 从受助者视角：有人分给了我
	var mem := {
		"seq": int(event.get("seq", 0)),
		"tick": int(event.get("tick", 0)),
		"type": my_type,
		"text": str(event.get("text", "")),
		"actor_id": str(event.get("actor_id", "")),
		"counterpart_id": counterpart,
	}
	actor["memories"].append(mem)
	if actor["memories"].size() > 20:
		actor["memories"].pop_front()

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
			"tom": a["tom"].snapshot(),
			"memories": (a["memories"] as Array).duplicate(),
		}
	out["relationships"] = relationships.snapshot()
	return out
