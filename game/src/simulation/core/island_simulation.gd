class_name IslandSimulation
extends RefCounted

const FIXED_LOCATION_ACTIONS := ["forage_berries", "drink_water", "fish", "gather_shells",
	"search_ruins", "gather_wood", "search_resource_source"]
const TRAVEL_STALL_LIMIT := 8
const Contract = preload("res://src/simulation/material_request/material_request_contract.gd")
const CommitmentContract = preload("res://src/simulation/commitment/commitment_contract.gd")
const CommitmentPolicy = preload("res://src/simulation/commitment/commitment_offer_policy.gd")
const MATERIAL_REQUEST_RETRYABLE_REASONS := [
	"REQUEST_EXPIRED",
	"TARGET_MISSING",
	"GIVER_INVENTORY_CHANGED",
	"TRANSFER_FAILED",
	"REQUEST_QUANTITY_STALE",
]
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

# P6.2 AgencyActionBridge 运行模式：OFF（默认，旧行为逐位不变）/ SHADOW（只记录）/ LIVE_BRIDGE（salient 进考虑集）
var agency_mode := "OFF"
# P6.3B-1 §三：计划执行开关（默认 false——不改变任何现有行为）。
# true 时仅在 LIVE_BRIDGE 下允许计划步骤候选参与考虑集；其他模式只观察不执行。
var agency_plan_execution_enabled := false
# P6.3B-4：根目标因果价值向当前计划步骤传播。独立开关默认 false，便于与旧执行路径 paired 对照。
var agency_causal_step_value_enabled := false
# P6.4: proposal admission and commitment, independent from step execution.
var agency_plan_adoption_enabled := false
# P7.0：UNKNOWN_SOURCE → 搜索/询问信息子目标。默认 false，framework 基线不变。
var agency_information_subgoals_enabled := false
var _information_tracker_state: InformationSubgoalTracker = null
# P7.1B：真实材料 blocker -> 主观持有者请求 -> 协商 -> 真实转移 -> 父计划重验。
# 默认 false，framework / information 的既有轨迹不变。
var agency_material_requests_enabled := false
var _material_request_runtime: MaterialRequestRuntimeBridge = null
# P7.2：条件承诺（交换 counter -> PENDING -> 转移激活 -> 履约/违约 -> 认知后果）。
# 默认 false，既有 profile 行为不变；权威台账仍是 obligations（单台账）。
var agency_commitment_consequences_enabled := false
var _commitment_runtime: CommitmentRuntimeBridge = null
# P7.2B：NO_SUBJECTIVE_TARGET → FIND_HOLDER 信息目标 → 开放式询问 → 来源化持有证据
# → 同一 material request 重新选目标。默认 false；旧 profile 行为不变。
var agency_holder_evidence_reachability_enabled := false
# P7.2C：C1 主观找人 + C2 询问仲裁 + C-0 客观材料审计。默认 false；
# 行为变化只在此 profile 开启；诊断计数器本身 write-only。
var agency_holder_reachability_enabled := false
# P7.2C C-0B：objective material-availability audit —— 只存在于诊断层的
# 真实世界持有者统计（行为系统绝不读取）；write-only，不入 state 编码。
var _objective_material_audit := {}
# P7.2C C-0A：仲裁探针——_agency_prepare 写入本轮 best ask 候选（utility 最大），
# 决策产出后对比胜者。write-only 诊断，绝不反向影响候选或决策。
var _holder_arbitration_probe: Dictionary = {}

# P7.2B-R1.1：opportunity funnel 诊断计数——纯加性、只写不读、不参与任何行为/
# RNG/排序决策；不进入 state 编码（audit 排除），仅随 summary 输出供分析器消费。
var _holder_funnel_diag := {}
# 信息交换使用独立随机流，避免一次询问消耗天气、捕鱼等世界随机序列。
var _information_rngs := {}
var _adoption_rngs := {}
var _adoption_traces: Array = []
var _world_seed := 0
# P6.3B-3：无进展上限按真正错失的决策机会计数；同值继续作为取消后的冷却 tick 数。
var agency_no_progress_timeout := 16
var _plan_tracker: PlanExecutionTracker = null
var _item_catalog: ItemCatalog = null
var _recipe_catalog: RecipeCatalog = null
var _agency_store: WorldKnowledgeStore = null
var _agency_cache := {}  # actor_id -> {hash, problems, proposals}
var agency_planner_calls := 0
var agency_cache_hits := 0
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
	_world_seed = seed
	_economy = {
		"berry_count": 4, "berry_food": 1, "berry_regrow_days": 5,
		"fish_prob": 0.5, "fish_amount": 1, "explore_food_prob": 0.015,
		"bush_capacity": 2,  # P5.2：每丛每再生窗口的份数（多人共享一丛；每次仍采 1）
	}.duplicate()
	for k in economy_overrides:
		if _economy.has(k):
			_economy[k] = economy_overrides[k]
	_init_world_resources()
	_init_actors(actor_configs)
	# P5：初始感知——落地时看一眼周围（他们刚上岛，只知道眼前的世界）
	var rect: Rect2i = map_query.get_map_rect()
	for id in actors:
		(actors[id]["spatial"] as SpatialBeliefMap).configure(rect)
		SpatialPerception.perceive(self, actors[id])

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
		berry_bushes.append({"pos": pos, "food": int(_economy["bush_capacity"]), "regrow_day": -1})
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
			"spatial": SpatialBeliefMap.new(),  # P5: 空间信念图（每人独立——只有看过的格子）
			"nav_plan": {},  # P5: 主观导航计划缓存 {target_key, path, tick}
			"norms": _init_norms(cfg.get("norms", {})),  # P1.5: personal/descriptive/injunctive 三层
			"social_stance": {},    # P1.5: 对每人的接近/回避倾向（解释系统写入）
			"pending_predictions": [],
			"place_beliefs": PlaceBelief.new(),  # P1.7: 地点信念（每人不同）
			"base": cfg.get("spawn", Vector2i(10, 10)),  # P1.7: 现居基地  # P1.5: 我对他人反应的预测（待观察验证）
			"grudges": {},          # P1.5: 已形成的记恨（可被新证据推翻）
			"last_transition": {},  # P1.5: 最近一次认知转移摘要（DecisionTrace 用）
			"last_decision_trace": {},
			"last_institution_trace": {},
			"memories": [],
			"open_questions": [],
			"observing": {},
			"claims_received": [],
			"institutional_goals": [],
			"observed_regularities": {},
			"conventions": [],
			"perceived_group_beliefs": {},
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
	if agency_material_requests_enabled:
		new_events.append_array(_material_requests_expire_due())
	if agency_commitment_consequences_enabled:
		_commitments_check_due()
	if agency_holder_evidence_reachability_enabled:
		_holder_goals_sync_all()
	# P7.2C C-0C：每 tick 携带统计（write-only；不读取、不参与行为）。
	if agency_holder_reachability_enabled:
		_record_material_carriage_ticks()

	# P5：感知先行——视野（昼夜/天气/LOS）→ 空间信念 + last_seen；决策只看信念
	for id in actors:
		SpatialPerception.perceive(self, actors[id])

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
			var insight_records: Array = result.get("insight_records", [])
			if insight_records.is_empty():
				for insight in result.get("insights", []):
					_emit("reflected", id, "%s" % str(insight), {})
			else:
				for record in insight_records:
					_emit("reflected", id, str(record.get("text", "")), {
						"reflection_kind": str(record.get("kind", "reflection")),
						"about_id": str(record.get("about_id", "")),
						"source_event_ids": (record.get("source_event_ids", []) as Array).duplicate(),
					})
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
	if agency_material_requests_enabled:
		_material_requests_process_actor(id, a, new_events)
	# 如果正在执行行动，倒计时
	if int(a.get("action_ticks_left", 0)) > 0:
		# 追踪移动：指向人的行动逐 tick 走向对方（对方会走动，追不上=扑空）；
		# 带地点目标的行动（采集/打水/伐木/探废墟）同样边走边执行——
		# 否则 2-tick 行动总在半路完成（67 次伐木 0 成功的死因）
		var cur_action: Dictionary = a.get("current_action", {})
		# P6.3B-2: if the actor's latest perception explicitly disconfirms the
		# resource target that justified this action, stop before further travel or
		# work. This reads the actor knowledge view, never world resource truth.
		if ActionTargetContract.is_disconfirmed(cur_action, _known_resources_view(a)):
			_abort_invalidated_action(id, a, new_events)
			return
		if cur_action.has("target_actor") and actors.has(str(cur_action["target_actor"])):
			# P5（SN-B 修复）：目标在视野内 → 实时追踪合法并刷新 last_seen；
			# 不在视野内 → 只用记忆位置（扑空是真实结果）。不再读真坐标当 GPS。
			var tgt_id := str(cur_action["target_actor"])
			var pursue_tile: Vector2i
			if _actor_visible_to(a, tgt_id):
				pursue_tile = actors[tgt_id]["tile"]
				(a["tom"] as TheoryOfMind).see_at(tgt_id, pursue_tile, tick)
			else:
				var ls: Dictionary = (a["tom"] as TheoryOfMind).last_seen_of(tgt_id)
				pursue_tile = ls.get("tile", a["tile"]) if not ls.is_empty() else a["tile"]
			var away := str(cur_action.get("action", "")) == "keep_distance"
			if away:
				pursue_tile = _away_tile(a["tile"], pursue_tile, a.get("spatial", null))
			if a["tile"] != pursue_tile:
				_move_toward(a, pursue_tile)
		elif _requires_fixed_location(cur_action) and cur_action["target"] != a["tile"]:
			var before_tile: Vector2i = a["tile"]
			_move_toward(a, cur_action["target"])
			if a["tile"] == before_tile:
				a["action_travel_stall_ticks"] = int(a.get("action_travel_stall_ticks", 0)) + 1
			else:
				a["action_travel_stall_ticks"] = 0
			# Travel and work are separate phases: work duration starts only after arrival.
			if a["tile"] != cur_action["target"]:
				if int(a["action_travel_stall_ticks"]) >= TRAVEL_STALL_LIMIT:
					_abort_unreachable_action(id, a, new_events)
				else:
					a["activity"] = "前往" + str(cur_action.get("desc", cur_action.get("action", "目标")))
				return
		elif cur_action.has("target") and typeof(cur_action["target"]) == TYPE_VECTOR2I and cur_action["target"] != a["tile"]:
			_move_toward(a, cur_action["target"])
		a["action_ticks_left"] = int(a["action_ticks_left"]) - 1
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
	# P6.2：决策边界提供主观 proposals/bridge mode（OFF 时不做任何事——旧行为逐位不变）
	var agency_extra := _agency_prepare(id, a) if str(agency_mode) != "OFF" else {}
	if agency_extra.has("information_goal"):
		actor_view["information_subgoal"] = (agency_extra["information_goal"] as Dictionary).duplicate(true)
	var decision: Dictionary = DecisionEngine.decide(actor_view, world, _rng, agency_extra)
	if agency_holder_evidence_reachability_enabled \
			and str(decision.get("action", "")) == "ask_item_holder":
		_holder_diag_inc("holder_ask_actions_selected")
	if agency_holder_reachability_enabled \
			and str(decision.get("action", "")) == "seek_holder_person":
		_holder_diag_inc("holder_seek_actions_selected")
	# P7.2C C-0A：询问仲裁诊断——只在 ACTIVE HOLDER goal 存在且本轮有 ask 候选时记录。
	# 读取已产生的 decision（不重算、不耗 RNG）；write-only。
	if agency_holder_reachability_enabled \
			and str(decision.get("action", "")) != "ask_item_holder" \
			and _holder_arbitration_probe != null:
		_record_inquiry_arbitration_loss(actor_view, decision)
	if agency_holder_reachability_enabled \
			and str(decision.get("action", "")) == "ask_item_holder" \
			and _holder_arbitration_probe != null:
		_record_inquiry_arbitration_win(decision)
	a["current_action"] = decision
	a["action_ticks_left"] = int(decision.get("duration", 1))
	a["action_travel_stall_ticks"] = 0
	a["activity"] = str(decision.get("desc", "？"))

	# P0: 把 trace 写回真实 actor（DecisionEngine 只写了 view 副本）
	if actor_view.has("last_decision_trace"):
		a["last_decision_trace"] = actor_view["last_decision_trace"]
	_enrich_trace(a, decision, gm)
	a.erase("_execution_receipt")
	if actor_view.has("_execution_receipt"):
		a["_execution_receipt"] = actor_view["_execution_receipt"].duplicate(true)
	# P6.3B-1：决策后通知执行 tracker（选中/暂停/前提失效）
	_plan_execution_on_decision(id, a, decision, agency_extra)

	# 如果目标不是当前位置，先移动（每 tick 1 格）
	var target = decision.get("target", null)
	if target != null and typeof(target) == TYPE_VECTOR2I:
		if a["tile"] != target:
			_move_toward(a, target)
			a["visited_tiles"][str(a["tile"])] = true

## P6.2：决策边界协调器——构造/缓存主观 ctx+proposals（bounded：hash 缓存，不每 tick 重规划）
func _recipe_catalog_if_any() -> RecipeCatalog:
	_ensure_catalogs()
	return _recipe_catalog

func _item_catalog_if_any() -> ItemCatalog:
	_ensure_catalogs()
	return _item_catalog

