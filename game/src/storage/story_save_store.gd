class_name StorySaveStore
extends RefCounted
## 不可变 generation 存档（OBS-04，M18）。
## 目录：<root>/saves/<world>/<timeline>/{current.json, generations/g_N/, journal/}
## 写入顺序：g_N 全部文件 + manifest（含逐文件哈希）→ 验证回读 → COMMITTED → current 指针。
## 加载只认 COMMITTED 且哈希全部通过的 generation；指针损坏按代际序回退。
## 测试注入项目 .tmp 隔离 root，不碰真实 user://。

const SAVE_FORMAT_VERSION := "0.4"

var save_root: String = "user://saves"

func _init(root := "") -> void:
	if root != "":
		save_root = root

func save_timeline(sim: StorySimulation, world_spec_path: String, map_hash: String) -> Dictionary:
	var world_id := str(sim.scenario.get("world_id", "unknown"))
	var timeline := "tl_%s" % world_id
	var dir := "%s/%s/%s" % [save_root, world_id, timeline]
	var gens_dir := dir + "/generations"
	var next_seq := _next_generation(gens_dir)
	var gen_dir: String = "%s/g_%03d" % [gens_dir, next_seq]
	DirAccess.make_dir_recursive_absolute(gen_dir)

	# 冻结快照（tick 边界的不可变数据）
	var state := _capture_state(sim)
	var events_text := ""
	for e in sim.events:
		events_text += JSON.stringify(e) + "\n"

	var files := {
		"world_spec.json": _read_or_placeholder(world_spec_path),
		"scenario.json": JSON.stringify(sim.scenario, "  "),
		"map.json": JSON.stringify({"map_hash": map_hash}, "  "),
		"state.json": JSON.stringify(state, "  "),
		"events.jsonl": events_text,
	}
	var manifest := {
		"save_format_version": SAVE_FORMAT_VERSION,
		"world_id": world_id, "timeline_id": timeline,
		"generation": next_seq, "tick": sim.tick, "event_seq": sim._seq,
		"lighthouse_lit": sim.lighthouse_lit,
		"godot_version": Engine.get_version_info().get("string", "4.7.2"),
		"files": {},
	}
	# 逐文件写入 + 哈希
	for fname in files:
		var fpath: String = gen_dir + "/" + fname
		var fa := FileAccess.open(fpath, FileAccess.WRITE)
		if fa == null:
			return {"ok": false, "code": "E_SAVE_CORRUPT", "message": "无法写入 " + fname}
		fa.store_string(files[fname])
		fa.close()
		manifest["files"][fname] = {
			"bytes": files[fname].length(),
			"sha256": _sha256(files[fname]),
		}
	manifest["files"]["manifest.json"] = {"pending": true}
	# manifest 自身写完后回读验证所有文件
	var mpath := gen_dir + "/manifest.json"
	var fm := FileAccess.open(mpath, FileAccess.WRITE)
	fm.store_string(JSON.stringify(manifest, "  "))
	fm.close()

	# 验证回读：逐文件哈希比对
	var vr := _verify_generation(gen_dir)
	if not vr.ok:
		return {"ok": false, "code": "E_SAVE_CORRUPT", "message": "写入后验证失败：" + vr.message}

	# COMMITTED 标记（全部通过后才创建）
	var fc := FileAccess.open(gen_dir + "/COMMITTED", FileAccess.WRITE)
	fc.store_string("ok\n")
	fc.close()

	# current 指针
	var fp := FileAccess.open(dir + "/current.json", FileAccess.WRITE)
	fp.store_string(JSON.stringify({"generation": next_seq, "committed": true}, "  "))
	fp.close()

	return {"ok": true, "code": "OK", "generation": next_seq, "dir": gen_dir, "manifest": manifest}

func load_latest() -> Dictionary:
	var base := _find_timeline_base()
	if base == "":
		return {"ok": false, "code": "E_DATA_MISSING", "message": "没有存档目录"}
	var current := _read_current(base)
	if current.has("generation"):
		var gen_dir: String = "%s/generations/g_%03d" % [base, int(current["generation"])]
		if FileAccess.file_exists(gen_dir + "/COMMITTED"):
			var v := _verify_generation(gen_dir)
			if v.ok:
				return _load_generation(gen_dir)
	# 指针缺失/损坏 → 按代际序从最新往下找
	var gens := _list_generations(base)
	for i in range(gens.size() - 1, -1, -1):
		var gen_dir: String = gens[i]
		if not FileAccess.file_exists(gen_dir + "/COMMITTED"):
			continue
		var v2 := _verify_generation(gen_dir)
		if v2.ok:
			return _load_generation(gen_dir)
	return {"ok": false, "code": "E_SAVE_CORRUPT", "message": "没有可加载的有效代际"}

