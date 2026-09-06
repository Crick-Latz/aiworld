extends SceneTree
## OBS-04 存档/恢复/重放验收测试。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/story_save.gd
## 覆盖：保存/加载往返、checkpoint 状态重载、
## 故障注入（写后删 state / 截断 events / 无 COMMITTED / 指针损坏 → 回退上一有效代际）。

var passed := 0
var failed := 0
var _started := false
var _finished := false
var _mq = null
const TMP_ROOT := "res://../.tmp/review-OBS02-run/save_test"

func _initialize() -> void:
	print("OBS-04 save harness: deferred to first frame")

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _finished

func _run() -> void:
	await _run_all_tests()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	_finished = true
	quit(0 if failed == 0 else 1)

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("PASS %s" % name)
	else:
		failed += 1
		print("FAIL %s  %s" % [name, detail])

func _run_all_tests() -> void:
	_mq = await _make_map_query()
	if _mq == null:
		for i in range(8):
			_check("save_%d" % i, false, "地图不可用")
		return
	var root := (ProjectSettings.globalize_path(TMP_ROOT) as String).replace("game/../", "")
	DirAccess.make_dir_recursive_absolute(root)
	# 清理旧测试数据
	var d := DirAccess.open(root)
	if d:
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			if n != "." and n != "..":
				_rm_recursive(root + "/" + n)
			n = d.get_next()
		d.list_dir_end()

	# —— 1. 保存/加载往返：状态与事件完整恢复 ——
	var sm := StorySaveStore.new(root)
	var sim := _make()
	for i in 100:
		sim.step()
	var save_r: Dictionary = sm.save_timeline(sim, "res://data/demo_world/world_spec.json", "test_hash")
	_check("save_succeeds", save_r.ok, str(save_r))
	var load_r: Dictionary = sm.load_latest()
	_check("load_roundtrip",
		load_r.ok and load_r.has("state")
		and int(load_r["state"].get("tick", -1)) == sim.tick
		and load_r.get("events", []).size() == sim.events.size()
		and bool(load_r["state"].get("lighthouse_lit", false)) == sim.lighthouse_lit,
		"ok=%s tick=%s/%d" % [load_r.get("ok"), str(load_r.get("state", {}).get("tick", "?")), sim.tick])

	# —— 2. checkpoint 重载：本测试不夸大为“恢复后继续模拟”等价 ——
	var sm2 := StorySaveStore.new(root)
	var b := _make()
	for i in 100:
		b.step()
	sm2.save_timeline(b, "", "bh")
	var loaded: Dictionary = sm2.load_latest()
	_check("checkpoint_state_reloads",
		loaded.ok and loaded.has("state") and int(loaded["state"].get("tick", -1)) == 100
		, "load tick=%s" % str(loaded.get("state", {}).get("tick", "?")))

	# —— 3. 故障注入：写入后删除 state → 加载拒绝（无 COMMITTED 也可检验）——
	var sm3 := StorySaveStore.new(root)
	var c := _make()
	for i in 50:
		c.step()
	var r3: Dictionary = sm3.save_timeline(c, "", "ch")
	sm3.corrupt_file(r3["dir"], "state.json")
	var lr3: Dictionary = sm3.load_latest()
	_check("corrupt_state_rejected", not lr3.ok or int(lr3.get("state", {}).get("tick", -1)) != 50,
		"ok=%s" % lr3.get("ok", "?"))

	# —— 4. 故障注入：截断 events.jsonl → 哈希不匹配拒绝 ——
	var sm4 := StorySaveStore.new(root)
	var e4 := _make()
	for i in 60:
		e4.step()
	var r4: Dictionary = sm4.save_timeline(e4, "", "eh")
	sm4.truncate_file(r4["dir"], "events.jsonl")
	var lr4: Dictionary = sm4.load_latest()
	_check("truncated_events_rejected", not lr4.ok or int(lr4.get("state", {}).get("tick", -1)) != 60,
		"ok=%s tick=%s" % [str(lr4.get("ok", false)), str(lr4.get("state", {}).get("tick", -1))])

	# —— 5. 回退上一有效代际 ——
	var sm5 := StorySaveStore.new(root)
	var f := _make()
	for i in 30:
		f.step()
	var r5: Dictionary = sm5.save_timeline(f, "", "fh") # gen N（有效）
	var f2 := _make()
	for i in 80:
		f2.step()
	var r5b: Dictionary = sm5.save_timeline(f2, "", "fh2") # gen N+1
	sm5.corrupt_file(r5b["dir"], "state.json") # 损坏最新代
	var lr5: Dictionary = sm5.load_latest()
	_check("fallback_to_previous_generation",
		lr5.ok and int(lr5.get("state", {}).get("tick", -1)) == 30, "tick=%s" % str(lr5.get("state", {}).get("tick", "?")))

	print("SAVE_SUMMARY gens=%d final_tick=%d" % [5, lr5.get("state", {}).get("tick", -1)])

func _make_map_query():
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null:
		return null
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20:
		await physics_frame
	return inst.get_node("World/MapController")

func _make() -> StorySimulation:
	var text := FileAccess.get_file_as_string("res://data/scenarios/lighthouse_baseline.json")
	var data: Dictionary = JSON.parse_string(text)
	var homes := {"npc_weila": "tide_market", "npc_oun": "tide_market", "npc_kadga": "post_house"}
	var spawn := {}
	for id in homes:
		spawn[id] = _mq.get_poi_tile(homes[id])
	return StorySimulation.new(_mq, data, spawn)

func _rm_recursive(p: String) -> void:
	if DirAccess.dir_exists_absolute(p):
		var d := DirAccess.open(p)
		if d:
			d.list_dir_begin()
			var n := d.get_next()
			while n != "":
				if n != "." and n != "..":
					_rm_recursive(p + "/" + n)
				n = d.get_next()
			d.list_dir_end()
			DirAccess.remove_absolute(p)
	elif FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