func _agency_prepare(id: String, a: Dictionary) -> Dictionary:
	if _agency_store == null:
		_agency_store = KnowledgePack.load_island_pack()
	var ctx := AgencyContextBuilder.build(self, a)
	var h := AgencyContextBuilder.context_hash(ctx)
	var problems: Array = ctx.get("activated_problems", [])
	var cached: Dictionary = _agency_cache.get(id, {})
	var proposals: Array = []
	if not cached.is_empty() and str(cached.get("hash", "")) == h and str(cached.get("problems", "")) == str(problems):
		proposals = cached.get("proposals", [])
		agency_cache_hits += 1
	else:
		for problem in problems:
			for p in MeansEndsPlanner.propose_plans(str(problem), _agency_store, ctx, _recipe_catalog_if_any(), _item_catalog_if_any()):
				proposals.append(p)
		_agency_planner_slim(proposals)
		_agency_cache[id] = {"hash": h, "problems": str(problems), "proposals": proposals}
		agency_planner_calls += 1
	var out := {"mode": str(agency_mode), "ctx": ctx, "context_hash": h,
		"problems": problems, "proposals": proposals,
		"causal_step_value_enabled": agency_causal_step_value_enabled}
	if agency_material_requests_enabled and str(agency_mode) == "LIVE_BRIDGE":
		out["material_requests_enabled"] = true
		var revalidated: Dictionary = _execution_tracker().consume_parent_revalidation(id, proposals, tick)
		if not revalidated.is_empty() and bool(revalidated.get("ok", false)):
			_emit("PARENT_PLAN_REVALIDATED", id, "%s 在材料到位后重新验证父计划" % a["display_name"], {
				"plan_id": str(revalidated.get("plan_id", "")),
				"transfer_event_id": str(revalidated.get("transfer_event_id", "")),
			})
	# P7.2：可解材料 blocker 进入主观估值（§十六修复——证据仅来自角色自己的认知）；
	# ACTIVE 承诺成为可竞争的履约计划。两者都只在 commitment profile 出现。
	if agency_commitment_consequences_enabled and str(agency_mode) == "LIVE_BRIDGE":
		out["commitment_consequences_enabled"] = true
		_annotate_blocker_resolution(id, proposals, ctx)
		var obligation_plans := _commitment_obligation_plans(id, a)
		if not obligation_plans.is_empty():
			proposals.append_array(obligation_plans)
	# P7.0：从结构化 UNKNOWN_SOURCE blocker 形成一个当前信息子目标。
	# tracker 只拿主观 ctx、proposals 和自身 needs，不接触地图真值。
	if agency_information_subgoals_enabled and str(agency_mode) == "LIVE_BRIDGE":
		var information_goal := _information_tracker().prepare(id, proposals, ctx,
			{"needs": a["needs"].duplicate(true)}, tick, _item_catalog_if_any())
		if not information_goal.is_empty():
			out["information_goal"] = information_goal
		# P7.2B-R1.1：opportunity funnel（只计数，不改变任何决策输入）。
		if agency_holder_evidence_reachability_enabled \
				and str(information_goal.get("query_kind", "SOURCE")) == "HOLDER" \
				and str(information_goal.get("state", "")) == "ACTIVE":
			_holder_diag_inc("holder_decision_ticks")
			var diag_view := _build_actor_view(id, a)
			diag_view["now_tick"] = tick
			information_goal["holder_reachability_enabled"] = agency_holder_reachability_enabled
			var asked_ids: Array = information_goal.get("asked_actor_ids", [])
			var excluded_ids: Array = information_goal.get("excluded_target_ids", [])
			var visible_count := 0
			var eligible_count := 0
			for peer in (diag_view.get("others_visible", []) as Array):
				visible_count += 1
				var peer_id := str((peer as Dictionary).get("id", ""))
				if asked_ids.has(peer_id):
					_holder_diag_inc("holder_peer_excluded_already_asked")
				elif excluded_ids.has(peer_id):
					_holder_diag_inc("holder_peer_excluded_request_refused")
				else:
					eligible_count += 1
			if visible_count > 0:
				_holder_diag_inc("holder_ticks_with_visible_peers")
			if eligible_count > 0:
				_holder_diag_inc("holder_ticks_with_eligible_peers")
			else:
				_holder_diag_inc("holder_ticks_with_no_eligible_peer")
			var diag_candidates := InformationActionPolicy.build(diag_view, information_goal, tick)
			_holder_diag_inc("holder_ask_candidates_emitted", diag_candidates.size())
			# P7.2C C-0A：best ask 候选探针（不改真实候选顺序）。
			if agency_holder_reachability_enabled and not diag_candidates.is_empty():
				var best_ask: Dictionary = diag_candidates[0]
				for dc in diag_candidates:
					if float((dc as Dictionary).get("utility", 0.0)) > float(best_ask.get("utility", 0.0)):
						best_ask = dc
				_holder_arbitration_probe = {
					"actor_id": id, "goal_id": str(information_goal.get("goal_id", "")),
					"item_id": str(information_goal.get("item_id", "")),
					"best_utility": float(best_ask.get("utility", 0.0)),
					"target_actor": str(best_ask.get("target_actor", "")),
				}
				_holder_diag_inc("holder_ask_candidate_ticks")
				_record_objective_material_audit(id, str(information_goal.get("item_id", "")))
			else:
				_holder_arbitration_probe = {}
			# P7.2C C-0B：objective audit 无论有无候选都采样（决策 tick 粒度）。
			if agency_holder_reachability_enabled and diag_candidates.is_empty():
				_record_objective_material_audit(id, str(information_goal.get("item_id", "")))
	# P6.3B-1 §三/§五：仅 LIVE_BRIDGE + 显式开启时，当前执行步骤进入决策（其他模式只观察）
	if agency_plan_execution_enabled and str(agency_mode) == "LIVE_BRIDGE":
		var tracker := _execution_tracker()
		var adoption := {}
		if agency_plan_adoption_enabled:
			if not _adoption_rngs.has(id):
				var plan_rng := RandomNumberGenerator.new()
				plan_rng.seed = SeedDeriver.derive(_world_seed, "plan_adoption:" + id)
				_adoption_rngs[id] = plan_rng
			var personality: PersonalityProfile = a["personality"]
			var dynamics := PersonalityDynamics.dynamics(personality, a.get("sensitivities", {}), a.get("norms", {}))
			var subjective_self := {"needs": a["needs"].duplicate(true), "traits": personality.traits.duplicate(true),
				"commitment_strength": dynamics["commitment_strength"]}
			adoption = PlanAdoptionPolicy.deliberate(subjective_self, tracker.adoption_candidates(id, proposals, tick),
				tracker.runs.get(id, {}), _adoption_rngs[id])
			adoption["actor_id"] = id
			adoption["tick"] = tick
			adoption["context_hash"] = h
			_adoption_traces.append(adoption.duplicate(true))
			a["last_plan_adoption"] = adoption.duplicate(true)
		var prep: Dictionary = tracker.prepare_decision(id, proposals, ctx, tick, adoption)
		# R1 §五：decision_tick = sim 真实决策 tick（world["tick"] 在 step 末才更新，
		# trace["tick"] 会滞后一位——新鲜性校验必须用显式携带的 decision_tick）
		out["decision_tick"] = tick
		if not prep.is_empty():
			out["execution_step"] = prep
			out["catalog"] = _recipe_catalog_if_any()
			out["items"] = _item_catalog_if_any()
	return out

## P7.0：信息子目标 tracker 与只读诊断接口。
func _information_tracker() -> InformationSubgoalTracker:
	if _information_tracker_state == null:
		_information_tracker_state = InformationSubgoalTracker.new()
	return _information_tracker_state

func agency_information_trace() -> Array:
	if _information_tracker_state == null:
		return []
	return _information_tracker_state.trace_snapshot()

func agency_information_goal(actor_id: String) -> Dictionary:
	if _information_tracker_state == null:
		return {}
	return _information_tracker_state.current_goal(actor_id)

func _information_rng(actor_id: String) -> RandomNumberGenerator:
	if not _information_rngs.has(actor_id):
		var rng := RandomNumberGenerator.new()
		rng.seed = SeedDeriver.derive(_world_seed, "information_exchange:" + actor_id)
		_information_rngs[actor_id] = rng
	return _information_rngs[actor_id]

func agency_information_rng_states() -> Dictionary:
	var states := {}
	var ids: Array = _information_rngs.keys()
	ids.sort()
	for id in ids:
		states[id] = str((_information_rngs[id] as RandomNumberGenerator).state)
	return states

## P6.3B-1：tracker 访问器（超时配置同步）+ 只读 trace/run 暴露
func _execution_tracker() -> PlanExecutionTracker:
	if _plan_tracker == null:
		_plan_tracker = PlanExecutionTracker.new()
	_plan_tracker.no_progress_timeout = agency_no_progress_timeout
	return _plan_tracker

func agency_execution_trace() -> Array:
	if _plan_tracker == null:
		return []
	return _plan_tracker.traces.duplicate(true)

func agency_plan_run(actor_id: String) -> Dictionary:
	if _plan_tracker == null:
		return {}
	return (_plan_tracker.runs.get(actor_id, {}) as Dictionary).duplicate(true)

## 决策后通知 tracker：只接受当次执行凭据，不从旧认知 trace 重挂身份。
## 继续意图也会启动新的物理行动；与仍在执行同一次行动严格区分。
## 选中时把行动身份存到 actor（不污染共享 Registry 候选对象），完成时原样带回。
func _plan_execution_on_decision(id: String, a: Dictionary, decision: Dictionary, agency_extra: Dictionary = {}) -> void:
	if not agency_plan_execution_enabled or str(agency_mode) != "LIVE_BRIDGE":
		return
	# Consume once; historical cognitive traces cannot authorize a new physical attempt.
	var ex: Dictionary = a.get("_execution_receipt", {})
	a.erase("_execution_receipt")
	if typeof(ex.get("decision_tick")) != TYPE_INT or ex["decision_tick"] != tick:
		return
	if ex.get("actor_id", "") != id or ex.get("chosen_key", "") != AgencyActionBridge.candidate_key(decision):
		return
	if ex.get("selection_mode", "") not in ["SOFTMAX", "INTENTION_CONTINUE"]:
		return
	var current_run := agency_plan_run(id)
	if ex.get("run_id", "") != current_run.get("run_id", "") or ex.get("step_id", "") != current_run.get("current_step_id", ""):
		return
	var ident: Dictionary = _execution_tracker().on_decision(id, decision, ex, tick)
	a["_plan_exec_inflight"] = ident
	var blocker_triggers := ["MATERIALS_MISSING", "NO_KNOWN_SOURCE", "NO_REGISTRY_CANDIDATE"]
	if agency_commitment_consequences_enabled:
		# P7.2 §十六：未知来源材料在计划里是 SUBGOAL(find X) 步骤——只在新
		# profile 把它的 INERT 也视作"材料可解缺口"（旧 profile 行为冻结）。
		blocker_triggers.append("SUBGOAL_INERT")
	if agency_material_requests_enabled and str(ex.get("blocker_reason", "")) in blocker_triggers:
		_material_requests_on_blocker(id, a, ex, agency_extra)

## P6.3B-1 §六 + R1 §四：行动完成回调——事件段 + 实际库存 + 行动身份；
## tracker 核对 run_id/attempt_id/step_id/candidate_key 与实际结果
func _plan_execution_on_complete(id: String, a: Dictionary, action: Dictionary, event_segment: Array) -> void:
	if not agency_plan_execution_enabled or str(agency_mode) != "LIVE_BRIDGE":
		return
	var identity: Dictionary = a.get("_plan_exec_inflight", {})
	a.erase("_plan_exec_inflight")
	_execution_tracker().on_action_complete(id, action, event_segment, a["inventory"], tick, identity)

func _information_subgoal_on_complete(id: String, a: Dictionary, action: Dictionary, event_segment: Array) -> void:
	if not agency_information_subgoals_enabled or str(agency_mode) != "LIVE_BRIDGE" \
			or _information_tracker_state == null:
		return
	var ctx_after := AgencyContextBuilder.build(self, a)
	_information_tracker_state.on_action_complete(id, action, event_segment, ctx_after, tick)

func _material_request_runtime_bridge() -> MaterialRequestRuntimeBridge:
	if _material_request_runtime == null:
		_material_request_runtime = MaterialRequestRuntimeBridge.new(_world_seed)
	return _material_request_runtime

func agency_material_request_trace() -> Array:
	if _material_request_runtime == null:
		return []
	return _material_request_runtime.trace_snapshot()

func agency_material_request_rng_states() -> Dictionary:
	if _material_request_runtime == null:
		return {}
	return _material_request_runtime.rng_states()

func agency_material_request(request_id: String) -> Dictionary:
	if _material_request_runtime == null:
		return {}
	return _material_request_runtime.request(request_id)

func _material_requests_on_blocker(id: String, a: Dictionary, execution: Dictionary, agency_extra: Dictionary) -> void:
	var run := agency_plan_run(id)
	if run.is_empty():
		return
	var step := _material_run_step(run, str(execution.get("step_id", "")))
	if step.is_empty():
		return
	var ctx: Dictionary = agency_extra.get("ctx", AgencyContextBuilder.build(self, a))
	var recipes: RecipeCatalog = agency_extra.get("catalog", _recipe_catalog_if_any())
	var root_goal := str(run.get("root_goal", ""))
	var result := _material_request_runtime_bridge().ensure_request_for_blocker(
		id,
		run,
		step,
		ctx,
		tick,
		recipes,
		_material_need_urgency(a, root_goal),
		str(execution.get("blocker_reason", ""))
	)
	if bool(result.get("created", false)):
		_emit_material_request_event("MATERIAL_REQUEST_CREATED", str(result.get("request", {}).get("requester_id", id)),
			result.get("request", {}))

func _material_requests_expire_due() -> Array:
	var out: Array = []
	for request in _material_request_runtime_bridge().expire_due(tick):
		_commitments_on_request_terminal(request, "SOURCE_REQUEST_FAILED", "REQUEST_EXPIRED")
		_emit_material_request_event("MATERIAL_REQUEST_EXPIRED", str(request.get("requester_id", "")), request)
		out.append(events[events.size() - 1])
	return out

func _material_requests_process_actor(id: String, a: Dictionary, new_events: Array) -> void:
	var bridge := _material_request_runtime_bridge()
	var actor_view := _build_actor_view(id, a)
	var pending := bridge.pending_requests_for(id)
	for request in pending:
		var stale_reason := _material_request_run_mismatch_reason(str(request.get("requester_id", "")), request)
		if stale_reason != "":
			bridge.fail_request(str(request.get("request_id", "")), tick, stale_reason)
			_commitments_on_request_terminal(request, "SOURCE_REQUEST_FAILED", stale_reason)
			_emit_material_request_event("MATERIAL_REQUEST_FAILED", str(request.get("requester_id", "")), request, {
				"reason": stale_reason,
			})
			continue
		var requester_id := str(request.get("requester_id", ""))
		var target_id := str(request.get("target_id", ""))
		if requester_id == id:
			_material_requests_process_requester(id, a, actor_view, request, new_events)
		if target_id == id and str(bridge.request(str(request.get("request_id", ""))).get("status", "")) == Contract.STATUS_WAITING_RESPONSE:
			_material_requests_process_responder(id, a, request, new_events)
	for request in bridge.restartable_terminal_requests_for(id):
		_material_requests_restart_if_still_needed(id, a, request)

func _material_requests_process_requester(
	requester_id: String,
	a: Dictionary,
	actor_view: Dictionary,
	request: Dictionary,
	new_events: Array
) -> void:
	var bridge := _material_request_runtime_bridge()
	var status := str(request.get("status", ""))
	match status:
		Contract.STATUS_ACTIVE:
			var beliefs := bridge.build_holder_beliefs(requester_id, str(request.get("item_id", "")), actor_view, tick)
			var offered := bridge.try_offer(str(request.get("request_id", "")), beliefs, tick)
			if bool(offered.get("ok", false)):
				_emit_material_request_event("MATERIAL_REQUEST_OFFERED", requester_id, offered.get("request", {}))
				# P7.2B：同 source_request_id 的真实 OFFERED 是 HOLDER 目标的唯一完成条件。
				if agency_holder_evidence_reachability_enabled:
					_information_tracker().resolve_holder_goal(requester_id, str(request.get("request_id", "")), tick)
			elif agency_holder_evidence_reachability_enabled \
					and str(offered.get("reason", "")) == "NO_SUBJECTIVE_TARGET":
				# 我不知道谁有 X——这本身就是向身边人打听的理由（开放询问入口）。
				# P7.2C C2：parent blockedness 随 run BLOCKED 驻留时长进入询问权重。
				var _run_for_block := agency_plan_run(requester_id)
				var _blocked_ticks := 0.5
				if not _run_for_block.is_empty() and str(_run_for_block.get("state", "")) == "BLOCKED":
					_blocked_ticks = clampf(float(tick - int(_run_for_block.get("updated_tick", tick))) / 48.0 + 0.5, 0.0, 1.0)
				request["parent_blockedness"] = _blocked_ticks
				_information_tracker().prepare_holder(requester_id, request, tick,
					bridge.excluded_targets_for(str(request.get("request_id", ""))),
					clampf(float(request.get("urgency", 0.5)), 0.0, 1.0))
		Contract.STATUS_WAITING_REQUESTER:
			var current_gap := _material_request_current_gap(requester_id, a, request)
			var counter: Dictionary = request.get("last_counter", {})
			if current_gap <= 0:
				if bridge.cancel_request(str(request.get("request_id", "")), tick, "NO_LONGER_NEEDED"):
					_emit_material_request_event("MATERIAL_REQUEST_CANCELLED", requester_id, request, {
						"reason": "NO_LONGER_NEEDED",
					})
			elif bool(counter.get("requires_exchange", false)):
				var handled := false
				if agency_commitment_consequences_enabled and not (counter.get("terms", {}) as Dictionary).is_empty():
					handled = _commitments_handle_exchange_counter(requester_id, a, request, new_events)
				if not handled:
					var rejected_condition := bridge.reject_counter(
						str(request.get("request_id", "")), tick, "COUNTER_CONDITION_UNSUPPORTED")
					if bool(rejected_condition.get("ok", false)):
						_emit_material_request_event("MATERIAL_COUNTER_REJECTED", requester_id,
							rejected_condition.get("request", {}), {"reason": "COUNTER_CONDITION_UNSUPPORTED"})
			elif int(request.get("accepted_quantity", 0)) > current_gap:
				var cancelled_stale := bridge.cancel_request(
					str(request.get("request_id", "")), tick, "REQUEST_QUANTITY_STALE")
				if cancelled_stale:
					_emit_material_request_event("MATERIAL_REQUEST_CANCELLED", requester_id,
						bridge.request(str(request.get("request_id", ""))), {"reason": "REQUEST_QUANTITY_STALE"})
			else:
				var accepted := bridge.accept_counter(str(request.get("request_id", "")), tick)
				if bool(accepted.get("ok", false)):
					_emit_material_request_event("MATERIAL_COUNTER_ACCEPTED", requester_id, accepted.get("request", {}))
					_material_requests_try_transfer(requester_id, a, accepted.get("request", {}), new_events)
		Contract.STATUS_WAITING_TRANSFER:
			_material_requests_try_transfer(requester_id, a, request, new_events)

