class_name WorldSpecLoader
extends RefCounted
## WorldSpec 加载器（WP-02 / R1）：文件读取 + 安静 JSON 解析 + 分层契约校验。
## 统一返回 { "ok": bool, "code": String, "message": String, "data": Dictionary }。
## 校验分层（R1）：
##   第一层 顶层类型防御——任何遍历、索引、float 转换之前完成；
##   第二层 嵌套类型防御——数组条目、size/terrain_weights/poi_rules/schedule/traits；
##   第三层 ID 唯一与引用完整——只有类型正确后才可能产生 E_REFERENCE_BROKEN。
## JSON 解析使用 JSON.new().parse()（安静，不向 stderr 打引擎 ERROR），失败消息只含行号与整理后的简短原因。

const SCHEMA_VERSION := "0.1"
const REQUIRED_TOP_KEYS := [
	"schema_version", "generator_version", "world_id", "title", "seed", "premise",
	"starting_region_id", "rules", "facts", "regions", "factions", "characters",
	"initial_relationships",
]
const STRING_FIELDS := ["world_id", "title", "premise", "starting_region_id", "generator_version"]
const ARRAY_FIELDS := ["facts", "regions", "factions", "characters", "initial_relationships"]
const FORBIDDEN_FIELD_NAMES := ["secret", "secrets", "api_key", "authorization"]
const WEIGHT_KEYS := ["ground", "water", "obstacle"]
const WEIGHT_TOLERANCE := 1e-6
const SEED_MIN := 0
const SEED_MAX := 2147483647
const SIZE_MIN := 32
const SIZE_MAX := 256

static func load_from_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _err("E_DATA_MISSING", "找不到数据文件：" + path)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return _err("E_JSON_INVALID", "数据文件为空或不可读：" + path)
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return _err("E_JSON_INVALID", "JSON 解析失败（第 %d 行）：%s" % [parser.get_error_line(), _sanitize(str(parser.get_error_message()))])
	var parsed = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _err("E_JSON_INVALID", "不是合法的 JSON 对象：" + path)
	return validate(parsed)

