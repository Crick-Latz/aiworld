class_name SpatialBeliefMap
extends RefCounted
## P5/P7 空间认知：每个 Actor 独立的空间信念图。
## World Truth ≠ Actor Spatial Knowledge。资源来源既可以来自亲眼观察，也可以来自
## 带来源的报告；后续亲眼重访拥有更高证据优先级，并可以推翻过期报告。

const CELL_UNKNOWN := 0
const CELL_BLOCKED := 2
const CELL_FREE := 1
const EVIDENCE_PERCEPT := "PERCEPT"
const EVIDENCE_REPORT := "REPORT"

var cells := {}            # "x,y" -> {state, obstacle, last_seen_tick}
var known_resources := {}  # "kind|x,y" -> resource belief entry
var map_rect: Rect2i = Rect2i()

func configure(rect: Rect2i) -> void:
	map_rect = rect

static func key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]

static func resource_key(kind: String, tile: Vector2i) -> String:
	return "%s|%s" % [kind, key(tile.x, tile.y)]

func observe_cell(x: int, y: int, state: int, obstacle: String, at_tick: int) -> void:
	cells[key(x, y)] = {"state": state, "obstacle": obstacle, "last_seen_tick": at_tick}

## 直接感知是当前角色最强的空间证据。保持旧签名，旧调用逐位兼容。
func observe_resource(kind: String, tile: Vector2i, present: bool, searched: bool, at_tick: int) -> void:
	if kind == "":
		return
	known_resources[resource_key(kind, tile)] = {
		"kind": kind,
		"tile": tile,
		"believed_present": present,
		"believed_searched": searched,
		"last_seen_tick": at_tick,
		"received_tick": at_tick,
		"confidence": 1.0,
		"evidence_kind": EVIDENCE_PERCEPT,
		"source_actor_id": "",
		"source_event_id": -1,
	}

## 接收他人报告。报告保存对方观察时间、接收时间、来源角色和事件号。
## 较旧报告不能覆盖更新的亲眼观察；同一观察时刻也以亲眼观察为准。
func learn_reported_resource(kind: String, tile: Vector2i, observed_tick: int,
		received_tick: int, source_actor_id: String, confidence: float,
		source_event_id: int = -1) -> bool:
	if kind == "" or source_actor_id == "" or observed_tick < 0 or received_tick < observed_tick:
		return false
	if not is_finite(confidence) or confidence <= 0.0:
		return false
	if map_rect.size != Vector2i.ZERO and not map_rect.has_point(tile):
		return false
	var rk := resource_key(kind, tile)
	var current: Dictionary = known_resources.get(rk, {})
	if not current.is_empty():
		var current_tick := int(current.get("last_seen_tick", -1))
		if current_tick > observed_tick:
			return false
		if current_tick == observed_tick and str(current.get("evidence_kind", EVIDENCE_PERCEPT)) == EVIDENCE_PERCEPT:
			return false
	known_resources[rk] = {
		"kind": kind,
		"tile": tile,
		"believed_present": true,
		"believed_searched": false,
		"last_seen_tick": observed_tick,
		"received_tick": received_tick,
		"confidence": clampf(confidence, 0.0, 1.0),
		"evidence_kind": EVIDENCE_REPORT,
		"source_actor_id": source_actor_id,
		"source_event_id": source_event_id,
	}
	return true

func is_known(x: int, y: int) -> bool:
	return cells.has(key(x, y))

func cell_state(x: int, y: int) -> int:
	var c: Dictionary = cells.get(key(x, y), {})
	return int(c.get("state", CELL_UNKNOWN))

func resource_belief(kind: String, tile: Vector2i) -> Dictionary:
	return (known_resources.get(resource_key(kind, tile), {}) as Dictionary).duplicate(true)

## 资源信念按观察时间新→旧、坐标稳定排序。默认只返回仍被认为可用的来源。
func resource_beliefs(kind: String, include_unavailable: bool = false) -> Array:
	var out: Array = []
	for rk in known_resources:
		var r: Dictionary = known_resources[rk]
		if str(r.get("kind", "")) != kind:
			continue
		var available := not bool(r.get("believed_searched", false)) if kind == "ruin" else bool(r.get("believed_present", false))
		if include_unavailable or available:
			out.append(r.duplicate(true))
	out.sort_custom(func(a, b):
		var at := int(a.get("last_seen_tick", -1))
		var bt := int(b.get("last_seen_tick", -1))
		if at != bt:
			return at > bt
		var av: Vector2i = a.get("tile", Vector2i.ZERO)
		var bv: Vector2i = b.get("tile", Vector2i.ZERO)
		return av.x < bv.x or (av.x == bv.x and av.y < bv.y))
	return out

## 某类资源的已知可用格。
func resource_tiles(kind: String) -> Array:
	var out: Array = []
	for r in resource_beliefs(kind):
		if float(r.get("confidence", 1.0)) > 0.0:
			out.append(r.get("tile", Vector2i.ZERO))
	return out

## 已知火堆（"x,y" -> true，供 sit_by_fire 兼容格式）
func fire_dict() -> Dictionary:
	var out := {}
	for r in resource_beliefs("fire"):
		var tile: Vector2i = r.get("tile", Vector2i.ZERO)
		out[key(tile.x, tile.y)] = true
	return out

func known_cell_count() -> int:
	return cells.size()

## 确定性内容 hash，包含报告来源和时间，保证信息到达会触发父计划重验。
func hash_state() -> String:
	var keys := cells.keys()
	keys.sort()
	var h := hash("")
	for k in keys:
		var c: Dictionary = cells[k]
		h = hash(str(h) + str(k) + str(int(c["state"])))
	var rkeys := known_resources.keys()
	rkeys.sort()
	for k in rkeys:
		var r: Dictionary = known_resources[k]
		h = hash(str(h) + str(k)
			+ str(bool(r.get("believed_present", false)))
			+ str(bool(r.get("believed_searched", false)))
			+ str(int(r.get("last_seen_tick", -1)))
			+ str(int(r.get("received_tick", -1)))
			+ str(float(r.get("confidence", 0.0)))
			+ str(r.get("evidence_kind", ""))
			+ str(r.get("source_actor_id", ""))
			+ str(int(r.get("source_event_id", -1))))
	return str(h)