func _material_requests_process_responder(
	responder_id: String,
	a: Dictionary,
	request: Dictionary,
	new_events: Array
) -> void:
	var requester_id := str(request.get("requester_id", ""))
	if not actors.has(requester_id) or not _is_nearby(a["tile"], actors[requester_id]["tile"]):
		return
	var bridge := _material_request_runtime_bridge()
	var context := _material_recipient_context(responder_id, requester_id, str(request.get("item_id", "")))
	var result := bridge.respond(str(request.get("request_id", "")), responder_id, context, tick)
	if not bool(result.get("ok", false)):
		return
	var response: Dictionary = result.get("response", {})
	var outcome := str(response.get("outcome", ""))
	var event_name: String = {
		Contract.OUTCOME_ACCEPT: "MATERIAL_REQUEST_ACCEPTED",
		Contract.OUTCOME_REFUSE: "MATERIAL_REQUEST_REFUSED",
		Contract.OUTCOME_COUNTER: "MATERIAL_REQUEST_COUNTERED",
		Contract.OUTCOME_UNKNOWN: "MATERIAL_REQUEST_UNKNOWN_RESPONSE",
	}.get(outcome, "MATERIAL_REQUEST_UNKNOWN_RESPONSE")
	_emit_material_request_event(event_name, requester_id, result.get("request", {}), {
		"responder_id": responder_id,
		"response_outcome": outcome,
		"response_reason": str(response.get("reason", "")),
	})
	if outcome == Contract.OUTCOME_ACCEPT:
		_material_requests_try_transfer(requester_id, actors[requester_id], result.get("request", {}), new_events)

func _material_requests_try_transfer(
	requester_id: String,
	requester: Dictionary,
	request: Dictionary,
	new_events: Array
) -> void:
	var target_id := str(request.get("target_id", ""))
	if not actors.has(target_id):
		_material_request_runtime_bridge().fail_request(str(request.get("request_id", "")), tick, "TARGET_MISSING")
		_commitments_on_request_terminal(request, "SOURCE_REQUEST_FAILED", "TARGET_MISSING")
		_emit_material_request_event("MATERIAL_REQUEST_FAILED", requester_id, request, {"reason": "TARGET_MISSING"})
		return
	if not _is_nearby(requester["tile"], actors[target_id]["tile"]):
		return
	var current_gap := _material_request_current_gap(requester_id, requester, request)
	if current_gap <= 0:
		if _material_request_runtime_bridge().cancel_request(str(request.get("request_id", "")), tick, "NO_LONGER_NEEDED"):
			_commitments_on_request_terminal(request, "SOURCE_REQUEST_FAILED", "NO_LONGER_NEEDED")
			_emit_material_request_event("MATERIAL_REQUEST_CANCELLED", requester_id, request, {
				"reason": "NO_LONGER_NEEDED",
			})
		return
	if int(request.get("accepted_quantity", 0)) > current_gap:
		if _material_request_runtime_bridge().cancel_request(str(request.get("request_id", "")), tick, "REQUEST_QUANTITY_STALE"):
			_commitments_on_request_terminal(request, "SOURCE_REQUEST_FAILED", "REQUEST_QUANTITY_STALE")
			_emit_material_request_event("MATERIAL_REQUEST_CANCELLED", requester_id, request, {
				"reason": "REQUEST_QUANTITY_STALE",
			})
		return
	var result := _material_request_runtime_bridge().transfer(
		str(request.get("request_id", "")),
		actors[target_id]["inventory"],
		requester["inventory"],
		tick
	)
	if bool(result.get("ok", false)):
		var transfer_event: Dictionary = result.get("event", {})
		_emit_material_transfer_event(target_id, transfer_event)
		_emit_material_request_event("MATERIAL_REQUEST_RESOLVED", requester_id, result.get("request", {}), {
			"transfer_event_id": str(transfer_event.get("event_id", "")),
		})
		_commitments_on_transfer_success(requester_id, result.get("request", {}), transfer_event)
		_material_requests_handle_revalidation(result)
	else:
		_commitments_on_request_terminal(request, "SOURCE_TRANSFER_FAILED",
			str(result.get("reason", "TRANSFER_FAILED")))
		_emit_material_request_event("MATERIAL_TRANSFER_FAILED", requester_id, result.get("request", request), {
			"reason": str(result.get("reason", "TRANSFER_FAILED")),
		})

func _material_requests_handle_revalidation(transfer_result: Dictionary) -> void:
	var request: Dictionary = transfer_result.get("request", {})
	var revalidation: Dictionary = transfer_result.get("revalidation", {})
	if request.is_empty() or revalidation.is_empty():
		return
	var requester_id := str(request.get("requester_id", ""))
	if not actors.has(requester_id):
		return
	var token := _execution_tracker().request_parent_revalidation(
		requester_id,
		str(request.get("parent_plan_id", "")),
		tick,
		str(revalidation.get("transfer_event_id", "")),
		str(request.get("parent_run_id", "")),
		str(request.get("blocker_step_id", ""))
	)
	if token.is_empty():
		return
	_emit_material_request_event("PARENT_PLAN_REVALIDATION_REQUESTED", requester_id, request, {
		"plan_id": str(request.get("parent_plan_id", "")),
		"transfer_event_id": str(revalidation.get("transfer_event_id", "")),
	})
	# A partial counter may leave the same material gap. Start the next request now
	# from the refreshed subjective context; the old request is already terminal.
	var requester: Dictionary = actors[requester_id]
	var run := agency_plan_run(requester_id)
	if run.is_empty() or str(run.get("plan_id", "")) != str(request.get("parent_plan_id", "")):
		return
	var step := _material_run_step(run, str(request.get("blocker_step_id", "")))
	if step.is_empty():
		return
	var ctx := AgencyContextBuilder.build(self, requester)
	var follow_up := _material_request_runtime_bridge().ensure_request_for_blocker(
		requester_id,
		run,
		step,
		ctx,
		tick,
		_recipe_catalog_if_any(),
		_material_need_urgency(requester, str(run.get("root_goal", ""))),
		str(request.get("blocker_reason", "")),
		str(request.get("request_id", "")),
		"PARTIAL_TRANSFER"
	)
	if bool(follow_up.get("created", false)):
		_emit_material_request_event("MATERIAL_REQUEST_CREATED", requester_id, follow_up.get("request", {}), {
			"retry_of_request_id": str(request.get("request_id", "")),
			"previous_terminal_reason": "PARTIAL_TRANSFER",
		})

func _material_requests_restart_if_still_needed(requester_id: String, a: Dictionary, old_request: Dictionary) -> void:
	var terminal_reason := _material_request_terminal_reason(old_request)
	if terminal_reason not in MATERIAL_REQUEST_RETRYABLE_REASONS:
		return
	if _material_request_run_mismatch_reason(requester_id, old_request) != "":
		return
	var current_gap := _material_request_current_gap(requester_id, a, old_request)
	if current_gap <= 0:
		return
	var run := agency_plan_run(requester_id)
	var step := _material_run_step(run, str(old_request.get("blocker_step_id", "")))
	if step.is_empty():
		return
	var ctx := AgencyContextBuilder.build(self, a)
	var result := _material_request_runtime_bridge().ensure_request_for_blocker(
		requester_id,
		run,
		step,
		ctx,
		tick,
		_recipe_catalog_if_any(),
		_material_need_urgency(a, str(run.get("root_goal", ""))),
		str(old_request.get("blocker_reason", "")),
		str(old_request.get("request_id", "")),
		terminal_reason
	)
	if bool(result.get("created", false)):
		_emit_material_request_event("MATERIAL_REQUEST_CREATED", requester_id, result.get("request", {}), {
			"retry_of_request_id": str(old_request.get("request_id", "")),
			"previous_terminal_reason": terminal_reason,
		})

func _material_request_terminal_reason(request: Dictionary) -> String:
	var reason := str(request.get("response_reason", ""))
	if reason == "" and str(request.get("status", "")) == Contract.STATUS_EXPIRED:
		return "REQUEST_EXPIRED"
	return reason

func _material_request_current_gap(requester_id: String, a: Dictionary, request: Dictionary) -> int:
	var run := agency_plan_run(requester_id)
	if _material_request_run_mismatch_reason(requester_id, request) != "":
		return 0
	var step := _material_run_step(run, str(request.get("blocker_step_id", "")))
	if step.is_empty():
		return 0
	var gap := _material_request_runtime_bridge().material_gap(
		step,
		run,
		AgencyContextBuilder.build(self, a),
		_recipe_catalog_if_any()
	)
	return int(gap.get("quantity", 0))

func _material_request_run_mismatch_reason(requester_id: String, request: Dictionary) -> String:
	var run := agency_plan_run(requester_id)
	if run.is_empty() or str(run.get("run_id", "")) != str(request.get("parent_run_id", "")):
		return "PARENT_RUN_CHANGED"
	if str(run.get("plan_id", "")) != str(request.get("parent_plan_id", "")):
		return "PARENT_RUN_CHANGED"
	if str(run.get("current_step_id", "")) != str(request.get("blocker_step_id", "")):
		return "BLOCKER_CHANGED"
	return ""

func _material_recipient_context(responder_id: String, requester_id: String, item_id: String) -> Dictionary:
	var responder: Dictionary = actors[responder_id]
	var traits: Dictionary = (responder["personality"] as PersonalityProfile).traits
	var trust := relationships.composite_trust(responder_id, requester_id)
	var relationship_value := MaterialRequestRuntimeBridge.relationship_signal(trust)
	var trust_value := MaterialRequestRuntimeBridge.trust_probability(trust)
	var need_pressure := _material_need_pressure(responder, item_id)
	var obligations_count := (responder.get("my_obligations", []) as Array).size()
	var context := {
		"inventory_quantity": int(responder["inventory"].get(item_id, 0)),
		"reserve_quantity": 0,
		"relationship": relationship_value,
		"trust": trust_value,
		"generosity": clampf((float(traits.get("altruism", 0.5)) + float(traits.get("empathy", 0.5))) * 0.5, 0.0, 1.0),
		"own_need_pressure": need_pressure,
		"risk_aversion": clampf(float(traits.get("caution", 0.5)), 0.0, 1.0),
		"commitment_load": clampf(float(obligations_count) / 3.0, 0.0, 1.0),
		"exchange_offer_value": 0.0,
	}
	if agency_commitment_consequences_enabled:
		# §十四：负担来自权威台账（ACTIVE 承诺 + 旧未偿 obligations）。
		context["commitment_load"] = CommitmentPolicy.commitment_load(
			_commitment_runtime_bridge().tracker.active_count_for_load(obligations, responder_id))
		# §七：承诺估值只来自 B 自己的认知——ToM reliable 信念、关系、互惠规范、
		# 以及 B 直接知道的"欠我的债"（不读 A 的真实未来或其他人的库存）。
		var tom: TheoryOfMind = responder.get("tom", null)
		var reliability_belief := 0.5
		if tom != null:
			reliability_belief = clampf((tom.belief_about(requester_id, "reliable") + 1.0) * 0.5, 0.0, 1.0)
		var owed_to_me := 0
		for record in obligations:
			if typeof(record) == TYPE_DICTIONARY \
					and str(record.get("debtor_id", record.get("debtor", ""))) == requester_id \
					and str(record.get("creditor_id", record.get("creditor", ""))) == responder_id \
					and CommitmentContract.counts_toward_load(record):
				owed_to_me += 1
		context["exchange_offer_value"] = CommitmentPolicy.estimate_promise_value({
			"debtor_reliability_belief": reliability_belief,
			"relationship": relationship_value,
			"own_reciprocity_norm": clampf(float(responder.get("norms", {}).get("personal", {}).get("reciprocity", 0.5)), 0.0, 1.0),
			"debtor_visible_commitment_load": clampf(float(owed_to_me) / 3.0, 0.0, 1.0),
		})
		context["exchange_terms_enabled"] = true
		# 谨慎的债权人要求更快回款（条款窗口随 risk_aversion 收紧）——
		# 与 A 的主观期限估计共同构成条款分歧的自然来源。
		context["exchange_due_ticks"] = maxi(96, int(float(CommitmentContract.DEFAULT_DUE_TICKS)
			* (1.3 - 0.5 * float(context["risk_aversion"]))))
	return context

func _material_need_pressure(actor: Dictionary, item_id: String) -> float:
	var tags: Array = _item_catalog_if_any().tags_of(item_id)
	var need_key := ""
	if tags.has("FOOD_ITEM"):
		need_key = "hunger"
	elif tags.has("WATER_ITEM"):
		need_key = "thirst"
	if need_key != "":
		return clampf(float(actor["needs"].get(need_key, 0)) / 1000.0, 0.0, 1.0)
	return clampf(maxf(float(actor["needs"].get("hunger", 0)), float(actor["needs"].get("thirst", 0))) / 2000.0, 0.0, 1.0)

func _material_need_urgency(actor: Dictionary, root_goal: String) -> float:
	var need_key: String = {"HUNGER": "hunger", "THIRST": "thirst", "ISOLATION": "social"}.get(root_goal, "")
	if need_key == "":
		return 0.5
	return clampf(float(actor["needs"].get(need_key, 0)) / 1000.0, 0.0, 1.0)

func _material_run_step(run: Dictionary, step_id: String) -> Dictionary:
	for step in run.get("steps", []):
		if typeof(step) == TYPE_DICTIONARY and str(step.get("step_id", "")) == step_id:
			return (step as Dictionary).duplicate(true)
	return {}

