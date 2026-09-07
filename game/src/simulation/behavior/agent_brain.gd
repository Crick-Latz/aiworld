class_name AgentBrain
extends RefCounted
## NPC 行为（OBS-01，M06）：authored profile 目标选择 + 状态机。
## 【P5 遗留标记】本模块属 WP-04/OBS-01 原型：读精确 POI + 全图 A*（全知导航）。
## 正式认知/叙事路径是 IslandSimulation（主观空间导航）。不得在新代码中引用本模块。
## 每 tick 前进一格（原型逻辑速度）；路径/到达/计划完成由逻辑 tick 判断。
## 无路 -> 阻塞事件 + 冷却 -> 冷却结束后按偏好轮换选合法目标。
## 不随机传送、不写死播放脚本；决策确定性可复现（不用墙钟/全局随机）。

const INSPECT_TICKS := 2
const WAIT_TICKS := 3
const BLOCK_COOLDOWN := 4

static func tick_actor(map_query, a: Dictionary, _tick: int) -> void:
	if not a.has("_pending_events"):
		a["_pending_events"] = []
	a["prev_tile"] = a["tile"]
	match a["activity"]:
		"idle":
			_plan(map_query, a)
		"moving":
			_advance(a)
		"inspecting":
			a["inspect_left"] = int(a["inspect_left"]) - 1
			if a["inspect_left"] <= 0:
				a["_pending_events"].append({"type": "inspect_done", "poi_name": a["target_poi"]})
				a["activity"] = "waiting"
				a["wait_left"] = WAIT_TICKS
		"waiting":
			a["wait_left"] = int(a["wait_left"]) - 1
			if a["wait_left"] <= 0:
				a["activity"] = "idle"
		"blocked":
			a["cooldown"] = int(a["cooldown"]) - 1
			if a["cooldown"] <= 0:
				a["activity"] = "idle"

static func _plan(map_query, a: Dictionary) -> void:
	var preferred: Array = a["preferred"]
	if preferred.is_empty():
		return
	# 稳定选择：从偏好列表找一个 != 当前所在/刚访问 的合法目标；阻塞后游标轮换
	for k in range(preferred.size()):
		var idx: int = (int(a["pref_cursor"]) + k) % preferred.size()
		var poi: String = str(preferred[idx])
		if poi == a["last_poi"]:
			continue
		var poi_tile: Vector2i = map_query.get_poi_tile(poi)
		if poi_tile.x < 0:
			continue
		if poi_tile == a["tile"]:
			continue # 已站在该 POI：不算目标，换下一个
		var path: Array = map_query.find_walk_path(Vector3i(a["tile"].x, 0, a["tile"].y), Vector3i(poi_tile.x, 0, poi_tile.y))
		if path.is_empty() or path.size() < 2:
			a["_pending_events"].append({"type": "target_blocked", "poi_name": poi})
			continue
		a["pref_cursor"] = (idx + 1) % preferred.size()
		a["target_poi"] = poi
		a["path"] = path
		a["path_index"] = 1 # 0 是当前格
		a["activity"] = "moving"
		a["_pending_events"].append({"type": "departed", "poi_name": poi})
		a["_pending_events"].append({"type": "activity_changed", "activity": "moving"})
		return
	# 全部不可达：进入冷却
	a["activity"] = "blocked"
	a["cooldown"] = BLOCK_COOLDOWN

static func _advance(a: Dictionary) -> void:
	var path: Array = a["path"]
	if int(a["path_index"]) < path.size():
		var cell: Vector2i = path[int(a["path_index"])]
		a["tile"] = cell
		a["path_index"] = int(a["path_index"]) + 1
	if int(a["path_index"]) >= path.size():
		_arrive(a)

static func _arrive(a: Dictionary) -> void:
	var poi: String = a["target_poi"]
	if str(poi) == "":
		a["activity"] = "idle" # 防御：无目标不装作到达
		return
	a["visited_pois"][poi] = int(a["visited_pois"].get(poi, 0)) + 1
	a["last_poi"] = poi
	a["activity"] = "inspecting"
	a["inspect_left"] = INSPECT_TICKS
	a["_pending_events"].append({"type": "arrived", "poi_name": poi})
	a["_pending_events"].append({"type": "activity_changed", "activity": "inspecting"})