static func validate(spec) -> Dictionary:
	# —— 第一层：顶层类型防御 ——
	if typeof(spec) != TYPE_DICTIONARY:
		return _err("E_SCHEMA_INVALID", "WorldSpec 顶层必须是对象")
	if str(spec.get("schema_version", "")) != SCHEMA_VERSION:
		return _err("E_SCHEMA_VERSION", "schema_version=%s 不兼容（当前只支持 %s）" % [str(spec.get("schema_version", "")), SCHEMA_VERSION])
	for k in REQUIRED_TOP_KEYS:
		if not spec.has(k):
			return _err("E_SCHEMA_INVALID", "缺少必填字段：" + k)
	for k in STRING_FIELDS:
		if typeof(spec[k]) != TYPE_STRING or str(spec[k]).is_empty():
			return _err("E_SCHEMA_INVALID", "%s 必须是非空字符串" % k)
	var seed_val = _as_int(spec["seed"])
	if seed_val == null or seed_val < SEED_MIN or seed_val > SEED_MAX:
		return _err("E_SCHEMA_INVALID", "seed 必须是 %d..%d 的整数" % [SEED_MIN, SEED_MAX])
	spec["seed"] = seed_val # JSON 整数以 float 解析，整值规范化回 int

	var sensitive := _find_forbidden_field(spec)
	if not sensitive.is_empty():
		return _err("E_SCHEMA_INVALID", "公共数据不允许出现字段：" + sensitive)

	if typeof(spec["rules"]) != TYPE_DICTIONARY:
		return _err("E_SCHEMA_INVALID", "rules 必须是对象")
	for k in ["truths", "forbidden_claims"]:
		if typeof(spec["rules"].get(k)) != TYPE_ARRAY:
			return _err("E_SCHEMA_INVALID", "rules.%s 必须是数组" % k)
	for k in ARRAY_FIELDS:
		if typeof(spec[k]) != TYPE_ARRAY:
			return _err("E_SCHEMA_INVALID", "%s 必须是数组" % k)

	# —— 第二层：嵌套类型防御 + ID 收集 ——
	var seen := {}
	var region_ids := {}
	var faction_ids := {}
	var char_ids := {}
	var poi_ids := {}

	for entry in spec["facts"]:
		if typeof(entry) != TYPE_DICTIONARY:
			return _err("E_SCHEMA_INVALID", "facts 条目必须是对象")
		if not _dup_check(seen, entry.get("id"), "fact"):
			return _err("E_SCHEMA_INVALID", "重复 ID：" + str(entry.get("id")))

	for region in spec["regions"]:
		if typeof(region) != TYPE_DICTIONARY:
			return _err("E_SCHEMA_INVALID", "regions 条目必须是对象")
		var size_err := _check_size(region.get("size"))
		if not size_err.is_empty():
			return _err("E_SCHEMA_INVALID", "region %s 的 %s" % [str(region.get("id")), size_err])
		var weight_err := _check_weights(region.get("terrain_weights"))
		if not weight_err.is_empty():
			return _err("E_SCHEMA_INVALID", "region %s 的 %s" % [str(region.get("id")), weight_err])
		var poi_rules = region.get("poi_rules")
		if typeof(poi_rules) != TYPE_ARRAY:
			return _err("E_SCHEMA_INVALID", "region %s 的 poi_rules 必须是数组" % str(region.get("id")))
		for poi in poi_rules:
			if typeof(poi) != TYPE_DICTIONARY:
				return _err("E_SCHEMA_INVALID", "region %s 的 poi_rules 条目必须是对象" % str(region.get("id")))
		if not _dup_check(seen, region.get("id"), "region"):
			return _err("E_SCHEMA_INVALID", "重复 ID：" + str(region.get("id")))
		region_ids[region.get("id")] = true
		for poi in poi_rules:
			if not _dup_check(seen, poi.get("id"), "poi"):
				return _err("E_SCHEMA_INVALID", "重复 ID：" + str(poi.get("id")))
			poi_ids[poi.get("id")] = true

	for faction in spec["factions"]:
		if typeof(faction) != TYPE_DICTIONARY:
			return _err("E_SCHEMA_INVALID", "factions 条目必须是对象")
		if not _dup_check(seen, faction.get("id"), "faction"):
			return _err("E_SCHEMA_INVALID", "重复 ID：" + str(faction.get("id")))
		faction_ids[faction.get("id")] = true

	for character in spec["characters"]:
		if typeof(character) != TYPE_DICTIONARY:
			return _err("E_SCHEMA_INVALID", "characters 条目必须是对象")
		if typeof(character.get("public_traits")) != TYPE_ARRAY:
			return _err("E_SCHEMA_INVALID", "character %s 的 public_traits 必须是数组" % str(character.get("id")))
		var schedule = character.get("schedule")
		if typeof(schedule) != TYPE_ARRAY:
			return _err("E_SCHEMA_INVALID", "character %s 的 schedule 必须是数组" % str(character.get("id")))
		for entry in schedule:
			if typeof(entry) != TYPE_DICTIONARY:
				return _err("E_SCHEMA_INVALID", "character %s 的 schedule 条目必须是对象" % str(character.get("id")))
		if not _dup_check(seen, character.get("id"), "character"):
			return _err("E_SCHEMA_INVALID", "重复 ID：" + str(character.get("id")))
		char_ids[character.get("id")] = true

	for rel in spec["initial_relationships"]:
		if typeof(rel) != TYPE_DICTIONARY:
			return _err("E_SCHEMA_INVALID", "initial_relationships 条目必须是对象")

	# —— 第三层：引用完整性（类型已确认，只有这里才可能 E_REFERENCE_BROKEN）——
	if not region_ids.has(spec["starting_region_id"]):
		return _err("E_REFERENCE_BROKEN", "starting_region_id 指向不存在的 region：" + str(spec["starting_region_id"]))
	for faction in spec["factions"]:
		if not region_ids.has(faction.get("home_region_id")):
			return _err("E_REFERENCE_BROKEN", "faction %s 的 home_region_id 指向不存在的 region：%s" % [str(faction.get("id")), str(faction.get("home_region_id"))])
	for character in spec["characters"]:
		if not faction_ids.has(character.get("faction_id")):
			return _err("E_REFERENCE_BROKEN", "character %s 的 faction_id 指向不存在的 faction：%s" % [str(character.get("id")), str(character.get("faction_id"))])
		if not poi_ids.has(character.get("home_poi_id")):
			return _err("E_REFERENCE_BROKEN", "character %s 的 home_poi_id 指向不存在的 POI：%s" % [str(character.get("id")), str(character.get("home_poi_id"))])
		for entry in character["schedule"]:
			var target = entry.get("target_id")
			if not poi_ids.has(target) and not char_ids.has(target):
				return _err("E_REFERENCE_BROKEN", "character %s 日程的 target_id 既不是 POI 也不是角色：%s" % [str(character.get("id")), str(target)])
	for rel in spec["initial_relationships"]:
		var from_id = rel.get("from_actor_id")
		var to_id = rel.get("to_actor_id")
		if not char_ids.has(from_id) or not char_ids.has(to_id):
			return _err("E_REFERENCE_BROKEN", "关系 %s -> %s 引用了不存在的角色" % [str(from_id), str(to_id)])
		if from_id == to_id:
			return _err("E_SCHEMA_INVALID", "关系 %s 指向自己" % str(from_id))

	return {"ok": true, "code": "OK", "message": "", "data": spec}