func _load_generation(gen_dir: String) -> Dictionary:
	var state_text := FileAccess.get_file_as_string(gen_dir + "/state.json")
	var events_text := FileAccess.get_file_as_string(gen_dir + "/events.jsonl")
	var scenario_text := FileAccess.get_file_as_string(gen_dir + "/scenario.json")
	var state: Dictionary = JSON.parse_string(state_text)
	var scenario: Dictionary = JSON.parse_string(scenario_text)
	var events: Array = []
	for line in events_text.split("\n"):
		if line.strip_edges() != "":
			events.append(JSON.parse_string(line))
	return {"ok": true, "code": "OK", "state": state, "events": events, "scenario": scenario, "dir": gen_dir}

# —— 故障注入钩子（测试用）：写入 state 后 / manifest 前 / COMMITTED 前 / 指针后 ——

func corrupt_file(gen_dir: String, fname: String) -> void:
	var p := gen_dir + "/" + fname
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

func truncate_file(gen_dir: String, fname: String) -> void:
	var p := gen_dir + "/" + fname
	var t := FileAccess.get_file_as_string(p)
	var fa := FileAccess.open(p, FileAccess.WRITE)
	fa.store_string(t.substr(0, maxi(t.length() - 10, 0)))
	fa.close()

# —— 内部 ——

func _capture_state(sim: StorySimulation) -> Dictionary:
	var actors_out := {}
	for id in sim.actors:
		var a: Dictionary = sim.actors[id]
		actors_out[id] = {
			"tile_x": a["tile"].x, "tile_z": a["tile"].y,
			"phase": a["phase"], "activity": a["activity"],
			"inventory": (a["inventory"]).duplicate(),
			"goal": a["goal"], "goal_status": a["goal_status"],
			"departed": sim._departed.has(id),
		}
	return {
		"tick": sim.tick, "lighthouse_lit": sim.lighthouse_lit,
		"consumed_fuel": sim.consumed_fuel, "actors": actors_out,
		"knowledge": _serialize_knowledge(sim),
	}

func _serialize_knowledge(sim: StorySimulation) -> Dictionary:
	var out := {}
	for id in sim.actors:
		out[id] = sim.knowledge.facts_known_by(id)
	return out

func _next_generation(gens_dir: String) -> int:
	if not DirAccess.dir_exists_absolute(gens_dir):
		return 1
	var d := DirAccess.open(gens_dir)
	if d == null:
		return 1
	var max_seq := 0
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n.begins_with("g_"):
			var s := int(n.substr(2))
			max_seq = maxi(max_seq, s)
		n = d.get_next()
	d.list_dir_end()
	return max_seq + 1

func _list_generations(base: String) -> Array:
	var gens_dir := base + "/generations"
	if not DirAccess.dir_exists_absolute(gens_dir):
		return []
	var d := DirAccess.open(gens_dir)
	if d == null:
		return []
	var out: Array = []
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n.begins_with("g_"):
			out.append(gens_dir + "/" + n)
		n = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

func _find_timeline_base() -> String:
	if not DirAccess.dir_exists_absolute(save_root):
		return ""
	var d := DirAccess.open(save_root)
	if d == null:
		return ""
	d.list_dir_begin()
	var world := d.get_next()
	while world != "":
		var world_path := save_root + "/" + world
		if DirAccess.dir_exists_absolute(world_path):
			# 进入 world 目录找 timeline 子目录
			var dt := DirAccess.open(world_path)
			if dt:
				dt.list_dir_begin()
				var tl_name := dt.get_next()
				while tl_name != "":
					var tl := world_path + "/" + tl_name
					if DirAccess.dir_exists_absolute(tl + "/generations"):
						dt.list_dir_end()
						d.list_dir_end()
						return tl
					tl_name = dt.get_next()
				dt.list_dir_end()
		world = d.get_next()
	d.list_dir_end()
	return ""

func _read_current(base: String) -> Dictionary:
	var p := base + "/current.json"
	if not FileAccess.file_exists(p):
		return {}
	var t := FileAccess.get_file_as_string(p)
	var r = JSON.parse_string(t)
	return r if typeof(r) == TYPE_DICTIONARY else {}

func _verify_generation(gen_dir: String) -> Dictionary:
	var mpath := gen_dir + "/manifest.json"
	if not FileAccess.file_exists(mpath):
		return {"ok": false, "message": "manifest 缺失"}
	var m = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	if typeof(m) != TYPE_DICTIONARY or not m.has("files"):
		return {"ok": false, "message": "manifest 不可解析"}
	for fname in m["files"]:
		if fname == "manifest.json":
			continue
		var fpath: String = gen_dir + "/" + fname
		if not FileAccess.file_exists(fpath):
			return {"ok": false, "message": "文件缺失 " + fname}
		var content := FileAccess.get_file_as_string(fpath)
		var expect: String = m["files"][fname].get("sha256", "")
		var actual := _sha256(content)
		if expect != actual:
			return {"ok": false, "message": "哈希不符 " + fname}
	return {"ok": true, "message": ""}

func _sha256(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()

func _read_or_placeholder(path: String) -> String:
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path)
	return "{}"
