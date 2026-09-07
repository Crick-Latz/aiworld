class_name SubjectiveNavigator
extends RefCounted
## P5：只读 SpatialBeliefMap 的 A*（SN 审计 第九节：A* on SubjectiveSpatialMap）。
## 绝不读 GeneratedMap/MapController——世界真值只在"迈一步"时由 IslandSimulation 裁决。
## 成本：KNOWN_FREE=1.0 · KNOWN_BLOCKED=不可通行 · UNKNOWN=uncertainty_cost
##（由人格动力供给：caution/fear/黑暗 ↑，curiosity ↓——禁止 actor 姓名硬编码）。
## 目标格可以是 UNKNOWN（"去那儿看看"）——目标不视为障碍。
## 确定性：二叉堆 + (f, g, x, y) 全序打破平局，同输入同输出。

const NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

static func find_path(belief: SpatialBeliefMap, from: Vector2i, to: Vector2i, unknown_cost: float, max_nodes: int = 600) -> Array:
	if from == to:
		return [from]
	if not belief.map_rect.has_point(to) or not belief.map_rect.has_point(from):
		return []
	var uc := clampf(unknown_cost, 1.05, 6.0)
	var g_score := {}
	var start_key := SpatialBeliefMap.key(from.x, from.y)
	g_score[start_key] = 0.0
	# 二叉堆元素 [f, g, x, y]；comparator 全序
	var heap: Array = [[_h(from, to), 0.0, from.x, from.y]]
	var came := {}
	var expanded := 0
	while not heap.is_empty():
		var node: Array = heap[0]
		_pop_min(heap)
		var cur_key := SpatialBeliefMap.key(int(node[2]), int(node[3]))
		if float(node[1]) > float(g_score.get(cur_key, 1e18)):
			continue  # 过期堆项
		if int(node[2]) == to.x and int(node[3]) == to.y:
			return _reconstruct(came, cur_key)
		expanded += 1
		if expanded > max_nodes:
			return []
		for d in NEIGHBORS:
			var nx: int = int(node[2]) + d.x
			var ny: int = int(node[3]) + d.y
			if not belief.map_rect.has_point(Vector2i(nx, ny)):
				continue
			var st := belief.cell_state(nx, ny)
			if st == SpatialBeliefMap.CELL_BLOCKED:
				continue
			var step_cost := uc if st == SpatialBeliefMap.CELL_UNKNOWN else 1.0
			var nkey := SpatialBeliefMap.key(nx, ny)
			var ng := float(node[1]) + step_cost
			if g_score.has(nkey) and float(g_score[nkey]) <= ng:
				continue
			g_score[nkey] = ng
			came[nkey] = cur_key
			_heap_push(heap, [ng + _h(Vector2i(nx, ny), to), ng, nx, ny])
	return []

static func _h(p: Vector2i, to: Vector2i) -> float:
	return float(absi(p.x - to.x) + absi(p.y - to.y))

static func _node_less(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	if a[1] != b[1]:
		return a[1] < b[1]
	if a[2] != b[2]:
		return a[2] < b[2]
	return a[3] < b[3]

static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if _node_less(heap[i], heap[parent]):
			var tmp: Array = heap[parent]
			heap[parent] = heap[i]
			heap[i] = tmp
			i = parent
		else:
			break

static func _pop_min(heap: Array) -> void:
	heap[0] = heap[heap.size() - 1]
	heap.remove_at(heap.size() - 1)
	var i := 0
	var n := heap.size()
	while true:
		var l := 2 * i + 1
		var r := 2 * i + 2
		var smallest := i
		if l < n and _node_less(heap[l], heap[smallest]):
			smallest = l
		if r < n and _node_less(heap[r], heap[smallest]):
			smallest = r
		if smallest == i:
			break
		var tmp: Array = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = tmp
		i = smallest

static func _reconstruct(came: Dictionary, end_key: String) -> Array:
	var path: Array = []
	var k := end_key
	while true:
		var parts := k.split(",")
		path.append(Vector2i(int(parts[0]), int(parts[1])))
		if not came.has(k):
			break
		k = str(came[k])
	path.reverse()
	return path