# 整数安全规范化：int 直接通过；整值有限 float 转回 int；布尔/字符串/非整值/越界返回 null
static func _as_int(v):
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT and is_finite(v) and v == floorf(v) and absf(v) <= 2147483647.0:
		return int(v)
	return null

static func _check_size(s) -> String:
	if typeof(s) != TYPE_DICTIONARY:
		return "size 必须是对象"
	for k in ["width", "depth"]:
		if not s.has(k):
			return "size 缺少字段 " + k
		var iv = _as_int(s[k])
		if iv == null:
			return "size.%s 必须是整数" % k
		if iv < SIZE_MIN or iv > SIZE_MAX:
			return "size.%s 超出 %d..%d 范围" % [k, SIZE_MIN, SIZE_MAX]
	return ""

static func _check_weights(w) -> String:
	if typeof(w) != TYPE_DICTIONARY:
		return "terrain_weights 必须是对象"
	for k in WEIGHT_KEYS:
		if not w.has(k):
			return "terrain_weights 缺少字段 " + k
		var v = w[k]
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			return "terrain_weights.%s 必须是数值" % k
		var f := float(v)
		if not is_finite(f):
			return "terrain_weights.%s 必须是有限数值" % k
		if f < 0.0 or f > 1.0:
			return "terrain_weights.%s 超出 0..1 范围" % k
	var total := float(w["ground"]) + float(w["water"]) + float(w["obstacle"])
	if absf(total - 1.0) > WEIGHT_TOLERANCE:
		return "terrain_weights 之和为 %s，必须等于 1" % str(total)
	return ""

static func _sanitize(reason: String) -> String:
	var r := reason.replace("\n", " ").strip_edges()
	return r.substr(0, 100)

static func _dup_check(seen: Dictionary, id, kind: String) -> bool:
	if id == null or str(id).is_empty():
		return false
	if seen.has(id):
		return false
	seen[id] = kind
	return true

static func _find_forbidden_field(value, depth := 0) -> String:
	if depth > 8:
		return ""
	if typeof(value) == TYPE_DICTIONARY:
		for k in value:
			var key := str(k).to_lower()
			if FORBIDDEN_FIELD_NAMES.has(key):
				return str(k)
			var found := _find_forbidden_field(value[k], depth + 1)
			if not found.is_empty():
				return found
	elif typeof(value) == TYPE_ARRAY:
		for item in value:
			var found := _find_forbidden_field(item, depth + 1)
			if not found.is_empty():
				return found
	return ""

static func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "data": {}}
