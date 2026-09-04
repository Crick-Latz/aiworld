class_name MapSnapshotCodec
extends RefCounted
## MapSnapshot 编解码与规范化哈希（WP-03 / R1）。
## R1：verify 是严格的契约校验器——任何类型断言/int()/索引/循环之前先做类型检查；
## 所有畸形输入安静返回 {ok:false, code:"E_SCHEMA_INVALID"}，不产生 SCRIPT ERROR；
## RLE 累计 count 超过期望长度立即拒绝（先于展开，防异常大 count 分配内存）；
## hash 必须是小写 sha256: + 64 个小写十六进制，且与 canonical payload 重算一致。
## hash 不参与自身哈希；JSON 键在 canonicalize 中按字典序排序。

const LAYER_NAMES := ["ground", "obstacle", "decoration", "elevation"]
const TOP_KEYS := ["schema_version", "generator_version", "world_id", "region_id", "width",
	"depth", "tile_encoding", "layers", "poi_tiles", "spawn_tile", "hash"]
const SCHEMA_VERSION := "0.1"
const GENERATOR_VERSION := "mapgen-0.1.0"
const TILE_ENCODING := "rle-v1"
const GROUND_VALUES := ["grass", "stone", "road", "sand"]
const OBSTACLE_VALUES := ["none", "water", "rock", "tree"]
const DECORATION_VALUES := ["none", "flower", "shrub"]

static func rle_encode_strings(values: PackedStringArray) -> Array:
	var out: Array = []
	var i := 0
	while i < values.size():
		var v := values[i]
		var run := 1
		while i + run < values.size() and values[i + run] == v:
			run += 1
		out.append([v, run])
		i += run
	return out

static func rle_encode_ints(values: PackedInt32Array) -> Array:
	var out: Array = []
	var i := 0
	while i < values.size():
		var v := values[i]
		var run := 1
		while i + run < values.size() and values[i + run] == v:
			run += 1
		out.append([v, run])
		i += run
	return out

# 解码并校验（基础防御版，R2）：参数不标注类型，让函数内的 typeof 防御真正可达——
# 错误类型的入参由本函数安静拒绝，而不是被 GDScript 参数检查挡成 runtime error。
static func rle_decode(rle, expected_len) -> Dictionary:
	if typeof(rle) != TYPE_ARRAY:
		return {"ok": false, "values": [], "message": "RLE 必须是数组"}
	if typeof(expected_len) != TYPE_INT or expected_len <= 0:
		return {"ok": false, "values": [], "message": "expected_len 必须是正整数"}
	var values: Array = []
	var total := 0
	for entry in rle:
		if typeof(entry) != TYPE_ARRAY or entry.size() != 2:
			return {"ok": false, "values": [], "message": "RLE 条目必须是 [value, count] 二元组"}
		var count = entry[1]
		if typeof(count) != TYPE_INT or count <= 0:
			return {"ok": false, "values": [], "message": "RLE count 必须是 >0 的整数"}
		total += count
		if total > expected_len:
			return {"ok": false, "values": [], "message": "RLE 累计 count 超过期望长度"}
		for _n in count:
			values.append(entry[0])
	if total != expected_len:
		return {"ok": false, "values": [], "message": "RLE 展开长度 %d 不等于 %d" % [total, expected_len]}
	return {"ok": true, "values": values, "message": ""}

static func build_snapshot(world_id: String, region_id: String, width: int, depth: int,
		ground: PackedStringArray, obstacle: PackedStringArray,
		decoration: PackedStringArray, elevation: PackedInt32Array,
		poi_tiles: Dictionary, spawn_tile: Vector3i) -> Dictionary:
	var sorted_ids: Array = []
	for pid in poi_tiles.keys():
		sorted_ids.append(pid)
	sorted_ids.sort() # poi_tiles 构造前先按 id 排序；canonicalize 在哈希前还会再排一次
	var snap: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"generator_version": GENERATOR_VERSION,
		"world_id": world_id,
		"region_id": region_id,
		"width": width,
		"depth": depth,
		"tile_encoding": TILE_ENCODING,
		"layers": {
			"ground": rle_encode_strings(ground),
			"obstacle": rle_encode_strings(obstacle),
			"decoration": rle_encode_strings(decoration),
			"elevation": rle_encode_ints(elevation),
		},
	}
	var poi_json: Dictionary = {}
	for pid in sorted_ids:
		var tile: Vector3i = poi_tiles[pid]
		poi_json[pid] = {"x": tile.x, "z": tile.z, "level": tile.y} # 对外只写 {x,z,level}
	snap["poi_tiles"] = poi_json
	snap["spawn_tile"] = {"x": spawn_tile.x, "z": spawn_tile.z, "level": spawn_tile.y}
	snap["hash"] = compute_hash(snap)
	return snap