func _emit_material_request_event(
	event_type: String,
	requester_id: String,
	request: Dictionary,
	extra: Dictionary = {}
) -> void:
	var payload := {
		"request_id": str(request.get("request_id", "")),
		"requester_id": str(request.get("requester_id", requester_id)),
		"target_id": str(request.get("target_id", "")),
		"parent_plan_id": str(request.get("parent_plan_id", "")),
		"parent_run_id": str(request.get("parent_run_id", "")),
		"blocker_step_id": str(request.get("blocker_step_id", "")),
		"blocker_reason": str(request.get("blocker_reason", "")),
		"item_id": str(request.get("item_id", "")),
		"quantity": int(request.get("requested_quantity", 0)),
		"accepted_quantity": int(request.get("accepted_quantity", 0)),
		"request_status": str(request.get("status", "")),
	}
	for key in extra:
		payload[key] = extra[key]
	_emit(event_type, requester_id, _material_request_event_text(event_type, request), payload)

func _emit_material_transfer_event(giver_id: String, transfer_event: Dictionary) -> void:
	var payload := transfer_event.duplicate(true)
	payload.erase("type")
	_emit(Contract.EVENT_ITEM_TRANSFER_COMPLETED, giver_id,
		"%s 将材料交给了 %s" % [giver_id, str(transfer_event.get("to_actor_id", ""))], payload)

func _material_request_event_text(event_type: String, request: Dictionary) -> String:
	return "%s %s %s" % [event_type, str(request.get("requester_id", "")), str(request.get("item_id", ""))]

# ── P7.2：条件承诺（权威台账 = obligations，单台账） ──

func _holder_diag_inc(key: String, n: int = 1) -> void:
	_holder_funnel_diag[key] = int(_holder_funnel_diag.get(key, 0)) + n

## P7.2C C-0A：行动类别分类（纯字符串映射，无 RNG、无行为读取）。
const ACTION_CATEGORY := {
	"forage_berries": "SURVIVAL", "drink_water": "SURVIVAL", "fish": "SURVIVAL",
	"gather_shells": "SURVIVAL", "gather_wood": "SURVIVAL", "search_ruins": "SURVIVAL",
	"rest": "SURVIVAL", "sit_by_fire": "SURVIVAL", "build_shelter": "SURVIVAL",
	"do_nothing": "SURVIVAL", "repay_debt": "OBLIGATION",
	"request_share": "SOCIAL", "request_water": "SOCIAL", "request_tool": "SOCIAL",
	"share_food": "SOCIAL", "socialize": "SOCIAL", "seek_person": "SOCIAL",
	"propose_rule": "SOCIAL", "ask_reason": "SOCIAL", "observe_person": "SOCIAL",
	"explore": "EXPLORATION", "relocate": "EXPLORATION", "keep_distance": "EXPLORATION",
	"search_resource_source": "INFORMATION_SOURCE", "ask_resource_source": "INFORMATION_SOURCE",
	"ask_item_holder": "HOLDER_INQUIRY",
	"craft_fish_spear": "PLAN_EXECUTION", "set_trap": "PLAN_EXECUTION", "light_fire": "PLAN_EXECUTION",
}

static func _action_category(action_name: String) -> String:
	return str(ACTION_CATEGORY.get(action_name, "OTHER"))

## C-0A：ask 候选存在但败选——记录胜者类别与 utility delta（write-only）。
func _record_inquiry_arbitration_loss(actor_view: Dictionary, decision: Dictionary) -> void:
	if _holder_arbitration_probe.is_empty():
		return
	var winner := str(decision.get("action", ""))
	var winner_utility := float(decision.get("utility", 0.0))
	var best_ask := float(_holder_arbitration_probe.get("best_utility", 0.0))
	var category := _action_category(winner)
	_holder_diag_inc("ask_candidate_lost")
	_holder_diag_inc("ask_lost_to_" + category)
	_holder_diag_inc("ask_loss_utility_delta_sum", int(round((winner_utility - best_ask) * 1000)))
	_holder_diag_inc("ask_loss_utility_delta_count")
	_holder_arbitration_probe = {}

## C-0A：ask 候选存在且胜选——记录（write-only）。
func _record_inquiry_arbitration_win(decision: Dictionary) -> void:
	if _holder_arbitration_probe.is_empty():
		return
	_holder_diag_inc("ask_candidate_won")
	var best_ask := float(_holder_arbitration_probe.get("best_utility", 0.0))
	_holder_diag_inc("ask_win_utility_sum", int(round(best_ask * 1000)))
	_holder_diag_inc("ask_win_utility_count")
	_holder_arbitration_probe = {}

## P7.2C C-0B：objective material-availability audit。
## 只在诊断层统计真实世界持有者——行为系统绝不读取本函数的任何输出；
## 输出仅进 _objective_material_audit（audit state 编码排除、summary 输出）。
func _record_objective_material_audit(requester_id: String, item_id: String) -> void:
	if item_id == "":
		return
	var holder_count := 0
	var nearest := -1
	var requester_tile: Vector2i = actors[requester_id]["tile"] if actors.has(requester_id) else Vector2i.ZERO
	var requester_tom: TheoryOfMind = actors[requester_id].get("tom", null) if actors.has(requester_id) else null
	var visible := 0
	var known_last_seen := 0
	for other_id in actors:
		if str(other_id) == requester_id:
			continue
		var other: Dictionary = actors[other_id]
		if int(other.get("inventory", {}).get(item_id, 0)) > 0:
			holder_count += 1
			var dist := absi(int(other["tile"].x) - requester_tile.x) + absi(int(other["tile"].y) - requester_tile.y)
			if nearest < 0 or dist < nearest:
				nearest = dist
			if _is_nearby(requester_tile, other["tile"]):
				visible += 1
			if requester_tom != null and not requester_tom.last_seen_of(str(other_id)).is_empty():
				known_last_seen += 1
	_obj_inc("objective_audit_ticks")
	if holder_count > 0:
		_obj_inc("objective_any_holder_ticks")
	else:
		_obj_inc("objective_no_holder_ticks")
	_obj_inc("objective_holder_count", holder_count)
	if nearest >= 0:
		_obj_inc("objective_nearest_holder_distance_sum", nearest)
		_obj_inc("objective_nearest_holder_count")
	_obj_inc("objective_actual_holder_visible_ticks", visible)
	_obj_inc("objective_actual_holder_known_last_seen_ticks", known_last_seen)
	_obj_inc("objective_actual_holder_unknown_ticks", holder_count - known_last_seen)
	_obj_inc("objective_audit_item_" + item_id + "_ticks")

func _obj_inc(key: String, n: int = 1) -> void:
	_objective_material_audit[key] = int(_objective_material_audit.get(key, 0)) + n

## P7.2C C-0C：材料驻留审计——中间材料库存生命周期（write-only）。
## 在库存事件点采样：gathered/crafted 进、craft 消耗出、craft 后盈余。
func _record_material_residence(actor_id: String, item_id: String, kind: String) -> void:
	if not agency_holder_reachability_enabled:
		return
	_obj_inc("material_event_" + kind + "_" + item_id)
	if kind == "acquired":
		_obj_inc("material_residence_open_" + item_id + "_" + actor_id)
	elif kind == "consumed":
		_obj_inc("material_residence_close_" + item_id + "_" + actor_id)

## C-0C：每 tick 携带统计（在 sync 全局时点调用一次）。
func _record_material_carriage_ticks() -> void:
	if not agency_holder_reachability_enabled:
		return
	for other_id in actors:
		var inv: Dictionary = actors[other_id].get("inventory", {})
		if int(inv.get("wood", 0)) > 0:
			_obj_inc("carriage_wood_actor_ticks")
		if int(inv.get("shells", 0)) > 0:
			_obj_inc("carriage_shells_actor_ticks")

func agency_holder_funnel_diagnostics() -> Dictionary:
	return _holder_funnel_diag.duplicate(true)

func agency_objective_material_audit() -> Dictionary:
	return _objective_material_audit.duplicate(true)

func _commitment_runtime_bridge() -> CommitmentRuntimeBridge:
	if _commitment_runtime == null:
		_commitment_runtime = CommitmentRuntimeBridge.new()
	return _commitment_runtime

func agency_commitment_trace() -> Array:
	if _commitment_runtime == null:
		return []
	return _commitment_runtime.trace_snapshot()

func agency_commitment_rng_states() -> Dictionary:
	if _commitment_runtime == null:
		return {}
	return _commitment_runtime.rng_states()

func _commitments_check_due() -> void:
	var bridge := _commitment_runtime_bridge()
	for record in bridge.cancel_orphaned(obligations, actors.keys(), tick):
		_emit_commitment_event(CommitmentContract.EVENT_COMMITMENT_CANCELLED, record,
			{"reason": CommitmentContract.CANCEL_CREDITOR_GONE})
		_refresh_obligation_views(str(record.get("debtor_id", "")), "")
	for record in bridge.violate_due(obligations, tick):
		_refresh_obligation_views(str(record.get("debtor_id", "")), str(record.get("creditor_id", "")))
		_emit_commitment_event(CommitmentContract.EVENT_COMMITMENT_VIOLATED, record, {
			"reason": "OVERDUE",
			"due_tick": int(record.get("due_tick", 0)),
		})

## A 对"用未来回报换材料"的独立判断 + B 的条款验证。返回 true = 本分支已处理。
func _commitments_handle_exchange_counter(
	requester_id: String,
	a: Dictionary,
	request: Dictionary,
	new_events: Array
) -> bool:
	var bridge := _commitment_runtime_bridge()
	var request_bridge := _material_request_runtime_bridge()
	var request_id := str(request.get("request_id", ""))
	var counter: Dictionary = request.get("last_counter", {})
	var decision: Dictionary = bridge.requester_exchange_decision(
		request, counter, _commitment_requester_context(requester_id, a, request, counter), tick)
	if not bool(decision.get("terms_match", true)):
		# §十三 误解路径：A 想成交但只能给更差条款——不成债、不转移、按误解（非违约）记账。
		var mismatch_rejected: Dictionary = request_bridge.reject_counter(request_id, tick, "TERMS_MISMATCH")
		if bool(mismatch_rejected.get("ok", false)):
			_emit_commitment_event(CommitmentContract.EVENT_COMMITMENT_TERMS_MISMATCH, {
				"commitment_id": "", "debtor_id": requester_id,
				"creditor_id": str(request.get("target_id", "")),
				"object_id": str(request.get("item_id", "")),
				"quantity": int(counter.get("quantity", 0)), "status": "",
				"source_request_id": request_id,
			}, {"demanded_terms": decision.get("demanded_terms", {}),
				"offered_terms": decision.get("offered_terms", {})})
			_emit_material_request_event("MATERIAL_COUNTER_REJECTED", requester_id,
				mismatch_rejected.get("request", {}), {"reason": "TERMS_MISMATCH"})
		return true
	if not bool(decision.get("accept", false)):
		# §八：A 不愿以未来承诺换材料——回落 P7.1 语义（拒绝 counter，换下一个持有者）。
		var declined: Dictionary = request_bridge.reject_counter(request_id, tick, "EXCHANGE_DECLINED")
		if bool(declined.get("ok", false)):
			_emit_material_request_event("MATERIAL_COUNTER_REJECTED", requester_id,
				declined.get("request", {}), {"reason": "EXCHANGE_DECLINED"})
		return true
	# A 接受 → B 验证承诺条款是否满足自己的条件（§七，只来自 B 的主观上下文）。
	var creditor_id := str(request.get("target_id", ""))
	var validation: Dictionary = bridge.creditor_validate_offer(
		decision.get("demanded_terms", {}), decision.get("offered_terms", {}),
		_commitment_creditor_context(creditor_id, requester_id, counter))
	if str(validation.get("decision", "")) != "ACCEPT":
		var refused: Dictionary = request_bridge.reject_counter(request_id, tick, "OFFER_VALUE_BELOW_MINIMUM")
		if bool(refused.get("ok", false)):
			_emit_material_request_event("MATERIAL_COUNTER_REJECTED", requester_id,
				refused.get("request", {}), {"reason": str(validation.get("reason", "OFFER_VALUE_BELOW_MINIMUM"))})
		return true
	var created: Dictionary = bridge.open_commitment_for_request(
		obligations, request, decision.get("offered_terms", {}), tick)
	if not bool(created.get("ok", false)):
		return true
	_refresh_obligation_views(requester_id, creditor_id)  # P7.2A: PENDING 不入视图——刷新后仍不可见
	_emit_commitment_event(CommitmentContract.EVENT_COMMITMENT_CREATED, created["commitment"], {})
	var accepted: Dictionary = request_bridge.accept_counter(request_id, tick)
	if bool(accepted.get("ok", false)):
		_emit_material_request_event("MATERIAL_COUNTER_ACCEPTED", requester_id, accepted.get("request", {}))
		_material_requests_try_transfer(requester_id, a, accepted.get("request", {}), new_events)
	return true

## A 的主观上下文（§八）——需求压力/互惠规范/已有负担/对 B 的信任/对资源的再获得性判断。
func _commitment_requester_context(
	requester_id: String,
	a: Dictionary,
	request: Dictionary,
	counter: Dictionary
) -> Dictionary:
	var creditor_id := str(request.get("target_id", ""))
	var trust := relationships.composite_trust(requester_id, creditor_id)
	var reobtainability := 0.25
	# 自己知道来源 → 高；不知道来源但 ToM 里有人持有 → 中；只剩盲搜 → 低。
	var ctx := AgencyContextBuilder.build(self, a)
	var item_tags: Array = _item_catalog_if_any().tags_of(str(request.get("item_id", "")))
	var knows_source := false
	for tag in ctx.get("known_source_tags", []):
		if item_tags.has(str(tag)):
			knows_source = true
			break
	var tom: TheoryOfMind = a.get("tom", null)
	var best_holder := 0.0
	if tom != null:
		for peer_id in actors:
			if str(peer_id) == requester_id:
				continue
			best_holder = maxf(best_holder, tom.belief_about(str(peer_id),
				MaterialRequestRuntimeBridge.holder_predicate(str(request.get("item_id", "")))))
	if knows_source:
		reobtainability = 0.8
	elif best_holder >= MaterialRequestRuntimeBridge.MIN_HOLDER_BELIEF:
		reobtainability = 0.55
	return {
		"need_urgency": _material_need_urgency(a, str(request.get("root_goal", ""))),
		"own_reciprocity_norm": clampf(float(a.get("norms", {}).get("personal", {}).get("reciprocity", 0.5)), 0.0, 1.0),
		"trust_in_creditor": MaterialRequestRuntimeBridge.trust_probability(trust),
		"relationship": MaterialRequestRuntimeBridge.relationship_signal(trust),
		"subjective_reobtainability": reobtainability,
		"active_commitment_load": CommitmentPolicy.commitment_load(
			_commitment_runtime_bridge().tracker.active_count_for_load(obligations, requester_id)),
		"promised_quantity_ratio": clampf(float(counter.get("quantity", 1)) / 3.0, 0.0, 1.0),
	}

