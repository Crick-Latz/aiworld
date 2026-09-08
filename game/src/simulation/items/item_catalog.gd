class_name ItemCatalog
extends RefCounted
## P6.3A ItemCatalog——物品规格的加载/验证/查询（数据与机制分离）。
## fail-closed：未知 item_id、重复 ID、畸形字段、未知 capability 安静拒绝（返回空/false 并计入 rejected）。

var items := {}          # item_id -> ItemSpec
var rejected: Array = [] # {reason, id}——诊断用

static func load_default() -> ItemCatalog:
	var cat := ItemCatalog.new()
	cat.load_file("res://data/items/items.json")
	return cat

func load_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("ItemCatalog: missing " + path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_reject("bad_json", path)
		return
	var items_arr = parsed.get("items", [])
	if typeof(items_arr) != TYPE_ARRAY:
		_reject("items_not_array", str(path))
		return
	for spec in items_arr:
		_register(spec)

func _register(spec: Variant) -> void:
	if typeof(spec) != TYPE_DICTIONARY:
		_reject("not_dict", "?")
		return
	var id := str(spec.get("item_id", ""))
	if id == "":
		_reject("missing_id", id)
		return
	if items.has(id):
		_reject("duplicate_id", id)
		return
	if str(spec.get("display_name", "")) == "":
		_reject("missing_name", id)
		return
	var tags = spec.get("tags", [])
	if typeof(tags) != TYPE_ARRAY:
		_reject("bad_tags", id)
		return
	for tag in tags:
		if typeof(tag) != TYPE_STRING or str(tag) == "":
			_reject("bad_tag_entry", id)
			return
	var caps = spec.get("provides_capabilities", [])
	if typeof(caps) != TYPE_ARRAY:
		_reject("bad_capabilities", id)
		return
	for cap in caps:
		if typeof(cap) != TYPE_STRING or not CapabilitySpec.has(str(cap)):
			_reject("unknown_capability", id + ":" + str(cap))
			return
	if typeof(spec.get("stackable", true)) != TYPE_BOOL:
		_reject("bad_stackable", id)
		return
	items[id] = {
		"item_id": id,
		"display_name": str(spec["display_name"]),
		"tags": (tags as Array).duplicate(),
		"provides_capabilities": (caps as Array).duplicate(),
		"stackable": bool(spec.get("stackable", true)),
	}

func has(item_id: String) -> bool:
	return items.has(item_id)

func spec(item_id: String) -> Dictionary:
	return items.get(item_id, {})

func tags_of(item_id: String) -> Array:
	return (items.get(item_id, {}).get("tags", []) as Array).duplicate()

## 物品实际提供的能力（唯一权威来源——AgencyContextBuilder 等一律经此派生）
func capabilities_of(item_id: String) -> Array:
	return (items.get(item_id, {}).get("provides_capabilities", []) as Array).duplicate()

func size() -> int:
	return items.size()

func _rejord() -> Array:
	return rejected

func _reject(reason: String, id: String) -> void:
	rejected.append({"reason": reason, "id": id})