static func canonicalize(value):
	var t := typeof(value)
	if t == TYPE_DICTIONARY:
		var out: Dictionary = {}
		var keys: Array = []
		for k in value:
			keys.append(k)
		keys.sort()
		for k in keys:
			out[k] = canonicalize(value[k])
		return out
	if t == TYPE_ARRAY:
		var arr: Array = []
		for item in value:
			arr.append(canonicalize(item))
		return arr
	return value

static func compute_hash(snapshot: Dictionary) -> String:
	var payload := snapshot.duplicate(true)
	payload.erase("hash")
	var text := JSON.stringify(canonicalize(payload), "")
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return "sha256:" + ctx.finish().hex_encode()

# —— 严格契约校验（R1）：安静，无类型强转，无 SCRIPT ERROR ——

static func verify(snapshot) -> Dictionary:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return _err("snapshot 必须是对象")
	for k in snapshot:
		if typeof(k) != TYPE_STRING or not TOP_KEYS.has(k):
			return _err("未知顶层字段：" + str(k))
	for k in TOP_KEYS:
		if not snapshot.has(k):
			return _err("缺少顶层字段 " + k)

	if typeof(snapshot["schema_version"]) != TYPE_STRING or snapshot["schema_version"] != SCHEMA_VERSION:
		return _err("schema_version 必须精确为 " + SCHEMA_VERSION)
	if typeof(snapshot["generator_version"]) != TYPE_STRING or snapshot["generator_version"] != GENERATOR_VERSION:
		return _err("generator_version 必须精确为 " + GENERATOR_VERSION)
	if typeof(snapshot["tile_encoding"]) != TYPE_STRING or snapshot["tile_encoding"] != TILE_ENCODING:
		return _err("tile_encoding 必须是 " + TILE_ENCODING)
	if not _is_valid_id(snapshot["world_id"]):
		return _err("world_id 必须是合法 ID 字符串")
	if not _is_valid_id(snapshot["region_id"]):
		return _err("region_id 必须是合法 ID 字符串")
	if typeof(snapshot["width"]) != TYPE_INT or snapshot["width"] < 32 or snapshot["width"] > 256:
		return _err("width 必须是 32..256 的整数")
	if typeof(snapshot["depth"]) != TYPE_INT or snapshot["depth"] < 32 or snapshot["depth"] > 256:
		return _err("depth 必须是 32..256 的整数")
	var width: int = snapshot["width"]
	var depth: int = snapshot["depth"]
	var expected := width * depth

	var layers = snapshot["layers"]
	if typeof(layers) != TYPE_DICTIONARY:
		return _err("layers 必须是对象")
	for k in layers:
		if typeof(k) != TYPE_STRING or not LAYER_NAMES.has(k):
			return _err("未知层 " + str(k))
	for k in LAYER_NAMES:
		if not layers.has(k):
			return _err("缺少层 " + k)

	var decoded := {}
	for k in LAYER_NAMES:
		var scan := _scan_layer(layers[k], expected, k != "elevation",
			GROUND_VALUES if k == "ground" else (OBSTACLE_VALUES if k == "obstacle" else (DECORATION_VALUES if k == "decoration" else [])))
		if not scan["ok"]:
			return _err("层 " + k + "：" + scan["message"])
		decoded[k] = scan["values"]

	var ground_values: Array = decoded["ground"]
	var obstacle_values: Array = decoded["obstacle"]
	var elevation_values: Array = decoded["elevation"]

	var poi_tiles = snapshot["poi_tiles"]
	if typeof(poi_tiles) != TYPE_DICTIONARY or poi_tiles.size() < 3:
		return _err("poi_tiles 必须是至少 3 项的对象")
	for pid in poi_tiles:
		if typeof(pid) != TYPE_STRING or not _is_valid_id(pid):
			return _err("poi_tiles 键必须是合法 ID：" + str(pid))
		var tile_check := _check_tile(poi_tiles[pid], width, depth, true)
		if not tile_check.is_empty():
			return _err("POI " + str(pid) + "：" + tile_check)
		var t: Dictionary = poi_tiles[pid]
		var idx: int = int(t["z"]) * width + int(t["x"])
		if obstacle_values[idx] != "none" or elevation_values[idx] != 0:
			return _err("POI " + str(pid) + " 对应格不可行走")

	var spawn_check := _check_tile(snapshot["spawn_tile"], width, depth, true)
	if not spawn_check.is_empty():
		return _err("spawn_tile：" + spawn_check)
	var st: Dictionary = snapshot["spawn_tile"]
	var sidx: int = int(st["z"]) * width + int(st["x"])
	if obstacle_values[sidx] != "none" or elevation_values[sidx] != 0:
		return _err("spawn_tile 与水/障碍重叠")

	var h = snapshot["hash"]
	if typeof(h) != TYPE_STRING or not _is_valid_hash(h):
		return _err("hash 必须是小写 sha256: + 64 个小写十六进制")
	if str(h) != compute_hash(snapshot):
		return _err("hash 与内容不符")
	return {"ok": true, "code": "OK", "message": ""}

