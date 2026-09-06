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
var relationships := RelationshipStore.new()
var obligations: Array = []
var _encounters := {}
var institutions: Array = []  # P2c-1: InstitutionRecord（客观层）   # P1.7c: dyad -> {co_presence, interactions, voluntary}  # P1.6: 承诺台账 {debtor, creditor, object, made_tick, due_tick, repaid}  # P1: 有向信任（A 信 B ≠ B 信 A）
var map_query

var _seq := 0
var _hunger_samples := {}   # P1.5 采样：id -> 饥饿累计（运行均值）
var _sample_count := 0
var _switch_counts := {}    # P1.5 采样：id -> 行动类型切换数（身份稳定性度量）
var _last_action_types := {}
var _rng := RandomNumberGenerator.new()

func _init(map_query, seed: int, actor_configs: Array, economy_overrides: Dictionary = {}) -> void:
	self.map_query = map_query
	_rng.seed = seed
	_economy = {
		"berry_count": 3, "berry_food": 1, "berry_regrow_days": 5,
		"fish_prob": 0.5, "fish_amount": 1, "explore_food_prob": 0.04,
	}.duplicate()
	for k in economy_overrides:
		if _economy.has(k):
			_economy[k] = economy_overrides[k]
	_init_world_resources()
	_init_actors(actor_configs)

var _economy := {}

func _init_world_resources() -> void:
	var map_size: Vector2i = map_query.map_size()
	# 在地图上散布资源（确定性随机）
	var berry_bushes: Array = []
	var water_springs: Array = []
	var fish_spots: Array = []
	var shell_beaches: Array = []
	var ruins: Array = []
	var trees: Array = []

	for i in int(_economy["berry_count"]):  # 浆果丛（默认稀疏——匮乏驱动社交；富裕世界可覆盖）
		var pos := _find_walkable_spot(map_size)
		berry_bushes.append({"pos": pos, "food": int(_economy["berry_food"]), "regrow_day": -1})
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
			"tom": TheoryOfMind.new(),  # 一阶心智模型（证据累积+响应预测）
			"norms": _init_norms(cfg.get("norms", {})),  # P1.5: personal/descriptive/injunctive 三层
			"social_stance": {},    # P1.5: 对每人的接近/回避倾向（解释系统写入）
			"pending_predictions": [],
			"place_beliefs": PlaceBelief.new(),  # P1.7: 地点信念（每人不同）
			"base": cfg.get("spawn", Vector2i(10, 10)),  # P1.7: 现居基地  # P1.5: 我对他人反应的预测（待观察验证）
			"grudges": {},          # P1.5: 已形成的记恨（可被新证据推翻）
			"last_transition": {},  # P1.5: 最近一次认知转移摘要（DecisionTrace 用）
			"last_decision_trace": {},
			"memories": [],
		}
	# P1: 反思系统需要把 id 翻译成名字（信念是人话，不是 id）
	var display_names := {}
	for id in actors:
		display_names[id] = str(actors[id]["display_name"])
	for id in actors:
		actors[id]["display_names"] = display_names

func encounter_graph() -> Dictionary:
	return _encounters.duplicate(true)

func get_actor_hunger_samples() -> Dictionary:
	var out := {}
	for id in _hunger_samples:
		out[id] = float(_hunger_samples[id]) / maxf(float(_sample_count), 1.0)
	return out

func get_actor_switch_counts() -> Dictionary:
	return _switch_counts.duplicate()

