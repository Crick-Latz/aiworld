class_name SpatialBeliefMap
extends RefCounted
## P5 空间认知：每个 Actor 独立的空间信念图（SN 审计 第十一节）。
## World Truth ≠ Actor Spatial Knowledge——这里只有"我看过的格子/资源"。
## UNKNOWN ≠ BLOCKED ≠ FREE：未知格在规划中按人格不确定性成本计价（SubjectiveNavigator）。
## 资源信念是观察时刻的快照：浆果被采光/废墟被搜过，只能重访才发现——记忆偏差是特性。

const CELL_UNKNOWN := 0
const CELL_BLOCKED := 2
const CELL_FREE := 1

var cells := {}            # "x,y" -> {"state": int, "obstacle": String, "last_seen_tick": int}
var known_resources := {}  # "kind|x,y" -> {"kind","tile","believed_present","believed_searched","last_seen_tick"}
var map_rect: Rect2i = Rect2i()

func configure(rect: Rect2i) -> void:
	map_rect = rect

static func key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]

func observe_cell(x: int, y: int, state: int, obstacle: String, at_tick: int) -> void:
	cells[key(x, y)] = {"state": state, "obstacle": obstacle, "last_seen_tick": at_tick}

## 资源快照：present/searched 是【观察时刻】的真值——之后世界变了，信念不会自动跟
func observe_resource(kind: String, tile: Vector2i, present: bool, searched: bool, at_tick: int) -> void:
	var k := "%s|%s" % [kind, key(tile.x, tile.y)]
	known_resources[k] = {"kind": kind, "tile": tile, "believed_present": present,
			"believed_searched": searched, "last_seen_tick": at_tick}

func is_known(x: int, y: int) -> bool:
	return cells.has(key(x, y))

func cell_state(x: int, y: int) -> int:
	var c: Dictionary = cells.get(key(x, y), {})
	return int(c.get("state", CELL_UNKNOWN))

## 某类资源的已知可用格（浆果=believed_present；废墟=not believed_searched）
func resource_tiles(kind: String) -> Array:
	var out: Array = []
	for k in known_resources:
		var r: Dictionary = known_resources[k]
		if str(r["kind"]) != kind:
			continue
		if kind == "ruin":
			if not bool(r["believed_searched"]):
				out.append(r["tile"])
		elif bool(r["believed_present"]):
			out.append(r["tile"])
	return out

## 已知火堆（"x,y" -> true，供 sit_by_fire 兼容格式）
func fire_dict() -> Dictionary:
	var out := {}
	for k in known_resources:
		var r: Dictionary = known_resources[k]
		if str(r["kind"]) == "fire" and bool(r["believed_present"]):
			out[key(int(r["tile"].x), int(r["tile"].y))] = true
	return out

func known_cell_count() -> int:
	return cells.size()

## SJ 确定性测试：内容 hash（键排序后拼接——不依赖字典迭代序）
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
		h = hash(str(h) + str(k) + str(bool(r["believed_present"])) + str(bool(r["believed_searched"])))
	return str(h)