## B 的验证上下文（§七）——估值只依赖 B 自己的 ToM/关系/规范与 A 对 B 的既有债务。
func _commitment_creditor_context(creditor_id: String, requester_id: String, counter: Dictionary) -> Dictionary:
	var creditor: Dictionary = actors.get(creditor_id, {})
	var trust := relationships.composite_trust(creditor_id, requester_id)
	var reliability_belief := 0.5
	var tom: TheoryOfMind = creditor.get("tom", null)
	if tom != null:
		reliability_belief = clampf((tom.belief_about(requester_id, "reliable") + 1.0) * 0.5, 0.0, 1.0)
	var owed_to_me := 0
	for record in obligations:
		if typeof(record) == TYPE_DICTIONARY \
				and str(record.get("debtor_id", record.get("debtor", ""))) == requester_id \
				and str(record.get("creditor_id", record.get("creditor", ""))) == creditor_id \
				and CommitmentContract.counts_toward_load(record):
			owed_to_me += 1
	return {
		"debtor_reliability_belief": reliability_belief,
		"relationship": MaterialRequestRuntimeBridge.relationship_signal(trust),
		"own_reciprocity_norm": clampf(float(creditor.get("norms", {}).get("personal", {}).get("reciprocity", 0.5)), 0.0, 1.0),
		"debtor_visible_commitment_load": clampf(float(owed_to_me) / 3.0, 0.0, 1.0),
		"minimum_offer_value": clampf(float(counter.get("minimum_offer_value", 0.35)), 0.0, 1.0),
	}

## 匹配的真实转移 → 承诺 ACTIVE（§四：对价交付后债务才成立）。
func _commitments_on_transfer_success(requester_id: String, request: Dictionary, transfer_event: Dictionary) -> void:
	if not agency_commitment_consequences_enabled:
		return
	var result: Dictionary = _commitment_runtime_bridge().activate_from_transfer(
		obligations, request, transfer_event, tick)
	if bool(result.get("ok", false)):
		_refresh_obligation_views(requester_id, str((result["commitment"] as Dictionary).get("creditor_id", "")))
		_emit_commitment_event(CommitmentContract.EVENT_COMMITMENT_ACTIVATED,
			result["commitment"], {"transfer_event_id": str(transfer_event.get("event_id", ""))})

## 来源请求终局且无对价 → PENDING 承诺取消（§五：transfer 前失败可取消，不背包袱）。
func _commitments_on_request_terminal(request: Dictionary, cancel_reason: String, detail: String) -> void:
	if not agency_commitment_consequences_enabled:
		return
	var cancelled: Array = _commitment_runtime_bridge().cancel_for_request(
		obligations, str(request.get("request_id", "")), cancel_reason, tick)
	for record in cancelled:
		_emit_commitment_event(CommitmentContract.EVENT_COMMITMENT_CANCELLED, record,
			{"reason": cancel_reason, "detail": detail})
		_refresh_obligation_views(str(record.get("debtor_id", "")), str(record.get("creditor_id", "")))

func _emit_commitment_event(event_type: String, record: Dictionary, extra: Dictionary = {}) -> void:
	var payload := {
		"commitment_id": str(record.get("commitment_id", "")),
		"debtor_id": str(record.get("debtor_id", record.get("debtor", ""))),
		"to_id": str(record.get("creditor_id", record.get("creditor", ""))),  # 债权人 = recipient 语义
		"object_id": str(record.get("object_id", record.get("object", ""))),
		"quantity": int(record.get("quantity", 0)),
		"status": str(record.get("status", "")),
		"source_request_id": str(record.get("source_request_id", "")),
		"parent_plan_id": str(record.get("parent_plan_id", "")),
		"parent_run_id": str(record.get("parent_run_id", "")),
		"blocker_step_id": str(record.get("blocker_step_id", "")),
		"terminal_reason": str(record.get("terminal_reason", "")),
		"source_transfer_event_id": str(record.get("source_transfer_event_id", "")),
	}
	for key in extra:
		payload[key] = extra[key]
	var debtor_id := str(payload["debtor_id"])
	var display := debtor_id
	if actors.has(debtor_id):
		display = str(actors[debtor_id]["display_name"])
	_emit(event_type, debtor_id, "%s 的承诺事件 %s" % [display, event_type], payload)

# ── P7.2 §九/§十六：义务可行动 + 可解材料 blocker 进入主观估值 ──

const RESOLVABLE_BLOCKER_REASONS := ["UNKNOWN_SOURCE", "MATERIALS_MISSING"]

## §十六修复：BLOCKED_PLAN 的材料类 blocker 附带"按角色自己证据估算的可解性"。
## 证据只有三种来源——自己的已知来源、自己 ToM 的持有信念、P7.0 盲搜可能。
func _annotate_blocker_resolution(id: String, proposals: Array, ctx: Dictionary) -> void:
	var tom: TheoryOfMind = actors[id].get("tom", null)
	var items := _item_catalog_if_any()
	var factors := {}
	for proposal in proposals:
		if typeof(proposal) != TYPE_DICTIONARY or str(proposal.get("status", "")) != "BLOCKED_PLAN":
			continue
		var blockers: Array = proposal.get("blockers", [])
		if blockers.is_empty():
			continue
		var resolvable := true
		for blk in blockers:
			if typeof(blk) != TYPE_DICTIONARY \
					or not RESOLVABLE_BLOCKER_REASONS.has(str(blk.get("reason_code", ""))):
				resolvable = false
				break
		if not resolvable:
			continue
		var confidence_factor := 1.0
		var extra_cost := 0.0
		var evidence := {}
		for blk in blockers:
			var item_id := str((blk as Dictionary).get("item_id", ""))
			if item_id == "":
				continue
			var factor: float = factors.get(item_id, -1.0)
			if factor < 0.0:
				factor = _resolution_factor(id, item_id, ctx, tom, items)
				factors[item_id] = factor
			confidence_factor = minf(confidence_factor, factor)
			extra_cost = maxf(extra_cost, 0.35 if str((blk as Dictionary).get("reason_code", "")) == "MATERIALS_MISSING" else 0.45)
			evidence[item_id] = {"confidence_factor": factor}
		if confidence_factor <= 0.0:
			continue
		proposal["blocker_resolution"] = {
			"resolvable": true,
			"confidence_factor": confidence_factor,
			"extra_cost": extra_cost,
			"evidence": evidence,
		}

func _resolution_factor(id: String, item_id: String, ctx: Dictionary, tom: TheoryOfMind, items: ItemCatalog) -> float:
	if items != null:
		var item_tags: Array = items.tags_of(item_id)
		for tag in ctx.get("known_source_tags", []):
			if item_tags.has(str(tag)):
				return 0.75  # 自己知道来源：采集可解
	if tom != null:
		var best_holder := 0.0
		for peer_id in actors:
			if str(peer_id) == id:
				continue
			best_holder = maxf(best_holder, tom.belief_about(str(peer_id),
				MaterialRequestRuntimeBridge.holder_predicate(item_id)))
		if best_holder >= MaterialRequestRuntimeBridge.MIN_HOLDER_BELIEF:
			return clampf(0.5 + 0.25 * minf(1.0, best_holder), 0.0, 0.75)  # 社会可解：P7.1 请求路径
	return 0.35  # 只剩 P7.0 盲搜：仍可尝试，但主观把握低

## §九：每个 ACTIVE 承诺生成可竞争的履约计划（缺口大 → ACQUIRE 在前，可继续
## 自然触发 P7.0 信息 / P7.1 请求；GIVE 走既有 repay_debt 行动）。
func _commitment_obligation_plans(id: String, a: Dictionary) -> Array:
	var out: Array = []
	for record in _commitment_runtime_bridge().tracker.active_of(obligations, id):
		var plan := _commitment_fulfillment_plan(record, a)
		if not plan.is_empty():
			out.append(plan)
	return out

func _commitment_fulfillment_plan(record: Dictionary, a: Dictionary) -> Dictionary:
	var cid := str(record.get("commitment_id", ""))
	var object_id := str(record.get("object_id", ""))
	var quantity := maxi(1, int(record.get("quantity", 1)))
	var possessed := int(a["inventory"].get(object_id, 0))
	var gap := maxi(0, quantity - possessed)
	var steps: Array = []
	if gap > 0:
		steps.append(PlanStepSpec.make("ACQUIRE", "ACQUIRE:%s#%s" % [object_id, cid],
			"PENDING", "", object_id, gap, "", "", [], [], [], [], "为兑现承诺补足 %s" % object_id))
	var repay_step := PlanStepSpec.make("MAIN", "MAIN:REPAY#%s" % cid, "PENDING",
		"repay_debt", object_id, quantity, "", "", [], [], [], [],
		"兑现对 %s 的承诺" % str(record.get("creditor_id", "")))
	repay_step["commitment_id"] = cid  # 候选匹配与完成判定都以承诺身份为锚
	steps.append(repay_step)
	var trust := relationships.composite_trust(str(record.get("debtor_id", "")), str(record.get("creditor_id", "")))
	var relationship_value := MaterialRequestRuntimeBridge.relationship_signal(trust)
	var reciprocity := clampf(float(a.get("norms", {}).get("personal", {}).get("reciprocity", 0.5)), 0.0, 1.0)
	var due_tick := int(record.get("due_tick", tick))
	var total := maxi(1, due_tick - int(record.get("activated_tick", tick)))
	var remaining := maxi(1, due_tick - tick)
	var urgency := clampf(1.0 - float(remaining) / float(total), 0.0, 1.0)
	return {
		"plan_id": "PLAN_OBLIGATION_%s" % cid,
		"root_goal": "OBLIGATION",
		"target_resource": object_id,
		"via_rule": "fulfill_commitment",
		"steps": steps,
		"missing_requirements": [],
		"blockers": [],
		"status": "READY",
		"expected_benefit": clampf(0.35 + relationship_value * 0.3 + reciprocity * 0.35, 0.0, 1.0),
		"estimated_cost": 0.3 + (0.4 if gap > 0 else 0.0),
		"estimated_risk": 0.2 if gap > 0 else 0.05,
		"confidence": 0.6 if gap > 0 else 0.85,
		"knowledge_refs": [], "belief_refs": [],
		"commitment_id": cid,
		"obligation_pressure": 0.45 + 0.55 * urgency,
	}

func _agency_planner_slim(proposals: Array) -> void:
	AgencyActionBridge.annotate_steps(proposals)

func _complete_action(id: String, a: Dictionary, new_events: Array) -> void:
	var action: Dictionary = a.get("current_action", {})
	var action_name := str(action.get("action", "wait"))
	a["current_action"] = null
	# P6.3B-1：本次行动产生的事件段（_emit 写 sim.events——按序号切片，供执行完成判定）
	var _ev_idx := events.size()
	a.erase("action_travel_stall_ticks")
	if _requires_fixed_location(action) and a["tile"] != action["target"]:
		_emit("action_target_missed", id, "%s 尚未抵达行动地点" % a["display_name"],
			{"action": action_name, "target": str(action["target"]), "actual": str(a["tile"])})
		a["activity"] = "未能抵达" + str(action.get("desc", action_name))
		_information_subgoal_on_complete(id, a, action, events.slice(_ev_idx))
		_plan_execution_on_complete(id, a, action, events.slice(_ev_idx))
		return

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
			_do_craft(id, a, new_events, action)
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
		"propose_rule", "counter_propose_rule":
			_do_propose_rule(id, a, action, new_events)
		"keep_distance":
			_do_keep_distance(id, a, action, new_events)
		"gather_wood":
			_do_gather_wood(id, a, new_events)
		"search_resource_source":
			_do_search_resource_source(id, a, action, new_events)
		"ask_resource_source":
			_do_ask_resource_source(id, a, action, new_events)
		"ask_item_holder":
			_holder_diag_inc("holder_ask_actions_completed")
			_do_ask_item_holder(id, a, action, new_events)
		"seek_holder_person":
			_do_seek_holder_person(id, a, action, new_events)
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
	# P7.0 / P6.3B-1：各 tracker 都只消费本次行动的事件段。
	_information_subgoal_on_complete(id, a, action, events.slice(_ev_idx))
	_plan_execution_on_complete(id, a, action, events.slice(_ev_idx))

func _requires_fixed_location(action: Dictionary) -> bool:
	return FIXED_LOCATION_ACTIONS.has(str(action.get("action", ""))) \
		and typeof(action.get("target", null)) == TYPE_VECTOR2I

func _abort_unreachable_action(id: String, a: Dictionary, _new_events: Array) -> void:
	var action: Dictionary = a.get("current_action", {}).duplicate(true)
	var event_start := events.size()
	a["current_action"] = null
	a["action_ticks_left"] = 0
	a.erase("action_travel_stall_ticks")
	var intention: IntentionManager = a.get("intentions", null)
	if intention != null:
		intention.force_interrupt("TARGET_UNREACHABLE")
	_emit("action_target_unreachable", id, "%s 找不到通往行动地点的路" % a["display_name"],
		{"action": str(action.get("action", "")), "target": str(action.get("target", "")), "actual": str(a["tile"])})
	a["activity"] = "无法抵达" + str(action.get("desc", action.get("action", "目标")))
	_information_subgoal_on_complete(id, a, action, events.slice(event_start))
	_plan_execution_on_complete(id, a, action, events.slice(event_start))

func _abort_invalidated_action(id: String, a: Dictionary, _new_events: Array) -> void:
	var action: Dictionary = a.get("current_action", {}).duplicate(true)
	var event_start := events.size()
	a["current_action"] = null
	a["action_ticks_left"] = 0
	a.erase("action_travel_stall_ticks")
	var intention: IntentionManager = a.get("intentions", null)
	if intention != null:
		intention.force_interrupt("TARGET_INVALIDATED")
	_emit("action_target_invalidated", id,
		"%s 发现目标地点已无法提供所需资源" % a["display_name"], {
			"action": str(action.get("action", "")),
			"target": str(action.get("target", "")),
			"target_source_key": str(action.get(ActionTargetContract.SOURCE_KEY_FIELD, "")),
		})
	a["activity"] = "重新考虑" + str(action.get("desc", action.get("action", "目标")))
	_information_subgoal_on_complete(id, a, action, events.slice(event_start))
	_plan_execution_on_complete(id, a, action, events.slice(event_start))

# ── 行动执行 ──

func _do_forage(id: String, a: Dictionary, ev: Array) -> void:
	for bush in world["berry_bushes"]:
		if bush["pos"] == a["tile"] and int(bush["food"]) > 0:
			var got := mini(1, int(bush["food"]))  # P5.2：每次采 1——多容量供多人分，不供单人搬空
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

## P6.3A-R2 §一：recipe_id 执行契约——严格 fail-closed
## 1) action 无 recipe_id 字段 → 走 legacy alias（compat_action 唯一索引）
## 2) action 有 recipe_id → 必须非空 String 且存在于 catalog，绝不回退 alias
## 3) recipe 的 compat_action 非空时必须与 action.action 一致，不一致拒绝
## 所有拒绝：库存不变、无事件、无能力变化、安静返回
func _do_craft(id: String, a: Dictionary, ev: Array, action: Dictionary = {}) -> void:
	_ensure_catalogs()
	var recipe: Dictionary = {}
	if not action.has("recipe_id"):
		# 1) 字段不存在 → legacy alias（compat_action 唯一索引）
		recipe = _recipe_catalog.by_compat_action(str(action.get("action", "")))
	else:
		var rid_val = action["recipe_id"]
		if typeof(rid_val) != TYPE_STRING or str(rid_val) == "":
			# 2a) 字段存在但 null/非 String/空 → 拒绝（不回退）
			return
		# 2b) 有效 String → 查 catalog；不存在则拒绝（不回退）
		recipe = _recipe_catalog.spec(str(rid_val))
		if recipe.is_empty():
			return
		# 3) compat_action 一致性检查
		var compat := str(recipe.get("compat_action", ""))
		if compat != "" and compat != str(action.get("action", "")):
			return
	if recipe.is_empty():
		return  # legacy alias 也找不到 → fail-closed
	var caps_before: Array = InventoryOps.capabilities_of_inventory(a["inventory"], _item_catalog)
	var txn: Dictionary = InventoryOps.consume_and_grant(a["inventory"], recipe, _item_catalog)
	if not bool(txn.get("ok", false)):
		return  # 原子失败：材料不足时库存逐位不变
	a["inventory"] = txn["inventory"]
	var caps_after: Array = InventoryOps.capabilities_of_inventory(a["inventory"], _item_catalog)
	var out_item := _recipe_catalog.primary_output(recipe)
	var out_name := str(_item_catalog.spec(out_item).get("display_name", out_item))
	_emit("crafted", id, "%s 制作了一把%s" % [a["display_name"], out_name],
			{"tool": out_item, "recipe_id": str(recipe.get("recipe_id", "")),
			"consumed_items": txn.get("consumed_items", {}), "produced_items": txn.get("produced_items", {}),
			"capabilities_before": caps_before, "capabilities_after": caps_after})
	AuthoritySystem.self_identity(a, "crafted")