## P1.5: 规范三层——personal（我认为该怎样）/descriptive（我以为别人通常怎样）/
## injunctive（我以为大家会谴责什么）。旧扁平格式自动归入 personal 层。
func _init_norms(overrides: Dictionary) -> Dictionary:
	var norms := {
		"personal": {"sharing": 0.5, "self_reliance": 0.5, "reciprocity": 0.5},
		"descriptive": {"sharing": 0.5, "reciprocity": 0.5},
		"injunctive": {"sharing": 0.5},
	}
	if overrides.has("personal"):
		for layer in ["personal", "descriptive", "injunctive"]:
			if overrides.has(layer):
				for k in overrides[layer]:
					if norms[layer].has(k):
						norms[layer][k] = clampf(float(overrides[layer][k]), 0.0, 1.0)
	else:
		for k in overrides:  # 旧扁平格式 → personal
			for layer in ["personal", "descriptive", "injunctive"]:
				if norms[layer].has(k):
					norms[layer][k] = clampf(float(overrides[k]), 0.0, 1.0)
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


	if tick % ReflectionSystem.REFLECT_INTERVAL == 0:
		for id in _ordered_ids():
			# P2d-5: 修订检查（AA）——违规多+合法性低 → amend 目标
			var pgb5: Dictionary = actors[id].get("perceived_group_beliefs", {})
			for rid5 in pgb5:
				if ComplianceSystem.should_amend(actors[id], str(rid5)):
					var goals5: Array = actors[id].get("institutional_goals", [])
					goals5.append({"object": str(pgb5[rid5]["rule"].get("object", "food")), "kind": "amend", "fraction": 0.25, "tick": tick})
					actors[id]["institutional_goals"] = goals5
			var result: Dictionary = ReflectionSystem.reflect(actors[id], tick)
			for insight in result.get("insights", []):
				_emit("reflected", id, "%s" % str(insight), {})
	# P1.6: 认识问题过期（人不会永远纠结；observing 到期清理）
	for id in actors:
		var qs2: Array = actors[id].get("open_questions", [])
		var keep_q: Array = []
		for q in qs2:
			if tick < int(q.get("expires", 0)):
				keep_q.append(q)
		actors[id]["open_questions"] = keep_q
		var obs: Dictionary = actors[id].get("observing", {})
		if not obs.is_empty() and tick >= int(obs.get("until", 0)):
			actors[id]["observing"] = {}
	# P1.5: 每 8 tick 解决到期的社会预测（预测误差学习）
	if tick % 8 == 0:
		_resolve_predictions()
	if tick % 24 == 0:
		_check_overdue_promises()

	# P1.5 行为采样（测试/扫描用）
	_sample_count += 1
	for id in actors:
		_hunger_samples[id] = float(_hunger_samples.get(id, 0.0)) + float(actors[id]["needs"]["hunger"])
		var ca = actors[id].get("current_action", null)
		var at := ""
		if ca != null and typeof(ca) == TYPE_DICTIONARY:
			at = str(ca.get("action", ""))
		if at != "":
			if _last_action_types.has(id) and str(_last_action_types[id]) != at:
				_switch_counts[id] = int(_switch_counts.get(id, 0)) + 1
			_last_action_types[id] = at

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
		# 追踪移动：指向人的行动逐 tick 走向对方（对方会走动，追不上=扑空）；
		# 带地点目标的行动（采集/打水/伐木/探废墟）同样边走边执行——
		# 否则 2-tick 行动总在半路完成（67 次伐木 0 成功的死因）
		var cur_action: Dictionary = a.get("current_action", {})
		if cur_action.has("target_actor") and actors.has(str(cur_action["target_actor"])):
			var pursue_tile: Vector2i = actors[str(cur_action["target_actor"])]["tile"]
			var away := str(cur_action.get("action", "")) == "keep_distance"
			if away:
				pursue_tile = _away_tile(a["tile"], pursue_tile)
			if a["tile"] != pursue_tile:
				_move_toward(a, pursue_tile)
		elif cur_action.has("target") and typeof(cur_action["target"]) == TYPE_VECTOR2I and cur_action["target"] != a["tile"]:
			_move_toward(a, cur_action["target"])
		if int(a["action_ticks_left"]) <= 0:
			_complete_action(id, a, new_events)
		else:
			a["activity"] = str(cur_action.get("desc", "忙碌"))
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
		"request_share", "request_water", "request_tool":
			_do_request(id, a, action, new_events)
		"repay_debt":
			_do_repay(id, a, action, new_events)
		"seek_person":
			_do_seek_person(id, a, action, new_events)
		"relocate":
			_do_relocate(id, a, action, new_events)
		"propose_rule":
			_do_propose_rule(id, a, action, new_events)
		"keep_distance":
			_do_keep_distance(id, a, action, new_events)
		"gather_wood":
			_do_gather_wood(id, a, new_events)
		"ask_reason":
			_do_ask_reason(id, a, action, new_events)
		"observe_person":
			_do_observe_person(id, a, action, new_events)
		"ask_third_party":
			_do_ask_third_party(id, a, action, new_events)
		"sit_by_fire":
			_do_sit_by_fire(id, a, new_events)
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
				bush["regrow_day"] = int(world_time["day"]) + int(_economy["berry_regrow_days"])
			a["inventory"]["food"] = int(a["inventory"].get("food", 0)) + got
			a["needs"]["hunger"] = clampi(int(a["needs"]["hunger"]) - 300, 0, 1000)
			_emit("foraged", id, "%s 采到了 %d 份浆果" % [a["display_name"], got], {"food": got})
			_compliance_check(id, a, "food", got)
			_flatten_resources()
			return
	_emit("foraged_empty", id, "%s 找了一圈，浆果已经被采光了" % a["display_name"], {})

func _do_drink(id: String, a: Dictionary, ev: Array) -> void:
	for spring in world["water_springs"]:
		if spring == a["tile"]:
			a["needs"]["thirst"] = 0
			a["inventory"]["water"] = mini(3, int(a["inventory"].get("water", 0)) + 2)  # 顺手灌满水壶——水成为可分享资源
			(a.get("place_beliefs") as PlaceBelief).observe_place(spring, ["water"], tick)
			_emit("drank", id, "%s 喝了水，还灌满了水壶" % a["display_name"], {})
			return

func _do_fish(id: String, a: Dictionary, ev: Array) -> void:
	# 海里的鱼不多（默认 0.5 概率 1 份）——鱼叉有用但不是印钞机
	if _rng.randf() < float(_economy["fish_prob"]):
		var got := int(_economy["fish_amount"])
		a["inventory"]["food"] = int(a["inventory"].get("food", 0)) + got
		_emit("fished", id, "%s 捕到了一条鱼！" % a["display_name"], {"food": got})
		_compliance_check(id, a, "food", got)
	else:
		_emit("fished_empty", id, "%s 空手而归" % a["display_name"], {})

func _do_shells(id: String, a: Dictionary, ev: Array) -> void:
	a["inventory"]["shells"] = int(a["inventory"].get("shells", 0)) + 1
	_emit("gathered_shells", id, "%s 捡到了贝壳" % a["display_name"], {"shells": 1})

func _do_explore(id: String, a: Dictionary, ev: Array) -> void:
	a["visited_tiles"][str(a["tile"])] = true
	# 随机发现（好奇心驱动探索的奖励）——野果稀少，否则探索成了食物印钞机
	var roll := _rng.randf()
	if roll < float(_economy["explore_food_prob"]):
		a["inventory"]["food"] = int(a["inventory"].get("food", 0)) + 1
		_emit("explored_found", id, "%s 探索时意外发现了一些野果" % a["display_name"], {"food": 1})
	elif roll < float(_economy["explore_food_prob"]) + 0.01:
		a["physical"]["injured"] = true
		_emit("explored_hurt", id, "%s 探索时被蛇咬伤了！" % a["display_name"], {"injury": true})
	else:
		_emit("explored", id, "%s 探索了周围" % a["display_name"], {})

func _do_ruins(id: String, a: Dictionary, ev: Array) -> void:
	for ruin in world["ruins"]:
		if ruin["pos"] == a["tile"] and not bool(ruin["searched"]):
			ruin["searched"] = true
			var loot: Dictionary = ruin["loot"]
			if loot.is_empty():
				_emit("ruins_empty", id, "%s 翻遍了废弃营地，什么也没找到" % a["display_name"], {})
			else:
				for item in loot:
					a["inventory"][item] = int(a["inventory"].get(item, 0)) + int(loot[item])
				var loot_names: Array = []
				for item in loot:
					loot_names.append("%s×%d" % [item, loot[item]])
				_emit("ruins_loot", id, "%s 在废弃营地找到了 %s" % [a["display_name"], "、".join(loot_names)], loot)
			if loot.has("food"):
				_compliance_check(id, a, "food", int(loot["food"]))
			return