# 严格层扫描：条目结构、值类型/白名单、count 类型与累计上限、精确总长；返回解码值
static func _scan_layer(rle, expected_len: int, string_layer: bool, whitelist: Array) -> Dictionary:
	if typeof(rle) != TYPE_ARRAY:
		return {"ok": false, "values": [], "message": "层必须是数组"}
	var values: Array = []
	var total := 0
	for entry in rle:
		if typeof(entry) != TYPE_ARRAY or entry.size() != 2:
			return {"ok": false, "values": [], "message": "条目必须是二元数组"}
		var v = entry[0]
		var count = entry[1]
		if string_layer:
			if typeof(v) != TYPE_STRING or str(v).is_empty() or str(v).length() > 40:
				return {"ok": false, "values": [], "message": "值必须是非空且 ≤40 字符的字符串"}
			if not whitelist.is_empty() and not whitelist.has(v):
				return {"ok": false, "values": [], "message": "值不在白名单内：" + str(v)}
		else:
			if typeof(v) != TYPE_INT or v < 0 or v > 255:
				return {"ok": false, "values": [], "message": "elevation 值必须是 0..255 的整数"}
		if typeof(count) != TYPE_INT or count <= 0:
			return {"ok": false, "values": [], "message": "count 必须是 >0 的整数"}
		total += count
		if total > expected_len:
			return {"ok": false, "values": [], "message": "累计 count 超过 width*depth"}
		for _n in count:
			values.append(v)
	if total != expected_len:
		return {"ok": false, "values": [], "message": "累计长度 %d 不等于 %d" % [total, expected_len]}
	return {"ok": true, "values": values, "message": ""}

# tile 结构检查：只含 x/z/level 三键，全 TYPE_INT，边界内，level 0..255；require_zero 时必须 level=0
static func _check_tile(tile, width: int, depth: int, require_zero: bool) -> String:
	if typeof(tile) != TYPE_DICTIONARY:
		return "必须是对象"
	if tile.size() != 3 or not (tile.has("x") and tile.has("z") and tile.has("level")):
		return "必须只含 x/z/level 三键"
	if typeof(tile["x"]) != TYPE_INT or typeof(tile["z"]) != TYPE_INT or typeof(tile["level"]) != TYPE_INT:
		return "x/z/level 必须是整数"
	if tile["x"] < 0 or tile["x"] >= width or tile["z"] < 0 or tile["z"] >= depth:
		return "坐标越界"
	if tile["level"] < 0 or tile["level"] > 255:
		return "level 超出 0..255"
	if require_zero and tile["level"] != 0:
		return "当前 mapgen 要求 level=0"
	return ""

static func _is_valid_id(v) -> bool:
	if typeof(v) != TYPE_STRING:
		return false
	var s: String = v
	if s.length() < 2 or s.length() > 48:
		return false
	var first := s.unicode_at(0)
	if not ((97 <= first and first <= 122)):
		return false
	for i in range(1, s.length()):
		var c := s.unicode_at(i)
		if not ((97 <= c and c <= 122) or (48 <= c and c <= 57) or c == 95):
			return false
	return true

static func _is_valid_hash(s) -> bool:
	if typeof(s) != TYPE_STRING:
		return false
	var str_v: String = s
	if not str_v.begins_with("sha256:"):
		return false
	var hex := str_v.substr(7)
	if hex.length() != 64:
		return false
	for ch in hex: # 严格小写十六进制
		if not (("0" <= ch and ch <= "9") or ("a" <= ch and ch <= "f")):
			return false
	return true

static func _err(message: String) -> Dictionary:
	return {"ok": false, "code": "E_SCHEMA_INVALID", "message": message}