## P6.3A-R1 §4：窄方法暴露只读知识 store（不进 actor Dictionary——首/后续 tick 同语义）
func agency_knowledge_store() -> WorldKnowledgeStore:
	if _agency_store == null:
		_agency_store = KnowledgePack.load_island_pack()
	return _agency_store

func _ensure_catalogs() -> void:
	if _item_catalog == null:
		_item_catalog = ItemCatalog.load_default()
		_recipe_catalog = RecipeCatalog.load_default(_item_catalog)

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
			var promise_seq := _emit("promise_made", id, "%s 说：『这份情我记下，以后报答』" % a["display_name"],
					{"to_id": target_id, "object": object_id})
			obligations.append({"debtor": id, "creditor": target_id, "object": object_id,
					"made_tick": tick, "due_tick": tick + 96, "repaid": false,
					"promise_event_seq": promise_seq})
			a["my_obligations"] = _obligations_of(id)
			target["owed_to_me"] = _owed_to(target_id)
	else:
		_emit(ev_prefix + "_request_refused", target_id,
				"%s 摇了摇头：%s——%s 的求助被拒绝了" % [target["display_name"], str(result.get("reason", "")), a["display_name"]],
				{"proposer_id": id, "object": object_id})
		# P5 拒绝记忆：刚被拒的人短期内拉不下脸再求（防无-source 世界里的求救刷屏）
		var rmem: Array = a.get("refusal_memory", [])
		rmem.append({"by": target_id, "tick": tick, "object": object_id})
		if rmem.size() > 8:
			rmem = rmem.slice(rmem.size() - 8)
		a["refusal_memory"] = rmem

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
	# P2.1 Gate5: counter 意图也走同一条公共讨论管线（is_counter 标记，被拒不改世界，被采纳升版本）
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
	var proposal_seq := _emit("rule_proposed", id, "%s 提出：『%s』" % [a["display_name"], rule_text],
			{"object": object_id, "rule": rule, "audience": audience.duplicate()})
	# 提议者自我表态（公开）
	RuleDiscourse.self_stance(a, rule, 1, audience.size() + 1, tick)
	var public_supports := 0
	var stance_records := {}  # P2.1.1：同一场讨论的显式立场记录——传播绝不重猜（P2.1.1 修复：原 last_rule_stance 幽灵字段已删）
	for other_id in audience:
		var w: Dictionary = actors[other_id]
		var stance_eval: Dictionary = RuleDiscourse.evaluate_proposal(w, rule, relationships)
		var st := int(stance_eval["stance"])
		stance_records[other_id] = st
		RuleDiscourse.self_stance(w, rule, st, audience.size() + 1, tick)
		if st > 0:
			public_supports += 1
			_emit("rule_supported", other_id, "%s 公开表示同意" % w["display_name"], {"rule": rule, "object": object_id})
		elif st < 0:
			_emit("rule_opposed", other_id, "%s 说：『%s，这个比例太高了』" % [w["display_name"], str(stance_eval["reason"])], {"rule": rule, "object": object_id})
		else:
			_emit("rule_abstained", other_id, "%s 沉默不语" % w["display_name"], {"rule": rule, "object": object_id})
	# 所有目击者更新感知——立场一律来自 stance_records（= 真实公开立场，集成级正确）
	for wid in actors:
		if wid == id or not _is_nearby(a["tile"], actors[wid]["tile"]):
			continue
		RuleDiscourse.witness_stance(actors[wid], rule, id, 1, audience.size() + 1, tick)
		for other_id2 in audience:
			RuleDiscourse.witness_stance(actors[wid], rule, other_id2, int(stance_records[other_id2]), audience.size() + 1, tick)
	# P2.1.1 事务式：先表决后改世界——被否决的提案绝不触碰 InstitutionRecord（修"先改后查"倒序）
	var adopted := public_supports >= 2
	if (goal_kind == "amend" or goal_kind == "counter_propose") and adopted:
		for inst in institutions:
			if str(inst["rule"].get("object", "")) == object_id:
				inst["rule"]["fraction"] = fraction
				inst["revised_tick"] = tick
				break
		_emit("rule_revised", id, "%s 的修订提议通过：比例改为 %d%%" % [a["display_name"], int(fraction * 100)], {"object": object_id, "fraction": fraction, "rule": rule, "source_event_ids": [proposal_seq]})
	# InstitutionRecord（P2.1.1 去重：同 object 已有活制度不重复建立——修 729/629 膨胀）
	if adopted and goal_kind != "amend" and goal_kind != "counter_propose":
		var already := false
		for inst in institutions:
			if str(inst["rule"].get("object", "")) == object_id:
				already = true
				break
		if not already:
				institutions.append({"rule": rule, "created_tick": tick, "supports": public_supports, "status": "active"})
				_emit("institution_established", id, "『%s』成了营地的正式约定" % rule_text, {"rule": rule, "object": object_id, "source_event_ids": [proposal_seq]})
		# P2.1.1 目标生命周期：制度建立 → 目标终结，不再重复开会（修 goal 不消费）
		var goals_left: Array = []
		for g9 in a.get("institutional_goals", []):
			if str(g9.get("object", "")) != object_id:
				goals_left.append(g9)
		a["institutional_goals"] = goals_left
## 债务辅助（视图供给）
## P7.2A：唯一判断 helper——承诺型记录按 authoritative status（PENDING 不入视图），
## 旧记录保持 repaid 语义。禁止在别处复制此判断。
func _is_outstanding_obligation(record: Dictionary) -> bool:
	if record.has("commitment_id"):
		return CommitmentContract.is_active_debt(record)
	return not bool(record.get("repaid", false))

func _obligations_of(debtor: String) -> Array:
	var out: Array = []
	for ob in obligations:
		if typeof(ob) == TYPE_DICTIONARY and str(ob["debtor"]) == debtor \
				and _is_outstanding_obligation(ob):
			out.append(ob)
	return out

func _owed_to(creditor: String) -> Array:
	var out: Array = []
	for ob in obligations:
		if typeof(ob) == TYPE_DICTIONARY and str(ob["creditor"]) == creditor \
				and _is_outstanding_obligation(ob):
			out.append(ob)
	return out

## P7.2A：状态转移后同步双方派生视图（ACTIVATED/FULFILLED/VIOLATED/CANCELLED/CREDITOR_GONE）。
func _refresh_obligation_views(debtor_id: String, creditor_id: String) -> void:
	if actors.has(debtor_id):
		actors[debtor_id]["my_obligations"] = _obligations_of(debtor_id)
	if creditor_id != "" and actors.has(creditor_id):
		actors[creditor_id]["owed_to_me"] = _owed_to(creditor_id)

