class_name SimulationCore
extends RefCounted
## 模拟核心（OBS-01，M05）：运行时状态唯一拥有者。
## 1 semantic tick = 1 游戏分钟；行为由 AgentBrain 决定；事件带全局递增 seq。
## 确定性：不读墙钟、无随机；同一初始状态与 seed 下，step 的调用分块方式
## 不影响语义状态与事件摘要。观察相机/UI 不消耗任何模拟随机性。

var tick := 0
var seed_value := 0
var actors: Dictionary = {} # id -> actor state Dictionary
var events: Array = []
var _event_seq := 0
var _map_query # duck-typed: is_walkable_tile(Vector3i)/find_walk_path(...)->Array/Vector2i cells

const ACTIVITY_IDLE := "idle"
const ACTIVITY_MOVING := "moving"
const ACTIVITY_INSPECTING := "inspecting"
const ACTIVITY_WAITING := "waiting"
const ACTIVITY_BLOCKED := "blocked"

func _init(map_query, actors_config: Array, world_seed: int) -> void:
	_map_query = map_query
	seed_value = world_seed
	for cfg in actors_config:
		actors[str(cfg["id"])] = {
			"id": str(cfg["id"]),
			"display_name": str(cfg.get("display_name", cfg["id"])),
			"tile": cfg["home"], # Vector2i
			"prev_tile": cfg["home"],
			"home": cfg["home"],
			"preferred": cfg.get("preferred", []),
			"pref_cursor": 0,
			"target_poi": "",
			"activity": ACTIVITY_IDLE,
			"path": [],
			"path_index": 0,
			"inspect_left": 0,
			"wait_left": 0,
			"cooldown": 0,
			"visited_pois": {}, # poi_id -> count
			"last_poi": "",
		}

func step() -> Array:
	tick += 1
	var new_events: Array = []
	for id in _ordered_ids():
		AgentBrain.tick_actor(_map_query, actors[id], tick)
	for id in _ordered_ids():
		var a: Dictionary = actors[id]
		var ev := _events_for_actor(a)
		for e in ev:
			e["seq"] = _event_seq
			_event_seq += 1
			e["tick"] = tick
			e["actor_id"] = id
			events.append(e)
			new_events.append(e)
	return new_events

func get_snapshot() -> Dictionary:
	var out := {"tick": tick, "actors": {}}
	for id in _ordered_ids():
		var a: Dictionary = actors[id]
		out["actors"][id] = {
			"id": a["id"], "display_name": a["display_name"],
			"tile": a["tile"], "prev_tile": a["prev_tile"],
			"target_poi": a["target_poi"], "activity": a["activity"],
			"visited_count": a["visited_pois"].size(),
		}
	return out

func get_actor(id: String) -> Dictionary:
	return actors[id]

# 事件摘要（确定性比较用）：只含 seq/tick/type/actor，不含文案
func event_summary() -> String:
	var parts: Array = []
	for e in events:
		parts.append("%d:%d:%s:%s" % [e["seq"], e["tick"], e["type"], e["actor_id"]])
	return "\n".join(parts)

func _ordered_ids() -> Array:
	var ids := actors.keys()
	ids.sort()
	return ids

func _events_for_actor(a: Dictionary) -> Array:
	var out: Array = []
	for e in a.get("_pending_events", []):
		e["text"] = _describe(a, e)
		out.append(e)
	a["_pending_events"] = []
	return out

func _describe(a: Dictionary, e: Dictionary) -> String:
	var who: String = a["display_name"]
	match e["type"]:
		"departed":
			return "%s 前往 %s" % [who, str(e["poi_name"])]
		"arrived":
			return "%s 到达 %s" % [who, str(e["poi_name"])]
		"inspect_done":
			return "%s 观察完 %s" % [who, str(e["poi_name"])]
		"target_blocked":
			return "%s 无法前往 %s，稍后改派" % [who, str(e["poi_name"])]
		"activity_changed":
			return "%s：%s" % [who, str(e["activity"])]
	return "%s %s" % [who, str(e["type"])]
