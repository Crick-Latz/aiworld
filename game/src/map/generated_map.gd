class_name GeneratedMap
extends RefCounted
## 生成地图的内部确定性数据（WP-03）。索引固定 index = z * width + x（row-major）。

var width: int = 0
var depth: int = 0
var retry_index: int = 0
var effective_seed: int = 0
var ground: PackedStringArray = []      # grass/stone/road/sand，长度 width*depth
var obstacle: PackedStringArray = []    # none/water/rock/tree
var decoration: PackedStringArray = []  # none/flower/shrub
var elevation: PackedInt32Array = []    # 0..3
var walkable: PackedByteArray = []      # 0/1，不写入 snapshot
var poi_tiles: Dictionary = {}          # poi_id -> Vector3i(x, level, z)
var spawn_tile: Vector3i = Vector3i.ZERO
var snapshot: Dictionary = {}
var map_hash: String = ""

func setup(w: int, d: int) -> void:
	width = w
	depth = d
	var total := w * d
	ground.resize(total)
	obstacle.resize(total)
	decoration.resize(total)
	elevation.resize(total)
	walkable.resize(total)
	for i in total:
		ground[i] = "none"
		obstacle[i] = "none"
		decoration[i] = "none"
		elevation[i] = 0
		walkable[i] = 0