## P1.6 还债执行：履约 → 可靠性上升（经 transition 的 PROMISE/FULFILLED 语义）
func _do_repay(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var creditor := str(action.get("target_actor", ""))
	var object_id := str(action.get("object", "food"))
	var spec: Dictionary = ResourceSpec.spec(object_id)
	# P7.2：承诺型债务走真实结算管线（身份/数量核验→一次性转移→证据→FULFILLED）；
	# 旧 obligations 路径保持不变。
	if agency_commitment_consequences_enabled:
		var obligation: Dictionary = action.get("obligation", {})
		var commitment_id := str(obligation.get("commitment_id", ""))
		if commitment_id != "":
			_commitments_settle_repay(id, a, commitment_id, creditor, object_id)
			return
	if not actors.has(creditor) or int(a["inventory"].get(object_id, 0)) < 2:
		return
	if not _is_nearby(a["tile"], actors[creditor]["tile"]):
		return  # 人不在——下次再说
	a["inventory"][object_id] = int(a["inventory"][object_id]) - 1
	actors[creditor]["inventory"][object_id] = int(actors[creditor]["inventory"].get(object_id, 0)) + 1
	var promise_event_seq := -1
	for ob in obligations:
		if str(ob["debtor"]) == id and str(ob["creditor"]) == creditor and str(ob["object"]) == object_id and not bool(ob["repaid"]):
			ob["repaid"] = true
			promise_event_seq = int(ob.get("promise_event_seq", 0))
			break
	a["my_obligations"] = _obligations_of(id)
	actors[creditor]["owed_to_me"] = _owed_to(creditor)
	_emit("promise_kept", id, "%s 把%s还给了 %s——他兑现了承诺" % [a["display_name"], str(spec["verb"]), actors[creditor]["display_name"]],
			{"to_id": creditor, "object": object_id,
			"source_event_ids": [promise_event_seq] if promise_event_seq >= 0 else []})

## 承诺型履约结算（§十）：bridge 核验身份/状态/数量并执行唯一一次转移。
func _commitments_settle_repay(debtor_id: String, a: Dictionary, commitment_id: String, creditor_id: String,
		object_id: String = "") -> void:
	if not actors.has(creditor_id) or not _is_nearby(a["tile"], actors[creditor_id]["tile"]):
		return  # 债主不在场——履约计划继续保留
	# P7.2A：结算绑定行动身份（debtor/creditor/object），错向 fail closed。
	var result: Dictionary = _commitment_runtime_bridge().settle(
		obligations, commitment_id, a["inventory"], actors[creditor_id]["inventory"], tick,
		debtor_id, creditor_id, object_id)
	if not bool(result.get("ok", false)):
		return
	_refresh_obligation_views(debtor_id, creditor_id)
	var evidence: Dictionary = result.get("event", {})
	var record: Dictionary = result.get("commitment", {})
	_emit_commitment_event(CommitmentContract.EVENT_COMMITMENT_TRANSFER_COMPLETED, record,
		{"transfer_event_id": str(evidence.get("event_id", ""))})
	_emit_commitment_event(CommitmentContract.EVENT_COMMITMENT_FULFILLED, record,
		{"transfer_event_id": str(evidence.get("event_id", ""))})

## 承诺到期检查：违约 → 可靠性崩（无人在场也生效——不守信迟早传开）
func _check_overdue_promises() -> void:
	for ob in obligations:
		# P7.2：承诺型记录由 CommitmentTracker 的 violate_due 统一裁决（每 tick 一次），
		# 此处只处理旧 obligations——避免双重违约事件。
		if ob is Dictionary and (ob as Dictionary).has("commitment_id"):
			continue
		if not bool(ob["repaid"]) and tick > int(ob["due_tick"]):
			ob["repaid"] = true  # 标记完结防重复
			if actors.has(str(ob["debtor"])):
				actors[str(ob["debtor"])]["my_obligations"] = _obligations_of(str(ob["debtor"]))
			_emit("promise_broken", str(ob["debtor"]), "%s 没能兑现他的承诺" % actors[str(ob["debtor"])]["display_name"],
					{"to_id": str(ob["creditor"]), "object": str(ob["object"]),
					"source_event_ids": [int(ob.get("promise_event_seq", -1))] if int(ob.get("promise_event_seq", -1)) >= 0 else []})

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
	var trace_id := "it_%d_%s" % [tick, id]  # P2.1.1：trace 先于分支声明
	var req_amt := amount  # 默认全额；分支内按规则比例修正
	if contribute > 0:
		contribute = mini(contribute, int(a["inventory"].get(object_id, 0)))
		a["inventory"][object_id] = int(a["inventory"].get(object_id, 0)) - contribute
		world["common_storage"] = world.get("common_storage", {})
		world["common_storage"][object_id] = int(world["common_storage"].get(object_id, 0)) + contribute
		_emit("storage_contributed", id, "%s 按约定把 %d 份%s放进了公共储备" % [a["display_name"], contribute, ResourceSpec.spec(object_id)["verb"]],
				{"object": object_id, "amount": contribute, "required": req_amt, "mode": mode, "rule_id": str(dec.get("rule_id", "")), "trace_id": trace_id})
	else:
		_emit("storage_withheld", id, "%s 找到了%s，但没有按约定交公" % [a["display_name"], ResourceSpec.spec(object_id)["verb"]],
				{"object": object_id, "mode": mode, "rule_id": str(dec.get("rule_id", "")), "trace_id": trace_id})
		# 违规者自己也知道刚才有谁在场（检测估计的事后校验）
		AuthoritySystem.self_identity(a, "acquire_" + object_id)
			# P2.1.1 DecisionTrace v5（全模式）：COMPLY/PARTIAL/VIOLATE 都留痕，事件可回指
		var rid_t := str(dec.get("rule_id", ""))
		var pt: Dictionary = ComplianceSystem.perceived_institution(a, rid_t) if rid_t != "" else {}
		a["last_institution_trace"] = {"trace_id": trace_id, "tick": tick, "rule_id": rid_t, "mode": mode,
			"required": int(round(float(amount) * float(a["perceived_group_beliefs"].get(rid_t, {}).get("rule", {}).get("fraction", 0.5)))) if rid_t != "" else 0,
			"actual": contribute, "recognition": float(pt.get("recognition", 0.0)),
			"shared_expectation": float(pt.get("shared_expectation", 0.0)), "legitimacy": float(pt.get("legitimacy", 0.0)) if not pt.is_empty() else 0.0,
			"detection": ComplianceSystem.estimate_detection(a)}

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
	var asked_seq := _emit("reason_asked", id, "%s 问 %s：那天为什么不帮我？" % [a["display_name"], target["display_name"]],
			{"to_id": about, "source_event_ids": (action.get("source_event_ids", []) as Array).duplicate()})
	# 回应：本人陈述（第一版诚实——说自己的真实主要原因；说谎是 Phase 2）
	var claim_prop := {}
	if int(target["inventory"].get("food", 0)) < 2:
		claim_prop = {"subject": about, "predicate": "has_food", "value": -0.8, "label": "我自己也没粮了"}
	else:
		claim_prop = {"subject": about, "predicate": "has_food", "value": 0.4, "label": "我想留着应急"}
	var express: float = float(target["personality"].traits.get("expressiveness", 0.5))
	if express < 0.25:
		# 闷葫芦：问不出话——但这本身也是信息（他不愿说）
		_emit("reason_deflected", about, "%s 沉默了一会儿，什么也没说" % target["display_name"],
				{"to_id": id, "source_event_ids": [asked_seq]})
		_close_question(id, about)
		return
	var claim := Claim.build(about, claim_prop, tick)
	Claim.listen(a, claim, relationships)
	_emit("reason_claimed", about, "%s 说：『%s』" % [target["display_name"], claim_prop["label"]],
			{"to_id": id, "claim": claim_prop["label"], "source_event_ids": [asked_seq]})
	_close_question(id, about)

func _do_observe_person(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var about := str(action.get("target_actor", ""))
	if not actors.has(about):
		return
	a["observing"] = {"about": about, "until": tick + 12,
		"source_event_ids": (action.get("source_event_ids", []) as Array).duplicate()}  # 注意力增益在 CognitiveTransition
	_emit("observing_person", id, "%s 开始不动声色地留意 %s" % [a["display_name"], actors[about]["display_name"]],
			{"to_id": about, "source_event_ids": (action.get("source_event_ids", []) as Array).duplicate()})
	# 观察不立即关问题：证据随目击累积，问题由证据自行解决或过期

func _do_ask_third_party(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var third := str(action.get("target_actor", ""))
	var about := str(action.get("about_actor", ""))
	if not actors.has(third) or not actors.has(about):
		return
	var third_a: Dictionary = actors[third]
	var question_sources: Array = (action.get("source_event_ids", []) as Array).duplicate()
	var asked_seq := _emit("asked_about", id, "%s 悄悄问 %s：最近见过 %s 拿到吃的吗？" % [a["display_name"], third_a["display_name"], actors[about]["display_name"]],
			{"to_id": third, "about": about, "source_event_ids": question_sources})
	# 第三人转述的是【他自己的感知】（ToM 信念），不是真相
	var their_belief: float = third_a["tom"].raw_belief(about, "has_food")
	if absf(their_belief) < 0.1:
		_emit("third_party_unknown", third, "%s 摇头：没太注意过" % third_a["display_name"], {"to_id": id, "source_event_ids": [asked_seq]})
		return
	var claim_prop := {"subject": about, "predicate": "has_food", "value": their_belief,
		"label": "我见过他最近空手而归" if their_belief < 0.0 else "我见他搞到过吃的"}
	var claim := Claim.build(third, claim_prop, tick)
	Claim.listen(a, claim, relationships)
	_emit("third_party_claimed", third, "%s 说：『%s』" % [third_a["display_name"], claim_prop["label"]],
			{"to_id": id, "about": about, "source_event_ids": [asked_seq]})
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

## P7.0 有目的搜索：目的地来自 actor 的主观地图；到达后的资源结论只能经 SpatialPerception。
func _do_search_resource_source(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var goal_id := str(action.get("information_goal_id", ""))
	var source_kind := str(action.get("source_kind", ""))
	var item_id := str(action.get("item_id", ""))
	SpatialPerception.perceive(self, a)
	var belief: SpatialBeliefMap = a.get("spatial", null)
	var found := {}
	if belief != null:
		var rows := belief.resource_beliefs(source_kind)
		if not rows.is_empty():
			found = rows[0]
	if found.is_empty():
		_emit("source_search_failed", id, "%s 搜索后仍不知道%s在哪里" % [a["display_name"], item_id], {
			"information_goal_id": goal_id, "parent_plan_id": str(action.get("parent_plan_id", "")),
			"item_id": item_id, "source_kind": source_kind, "searched_tile": str(a["tile"]),
		})
		return
	var source_tile: Vector2i = found.get("tile", Vector2i.ZERO)
	_emit("source_search_found", id, "%s 发现了%s的来源" % [a["display_name"], item_id], {
		"information_goal_id": goal_id, "parent_plan_id": str(action.get("parent_plan_id", "")),
		"item_id": item_id, "source_kind": source_kind, "source_tile": str(source_tile),
		"source_x": source_tile.x, "source_y": source_tile.y,
		"observed_tick": int(found.get("last_seen_tick", tick)),
		"confidence": float(found.get("confidence", 1.0)), "evidence_kind": SpatialBeliefMap.EVIDENCE_PERCEPT,
	})

## P7.0 询问来源：目标由提问者的 ToM 证据选择；回答内容只来自回答者自己的空间信念。
func _do_ask_resource_source(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var target_id := str(action.get("target_actor", ""))
	var goal_id := str(action.get("information_goal_id", ""))
	var source_kind := str(action.get("source_kind", ""))
	var item_id := str(action.get("item_id", ""))
	if not actors.has(target_id) or not _is_nearby(a["tile"], actors[target_id]["tile"]):
		_emit("source_information_missed", id, "%s 没能向目标问到消息" % a["display_name"], {
			"information_goal_id": goal_id, "parent_plan_id": str(action.get("parent_plan_id", "")),
			"item_id": item_id, "source_kind": source_kind, "target_id": target_id,
		})
		return
	var target: Dictionary = actors[target_id]
	_emit("source_information_requested", id, "%s 向 %s 打听%s的来源" % [a["display_name"], target["display_name"], item_id], {
		"information_goal_id": goal_id, "parent_plan_id": str(action.get("parent_plan_id", "")),
		"item_id": item_id, "source_kind": source_kind, "target_id": target_id,
	})
	var response := InformationExchangePolicy.evaluate(target, id, source_kind,
		relationships.composite_trust(target_id, id), tick, _information_rng(target_id))
	var response_kind := str(response.get("response", InformationExchangePolicy.RESPONSE_UNKNOWN))
	var common := {
		"information_goal_id": goal_id, "parent_plan_id": str(action.get("parent_plan_id", "")),
		"item_id": item_id, "source_kind": source_kind, "to_id": id, "target_id": id,
		"reason_code": str(response.get("reason_code", "")),
		"observed_tick": int(response.get("observed_tick", -1)),
		"age_ticks": int(response.get("age_ticks", -1)),
		"confidence": float(response.get("confidence", 0.0)),
	}
	match response_kind:
		InformationExchangePolicy.RESPONSE_SHARE:
			var tile: Vector2i = response.get("tile", Vector2i.ZERO)
			common["source_tile"] = str(tile)
			common["source_x"] = tile.x
			common["source_y"] = tile.y
			var seq := _emit("source_information_shared", target_id,
				"%s 告诉 %s：我见过%s来源" % [target["display_name"], a["display_name"], item_id], common)
			var asker_belief: SpatialBeliefMap = a.get("spatial", null)
			if asker_belief != null:
				asker_belief.learn_reported_resource(source_kind, tile, int(response.get("observed_tick", tick)),
					tick, target_id, float(response.get("confidence", 0.0)), seq)
		InformationExchangePolicy.RESPONSE_REFUSE:
			_emit("source_information_refused", target_id, "%s 不愿透露来源" % target["display_name"], common)
		InformationExchangePolicy.RESPONSE_STALE:
			_emit("source_information_stale", target_id, "%s 只记得一条过时线索" % target["display_name"], common)
		_:
			_emit("source_information_unknown", target_id, "%s 也不知道来源" % target["display_name"], common)

## P7.2B：开放式持有询问执行。回答方只用两类合法信息源——自己的库存自知、
## 自己 ToM 的第三方持有证据；报告带 observed/received 双时间与 reporter 来源，
## 请求者以 claim 证据写入自己的 ToM（绝不直读对方库存）。
## P7.2C C1：主观找人执行——走向自己 ToM last_seen 记忆的位置；到场与否由
## 真实世界裁决（扑空是合法结果，绝不读真实坐标修正）。到场产生一次相遇，
## 下一决策 tick 被找者进入 others_visible，询问即可自然发生。
func _do_seek_holder_person(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var target_id := str(action.get("target_actor", ""))
	var goal_id := str(action.get("information_goal_id", ""))
	var item_id := str(action.get("item_id", ""))
	if agency_holder_reachability_enabled:
		_holder_diag_inc("holder_seek_actions_completed")
	if not actors.has(target_id):
		if agency_holder_reachability_enabled:
			_holder_diag_inc("holder_seek_person_gone")
		_emit("holder_seek_person_not_found", id, "%s 找的人已经不在了" % a["display_name"], {
			"information_goal_id": goal_id, "source_request_id": str(action.get("source_request_id", "")),
			"item_id": item_id, "target_id": target_id,
		})
		return
	var target: Dictionary = actors[target_id]
	if _is_nearby(a["tile"], target["tile"]):
		if agency_holder_reachability_enabled:
			_holder_diag_inc("holder_seek_found_person")
		_emit("holder_seek_found_person", id,
			"%s 找到了 %s" % [a["display_name"], target["display_name"]], {
				"information_goal_id": goal_id, "source_request_id": str(action.get("source_request_id", "")),
				"item_id": item_id, "target_id": target_id, "to_id": target_id,
			})
	else:
		if agency_holder_reachability_enabled:
			_holder_diag_inc("holder_seek_person_missed")
		_emit("holder_seek_person_not_found", id,
			"%s 扑了个空——%s 已经不在那里了" % [a["display_name"], target["display_name"]], {
				"information_goal_id": goal_id, "source_request_id": str(action.get("source_request_id", "")),
				"item_id": item_id, "target_id": target_id,
			})

func _do_ask_item_holder(id: String, a: Dictionary, action: Dictionary, ev: Array) -> void:
	var target_id := str(action.get("target_actor", ""))
	var goal_id := str(action.get("information_goal_id", ""))
	var item_id := str(action.get("item_id", ""))
	if not actors.has(target_id) or not _is_nearby(a["tile"], actors[target_id]["tile"]):
		_holder_diag_inc("holder_ask_target_missed")
		_emit("holder_information_missed", id, "%s 没能找到想打听的人" % a["display_name"], {
			"information_goal_id": goal_id, "source_request_id": str(action.get("source_request_id", "")),
			"item_id": item_id, "target_id": target_id,
		})
		return
	var target: Dictionary = actors[target_id]
	_holder_diag_inc("holder_ask_actions_started")
	_holder_diag_inc("holder_queries_received")
	if int(target.get("inventory", {}).get(item_id, 0)) > 0:
		_holder_diag_inc("holder_responder_self_holder_at_query")
	var responder_tom: TheoryOfMind = target.get("tom", null)
	if responder_tom != null:
		var _rows := responder_tom.subjects_with_evidence(TheoryOfMind.possession_predicate(item_id))
		var _fresh := false
		var _stale := false
		for _row in _rows:
			var _pid := str((_row as Dictionary).get("actor_id", ""))
			if _pid == "" or _pid == id or _pid == target_id:
				continue
			if float((_row as Dictionary).get("belief", 0.0)) <= 0.0:
				continue
			var _pt := int((_row as Dictionary).get("positive_evidence_tick", -1))
			if _pt >= 0 and tick - _pt <= InformationExchangePolicy.MAX_REPORT_AGE_TICKS:
				_fresh = true
			else:
				_stale = true
		if _fresh:
			_holder_diag_inc("holder_responder_fresh_third_party_available")
		elif _stale:
			_holder_diag_inc("holder_responder_stale_third_party_available")
	_emit("holder_information_requested", id,
		"%s 向 %s 打听：你或你知道的人有%s吗？" % [a["display_name"], target["display_name"], item_id], {
			"information_goal_id": goal_id, "source_request_id": str(action.get("source_request_id", "")),
			"parent_plan_id": str(action.get("parent_plan_id", "")),
			"item_id": item_id, "target_id": target_id, "to_id": target_id,
			"holder_predicate": str(action.get("holder_predicate", "")),
		})
	var response := InformationExchangePolicy.evaluate_holder_query(target, id, item_id,
		relationships.composite_trust(target_id, id), tick, _information_rng(target_id))
	var kind := str(response.get("response", InformationExchangePolicy.HOLDER_UNKNOWN))
	var reported_holder := str(response.get("reported_holder_id", ""))
	var common := {
		"information_goal_id": goal_id,
		"source_request_id": str(action.get("source_request_id", "")),
		"parent_plan_id": str(action.get("parent_plan_id", "")),
		"item_id": item_id,
		"to_id": id, "target_id": id,
		"reporter_id": str(response.get("reporter_id", target_id)),
		"reported_holder_id": reported_holder,
		"observed_tick": int(response.get("observed_tick", -1)),
		"received_tick": tick,
		"confidence": float(response.get("confidence", 0.0)),
		"evidence_kind": str(response.get("evidence_kind", "")),
		"reason_code": str(response.get("reason_code", "")),
		"holder_predicate": str(action.get("holder_predicate", "")),
	}
	_holder_diag_inc("holder_response_" + kind)
	var event_type: String = {
		InformationExchangePolicy.HOLDER_SHARE: "holder_information_shared",
		InformationExchangePolicy.HOLDER_REFUSE: "holder_information_refused",
		InformationExchangePolicy.HOLDER_STALE: "holder_information_stale",
		InformationExchangePolicy.HOLDER_SELF_ABSENT: "holder_information_self_absent",
	}.get(kind, "holder_information_unknown")
	var text := "%s 回答 %s" % [target["display_name"], a["display_name"]]
	var seq := _emit(event_type, target_id, text, common)
	# 请求者认知写入：SHARE=正向 claim；SELF_ABSENT=关于回答者的负向 claim。
	if kind == InformationExchangePolicy.HOLDER_SHARE and reported_holder != "":
		var weight := _holder_report_weight(id, target_id,
			float(response.get("confidence", 0.0)))
		(a["tom"] as TheoryOfMind).add_reported_evidence(reported_holder,
			TheoryOfMind.possession_predicate(item_id), 1.0, weight, seq,
			int(response.get("observed_tick", tick)), tick, target_id)
		_information_tracker().trace_holder_report(id, goal_id, {
			"event": "HOLDER_EVIDENCE_APPLIED", "positive": true,
			"reporter_id": target_id, "reported_holder_id": reported_holder,
			"item_id": item_id, "observed_tick": int(response.get("observed_tick", -1)),
			"received_tick": tick, "confidence": float(response.get("confidence", 0.0)),
			"weight": weight, "evidence_kind": str(response.get("evidence_kind", "")),
			"evidence_ref": "event:%d" % seq,
		})
	elif kind == InformationExchangePolicy.HOLDER_SELF_ABSENT:
		var neg_weight := _holder_report_weight(id, target_id, 1.0)
		(a["tom"] as TheoryOfMind).add_reported_evidence(target_id,
			TheoryOfMind.possession_predicate(item_id), -1.0, neg_weight, seq,
			tick, tick, target_id)
		_information_tracker().trace_holder_report(id, goal_id, {
			"event": "HOLDER_EVIDENCE_APPLIED", "positive": false,
			"reporter_id": target_id, "reported_holder_id": target_id,
			"item_id": item_id, "observed_tick": tick, "received_tick": tick,
			"confidence": 1.0, "weight": neg_weight, "evidence_kind": "SELF_REPORT",
			"evidence_ref": "event:%d" % seq,
		})

## 报告可信度 = 报告内容置信度 × 请求者对报告者的主观可信度（关系+ToM reliable）。
## 单调：对 reporter 越信任，同一份报告的 evidence weight 不下降。
func _holder_report_weight(requester_id: String, reporter_id: String, report_confidence: float) -> float:
	var trust := relationships.composite_trust(requester_id, reporter_id)
	var trust_prob := clampf((float(trust) + 1000.0) / 2000.0, 0.0, 1.0)
	var tom: TheoryOfMind = actors[requester_id].get("tom", null)
	var reliable := 0.5
	if tom != null:
		reliable = clampf((tom.belief_about(reporter_id, "reliable") + 1.0) * 0.5, 0.0, 1.0)
	var credibility := clampf(trust_prob * 0.5 + reliable * 0.5, 0.05, 1.0)
	return clampf(report_confidence * credibility, 0.0, 1.0)

## 每周期校准：active HOLDER 目标引用的 request 是否仍活着、身份是否漂移、缺口是否仍在。
func _holder_goals_sync_all() -> void:
	var tracker := _information_tracker()
	for actor_id in actors.keys():
		var goal := tracker.current_goal(str(actor_id))
		if goal.is_empty() or str(goal.get("state", "")) != "ACTIVE" \
				or str(goal.get("query_kind", "SOURCE")) != "HOLDER":
			continue
		var requester_id := str(actor_id)
		var request := _material_request_runtime_bridge().request(str(goal.get("source_request_id", "")))
		var mismatch := ""
		if request.is_empty() or Contract.is_terminal(str(request.get("status", ""))):
			mismatch = "SOURCE_REQUEST_TERMINAL"
		else:
			mismatch = _material_request_run_mismatch_reason(requester_id, request)
		var gap := 0
		if mismatch == "" and actors.has(requester_id):
			gap = _material_request_current_gap(requester_id, actors[requester_id], request)
		_holder_diag_inc("holder_active_ticks")
		var invalid_reason := tracker.holder_goal_still_valid(requester_id, mismatch, gap)
		if invalid_reason != "":
			tracker.cancel_holder_goal(requester_id, invalid_reason, tick)

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
			bush["food"] = int(_economy["bush_capacity"])
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
			# P5（SN-F 修复）：注意到某人 = 看得见（视野/LOS）或近到听得见（≤3）
			if dist <= 3 or _actor_visible_to(a, other_id):
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
	# P5：只有 per-actor 键（appears_hungry_X）——全局聚合键已删，
	# 岛东看见的饿不该影响岛西的分享决策（跨角色感知泄漏修复）
	for id in actors:
		var appears := false
		for other_id in world["nearby_" + id]:
			if float(actors[id]["tom"].belief_about(other_id, "hungry")) > 0.4:
				appears = true
		world["appears_hungry_" + id] = appears

func _build_actor_view(id: String, a: Dictionary) -> Dictionary:
	# P1: 决策需要的社交信息——ToM、对每人的信任、附近有谁（不含他们的隐私状态）
	var trust_of := {}
	var others_nearby: Array = []
	var others_visible: Array = []
	var others_all: Array = []  # P2.1.1: known_others = 可见者 + last_seen 记忆（陈旧性由 tick 体现）
	for other_id in actors:
		if other_id == id:
			continue
		trust_of[other_id] = relationships.get_trust(id, other_id)
		var otile: Vector2i = actors[other_id]["tile"]
		pass  # P2.1.1：不再提供实时全图坐标（上帝视角泄漏）
		var d := absi(a["tile"].x - otile.x) + absi(a["tile"].y - otile.y)
		var ls2: Dictionary = a["tom"].last_seen_of(other_id)  # P2.1.1: 记忆位置（无实时真值）
		# P5（SN-F 修复）：可见 = 视野（昼夜/天气/LOS），不再是固定曼哈顿 12 格
		if _actor_visible_to(a, other_id):
			others_visible.append({"id": other_id, "tile": otile})  # 看得见 → 可以走过去求助
			others_all.append({"id": other_id, "tile": otile})
		if not ls2.is_empty():
			others_all.append({"id": other_id, "tile": ls2["tile"], "stale_tick": int(ls2["tick"])})  # 记忆位置（可能过时——扑空是真实的）
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
		"spatial": a.get("spatial", null),
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
		# P5（SN 资源修复）：决策只看自己见过的资源；饥饿感知只看自己 ToM 的判断
		"known_recipe_refs": _known_recipe_refs_view(a),
		"known_resources": _known_resources_view(a),
		"appears_hungry_nearby": bool(world.get("appears_hungry_" + id, false)),
	}

## P6.3A：主观已知配方 refs（经世界包知识 ∩ RecipeCatalog——AgencyContextBuilder 同源）
func _known_recipe_refs_view(a: Dictionary) -> Array:
	_ensure_catalogs()
	return RecipeKnowledgeAdapter.known_recipe_refs(_expertise_tags_of(a), agency_knowledge_store(), _recipe_catalog)

func _expertise_tags_of(a: Dictionary) -> Array:
	# 与 AgencyContextBuilder 同语义：自己的 LifeHistory 文本关键词
	var tags: Array = []
	var life = a.get("life_history", null)
	if life != null:
		for ev in life.events:
			var desc := str(ev.get("desc", ""))
			for pair in [["房", "WOODWORKING"], ["修", "WOODWORKING"], ["工", "WOODWORKING"], ["船", "NAVIGATION"], ["海难", "NAVIGATION"], ["航海", "NAVIGATION"], ["粮", "FOODHANDLING"], ["饥", "FOODHANDLING"], ["厨", "FOODHANDLING"]]:
				if desc.find(str(pair[0])) != -1 and not tags.has(str(pair[1])):
					tags.append(str(pair[1]))
	return tags

## P5：从空间信念导出决策用资源视图（只含 believed_available 的）
func _known_resources_view(a: Dictionary) -> Dictionary:
	var belief: SpatialBeliefMap = a.get("spatial", null)
	if belief == null:
		return {}
	return {
		"berry_bushes": belief.resource_tiles("berry"),
		"water_springs": belief.resource_tiles("water"),
		"fish_spots": belief.resource_tiles("fish"),
		"shell_beaches": belief.resource_tiles("shell"),
		"ruins": belief.resource_tiles("ruin"),
		"trees": belief.resource_tiles("tree"),
		"fires": belief.fire_dict(),
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

## P5 主观导航：路径来自 SpatialBeliefMap（UNKNOWN 按人格定成本）；
## 世界真值只在"迈一步"时裁决——撞墙 = movement_blocked + 信念修正 + 下 tick 重规划（SN 第十/十五节）
func _move_toward(a: Dictionary, target: Vector2i) -> void:
	var belief: SpatialBeliefMap = a.get("spatial", null)
	if belief == null:
		_move_toward_truth(a, target)
		return
	var target_key := "%d,%d" % [target.x, target.y]
	var plan: Dictionary = a.get("nav_plan", {})
	var path: Array = plan.get("path", [])
	# 重规划时机：目标变了 / 计划耗尽 / 计划过期（新信念可能给出更好的路）/ 不在计划轨上
	if str(plan.get("target_key", "")) != target_key or path.size() <= 1 \
			or tick - int(plan.get("tick", -9999)) >= 24 or _plan_index_of(path, a["tile"]) < 0:
		path = SubjectiveNavigator.find_path(belief, a["tile"], target, _unknown_cost(a))
		a["nav_plan"] = {"target_key": target_key, "path": path, "tick": tick}
	if path.size() > 1:
		var idx := _plan_index_of(path, a["tile"])
		var next: Vector2i = path[idx + 1]
		if map_query.is_walkable_tile(Vector3i(next.x, 0, next.y)):
			# P5.1 观测埋点：这一步踩进的是已知格还是未知格（规划者敢不敢闯）
			a["_p5_step_kind"] = "unknown" if belief.cell_state(next.x, next.y) == SpatialBeliefMap.CELL_UNKNOWN else "known"
			a["tile"] = next
			a["nav_plan"]["path"] = path.slice(idx + 1)
			return
		# 信念错了：主观认为可走、真实不可走 → 当场看见 → 修正 → 重规划
		var block_kind := "stale_free" if belief.cell_state(next.x, next.y) == SpatialBeliefMap.CELL_FREE else "unknown_obstacle"
		belief.observe_cell(next.x, next.y, SpatialBeliefMap.CELL_BLOCKED,
				map_query.get_obstacle(next.x, next.y), tick)
		_emit("movement_blocked", str(a.get("id", "")),
				"%s 被挡住了，只好重新找路" % str(a.get("display_name", "")),
				{"pos": str(next), "block_kind": block_kind})
		a["nav_plan"] = {}
		return
	# 信念中无路（目标被已知障碍围死/全然未知）→ 沿目标方向直线摸索一步（允许迷路）
	_step_toward_direct(a, target)

func _plan_index_of(path: Array, pos: Vector2i) -> int:
	for i in path.size():
		if path[i] is Vector2i and path[i].x == pos.x and path[i].y == pos.y:
			return i
	return -1

## 直线摸索：优先已知自由格，其次未知格（敢闯）；已知障碍不走
func _step_toward_direct(a: Dictionary, target: Vector2i) -> void:
	var belief: SpatialBeliefMap = a.get("spatial", null)
	var best: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = a["tile"] + d
		var cur_dist := absi(a["tile"].x - target.x) + absi(a["tile"].y - target.y)
		var n_dist := absi(n.x - target.x) + absi(n.y - target.y)
		if n_dist >= cur_dist or not belief.map_rect.has_point(n):
			continue
		var st := belief.cell_state(n.x, n.y)
		if st == SpatialBeliefMap.CELL_BLOCKED:
			continue
		var priority := 0 if st == SpatialBeliefMap.CELL_FREE else 1
		best.append([priority, n_dist, n])
	if best.is_empty():
		return
	best.sort_custom(func(x, y): return int(x[0]) < int(y[0]) or (int(x[0]) == int(y[0]) and int(x[1]) < int(y[1])))
	var step_to: Vector2i = best[0][2]
	if map_query.is_walkable_tile(Vector3i(step_to.x, 0, step_to.y)):
		a["_p5_step_kind"] = "unknown" if belief.cell_state(step_to.x, step_to.y) == SpatialBeliefMap.CELL_UNKNOWN else "known"
		a["tile"] = step_to
	else:
		var d_kind := "stale_free" if belief.cell_state(step_to.x, step_to.y) == SpatialBeliefMap.CELL_FREE else "unknown_obstacle"
		belief.observe_cell(step_to.x, step_to.y, SpatialBeliefMap.CELL_BLOCKED,
				map_query.get_obstacle(step_to.x, step_to.y), tick)
		_emit("movement_blocked", str(a.get("id", "")),
				"%s 撞上了什么，停了下来" % str(a.get("display_name", "")),
				{"pos": str(step_to), "block_kind": d_kind})
		a["nav_plan"] = {}

## 未知格成本：谨慎/恐惧/黑夜 → 更贵；好奇 → 更便宜（人格动力供给，禁止角色名硬编码）
func _unknown_cost(a: Dictionary) -> float:
	var p: PersonalityProfile = a.get("personality", null)
	var cost := 1.2
	if p != null:
		cost += float(p.traits.get("caution", 0.5)) * 1.5
		cost += float(p.emotions.get("fear", 0.0)) * 2.0
		cost -= float(p.traits.get("curiosity", 0.5)) * 0.8
	if bool(world.get("is_night", false)):
		cost += 1.0
	return cost

## 遗留真值寻路（无空间信念的对象不应出现；保险通道，仅裁决不泄露给决策）
func _move_toward_truth(a: Dictionary, target: Vector2i) -> void:
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
		# P5（SN-F 修复）：目击 = 看得见（视野/LOS）或贴得很近（≤3 格听得见动静）
		var ev_actor_tile: Vector2i = actors[actor_id]["tile"] if actors.has(actor_id) else Vector2i.ZERO
		var close_enough := absi(ev_actor_tile.x - a["tile"].x) + absi(ev_actor_tile.y - a["tile"].y) <= 3
		var spatial: bool = id == actor_id or close_enough or SpatialPerception.can_see(map_query,
				int(world_time.get("hour", 12)), str(world.get("weather", "clear")), a["tile"], ev_actor_tile)
		# P7.2A：承诺直接当事方通道——债权人（to_id）无需目击即可得知自己的承诺结局
		#（到期未收款本身就是债权人的直接证据）；但非空间目击时不得经 see_at 获得
		# 债务人当前位置，第三方仍只走空间感知。仅 COMMITMENT_* 事件，旧类型零改动。
		var direct_recipient: bool = type.begins_with("COMMITMENT_") \
				and id != actor_id and id == str(e.get("to_id", ""))
		var is_witness: bool = spatial or direct_recipient
		if is_witness:
			var salience := 0.5
			if id == actor_id or str(e.get("proposer_id", "")) == id or str(e.get("to_id", "")) == id or str(e.get("target_id", "")) == id:
				salience = 1.0  # 事件涉及我
			elif ["explored_hurt", "weather_storm"].has(str(e.get("type", ""))):
				salience = 0.9  # 危险
			witnesses.append({"id": id, "a": a, "salience": salience, "spatial": spatial})
	witnesses.sort_custom(func(x, y): return float(x["salience"]) > float(y["salience"]))
	for w in witnesses.slice(0, 3):
		var id = w["id"]
		var a: Dictionary = w["a"]
		if id != actor_id and actors.has(actor_id) and bool(w.get("spatial", true)):
			a["tom"].see_at(actor_id, actors[actor_id]["tile"], tick)  # 我看见他在哪（直接当事方非目击者除外）
		CognitiveTransition.process(a, e, {"relationships": relationships, "tick": tick})
		# P7.0：目击某人实际利用资源，构成“他知道这类来源”的主观证据。
		# 证据只写目击者 ToM；看不见的人不会凭空知道。
		if id != actor_id:
			var demonstrated_source := InformationExchangePolicy.source_kind_for_event(str(e.get("type", "")))
			if demonstrated_source == "__EVENT_FIELD__":
				demonstrated_source = str(e.get("source_kind", ""))
			if demonstrated_source != "":
				a["tom"].add_evidence(actor_id, InformationExchangePolicy.knowledge_predicate(demonstrated_source),
					1.0, 0.65, int(e.get("seq", -1)), tick)
			if agency_material_requests_enabled:
				for observation in MaterialRequestRuntimeBridge.possession_observations(e):
					var holder_id := str(observation.get("actor_id", ""))
					var observed_item := str(observation.get("item_id", ""))
					if holder_id != "" and holder_id != id and observed_item != "":
						a["tom"].add_evidence(holder_id, MaterialRequestRuntimeBridge.holder_predicate(observed_item),
							1.0, 0.65, int(e.get("seq", -1)), tick)
		# P2.1.1：遵守观察链（独立于执法链）——目击贡献/违规 → descriptive_compliance
		var evt_rule := str(e.get("rule_id", ""))
		if evt_rule != "" and id != actor_id:
			ComplianceSystem.observe_compliance(a, evt_rule, str(e.get("type", "")) == "storage_contributed", tick)
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
			if e.has("rule"):
				AuthoritySystem.public_endorsement(a, str(e["rule"].get("proposer", e.get("actor_id", ""))), int(e.get("seq", 0)), tick)  # P2.1.1：背书记给提案者
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

## P5：可见判定（昼夜/天气/LOS）——决策视野用这个，不用真坐标距离
func _actor_visible_to(a: Dictionary, other_id: String) -> bool:
	if not actors.has(other_id):
		return false
	return SpatialPerception.can_see(map_query, int(world_time.get("hour", 12)),
			str(world.get("weather", "clear")), a["tile"], actors[other_id]["tile"])

## 远离目标方向的可行走格（回避用；P5：只信自己的空间信念）
func _away_tile(mine: Vector2i, their: Vector2i, belief: SpatialBeliefMap) -> Vector2i:
	var dir := mine - their
	if dir == Vector2i.ZERO:
		dir = Vector2i(1, 1)
	for c in [mine + Vector2i(sign(dir.x) * 3, 0), mine + Vector2i(0, sign(dir.y) * 3), mine + Vector2i(sign(dir.x) * 2, sign(dir.y) * 2)]:
		if c.x > 2 and c.y > 2 and belief != null and belief.cell_state(c.x, c.y) == SpatialBeliefMap.CELL_FREE:
			return c
	return mine

## 互动半径（说话/递交的物理距离 ≤8）——不是视野；视野判定走 _actor_visible_to
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

## Plan-choice traces are observations; they never authorize a physical action.
func agency_adoption_trace() -> Array:
	return _adoption_traces.duplicate(true)

func agency_adoption_rng_states() -> Dictionary:
	var states := {}
	for id in _adoption_rngs:
		states[id] = str((_adoption_rngs[id] as RandomNumberGenerator).state)
	return states