func _do_shelter(id: String, a: Dictionary, ev: Array) -> void:
	if int(a["inventory"].get("wood", 0)) >= 2:
		a["inventory"]["wood"] = int(a["inventory"]["wood"]) - 2
		world["shelters"][str(a["tile"])] = true
		_emit("shelter_built", id, "%s 搭建了一个简易庇护所" % a["display_name"], {"pos": str(a["tile"])})
		AuthoritySystem.self_identity(a, "shelter_built")

func _do_craft(id: String, a: Dictionary, ev: Array) -> void:
	if int(a["inventory"].get("shells", 0)) >= 1 and int(a["inventory"].get("wood", 0)) >= 1:
		a["inventory"]["shells"] = int(a["inventory"]["shells"]) - 1
		a["inventory"]["wood"] = int(a["inventory"]["wood"]) - 1
		a["inventory"]["fish_spear"] = 1
		_emit("crafted", id, "%s 制作了一把鱼叉" % a["display_name"], {"tool": "fish_spear"})
		AuthoritySystem.self_identity(a, "crafted")

func _do_fire(id: String, a: Dictionary, ev: Array) -> void:
	if int(a["inventory"].get("wood", 0)) >= 1:
		a["inventory"]["wood"] = int(a["inventory"]["wood"]) - 1
		world["fires"][str(a["tile"])] = true
		_emit("fire_lit", id, "%s 生了一堆火" % a["display_name"], {"pos": str(a["tile"])})

func _do_socialize(id: String, a: Dictionary, ev: Array) -> void:
	a["needs"]["social"] = clampi(int(a["needs"]["social"]) - 300, 0, 1000)
	var others: Array = []
	for other_id in actors:
		if other_id != id:
			others.append(actors[other_id]["display_name"])
	_emit("socialized", id, "%s 和 %s 聊了聊天" % [a["display_name"], "、".join(others)], {})

func _do_share(id: String, a: Dictionary, ev: Array) -> void:
	# 分享对象按【分享者的感知】挑（ToM hungry 感知槽），不读他人真实 hunger——
	# 看走眼（把不饿的人当饿了）是合法的感知误差，这正是人味来源
	if int(a["inventory"].get("food", 0)) < 2:
		return
	var hungriest := ""
	var hungriest_percept := 0.45  # 感知饥饿度阈值（0..1 尺度）
	var surplus := int(a["inventory"].get("food", 0)) >= 3
	var my_h_percept := clampf(float(a["needs"].get("hunger", 0)) / 1000.0, 0.0, 1.0)
	for other_id in actors:
		if other_id == id:
			continue
		# 感知门：我只知道"我以为他多饿"——来源是他开口要过/被我看见吃东西
		var per_hunger: float = a["tom"].belief_about(other_id, "hungry")
		var worth: bool = per_hunger > 0.45 or per_hunger > my_h_percept + 0.15 \
			or (surplus and per_hunger > 0.15)
		if worth and per_hunger > hungriest_percept and _is_nearby(a["tile"], actors[other_id]["tile"]):
			hungriest_percept = per_hunger
			hungriest = other_id
	if hungriest == "":
		return  # 没看到有谁需要——分享没有对象（事件流不记——没发生的事）
	a["inventory"]["food"] = int(a["inventory"]["food"]) - 1
	actors[hungriest]["inventory"]["food"] = int(actors[hungriest]["inventory"].get("food", 0)) + 1
	actors[hungriest]["needs"]["hunger"] = clampi(int(actors[hungriest]["needs"]["hunger"]) - 200, 0, 1000)
	_emit("shared_food", id, "%s 把食物分给了 %s" % [a["display_name"], actors[hungriest]["display_name"]],
		{"to_id": hungriest})

