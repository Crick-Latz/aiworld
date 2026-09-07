class_name KnowledgePack
extends RefCounted
## P6.0 §14-15 World Pack 加载器。
## data/knowledge/common_human.json —— 全人类常识（火会烧、水能喝）
## data/knowledge/island_survival.json —— 荒岛文化层（矛/火/筏的做法知识）
## 未来：three_kingdoms.json / wuxia.json / modern.json 只换包，不换脑子。

static func load_island_pack() -> WorldKnowledgeStore:
	var store := WorldKnowledgeStore.new()
	_merge_file(store, "res://data/knowledge/common_human.json")
	_merge_file(store, "res://data/knowledge/island_survival.json")
	return store

static func load_files(paths: Array) -> WorldKnowledgeStore:
	var store := WorldKnowledgeStore.new()
	for p in paths:
		_merge_file(store, str(p))
	return store

static func _merge_file(store: WorldKnowledgeStore, path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("KnowledgePack: missing " + path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("KnowledgePack: bad json " + path)
		return
	store.load_pack(parsed)