## P1.5: 请求-回应协议。提议者开口（一次决策），目标独立评估（第二次决策）。
## 接受/拒绝都产生事件 → 双方经 CognitiveTransition 完成评价/解释/信念/关系更新。
## 本函数不再直接修改任何认知状态（无固定 trust/norm 变化）——
## 并在目标决策时记录其预测（供预测误差学习）。
## P1.6 泛化请求执行：event 类型、库存项、缓解量、承诺全部来自 ResourceSpec——
## 加新资源不需要改这个函数。
func _do_request(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var target_id := str(action.get("target_actor", ""))
	var object_id := str(action.get("object", "food"))
	var spec: Dictionary = ResourceSpec.spec(object_id)
	var ev_prefix: String = {"food": "food", "water": "water", "fish_spear": "tool"}.get(object_id, "food")
	if not actors.has(target_id):
		return
	var target: Dictionary = actors[target_id]
	if not _is_nearby(a["tile"], target["tile"]):
		_emit("request_missed", id, "%s 想开口，但 %s 已经走远了" % [a["display_name"], target["display_name"]], {})
		return
	_emit(ev_prefix + "_requested", id, "%s 向 %s 要%s" % [a["display_name"], target["display_name"], str(spec["verb"])],
			{"target_id": target_id, "object": object_id})
	var trust_toward_proposer := relationships.composite_trust(target_id, id)
	var result: Dictionary = SocialSystem.evaluate_resource_request(target, a, object_id, trust_toward_proposer, _rng)
	(target.get("pending_predictions", []) as Array).append({
		"tick": tick, "about_id": id, "resolve_tick": tick + 24,
		"my_tile": target["tile"], "about_tile": a["tile"],
		"predictions": result.get("reactions_forecast", {}),
	})
	if bool(result.get("accepted", false)):
		target["inventory"][object_id] = int(target["inventory"].get(object_id, 0)) - 1
		a["inventory"][object_id] = int(a["inventory"].get(object_id, 0)) + 1
		if int(spec["relief"]) > 0:
			a["needs"][spec["need"]] = clampi(int(a["needs"][spec["need"]]) - int(spec["relief"]), 0, 1000)
		_emit(ev_prefix + "_request_accepted", target_id,
				"%s 把%s给了 %s" % [target["display_name"], str(spec["verb"]), a["display_name"]],
				{"proposer_id": id, "object": object_id})
		# 承诺被接受 → 债务台账（P1.6 #20）
		if bool(action.get("offers_promise", false)):
			obligations.append({"debtor": id, "creditor": target_id, "object": object_id,
					"made_tick": tick, "due_tick": tick + 96, "repaid": false})
			a["my_obligations"] = _obligations_of(id)
			target["owed_to_me"] = _owed_to(target_id)
			_emit("promise_made", id, "%s 说：『这份情我记下，以后报答』" % a["display_name"],
					{"to_id": target_id, "object": object_id})
	else:
		_emit(ev_prefix + "_request_refused", target_id,
				"%s 摇了摇头：%s——%s 的求助被拒绝了" % [target["display_name"], str(result.get("reason", "")), a["display_name"]],
				{"proposer_id": id, "object": object_id})

## P1.7b 寻人执行：走到记忆位置；人在则当场产生一次相遇（后续 ask_reason 由决策层接手）
func _do_seek_person(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var target_id := str(action.get("target_actor", ""))
	if not actors.has(target_id):
		return
	if _is_nearby(a["tile"], actors[target_id]["tile"]):
		_emit("found_person", id, "%s 找到了 %s" % [a["display_name"], actors[target_id]["display_name"]], {"to_id": target_id})
	else:
		_emit("person_not_found", id, "%s 扑了个空——人已经不在了" % a["display_name"], {})

## P1.7b 迁居执行：设新基地（熟悉度从零累积——搬家有真实成本）
func _do_relocate(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var target: Vector2i = action.get("target", a["tile"])
	a["base"] = target
	_emit("relocated", id, "%s 搬到了新住处" % a["display_name"], {"pos": str(target)})

## P2b 规则提议执行：公共讨论（PublicEvent）→ 各人独立表态 → InstitutionRecord
## 规则建立只记录客观事实"被正式建立过"；每个 NPC 的认知仍走 PerceivedGroupBelief
func _do_propose_rule(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var object_id := str(action.get("object", "food"))
	var fraction: float = float(action.get("fraction", 0.5))
	var goal_kind := str(action.get("goal_kind", ""))
	var rule := RuleDiscourse.build_rule(id, object_id, fraction)
	var audience: Array = []
	for other_id in actors:
		if other_id != id and _is_nearby(a["tile"], actors[other_id]["tile"]):
			audience.append(other_id)
	if audience.is_empty():
		return  # 没有公众就没有公共性
	var rule_text := "每次找到%s，拿出 %d%% 放到公共储备" % [ResourceSpec.spec(object_id)["verb"], int(fraction * 100)]
	_emit("rule_proposed", id, "%s 提出：『%s』" % [a["display_name"], rule_text],
			{"object": object_id, "rule": rule, "audience": audience.duplicate()})
	# 提议者自我表态（公开）
	RuleDiscourse.self_stance(a, rule, 1, audience.size() + 1, tick)
	var public_supports := 0
	# 每个在场者独立评估并公开表态（含反提案）——绝不同步修改信念
	for other_id in audience:
		var w: Dictionary = actors[other_id]
		var stance_eval: Dictionary = RuleDiscourse.evaluate_proposal(w, rule, relationships)
		RuleDiscourse.self_stance(w, rule, int(stance_eval["stance"]), audience.size() + 1, tick)
		var st := int(stance_eval["stance"])
		if st > 0:
			public_supports += 1
			_emit("rule_supported", other_id, "%s 公开表示同意" % w["display_name"], {"rule": rule, "object": object_id})
		elif st < 0:
			_emit("rule_opposed", other_id, "%s 说：『%s，这个比例太高了』" % [w["display_name"], str(stance_eval["reason"])], {"rule": rule, "object": object_id})
		else:
			_emit("rule_abstained", other_id, "%s 沉默不语" % w["display_name"], {"rule": rule, "object": object_id})
	# 所有目击者（含旁观）更新对群体立场的感知
	for wid in actors:
		if wid == id:
			continue
		if _is_nearby(a["tile"], actors[wid]["tile"]):
			RuleDiscourse.witness_stance(actors[wid], rule, id, 1, audience.size() + 1, tick)
			for other_id2 in audience:
				var st2 := 1 if str(actors[other_id2].get("last_rule_stance", "1")) == "1" else -1
				RuleDiscourse.witness_stance(actors[wid], rule, other_id2, st2, audience.size() + 1, tick)
	# amend 目标 → 规则修订事件（AA：新比例可能获得更高遵守）
	if goal_kind == "amend":
		for inst in institutions:
			if str(inst["rule"].get("object", "")) == object_id:
				inst["rule"]["fraction"] = fraction
				inst["revised_tick"] = tick
				break
		_emit("rule_revised", id, "%s 提议把比例改到 %d%%" % [a["display_name"], int(fraction * 100)], {"object": object_id, "fraction": fraction})
	# InstitutionRecord：客观事实——规则被公开提议且获得足够公开支持
	if public_supports >= 2:
		institutions.append({"rule": rule, "created_tick": tick, "supports": public_supports, "status": "active"})
		_emit("institution_established", id, "『%s』成了营地的正式约定" % rule_text, {"rule": rule, "object": object_id})

## 债务辅助（视图供给）
func _obligations_of(debtor: String) -> Array:
	var out: Array = []
	for ob in obligations:
		if str(ob["debtor"]) == debtor and not bool(ob["repaid"]):
			out.append(ob)
	return out

func _owed_to(creditor: String) -> Array:
	var out: Array = []
	for ob in obligations:
		if str(ob["creditor"]) == creditor and not bool(ob["repaid"]):
			out.append(ob)
	return out

## P1.6 还债执行：履约 → 可靠性上升（经 transition 的 PROMISE/FULFILLED 语义）
func _do_repay(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var creditor := str(action.get("target_actor", ""))
	var object_id := str(action.get("object", "food"))
	var spec: Dictionary = ResourceSpec.spec(object_id)
	if not actors.has(creditor) or int(a["inventory"].get(object_id, 0)) < 2:
		return
	if not _is_nearby(a["tile"], actors[creditor]["tile"]):
		return  # 人不在——下次再说
	a["inventory"][object_id] = int(a["inventory"][object_id]) - 1
	actors[creditor]["inventory"][object_id] = int(actors[creditor]["inventory"].get(object_id, 0)) + 1
	for ob in obligations:
		if str(ob["debtor"]) == id and str(ob["creditor"]) == creditor and str(ob["object"]) == object_id and not bool(ob["repaid"]):
			ob["repaid"] = true
			break
	a["my_obligations"] = _obligations_of(id)
	actors[creditor]["owed_to_me"] = _owed_to(creditor)
	_emit("promise_kept", id, "%s 把%s还给了 %s——他兑现了承诺" % [a["display_name"], str(spec["verb"]), actors[creditor]["display_name"]],
			{"to_id": creditor, "object": object_id})

## 承诺到期检查：违约 → 可靠性崩（无人在场也生效——不守信迟早传开）
func _check_overdue_promises() -> void:
	for ob in obligations:
		if not bool(ob["repaid"]) and tick > int(ob["due_tick"]):
			ob["repaid"] = true  # 标记完结防重复
			if actors.has(str(ob["debtor"])):
				actors[str(ob["debtor"])]["my_obligations"] = _obligations_of(str(ob["debtor"]))
			_emit("promise_broken", str(ob["debtor"]), "%s 没能兑现他的承诺" % actors[str(ob["debtor"])]["display_name"],
					{"to_id": str(ob["creditor"]), "object": str(ob["object"])})

## 预测误差学习：解决到期的社会预测——预测 vs 实际观察 → 修正响应模型
func _resolve_predictions() -> void:
	for decider_id in actors:
		var decider: Dictionary = actors[decider_id]
		var pending: Array = decider.get("pending_predictions", [])
		var keep: Array = []
		for pred in pending:
			if tick < int(pred.get("resolve_tick", 0)):
				keep.append(pred)
				continue
			var about_id := str(pred.get("about_id", ""))
			if actors.has(about_id):
				_observe_and_learn(decider, pred, about_id)
		decider["pending_predictions"] = keep

func _observe_and_learn(decider: Dictionary, pred: Dictionary, about_id: String) -> void:
	var tom: TheoryOfMind = decider.get("tom", null)
	if tom == null:
		return
	var since := int(pred.get("tick", 0))
	var predictions: Dictionary = pred.get("predictions", {})
	if predictions.is_empty():
		return
	var observed := {}
	for e in events:
		if int(e.get("tick", 0)) <= since:
			continue
		var t := str(e.get("type", ""))
		if t == "food_requested" and str(e.get("actor_id", "")) == about_id:
			if str(e.get("target_id", "")) == str(decider.get("id", "")):
				observed["asks_me_again"] = 1.0
			else:
				observed["asks_other"] = 1.0
		elif (t == "shared_food" and str(e.get("actor_id", "")) == about_id and str(e.get("to_id", "")) == str(decider.get("id", ""))) \
			or (t == "food_request_accepted" and str(e.get("actor_id", "")) == about_id and str(e.get("proposer_id", "")) == str(decider.get("id", ""))):
			observed["shares_with_me"] = 1.0
	# 距离观察：她现在比预测时离我更远很多 → 她在回避我
	if actors.has(about_id):
		var my_tile: Vector2i = decider["tile"]
		var her_tile: Vector2i = actors[about_id]["tile"]
		var dist_now := absi(my_tile.x - her_tile.x) + absi(my_tile.y - her_tile.y)
		var my_then: Vector2i = pred.get("my_tile", my_tile)
		var her_then: Vector2i = pred.get("about_tile", her_tile)
		var dist_then := absi(my_then.x - her_then.x) + absi(my_then.y - her_then.y)
		if dist_now - dist_then >= 4:
			observed["avoids_me"] = 1.0
		elif dist_now - dist_then <= 1:
			observed["avoids_me"] = 0.0
	# 误差 → 修正响应模型
	var total_error := 0.0
	var n := 0
	for dim in observed:
		if not predictions.has(dim):
			continue
		var p_val := float(predictions[dim])
		var o_val := float(observed[dim])
		var err := absf(p_val - o_val)
		total_error += err
		n += 1
		tom.update_response(about_id, dim, o_val, 0.3 + err * 0.5)
	if n > 0:
		tom.record_prediction_error(tick, about_id, total_error / n)

func _do_rest(id: String, a: Dictionary, ev: Array) -> void:
	a["needs"]["energy"] = clampi(int(a["needs"]["energy"]) + 400, 0, 1000)
	a["needs"]["hunger"] = clampi(int(a["needs"]["hunger"]) + 100, 0, 1000)
	_emit("rested", id, "%s 休息了一会儿" % a["display_name"], {})

## P2c 合规决策：获取资源后，若【我认知里】存在有效规则 → 交/少交/不交
## 违规事件只被附近者目击（感知门）——独处时的违规 = 隐藏违规，世界知道而人不知
func _compliance_check(id: String, a: Dictionary, object_id: String, amount: int) -> void:
	if amount <= 0:
		return
	var dec: Dictionary = ComplianceSystem.decide_on_acquisition(a, object_id, amount)
	var mode := str(dec.get("mode", "NONE"))
	if mode == "NONE":
		return
	var contribute := int(dec.get("contribute", 0))
	if contribute > 0:
		contribute = mini(contribute, int(a["inventory"].get(object_id, 0)))
		a["inventory"][object_id] = int(a["inventory"].get(object_id, 0)) - contribute
		world["common_storage"] = world.get("common_storage", {})
		world["common_storage"][object_id] = int(world["common_storage"].get(object_id, 0)) + contribute
		_emit("storage_contributed", id, "%s 按约定把 %d 份%s放进了公共储备" % [a["display_name"], contribute, ResourceSpec.spec(object_id)["verb"]],
				{"object": object_id, "amount": contribute, "mode": mode})
	else:
		_emit("storage_withheld", id, "%s 找到了%s，但没有按约定交公" % [a["display_name"], ResourceSpec.spec(object_id)["verb"]],
				{"object": object_id, "mode": mode, "rule_id": str(dec.get("rule_id", ""))})
		# 违规者自己也知道刚才有谁在场（检测估计的事后校验）
		AuthoritySystem.self_identity(a, "acquire_" + object_id)
		# DecisionTrace v5：制度决策全程留痕（P3a 的唯一信息源）
		a["last_institution_trace"] = {"tick": tick, "rule_id": str(dec.get("rule_id", "")), "mode": mode,
			"contribute": contribute, "detected_estimate": ComplianceSystem.estimate_detection(a)}

func _do_eat(id: String, a: Dictionary, ev: Array) -> void:
	if int(a["inventory"].get("food", 0)) < 1:
		return
	a["inventory"]["food"] = int(a["inventory"]["food"]) - 1
	a["needs"]["hunger"] = clampi(int(a["needs"]["hunger"]) - 350, 0, 1000)
	_emit("ate_food", id, "%s 吃了些存粮" % a["display_name"], {"food": -1})

## P1.6 认识行动执行——调查也必须经过感知/声明系统，绝不直接读真相
func _do_ask_reason(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var about := str(action.get("target_actor", ""))
	if not actors.has(about):
		return
	var target: Dictionary = actors[about]
	_emit("reason_asked", id, "%s 问 %s：那天为什么不帮我？" % [a["display_name"], target["display_name"]], {"to_id": about})
	# 回应：本人陈述（第一版诚实——说自己的真实主要原因；说谎是 Phase 2）
	var claim_prop := {}
	if int(target["inventory"].get("food", 0)) < 2:
		claim_prop = {"subject": about, "predicate": "has_food", "value": -0.8, "label": "我自己也没粮了"}
	else:
		claim_prop = {"subject": about, "predicate": "has_food", "value": 0.4, "label": "我想留着应急"}
	var express: float = float(target["personality"].traits.get("expressiveness", 0.5))
	if express < 0.25:
		# 闷葫芦：问不出话——但这本身也是信息（他不愿说）
		_emit("reason_deflected", about, "%s 沉默了一会儿，什么也没说" % target["display_name"], {"to_id": id})
		_close_question(id, about)
		return
	var claim := Claim.build(about, claim_prop, tick)
	Claim.listen(a, claim, relationships)
	_emit("reason_claimed", about, "%s 说：『%s』" % [target["display_name"], claim_prop["label"]], {"to_id": id, "claim": claim_prop["label"]})
	_close_question(id, about)

func _do_observe_person(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var about := str(action.get("target_actor", ""))
	if not actors.has(about):
		return
	a["observing"] = {"about": about, "until": tick + 12}  # 注意力增益在 CognitiveTransition
	_emit("observing_person", id, "%s 开始不动声色地留意 %s" % [a["display_name"], actors[about]["display_name"]], {"to_id": about})
	# 观察不立即关问题：证据随目击累积，问题由证据自行解决或过期

func _do_ask_third_party(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var third := str(action.get("target_actor", ""))
	var about := str(action.get("about_actor", ""))
	if not actors.has(third) or not actors.has(about):
		return
	var third_a: Dictionary = actors[third]
	_emit("asked_about", id, "%s 悄悄问 %s：最近见过 %s 拿到吃的吗？" % [a["display_name"], third_a["display_name"], actors[about]["display_name"]], {"to_id": third, "about": about})
	# 第三人转述的是【他自己的感知】（ToM 信念），不是真相
	var their_belief: float = third_a["tom"].raw_belief(about, "has_food")
	if absf(their_belief) < 0.1:
		_emit("third_party_unknown", third, "%s 摇头：没太注意过" % third_a["display_name"], {"to_id": id})
		return
	var claim_prop := {"subject": about, "predicate": "has_food", "value": their_belief,
		"label": "我见过他最近空手而归" if their_belief < 0.0 else "我见他搞到过吃的"}
	var claim := Claim.build(third, claim_prop, tick)
	Claim.listen(a, claim, relationships)
	_emit("third_party_claimed", third, "%s 说：『%s』" % [third_a["display_name"], claim_prop["label"]], {"to_id": id, "about": about})
	_close_question(id, about)

func _close_question(id: String, about: String) -> void:
	var qs: Array = actors[id].get("open_questions", [])
	for i in range(qs.size()):
		if str(qs[i].get("about", "")) == about:
			qs.remove_at(i)
			break
	actors[id]["open_questions"] = qs

func _do_gather_wood(id: String, a: Dictionary, ev: Array) -> void:
	for tree in world["trees"]:
		if absi(tree.x - a["tile"].x) + absi(tree.y - a["tile"].y) <= 1:
			a["inventory"]["wood"] = int(a["inventory"].get("wood", 0)) + 1
			_emit("gathered_wood", id, "%s 拾了一些柴火" % a["display_name"], {"wood": 1})
			return
	_emit("gather_wood_empty", id, "%s 找了一圈，附近没有合适的柴" % a["display_name"], {})

## 火边休憩：恢复精力、缓解恐惧、降低孤独（营地效应）
func _do_sit_by_fire(id: String, a: Dictionary, ev: Array) -> void:
	a["needs"]["energy"] = clampi(int(a["needs"]["energy"]) + 200, 0, 1000)
	a["needs"]["social"] = clampi(int(a["needs"]["social"]) - 80, 0, 1000)
	# 营地=共同在场：火边有同伴时，这就是社交（同 socialized 事件，下游全兼容）
	var company: Array = []
	for other_id in actors:
		if other_id != id and absi(actors[other_id]["tile"].x - a["tile"].x) + absi(actors[other_id]["tile"].y - a["tile"].y) <= 3:
			company.append(actors[other_id]["display_name"])
	if company.size() > 0:
		a["needs"]["social"] = clampi(int(a["needs"]["social"]) - 150, 0, 1000)
		_emit("socialized", id, "%s 和 %s 在火边聊了聊天" % [a["display_name"], "、".join(company)], {})
	else:
		a["personality"].adjust_emotion("fear", -0.1)
		_emit("sat_by_fire", id, "%s 独自在篝火边坐了一会儿" % a["display_name"], {})

## 回避：朝远离目标的方向走（不是 fallback——回避是主动的合法行为）
func _do_keep_distance(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var avoid_id := str(action.get("avoid_of", ""))
	if not actors.has(avoid_id):
		return
	var their: Vector2i = actors[avoid_id]["tile"]
	var mine: Vector2i = a["tile"]
	# 候选：沿"远离他"的方向走 3 格
	var dir := mine - their
	if dir == Vector2i.ZERO:
		dir = Vector2i(1, 1)
	var candidates := [mine + Vector2i(sign(dir.x) * 3, 0), mine + Vector2i(0, sign(dir.y) * 3),
		mine + Vector2i(sign(dir.x) * 2, sign(dir.y) * 2)]
	var best: Vector2i = mine
	var best_dist := absi(mine.x - their.x) + absi(mine.y - their.y)
	for c in candidates:
		if c.x < 2 or c.y < 2:
			continue
		if map_query.is_walkable_tile(Vector3i(c.x, 0, c.y)):
			var d := absi(c.x - their.x) + absi(c.y - their.y)
			if d > best_dist:
				best_dist = d
				best = c
	if best != mine:
		_move_toward(a, best)
	_emit("kept_distance", id, "%s 悄悄拉开了距离" % a["display_name"], {"avoid_of": avoid_id})

# ── 系统更新 ──

func _update_world_time() -> void:
	world_time["hour"] = int(world_time["hour"]) + 1
	if int(world_time["hour"]) >= 24:
		world_time["hour"] = 0
		world_time["day"] = int(world_time["day"]) + 1
		_daily_update()
	world["is_night"] = int(world_time["hour"]) >= 20 or int(world_time["hour"]) < 6

func _daily_update() -> void:
	# 浆果丛刷新（默认 5 天一茬；岛上养不活三个人——匮乏驱动社交）
	for bush in world["berry_bushes"]:
		if int(bush["food"]) <= 0 and int(world_time["day"]) >= int(bush.get("regrow_day", 9999)):
			bush["food"] = int(_economy["berry_food"])
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
			actors[id]["physical"]["wet"] = true  # 情绪反应由 CognitiveTransition 处理
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
	# P1.6 被动感知（看脸色）：身边的人的饥饿是中等可见状态——
	# 观察者获得朝真实方向、但按可见度衰减的噪声证据（≠直读真值）
	for id in actors:
		var a6: Dictionary = actors[id]
		var vis: float = 0.35 + float(a6["personality"].traits.get("empathy", 0.5)) * 0.25  # 共情高的人看得准
		for other_id in world["nearby_" + id]:
			var true_h: float = clampf(float(actors[other_id]["needs"].get("hunger", 0)) / 1000.0, 0.0, 1.0)
			if true_h > 0.5:
				a6["tom"].add_evidence(other_id, "hungry", 1.0, 0.12 * vis, -1, tick)
			elif true_h < 0.25:
				a6["tom"].add_evidence(other_id, "hungry", -1.0, 0.10 * vis, -1, tick)
	# P1.7c 遭遇图：共同在场时长（≤8 格）与互动计数——社会网络拓扑的实测数据
	for id in actors:
		for other_id in actors:
			if other_id <= id or other_id == id:
				continue  # 每对只记一次
			var d7 := absi(actors[id]["tile"].x - actors[other_id]["tile"].x) + absi(actors[id]["tile"].y - actors[other_id]["tile"].y)
			var dyad := "%s|%s" % [id, other_id]
			if d7 <= 8:
				if not _encounters.has(dyad):
					_encounters[dyad] = {"co_presence": 0, "interactions": 0, "voluntary": 0}
				_encounters[dyad]["co_presence"] = int(_encounters[dyad]["co_presence"]) + 1
				# 主动接触：任一方的当前行动以对方为目标（求助/找人/认识行动）
				var ca1 = actors[id].get("current_action", {})
				var ca2 = actors[other_id].get("current_action", {})
				if (ca1 != null and str(ca1.get("target_actor", "")) == other_id) or (ca2 != null and str(ca2.get("target_actor", "")) == id):
					_encounters[dyad]["voluntary"] = int(_encounters[dyad]["voluntary"]) + 1
	# P1.6 感知门：「谁看起来饿了」由各观察者的 ToM 感知决定，不读真实 hunger；
	# 病伤是高可见状态（可观察性分级），保留直读
	var anyone_appears_hungry := false
	var anyone_needs_help := false
	for id in actors:
		var appears := false
		for other_id in world["nearby_" + id]:
			if float(actors[id]["tom"].belief_about(other_id, "hungry")) > 0.4:
				appears = true
		world["appears_hungry_" + id] = appears
		if appears:
			anyone_appears_hungry = true
		if bool(actors[id]["physical"].get("sick", false)) or bool(actors[id]["physical"].get("injured", false)):
			anyone_needs_help = true
	world["someone_hungry_nearby"] = anyone_appears_hungry  # 兼容键：语义=有人看起来饿了
	world["someone_needs_help_nearby"] = anyone_needs_help

func _build_actor_view(id: String, a: Dictionary) -> Dictionary:
	# P1: 决策需要的社交信息——ToM、对每人的信任、附近有谁（不含他们的隐私状态）
	var trust_of := {}
	var others_nearby: Array = []
	var others_visible: Array = []
	var others_all: Array = []
	for other_id in actors:
		if other_id == id:
			continue
		trust_of[other_id] = relationships.get_trust(id, other_id)
		var otile: Vector2i = actors[other_id]["tile"]
		others_all.append({"id": other_id, "tile": otile})
		var d := absi(a["tile"].x - otile.x) + absi(a["tile"].y - otile.y)
		if d <= 12:
			others_visible.append({"id": other_id, "tile": otile})  # 喊话/可视范围：求助可以走过去问
		if other_id in world.get("nearby_" + id, []):
			others_nearby.append({"id": other_id, "tile": otile})
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
		"others_visible": others_visible,
		"others_all": others_all,
		"norms": a.get("norms", {}),
		"my_obligations": a.get("my_obligations", []),
			"open_questions": a.get("open_questions", []),
			"institutional_goals": a.get("institutional_goals", []),
			"place_beliefs": a.get("place_beliefs", PlaceBelief.new()),
			"base": a.get("base", a["tile"]),
			"_relationships_hint": relationships,
			"_owed_hint": clampf(float((a.get("my_obligations", []) as Array).size()) / 2.0, 0.0, 1.0),  # P1.6: 未解之惑进决策视野——不然永远没人去问
		"social_stance": a.get("social_stance", {}),
		"grudges": a.get("grudges", {}),
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
	# P1.5：目击者一律经 CognitiveTransition 处理——
	# 主观事件 → 记忆检索 → 评价 → 解释竞争 → 信念/情绪/关系/倾向更新 → 主观记忆。
	# 禁止任何旁路直接改情绪/信任/规范。
	# P1.7e 最小注意力预算：同一时刻最多 3 个目击者进入深层认知（按相关性排序）
	# 危险/涉及自己/新颖事件优先——保证 P2 多事件并发时 NPC 不会全知
	var witnesses: Array = []
	for id in actors:
		var a: Dictionary = actors[id]
		var is_witness: bool = id == actor_id or _is_nearby(actors[actor_id]["tile"] if actors.has(actor_id) else Vector2i.ZERO, a["tile"])
		if is_witness:
			var salience := 0.5
			if id == actor_id or str(e.get("proposer_id", "")) == id or str(e.get("to_id", "")) == id or str(e.get("target_id", "")) == id:
				salience = 1.0  # 事件涉及我
			elif ["explored_hurt", "weather_storm"].has(str(e.get("type", ""))):
				salience = 0.9  # 危险
			witnesses.append({"id": id, "a": a, "salience": salience})
	witnesses.sort_custom(func(x, y): return float(x["salience"]) > float(y["salience"]))
	for w in witnesses.slice(0, 3):
		var id = w["id"]
		var a: Dictionary = w["a"]
		if id != actor_id and actors.has(actor_id):
			a["tom"].see_at(actor_id, actors[actor_id]["tile"], tick)  # 我看见他在哪
		CognitiveTransition.process(a, e, {"relationships": relationships, "tick": tick})
		# P2d: 目击违规 → 执行反应（公共品困境：管或不管）+ 执行期望学习
		if str(e.get("type", "")) == "storage_withheld" and id != actor_id:
			var violator_rid := str(e.get("rule_id", ""))
			var reaction: Dictionary = ComplianceSystem.react_to_violation(a, str(actor_id), violator_rid)
			if str(reaction["reaction"]) == "CONFRONT":
				_emit("confronted_violation", id, "%s 当面质问 %s：约定呢？" % [a["display_name"], actors[actor_id]["display_name"]], {"to_id": str(actor_id), "rule_id": violator_rid})
				ComplianceSystem.learn_enforcement(a, violator_rid, true, tick)
				if actors.has(actor_id):
					ComplianceSystem.learn_enforcement(actors[actor_id], violator_rid, true, tick)
				# 被罚 → 可靠度证据（经既有管线，非直改）
				a["tom"].add_evidence(str(actor_id), "reliable", -1.0, ComplianceSystem.violation_evidence_weight(PersonalityDynamics.dynamics(a["personality"], a.get("sensitivities", {}), a.get("norms", {}))), int(e.get("seq", 0)), tick)
			else:
				ComplianceSystem.learn_enforcement(a, violator_rid, false, tick)  # 沉默 → 执行力下降（大家都知道但没人管）
			# AD: 违规者若是规则提案者 → 权威崩塌
			var rid_prop := str(e.get("rule_id", ""))
			if a.get("perceived_group_beliefs", {}).has(rid_prop):
				var rule_d: Dictionary = a["perceived_group_beliefs"][rid_prop].get("rule", {})
				if str(rule_d.get("proposer", "")) == str(actor_id):
					AuthoritySystem.authority_violation(a, str(actor_id), int(e.get("seq", 0)), tick)
		# P2.1: 目击公共提案/表态 → 我知道这条规则存在（recognition，≠期待大家守）
		if str(e.get("type", "")) == "rule_proposed" and e.has("rule"):
			var prule: Dictionary = e.get("rule", {})
			var prid := str(prule.get("rule_id", ""))
			if not a.get("perceived_group_beliefs", {}).has(prid):
				a["perceived_group_beliefs"][prid] = {"rule": prule, "member_stance": {}, "publicity": 0.0, "shared_expectation": 0.0, "recognition": 1.0}
			else:
				a["perceived_group_beliefs"][prid]["recognition"] = 1.0
		# P2e: 目击能力行为 → 领域权威证据（涌现角色）
		AuthoritySystem.observe_competence(a, str(e.get("type", "")), str(actor_id), int(e.get("seq", 0)), tick)
		# P2e-4: 公开支持 → 提案者协调权威
		if str(e.get("type", "")) == "rule_supported":
			AuthoritySystem.public_endorsement(a, str(e.get("actor_id", "")), int(e.get("seq", 0)), tick)
			# P2a: 目击行为 → 我的局部规律观察（约定涌现，非全局统计）
		var sem11: Dictionary = ResourceSpec.semantics_of(e)
		if sem11.has("act") and id != actor_id:
			if (str(sem11["act"]) == "GIVE" and str(sem11.get("response", "")) == "DONE") or (str(sem11["act"]) == "REQUEST" and str(sem11.get("response", "")) == "ACCEPT"):
				ConventionSystem.observe(a, "GIVE:" + str(sem11.get("object", "food")), true, tick)
			elif str(sem11["act"]) == "REQUEST" and str(sem11.get("response", "")) == "REFUSE":
				ConventionSystem.observe(a, "GIVE:" + str(sem11.get("object", "food")), false, tick)
				# 协调摩擦 → 制度目标（我们需要个规矩）
				if str(e.get("proposer_id", "")) == id and ConventionSystem.should_seek_rule(a, str(sem11.get("object", "food")), 0.6):
					var goals9: Array = a.get("institutional_goals", [])
					goals9.append({"object": str(sem11.get("object", "food")), "kind": "we_need_a_rule", "tick": tick})
					a["institutional_goals"] = goals9
	return int(e["seq"])

## 远离目标方向的可行走格（回避用）
func _away_tile(mine: Vector2i, their: Vector2i) -> Vector2i:
	var dir := mine - their
	if dir == Vector2i.ZERO:
		dir = Vector2i(1, 1)
	for c in [mine + Vector2i(sign(dir.x) * 3, 0), mine + Vector2i(0, sign(dir.y) * 3), mine + Vector2i(sign(dir.x) * 2, sign(dir.y) * 2)]:
		if c.x > 2 and c.y > 2 and map_query.is_walkable_tile(Vector3i(c.x, 0, c.y)):
			return c
	return mine

func _is_nearby(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) <= 8

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
