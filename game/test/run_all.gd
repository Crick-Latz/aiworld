extends SceneTree
## WP-02 离线测试（headless）。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/run_all.gd
## 退出码：全部通过 = 0；任一失败 = 1。全程零网络、零存档。

var passed := 0
var failed := 0
var _tests_started := false
var _tests_finished := false

const AUTOLOAD_SCRIPTS := [
	"res://src/autoload/app_config.gd",
	"res://src/autoload/contract_registry.gd",
	"res://src/autoload/event_hub.gd",
	"res://src/autoload/game_session.gd",
	"res://src/autoload/simulation.gd",
	"res://src/autoload/save_manager.gd",
	"res://src/autoload/ai_client.gd",
]
const INPUT_ACTIONS := [
	"move_up", "move_down", "move_left", "move_right",
	"camera_rotate_left", "camera_rotate_right",
	"interact", "cancel", "toggle_log", "toggle_debug",
	"quick_save", "quick_load",
]

# 在 _initialize 里 add_child 的节点，其 _ready/@onready 会推迟到第一帧才传播；
# 因此测试推迟到首个 _process 帧执行。R1 起测试含 await（布局/Esc 输入），
# 改为异步：挂起后引擎继续跑帧，直到 quit()。
func _initialize() -> void:
	print("WP-02 test harness: tests deferred to first frame")

func _process(_delta: float) -> bool:
	if not _tests_started:
		_tests_started = true
		_run_all_tests()
	return _tests_finished

func _run_all_tests() -> void:
	_test_valid_spec()
	_test_missing_field()
	_test_bad_version()
	_test_broken_refs()
	_test_bad_json()
	_test_missing_file()
	_test_secret_and_duplicate()
	_test_scene_and_autoloads()
	_test_debug_fields()
	_test_failure_stops_world()
	_test_malformed_top_level()
	_test_malformed_nested()
	_test_quiet_json()
	_test_process_mode()
	_test_config_blocks_world()
	_test_shadow_distance()
	_test_seed_deriver()
	_test_grid_coord()
	_test_rle_and_hash()
	_test_map_seeds()
	_test_unreachable()
	_test_projector()
	_test_main_scene_map()
	_test_biome_profiles()
	_test_snapshot_strict()
	_test_r1_scene()
	_test_rle_decode_type_defense()
	_test_biome_nine()
	_test_player_scene()
	_test_selector()
	_test_navigator_unit()
	_test_boundary()
	_test_wp04_scene()
	await _test_wp04_r1_pause_and_layout()
	_test_config_defense()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	_tests_finished = true
	quit(0 if failed == 0 else 1)

func _check(test_name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("PASS %s" % test_name)
	else:
		failed += 1
		print("FAIL %s  %s" % [test_name, detail])

func _load_demo_result() -> Dictionary:
	return WorldSpecLoader.load_from_path("res://data/demo_world/world_spec.json")

func _test_valid_spec() -> void:
	var r := _load_demo_result()
	_check("valid_spec_ok", r.ok, r.message)
	_check("valid_spec_world_id", r.ok and r.data.get("world_id") == "mist_harbor", str(r.code))
	_check("valid_spec_seed", r.ok and int(r.data.get("seed", -1)) == 20260904, str(r.code))

func _test_missing_field() -> void:
	var r := WorldSpecLoader.load_from_path("res://test/fixtures/missing_field.json")
	_check("missing_field_rejected", not r.ok and r.code == "E_SCHEMA_INVALID", r.code + " " + r.message)

func _test_bad_version() -> void:
	var r := WorldSpecLoader.load_from_path("res://test/fixtures/bad_version.json")
	_check("bad_version_rejected", not r.ok and r.code == "E_SCHEMA_VERSION", r.code + " " + r.message)

func _test_broken_refs() -> void:
	var r1 := WorldSpecLoader.load_from_path("res://test/fixtures/broken_ref_faction.json")
	_check("broken_ref_faction_region", not r1.ok and r1.code == "E_REFERENCE_BROKEN", r1.code + " " + r1.message)
	var base := _load_demo_result()
	var spec: Dictionary = base.data.duplicate(true)
	spec["characters"][0]["home_poi_id"] = "nope_poi"
	var r2 := WorldSpecLoader.validate(spec)
	_check("broken_ref_character_poi", not r2.ok and r2.code == "E_REFERENCE_BROKEN", r2.code + " " + r2.message)

func _test_bad_json() -> void:
	var r := WorldSpecLoader.load_from_path("res://test/fixtures/bad_json.json")
	_check("bad_json_rejected", not r.ok and r.code == "E_JSON_INVALID", r.code + " " + r.message)

func _test_missing_file() -> void:
	var r := WorldSpecLoader.load_from_path("res://data/demo_world/definitely_not_here.json")
	_check("missing_file_rejected", not r.ok and r.code == "E_DATA_MISSING", r.code + " " + r.message)

func _test_secret_and_duplicate() -> void:
	var base := _load_demo_result()
	var with_secret: Dictionary = base.data.duplicate(true)
	with_secret["secrets"] = []
	var r1 := WorldSpecLoader.validate(with_secret)
	_check("secret_field_rejected", not r1.ok and r1.code == "E_SCHEMA_INVALID" and r1.message.find("secrets") != -1, r1.code + " " + r1.message)
	var with_dup: Dictionary = base.data.duplicate(true)
	with_dup["characters"].append(with_dup["characters"][0].duplicate(true))
	var r2 := WorldSpecLoader.validate(with_dup)
	_check("duplicate_id_rejected", not r2.ok and r2.code == "E_SCHEMA_INVALID" and r2.message.find("重复 ID") != -1, r2.code + " " + r2.message)

func _test_scene_and_autoloads() -> void:
	var ps := load("res://scenes/main/main.tscn")
	_check("main_scene_loadable", ps != null and ps is PackedScene)
	for script_path in AUTOLOAD_SCRIPTS:
		var s = load(script_path)
		_check("autoload_parse_" + script_path.get_file().get_basename(), s != null and s.can_instantiate(), script_path)
	for action in INPUT_ACTIONS:
		_check("input_action_" + action, InputMap.has_action(action), action)
	if ps != null and ps is PackedScene:
		var inst = ps.instantiate()
		var structure_ok := inst.get_node_or_null("World/Environment") != null \
			and inst.get_node_or_null("World/Sun") != null \
			and inst.get_node_or_null("World/GroundGrid") != null \
			and inst.get_node_or_null("World/ObstacleGrid") != null \
			and inst.get_node_or_null("World/PropRoot") != null \
			and inst.get_node_or_null("World/PoiRoot") != null \
			and inst.get_node_or_null("World/ActorRoot") != null \
			and inst.get_node_or_null("World/TriggerRoot") != null \
			and inst.get_node_or_null("World/MapController") != null \
			and inst.get_node_or_null("World/CameraRig/YawPivot/MainCamera") != null \
			and inst.get_node_or_null("Ui/Hud/TitleLabel") != null \
			and inst.get_node_or_null("Ui/ErrorPanel/ErrorBox/ErrorVBox/ErrorCodeLabel") != null \
			and inst.get_node_or_null("Ui/DebugOverlay/DebugPanel/DebugVBox/DebugWorldLabel") != null \
			and inst.get_node_or_null("Audio") != null
		_check("scene_tree_structure", structure_ok)
		inst.free()

func _test_debug_fields() -> void:
	var ps: PackedScene = load("res://scenes/main/main.tscn")
	if ps == null:
		_check("debug_fields_ready", false, "主场景不可加载")
		return
	var inst = ps.instantiate()
	root.add_child(inst) # _ready 运行：正常走 autoload，独立环境走直接加载，两者都会 apply_world
	var d: Dictionary = inst.get_debug_info()
	_check("debug_world_id", str(d.get("world_id", "")) == "mist_harbor", str(d))
	_check("debug_schema_version", str(d.get("schema_version", "")) == "0.1", str(d))
	_check("debug_seed", str(d.get("seed", "")) == "20260904", str(d))
	_check("debug_generator_version", str(d.get("generator_version", "")) == "worldgen-0.1.0", str(d))
	_check("debug_mode", str(d.get("mode", "")) == "demo", str(d))
	_check("debug_camera_orthogonal", str(d.get("camera_projection", "")) == "orthogonal", str(d))
	_check("debug_camera_size", absf(float(d.get("camera_orthogonal_size", 0.0)) - 20.0) < 0.001, str(d))
	root.remove_child(inst)
	inst.free()

func _test_failure_stops_world() -> void:
	var ps: PackedScene = load("res://scenes/main/main.tscn")
	if ps == null:
		_check("failure_stops_world", false, "主场景不可加载")
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	inst.apply_error("E_REFERENCE_BROKEN", "测试：断裂引用")
	_check("failure_hides_world", inst.world_root.visible == false)
	_check("failure_stops_processing", inst.world_root.is_processing() == false)
	_check("failure_shows_error_panel", inst.error_panel.visible == true)
	_check("failure_error_code_shown", inst.error_code_label.text == "E_REFERENCE_BROKEN")
	var d: Dictionary = inst.get_debug_info()
	_check("failure_debug_error", str(d.get("error", "")).find("E_REFERENCE_BROKEN") == 0, str(d))
	root.remove_child(inst)
	inst.free()

# —— WP-02-R1 新增：数据加载防御与错误状态 ——

func _fresh_spec() -> Dictionary:
	var base := WorldSpecLoader.load_from_path("res://data/demo_world/world_spec.json")
	return base.data.duplicate(true)

func _expect_invalid(test_name: String, spec: Dictionary) -> void:
	var r := WorldSpecLoader.validate(spec)
	_check(test_name, not r.ok and r.code == "E_SCHEMA_INVALID", r.code + " " + r.message)

func _test_malformed_top_level() -> void:
	var s: Dictionary
	s = _fresh_spec(); s["facts"] = null
	_expect_invalid("malformed_facts_null", s)
	s = _fresh_spec(); s["regions"] = "bad"
	_expect_invalid("malformed_regions_string", s)
	s = _fresh_spec(); s["factions"] = 123
	_expect_invalid("malformed_factions_number", s)
	s = _fresh_spec(); s["characters"] = {}
	_expect_invalid("malformed_characters_dict", s)
	s = _fresh_spec(); s["initial_relationships"] = null
	_expect_invalid("malformed_relationships_null", s)
	s = _fresh_spec(); s["rules"] = null
	_expect_invalid("malformed_rules_null", s)
	s = _fresh_spec(); s["rules"] = {"truths": "bad", "forbidden_claims": []}
	_expect_invalid("malformed_rules_truths_string", s)
	s = _fresh_spec(); s["seed"] = "7"
	_expect_invalid("malformed_seed_string", s)
	s = _fresh_spec(); s["seed"] = true
	_expect_invalid("malformed_seed_bool", s)
	s = _fresh_spec(); s["seed"] = 1.5
	_expect_invalid("malformed_seed_fractional", s)
	s = _fresh_spec(); s["seed"] = -5
	_expect_invalid("malformed_seed_negative", s)
	s = _fresh_spec(); s["world_id"] = ""
	_expect_invalid("malformed_world_id_empty", s)
	s = _fresh_spec(); s["premise"] = 42
	_expect_invalid("malformed_premise_number", s)

func _test_malformed_nested() -> void:
	var s: Dictionary
	s = _fresh_spec(); s["regions"][0]["terrain_weights"] = "bad"
	_expect_invalid("nested_terrain_weights_string", s)
	s = _fresh_spec(); s["regions"][0]["terrain_weights"].erase("water")
	_expect_invalid("nested_terrain_missing_field", s)
	s = _fresh_spec(); s["regions"][0]["terrain_weights"]["ground"] = "x"
	_expect_invalid("nested_terrain_non_numeric", s)
	s = _fresh_spec(); s["regions"][0]["terrain_weights"]["ground"] = INF
	_expect_invalid("nested_terrain_infinite", s)
	s = _fresh_spec(); s["regions"][0]["terrain_weights"]["ground"] = NAN
	_expect_invalid("nested_terrain_nan", s)
	s = _fresh_spec(); s["regions"][0]["terrain_weights"]["ground"] = 1.5
	_expect_invalid("nested_terrain_out_of_range", s)
	s = _fresh_spec(); s["regions"][0]["size"] = "bad"
	_expect_invalid("nested_size_string", s)
	s = _fresh_spec(); s["regions"][0]["size"] = {"width": "x", "depth": 64}
	_expect_invalid("nested_size_width_string", s)
	s = _fresh_spec(); s["regions"][0]["size"] = {"width": 8, "depth": 64}
	_expect_invalid("nested_size_out_of_range", s)
	s = _fresh_spec(); s["regions"][0]["poi_rules"] = "bad"
	_expect_invalid("nested_poi_rules_string", s)
	s = _fresh_spec(); s["characters"][0]["schedule"] = "bad"
	_expect_invalid("nested_schedule_string", s)
	s = _fresh_spec(); s["characters"][0]["public_traits"] = "bad"
	_expect_invalid("nested_public_traits_string", s)

func _test_quiet_json() -> void:
	var r := WorldSpecLoader.load_from_path("res://test/fixtures/bad_json.json")
	_check("quiet_json_code", not r.ok and r.code == "E_JSON_INVALID", r.code)
	_check("quiet_json_message_has_line", r.message.find("JSON 解析失败（第") != -1, r.message)

func _test_process_mode() -> void:
	var ps: PackedScene = load("res://scenes/main/main.tscn")
	if ps == null:
		_check("process_mode_disabled_on_error", false, "主场景不可加载")
		_check("process_mode_inherit_on_world", false, "主场景不可加载")
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	var sun_node = inst.get_node("World/Sun")
	inst.apply_error("E_SCHEMA_INVALID", "测试：停用子树")
	_check("process_mode_disabled_on_error", inst.world_root.process_mode == Node.PROCESS_MODE_DISABLED and sun_node.can_process() == false)
	var r := WorldSpecLoader.load_from_path("res://data/demo_world/world_spec.json")
	inst.apply_world(r.data)
	_check("process_mode_inherit_on_world", inst.world_root.process_mode == Node.PROCESS_MODE_INHERIT and sun_node.can_process() == true)
	root.remove_child(inst)
	inst.free()

func _test_config_blocks_world() -> void:
	var app = root.get_node_or_null("AppConfig")
	if app == null:
		_check("config_failure_blocks_world", false, "AppConfig 未加载")
		_check("config_failure_keeps_message", false, "AppConfig 未加载")
		return
	var saved_code := str(app.last_error_code)
	var saved_msg := str(app.last_error_message)
	app.last_error_code = "E_JSON_INVALID"
	app.last_error_message = "测试注入的配置失败"
	var gs = load("res://src/autoload/game_session.gd").new()
	root.add_child(gs) # _ready：应被配置失败阻断，不读取 WorldSpec
	_check("config_failure_blocks_world", gs.world.is_empty() and gs.world_error_code == "E_JSON_INVALID", gs.world_error_code)
	_check("config_failure_keeps_message", gs.world_error_message == "测试注入的配置失败", gs.world_error_message)
	root.remove_child(gs)
	gs.free()
	app.last_error_code = saved_code
	app.last_error_message = saved_msg

func _test_shadow_distance() -> void:
	var ps: PackedScene = load("res://scenes/main/main.tscn")
	if ps == null:
		_check("shadow_max_distance_40", false, "主场景不可加载")
		return
	var inst = ps.instantiate()
	var d = float(inst.get_node("World/Sun").directional_shadow_max_distance)
	_check("shadow_max_distance_40", absf(d - 40.0) < 0.001, str(d))
	inst.free()

# —— WP-03 新增：确定性 2.5D 地图 ——

func _fail_cat(failures: Dictionary, cat: String, seed: int) -> void:
	if not failures.has(cat):
		failures[cat] = []
	failures[cat].append(seed)

func _map_test_config() -> Dictionary:
	var app = root.get_node_or_null("AppConfig")
	if app and typeof(app.raw) == TYPE_DICTIONARY and typeof(app.raw.get("map")) == TYPE_DICTIONARY:
		return app.raw.get("map")
	return {}

func _demo_spec() -> Dictionary:
	var r := WorldSpecLoader.load_from_path("res://data/demo_world/world_spec.json")
	return r.data.duplicate(true)

func _test_seed_deriver() -> void:
	_check("seed_deriver_deterministic", SeedDeriver.derive(20260904, "map:r:elevation", 0) == SeedDeriver.derive(20260904, "map:r:elevation", 0))
	_check("seed_deriver_namespace_isolated", SeedDeriver.derive(20260904, "map:r:a", 0) != SeedDeriver.derive(20260904, "map:r:b", 0))
	_check("seed_deriver_index_isolated", SeedDeriver.derive(20260904, "map:r:a", 0) != SeedDeriver.derive(20260904, "map:r:a", 1))
	var in_range := true
	for ns in ["map:r:elevation", "map:r:moisture", "map:r:poi:p1", "map:r:decoration"]:
		for idx in [0, 1, 7, 12345]:
			var v := SeedDeriver.derive(99, ns, idx)
			if v < 0 or v > 9223372036854775807:
				in_range = false
	_check("seed_deriver_nonnegative_63bit", in_range)

func _test_grid_coord() -> void:
	_check("grid_index", GridCoord.to_index(3, 5, 64) == 323)
	_check("grid_bounds", GridCoord.in_bounds(0, 0, 64, 64) and GridCoord.in_bounds(63, 63, 64, 64) and not GridCoord.in_bounds(64, 0, 64, 64) and not GridCoord.in_bounds(-1, 0, 64, 64))
	var ok := true
	for tile in [Vector3i(0, 0, 0), Vector3i(63, 3, 63), Vector3i(31, 2, 17)]:
		if GridCoord.world_to_tile(GridCoord.tile_to_world(tile)) != tile:
			ok = false
	_check("grid_tile_world_roundtrip", ok)

func _test_rle_and_hash() -> void:
	var single := MapSnapshotCodec.rle_encode_strings(PackedStringArray(["grass", "grass", "grass"]))
	_check("rle_single_value", single.size() == 1 and single[0][0] == "grass" and single[0][1] == 3)
	var dec := MapSnapshotCodec.rle_decode(MapSnapshotCodec.rle_encode_strings(PackedStringArray(["a", "b", "a", "b"])), 4)
	_check("rle_alternating_roundtrip", dec.ok and dec.values == ["a", "b", "a", "b"])
	_check("rle_zero_count_rejected", not MapSnapshotCodec.rle_decode([["x", 0]], 0).ok)
	_check("rle_bad_length_rejected", not MapSnapshotCodec.rle_decode([["x", 3]], 5).ok)
	var g := PackedStringArray()
	var o := PackedStringArray()
	var dc := PackedStringArray()
	var el := PackedInt32Array()
	for i in 1024:
		g.append("grass")
		o.append("none")
		dc.append("none")
		el.append(0)
	var snap := MapSnapshotCodec.build_snapshot("w_test", "r_test", 32, 32, g, o, dc, el,
		{"poi_a": Vector3i(1, 0, 2), "poi_b": Vector3i(5, 0, 7), "poi_c": Vector3i(9, 0, 11)}, Vector3i(1, 0, 3))
	_check("snapshot_verify_ok", MapSnapshotCodec.verify(snap).ok)
	var bad_hash: Dictionary = snap.duplicate(true)
	bad_hash["hash"] = "sha256:" + "0".repeat(64)
	_check("snapshot_tampered_hash_rejected", not MapSnapshotCodec.verify(bad_hash).ok)
	var unknown_layer: Dictionary = snap.duplicate(true)
	unknown_layer["layers"]["extra_layer"] = [["x", 1]]
	_check("snapshot_unknown_layer_rejected", not MapSnapshotCodec.verify(unknown_layer).ok)
	var bad_len: Dictionary = snap.duplicate(true)
	bad_len["layers"]["ground"] = [["grass", 10]]
	_check("snapshot_bad_rle_length_rejected", not MapSnapshotCodec.verify(bad_len).ok)

func _test_map_seeds() -> void:
	var spec := _demo_spec()
	var config := _map_test_config()
	var failures := {}
	var bad_seeds := {}
	var hashes := {}
	var passed_seeds := 0
	var t0 := Time.get_ticks_msec()
	for seed in range(1, 21):
		spec["seed"] = seed
		var r := MapGenerator.generate(spec, config)
		if not r.ok:
			_fail_cat(failures, "gen_ok", seed)
			bad_seeds[seed] = true
			print("MAP_SEED seed=%d FAILED code=%s msg=%s" % [seed, str(r.code), str(r.message)])
			continue
		var m: GeneratedMap = r.data
		if m.width != 64 or m.depth != 64:
			_fail_cat(failures, "size", seed)
		if m.ground.size() != 4096 or m.obstacle.size() != 4096 or m.decoration.size() != 4096 or m.elevation.size() != 4096:
			_fail_cat(failures, "layer_len", seed)
		var snap: Dictionary = m.snapshot
		var layers: Dictionary = snap["layers"]
		var rt_ok := true
		for pair in [["ground", m.ground], ["obstacle", m.obstacle], ["decoration", m.decoration]]:
			var d := MapSnapshotCodec.rle_decode(layers[pair[0]], 4096)
			if not d.ok:
				rt_ok = false
				break
			var arr: PackedStringArray = pair[1]
			for i in 4096:
				if str(d.values[i]) != arr[i]:
					rt_ok = false
					break
		if rt_ok:
			var de := MapSnapshotCodec.rle_decode(layers["elevation"], 4096)
			if de.ok:
				for i in 4096:
					if int(de.values[i]) != m.elevation[i]:
						rt_ok = false
						break
			else:
				rt_ok = false
		if not rt_ok:
			_fail_cat(failures, "rle_roundtrip", seed)
		var wl_ok := true
		for i in 4096:
			if not ["grass", "stone", "road", "sand"].has(m.ground[i]):
				wl_ok = false
			if not ["none", "water", "rock", "tree"].has(m.obstacle[i]):
				wl_ok = false
			if not ["none", "flower", "shrub"].has(m.decoration[i]):
				wl_ok = false
			if m.elevation[i] < 0 or m.elevation[i] > 3:
				wl_ok = false
		if not wl_ok:
			_fail_cat(failures, "whitelist", seed)
		var poi_ok := true
		var poi_ids: Array = snap["poi_tiles"].keys()
		var total := 64
		for pid in poi_ids:
			var t: Dictionary = snap["poi_tiles"][pid]
			if t["x"] < 4 or t["x"] > total - 5 or t["z"] < 4 or t["z"] > total - 5 or int(t["level"]) != 0:
				poi_ok = false
		for a in range(poi_ids.size()):
			for b in range(a + 1, poi_ids.size()):
				var ta: Dictionary = snap["poi_tiles"][poi_ids[a]]
				var tb: Dictionary = snap["poi_tiles"][poi_ids[b]]
				if absi(int(ta["x"]) - int(tb["x"])) + absi(int(ta["z"]) - int(tb["z"])) < 10:
					poi_ok = false
		if not poi_ok:
			_fail_cat(failures, "poi", seed)
		var st: Dictionary = snap["spawn_tile"]
		var si := int(st["z"]) * 64 + int(st["x"])
		if int(st["level"]) != 0 or m.obstacle[si] != "none" or m.walkable[si] != 1:
			_fail_cat(failures, "spawn", seed)
		var reach := MapGenerator._flood(m, Vector2i(int(st["x"]), int(st["z"])))
		var reach_ok := true
		for pid in poi_ids:
			var t2: Dictionary = snap["poi_tiles"][pid]
			if not reach.has(int(t2["z"]) * 64 + int(t2["x"])):
				reach_ok = false
		if not reach_ok:
			_fail_cat(failures, "reach", seed)
		var rt := MapGenerator._ratios(m)
		if rt["walk"] < 0.65 or rt["walk"] > 0.82 or rt["water"] < 0.05 or rt["water"] > 0.18 or rt["solid"] < 0.10 or rt["solid"] > 0.25:
			_fail_cat(failures, "ratios", seed)
		if not MapSnapshotCodec.verify(snap).ok:
			_fail_cat(failures, "codec_verify", seed)
		if m.retry_index < 0 or m.retry_index > 7:
			_fail_cat(failures, "retry_range", seed)
		var r2 := MapGenerator.generate(spec, config)
		var det_ok: bool = r2.ok
		if det_ok:
			det_ok = r2.data.map_hash == m.map_hash and JSON.stringify(MapSnapshotCodec.canonicalize(r2.data.snapshot)) == JSON.stringify(MapSnapshotCodec.canonicalize(snap))
		if not det_ok:
			_fail_cat(failures, "determinism", seed)
		if failures.has("gen_ok") and seed in failures["gen_ok"]:
			continue
		var seed_failed := false
		for cat in failures:
			if seed in failures[cat]:
				seed_failed = true
		if seed_failed:
			bad_seeds[seed] = true
		else:
			passed_seeds += 1
		print("MAP_SEED seed=%d ok hash=%s retry=%d" % [seed, m.map_hash, m.retry_index])
		hashes[m.map_hash] = true
	var ms := Time.get_ticks_msec() - t0
	print("MAP_SUMMARY seeds=20 passed=%d failed=%d unique_hashes=%d duration_ms=%d" % [passed_seeds, bad_seeds.size(), hashes.size(), ms])
	for cat in ["gen_ok", "size", "layer_len", "rle_roundtrip", "whitelist", "poi", "spawn", "reach", "ratios", "codec_verify", "retry_range", "determinism"]:
		_check("map_cat_" + cat, not failures.has(cat), str(failures.get(cat, [])))
	_check("map_unique_hashes_ge18", hashes.size() >= 18, str(hashes.size()))

func _test_unreachable() -> void:
	var spec := _demo_spec()
	spec["seed"] = 1
	spec["regions"][0]["size"] = {"width": 32, "depth": 32} # 候选区 24x24，POI 距离 64 必然无解
	var config := _map_test_config().duplicate(true)
	config["poi_min_manhattan_distance"] = 64
	var t0 := Time.get_ticks_msec()
	var r := MapGenerator.generate(spec, config)
	var ms := Time.get_ticks_msec() - t0
	_check("unreachable_code", not r.ok and str(r.code) == "E_MAP_UNREACHABLE", str(r.code) + " " + str(r.message))
	_check("unreachable_attempts_8", int(r.attempts) == 8, str(r.attempts))
	print("MAP_UNREACHABLE_PROBE duration_ms=%d" % ms)

func _test_projector() -> void:
	var config := _map_test_config()
	var spec1 := _demo_spec()
	spec1["seed"] = 1
	var r1 := MapGenerator.generate(spec1, config)
	if not r1.ok:
		_check("projector_first_projection", false, "seed=1 生成失败")
		return
	var m1: GeneratedMap = r1.data
	var lib := PrototypeMeshLibrary.build()
	var gg := GridMap.new()
	gg.cell_size = Vector3(1, 0.5, 1)
	gg.mesh_library = lib
	var og := GridMap.new()
	og.cell_size = Vector3(1, 0.5, 1)
	og.mesh_library = lib
	var pr := Node3D.new()
	root.add_child(gg)
	root.add_child(og)
	root.add_child(pr)
	var p1 := MapProjector.project(m1, gg, og, pr, lib)
	_check("projector_first_projection", p1.ok and int(p1.ground_cells) == 4096 and int(p1.obstacle_cells) > 0 and int(p1.poi_count) == m1.poi_tiles.size(), str(p1))
	_check("projector_ground_used_cells", gg.get_used_cells().size() == 4096)
	var spec2 := _demo_spec()
	spec2["seed"] = 2
	var r2 := MapGenerator.generate(spec2, config)
	var m2: GeneratedMap = r2.data
	var p2 := MapProjector.project(m2, gg, og, pr, lib)
	var expect_obs := 0
	for i in m2.obstacle.size():
		if m2.obstacle[i] != "none":
			expect_obs += 1
	_check("projector_second_no_stale", p2.ok and gg.get_used_cells().size() == 4096 and pr.get_children().size() == m2.poi_tiles.size())
	_check("projector_obstacle_match", og.get_used_cells().size() == expect_obs)
	root.remove_child(gg)
	root.remove_child(og)
	root.remove_child(pr)
	gg.free()
	og.free()
	pr.free()

func _test_main_scene_map() -> void:
	var ps: PackedScene = load("res://scenes/main/main.tscn")
	if ps == null:
		_check("main_scene_ground_grid_4096", false, "主场景不可加载")
		_check("main_scene_poi_markers", false, "主场景不可加载")
		_check("main_scene_map_hash_visible", false, "主场景不可加载")
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	var gg: GridMap = inst.get_node("World/GroundGrid")
	var pr = inst.get_node("World/PoiRoot")
	var d: Dictionary = inst.get_debug_info()
	_check("main_scene_ground_grid_4096", gg.get_used_cells().size() == 4096)
	_check("main_scene_poi_markers", pr.get_children().size() == 3)
	_check("main_scene_map_hash_visible", str(d.get("map_hash", "")).begins_with("sha256:"))
	root.remove_child(inst)
	inst.free()

# —— WP-03-R1 新增 ——

func _test_biome_profiles() -> void:
	var config := _map_test_config()
	var base := _demo_spec()
	var info := {}
	for b in ["forest", "desert", "mountain"]:
		var s := base.duplicate(true)
		s["regions"][0]["biome"] = b
		s["seed"] = 11
		var r := MapGenerator.generate(s, config)
		if not r.ok:
			_check("biome_%s_generates" % b, false, str(r.code) + " " + str(r.message))
			continue
		var m: GeneratedMap = r.data
		var c := {"tree": 0, "sand": 0, "rock": 0, "stone": 0, "hash": m.map_hash}
		for i in m.obstacle.size():
			if m.obstacle[i] == "tree":
				c["tree"] += 1
			elif m.obstacle[i] == "rock":
				c["rock"] += 1
		for i in m.ground.size():
			if m.ground[i] == "sand":
				c["sand"] += 1
			elif m.ground[i] == "stone":
				c["stone"] += 1
		info[b] = c
		_check("biome_%s_generates" % b, true)
	if info.size() == 3:
		var f: Dictionary = info["forest"]
		var de: Dictionary = info["desert"]
		var mo: Dictionary = info["mountain"]
		_check("biome_forest_differs_desert_layers",
			str(f["hash"]) != str(de["hash"]) and (int(f["tree"]) != int(de["tree"]) or int(f["sand"]) != int(de["sand"])),
			"tree %d/%d sand %d/%d" % [f["tree"], de["tree"], f["sand"], de["sand"]])
		_check("biome_forest_more_trees_than_desert", int(f["tree"]) >= int(de["tree"]) + 100,
			"forest=%d desert=%d" % [f["tree"], de["tree"]])
		_check("biome_desert_more_sand_than_forest", int(de["sand"]) >= int(f["sand"]) + 400,
			"desert=%d forest=%d" % [de["sand"], f["sand"]])
		_check("biome_mountain_more_rock_or_stone_than_forest",
			int(mo["rock"]) + int(mo["stone"]) >= int(f["rock"]) + int(f["stone"]) + 400,
			"mountain=%d forest=%d" % [int(mo["rock"]) + int(mo["stone"]), int(f["rock"]) + int(f["stone"])])

func _strict_base_snapshot() -> Dictionary:
	var g := PackedStringArray()
	var o := PackedStringArray()
	var dc := PackedStringArray()
	var el := PackedInt32Array()
	for i in 1024:
		g.append("grass")
		o.append("none")
		dc.append("none")
		el.append(0)
	return MapSnapshotCodec.build_snapshot("w_test", "r_test", 32, 32, g, o, dc, el,
		{"poi_a": Vector3i(1, 0, 2), "poi_b": Vector3i(5, 0, 7), "poi_c": Vector3i(9, 0, 11)}, Vector3i(1, 0, 3))

func _rehashed(mut: Dictionary) -> Dictionary:
	mut["hash"] = MapSnapshotCodec.compute_hash(mut)
	return mut

func _test_snapshot_strict() -> void:
	var base := _strict_base_snapshot()
	_check("snapshot_strict_base_ok", MapSnapshotCodec.verify(base).ok, str(MapSnapshotCodec.verify(base).message))
	var m1: Dictionary = base.duplicate(true)
	m1["schema_version"] = "9.9"
	_check("snapshot_bad_schema_version", not MapSnapshotCodec.verify(_rehashed(m1)).ok)
	var m2: Dictionary = base.duplicate(true)
	m2["generator_version"] = "mapgen-0.0.9"
	_check("snapshot_bad_generator_version", not MapSnapshotCodec.verify(_rehashed(m2)).ok)
	var m3: Dictionary = base.duplicate(true)
	m3["tile_encoding"] = "raw"
	_check("snapshot_bad_tile_encoding", not MapSnapshotCodec.verify(_rehashed(m3)).ok)
	var m4: Dictionary = base.duplicate(true)
	m4["width"] = "64"
	_check("snapshot_width_string", not MapSnapshotCodec.verify(_rehashed(m4)).ok)
	var m5: Dictionary = base.duplicate(true)
	m5["layers"] = "bad"
	_check("snapshot_layers_string_no_runtime_error", not MapSnapshotCodec.verify(_rehashed(m5)).ok)
	var m6: Dictionary = base.duplicate(true)
	m6["layers"]["ground"] = [[123, 1024]]
	_check("snapshot_ground_value_number", not MapSnapshotCodec.verify(_rehashed(m6)).ok)
	var m7: Dictionary = base.duplicate(true)
	m7["layers"]["elevation"] = [["0", 1024]]
	_check("snapshot_elevation_value_string", not MapSnapshotCodec.verify(_rehashed(m7)).ok)
	var m8: Dictionary = base.duplicate(true)
	m8["poi_tiles"] = {}
	_check("snapshot_empty_poi_tiles", not MapSnapshotCodec.verify(_rehashed(m8)).ok)
	var m9: Dictionary = base.duplicate(true)
	m9["poi_tiles"]["poi_a"] = {"x": "1", "z": 2, "level": 0}
	_check("snapshot_tile_wrong_type", not MapSnapshotCodec.verify(_rehashed(m9)).ok)
	var m10: Dictionary = base.duplicate(true)
	m10["poi_tiles"]["poi_a"] = {"x": 999, "z": 2, "level": 0}
	_check("snapshot_tile_out_of_bounds", not MapSnapshotCodec.verify(_rehashed(m10)).ok)
	var m11: Dictionary = base.duplicate(true)
	m11["poi_tiles"]["poi_a"] = {"x": 1, "z": 2, "level": 0, "y": 0}
	_check("snapshot_tile_extra_key", not MapSnapshotCodec.verify(_rehashed(m11)).ok)
	var m12: Dictionary = base.duplicate(true)
	m12["extra_top"] = 1
	_check("snapshot_extra_top_key", not MapSnapshotCodec.verify(_rehashed(m12)).ok)
	var m13: Dictionary = base.duplicate(true)
	m13["layers"]["ground"] = [["grass", 999999999]]
	_check("snapshot_huge_rle_count_rejected_before_expand", not MapSnapshotCodec.verify(_rehashed(m13)).ok)
	var m14: Dictionary = base.duplicate(true)
	m14["hash"] = "sha256:" + str(base["hash"]).substr(7).to_upper()
	_check("snapshot_uppercase_hash_rejected", not MapSnapshotCodec.verify(m14).ok)
	var m15: Dictionary = base.duplicate(true)
	m15["poi_tiles"]["poi_a"] = {"x": 1, "z": 2, "level": 1}
	_check("snapshot_tile_nonzero_level_rejected", not MapSnapshotCodec.verify(_rehashed(m15)).ok)

func _test_r1_scene() -> void:
	var ps: PackedScene = load("res://scenes/main/main.tscn")
	if ps == null:
		for n in ["reset_success_first", "reset_failure_clears", "reset_failure_shows_error",
				"reset_success_again", "reset_main_error_cleared",
				"poi_uses_display_name_and_readable_settings", "hud_has_contrast"]:
			_check(n, false, "主场景不可加载")
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	var ctl = inst.get_node("World/MapController")
	var spec := _demo_spec()
	var cfg := _map_test_config()
	var r1: Dictionary = ctl.build(spec, cfg)
	_check("reset_success_first", r1.ok and ctl.has_map())
	var bad := spec.duplicate(true)
	bad["starting_region_id"] = "nope_region"
	var r2: Dictionary = ctl.build(bad, cfg)
	_check("reset_failure_clears",
		not r2.ok and not ctl.has_map()
		and inst.get_node("World/GroundGrid").get_used_cells().size() == 0
		and inst.get_node("World/PoiRoot").get_children().size() == 0)
	var dbg: Dictionary = ctl.get_map_debug()
	_check("reset_failure_shows_error", str(dbg.get("map_error", "")).find("E_SCHEMA_INVALID") != -1, str(dbg.get("map_error")))
	var r3: Dictionary = ctl.build(spec, cfg)
	_check("reset_success_again",
		r3.ok and ctl.has_map() and inst.get_node("World/GroundGrid").get_used_cells().size() == 4096)
	inst.apply_error("E_MAP_UNREACHABLE", "测试：错误状态")
	inst.apply_world(spec)
	var d2: Dictionary = inst.get_debug_info()
	_check("reset_main_error_cleared", str(d2.get("error", "")).find("-: -") == 0, str(d2.get("error")))
	# POI 显示名与可读性
	var names := {"post_house": "风铃驿站", "tide_market": "潮汐市集", "old_lighthouse": "旧灯塔"}
	var poi_ok := inst.get_node("World/PoiRoot").get_children().size() == 3
	for c in inst.get_node("World/PoiRoot").get_children():
		var pid := str(c.get_meta("poi_id", ""))
		if not names.has(pid):
			poi_ok = false
			continue
		var lbl: Label3D = c.get_node_or_null("Label3D")
		if lbl == null or lbl.text != names[pid]:
			poi_ok = false
		elif not lbl.fixed_size or not lbl.no_depth_test:
			poi_ok = false
			poi_ok = false
		elif lbl.font_size < 18 or lbl.font_size > 24 or lbl.outline_size < 3 or lbl.outline_size > 6:
			poi_ok = false
	_check("poi_uses_display_name_and_readable_settings", poi_ok)
	var tl: Label = inst.get_node("Ui/Hud/TitleLabel")
	_check("hud_has_contrast", tl.has_theme_constant_override("outline_size") and tl.get_theme_constant("outline_size") >= 4)
	root.remove_child(inst)
	inst.free()

# —— WP-03-R2 新增 ——

func _test_rle_decode_type_defense() -> void:
	var good := MapSnapshotCodec.rle_encode_strings(PackedStringArray(["a", "a", "b"]))
	_check("rle_decode_string_rle_rejected", not MapSnapshotCodec.rle_decode("bad", 3).ok)
	_check("rle_decode_len_string_rejected", not MapSnapshotCodec.rle_decode(good, "3").ok)
	_check("rle_decode_len_float_rejected", not MapSnapshotCodec.rle_decode(good, 3.5).ok)
	_check("rle_decode_len_bool_rejected", not MapSnapshotCodec.rle_decode(good, true).ok)
	_check("rle_decode_len_zero_rejected", not MapSnapshotCodec.rle_decode(good, 0).ok)
	_check("rle_decode_len_negative_rejected", not MapSnapshotCodec.rle_decode(good, -3).ok)
	var rt := MapSnapshotCodec.rle_decode(good, 3)
	_check("rle_decode_roundtrip_kept", rt.ok and rt.values == ["a", "a", "b"])

func _test_biome_nine() -> void:
	var config := _map_test_config()
	var base := _demo_spec()
	var hashes := {}
	var all_ok := true
	for b in ["plains", "forest", "mountain", "desert", "snow", "swamp", "coast", "urban", "ruins"]:
		var s := base.duplicate(true)
		s["regions"][0]["biome"] = b
		s["seed"] = 11
		var r := MapGenerator.generate(s, config)
		if r.ok:
			hashes[r.data.map_hash] = true
		else:
			all_ok = false
			print("BIOME_NINE seed=11 biome=%s FAILED %s" % [b, str(r.code)])
	_check("biome_all_nine_generate", all_ok)
	_check("biome_all_nine_unique_hashes", hashes.size() == 9, str(hashes.size()))

# —— WP-04 新增：玩家纵切单元测试 ——

func _test_player_scene() -> void:
	var ps: PackedScene = load("res://scenes/actors/player.tscn")
	if ps == null:
		for n in ["player_scene_loadable", "player_collision_layers", "player_capsule_shape",
				"player_motion_params", "player_interaction_area", "player_ground_probe", "player_visual_billboard"]:
			_check(n, false, "场景不可加载")
		return
	_check("player_scene_loadable", true)
	var inst = ps.instantiate()
	var body: CharacterBody3D = inst
	_check("player_collision_layers", body.collision_layer == 2 and body.collision_mask == 1)
	var cs: CollisionShape3D = inst.get_node("CollisionShape3D")
	var cap: CapsuleShape3D = cs.shape
	_check("player_capsule_shape",
		absf(cap.radius - 0.32) < 0.001 and absf(cap.height - 1.6) < 0.001 and absf(cs.position.y - 0.8) < 0.001)
	_check("player_motion_params",
		body.motion_mode == CharacterBody3D.MOTION_MODE_GROUNDED
		and absf(body.floor_snap_length - 0.25) < 0.001
		and absf(body.floor_max_angle - deg_to_rad(45.0)) < 0.001)
	var area: Area3D = inst.get_node("InteractionArea")
	var sph: SphereShape3D = inst.get_node("InteractionArea/InteractionShape").shape
	_check("player_interaction_area",
		area.collision_layer == 0 and area.collision_mask == 8 and area.monitoring
		and absf(sph.radius - 1.75) < 0.001)
	var probe: RayCast3D = inst.get_node("GroundProbe")
	_check("player_ground_probe",
		probe.collision_mask == 1 and probe.target_position.y <= -0.5 and probe.target_position.y >= -0.8)
	var sprite: AnimatedSprite3D = inst.get_node("VisualRoot/AnimatedSprite3D")
	_check("player_visual_billboard",
		sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED and absf(sprite.position.y - 0.85) < 0.001)
	inst.free()

func _test_selector() -> void:
	var fwd := Vector3(0, 0, -1)
	var near := {"target_id": "b_near", "display_name": "近", "position": Vector3(0.5, 0, 0.5)}
	var far := {"target_id": "a_far", "display_name": "远", "position": Vector3(1.5, 0, 0)}
	var sel: Dictionary = InteractionTargetSelector.select([far, near], Vector3.ZERO, fwd)
	_check("selector_distance_priority", str(sel.get("target_id")) == "b_near")
	var front := {"target_id": "z_front", "display_name": "前", "position": Vector3(0, 0, -1.0)}
	var back := {"target_id": "a_back", "display_name": "后", "position": Vector3(0, 0, 1.0)}
	var sel2: Dictionary = InteractionTargetSelector.select([back, front], Vector3.ZERO, fwd)
	_check("selector_angle_priority", str(sel2.get("target_id")) == "z_front")
	var c1 := {"target_id": "b", "display_name": "", "position": Vector3(1, 0, 0)}
	var c2 := {"target_id": "a", "display_name": "", "position": Vector3(1, 0, 0)}
	var sel3: Dictionary = InteractionTargetSelector.select([c1, c2], Vector3.ZERO, fwd)
	_check("selector_id_tiebreak", str(sel3.get("target_id")) == "a")
	var toofar := {"target_id": "out", "display_name": "", "position": Vector3(2.0, 0, 0)}
	_check("selector_radius_exclusion", InteractionTargetSelector.select([toofar], Vector3.ZERO, fwd).is_empty())
	var same := {"target_id": "same", "display_name": "", "position": Vector3(0, 0, 0)}
	var sel5: Dictionary = InteractionTargetSelector.select([same], Vector3.ZERO, fwd)
	_check("selector_coincident_angle_zero", str(sel5.get("target_id")) == "same")

func _test_navigator_unit() -> void:
	var config := _map_test_config()
	var spec := _demo_spec()
	spec["seed"] = 3
	var r := MapGenerator.generate(spec, config)
	if not r.ok:
		for n in ["navigator_paths_to_pois", "navigator_deterministic", "navigator_unwalkable_empty",
				"navigator_max_nodes_empty", "navigator_out_of_bounds_empty"]:
			_check(n, false, "地图生成失败")
		return
	var m: GeneratedMap = r.data
	var pois: Dictionary = m.poi_tiles
	var spawn: Vector3i = m.spawn_tile
	var all_paths := true
	for pid in pois:
		if MapNavigator.find_path(m, spawn, pois[pid], 256).is_empty():
			all_paths = false
	_check("navigator_paths_to_pois", all_paths)
	var pid0 = pois.keys()[0]
	var p1: Array = MapNavigator.find_path(m, spawn, pois[pid0], 256)
	var p2: Array = MapNavigator.find_path(m, spawn, pois[pid0], 256)
	_check("navigator_deterministic", p1 == p2 and not p1.is_empty())
	var blocked := Vector3i(-1, 0, -1)
	for z in m.depth:
		for x in m.width:
			if m.obstacle[z * m.width + x] != "none":
				blocked = Vector3i(x, 0, z)
				break
		if blocked.x >= 0:
			break
	_check("navigator_unwalkable_empty", MapNavigator.find_path(m, spawn, blocked, 256).is_empty())
	_check("navigator_max_nodes_empty", MapNavigator.find_path(m, spawn, pois[pid0], 1).is_empty())
	_check("navigator_out_of_bounds_empty", MapNavigator.find_path(m, spawn, Vector3i(999, 0, 999), 256).is_empty())

func _test_boundary() -> void:
	var root := Node3D.new()
	MapBoundaryBuilder.build(root, 32, 32)
	_check("boundary_count_names",
		root.get_child_count() == 4 and root.get_node("West") != null and root.get_node("East") != null
		and root.get_node("North") != null and root.get_node("South") != null)
	var t := 0.3
	var h := 3.0
	var west: StaticBody3D = root.get_node("West")
	var wshape: BoxShape3D = west.get_node("CollisionShape3D").shape
	_check("boundary_west_geometry",
		absf(west.position.x - (-t * 0.5)) < 0.001 and absf(west.position.y - h * 0.5) < 0.001
		and absf(wshape.size.x - t) < 0.001 and absf(wshape.size.z - (32.0 + 2.0 * t)) < 0.001)
	var north: StaticBody3D = root.get_node("North")
	var nshape: BoxShape3D = north.get_node("CollisionShape3D").shape
	_check("boundary_north_geometry",
		absf(north.position.z - (-t * 0.5)) < 0.001 and absf(nshape.size.x - (32.0 + 2.0 * t)) < 0.001
		and absf(nshape.size.z - t) < 0.001)
	var layers_ok := true
	for c in root.get_children():
		if not (c is StaticBody3D) or c.collision_layer != 1:
			layers_ok = false
	_check("boundary_layers", layers_ok)
	MapBoundaryBuilder.clear(root)
	_check("boundary_clear", root.get_child_count() == 0)
	root.free()

func _test_wp04_scene() -> void:
	var ps: PackedScene = load("res://scenes/main/main.tscn")
	if ps == null:
		for n in ["interface_poi_tiles_copy", "interface_rect_and_walkable", "interface_find_path",
				"poi_area3d_structure", "poi_label_params", "hud_control_hint_text", "hud_prompt_hidden",
				"boundary_built_four", "player_spawned", "pause_state_menu", "resume_state",
				"error_blocks_pause", "error_cleanup_no_player", "camera_config_defaults", "camera_zoom_clamp"]:
			_check(n, false, "主场景不可加载")
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	var ctl = inst.get_node("World/MapController")
	var pois: Dictionary = ctl.get_poi_tiles()
	var first_key = pois.keys()[0]
	var original_tile: Vector3i = pois[first_key]
	pois[first_key] = Vector3i(999, 0, 999)
	_check("interface_poi_tiles_copy",
		ctl.get_poi_tiles()[first_key] == original_tile and ctl.get_poi_tiles().size() == 3)
	_check("interface_rect_and_walkable",
		ctl.get_map_rect() == Rect2i(0, 0, 64, 64)
		and ctl.is_walkable_tile(ctl.get_spawn_tile())
		and not ctl.is_walkable_tile(Vector3i(-1, 0, 0))
		and not ctl.is_walkable_tile(Vector3i(5, 1, 5)))
	_check("interface_find_path", ctl.find_walk_path(ctl.get_spawn_tile(), ctl.get_spawn_tile()).size() >= 1)
	var poi_ok := true
	var pr = inst.get_node("World/PoiRoot")
	for c in pr.get_children():
		if not (c is Area3D):
			poi_ok = false
			continue
		if not bool(c.get_meta("interactable", false)) or str(c.get_meta("target_type", "")) != "poi":
			poi_ok = false
		if c.collision_layer != 8:
			poi_ok = false
		if c.get_node_or_null("Label3D") == null or c.get_node_or_null("MarkerMesh") == null:
			poi_ok = false
	_check("poi_area3d_structure", poi_ok)
	var lbl0: Label3D = pr.get_child(0).get_node("Label3D")
	_check("poi_label_params",
		lbl0.font_size >= 18 and lbl0.font_size <= 24 and lbl0.outline_size >= 3 and lbl0.outline_size <= 6)
	_check("hud_control_hint_text",
		inst.get_node("Ui/Hud/ControlHintLabel").text == "WASD/方向键移动 · Q/R旋转 · 滚轮缩放 · E/空格交互 · Esc暂停")
	_check("hud_prompt_hidden", not inst.get_node("Ui/Hud/InteractionPrompt").visible)
	_check("boundary_built_four", inst.get_node("World/BoundaryRoot").get_child_count() == 4)
	_check("player_spawned", inst.get_node("World/ActorRoot").get_child_count() == 1)
	var pc = inst.get_node("Ui/PauseController")
	pc.pause()
	_check("pause_state_menu", paused and inst.get_node("Ui/PauseMenu").visible)
	pc.resume()
	_check("resume_state", not paused and not inst.get_node("Ui/PauseMenu").visible)
	var cam_ctl = inst.get_node("World/CameraRig")
	var cam: Camera3D = inst.get_node("World/CameraRig/YawPivot/MainCamera")
	_check("camera_config_defaults",
		cam.projection == Camera3D.PROJECTION_ORTHOGONAL
		and absf(cam.size - 20.0) < 0.001
		and absf(cam.position.x - 12.0) < 0.001 and absf(cam.position.y - 12.0) < 0.001 and absf(cam.position.z - 12.0) < 0.001)
	cam_ctl.apply_zoom(-1000.0)
	var z1: float = cam.size
	cam_ctl.apply_zoom(1000.0)
	var z2: float = cam.size
	_check("camera_zoom_clamp", absf(z1 - 12.0) < 0.001 and absf(z2 - 30.0) < 0.001)
	inst.apply_error("E_MAP_UNREACHABLE", "测试：错误状态")
	pc.pause()
	_check("error_blocks_pause", not paused)
	pc.resume()
	_check("error_cleanup_no_player",
		inst.get_node("World/ActorRoot").get_child_count() == 0
		and inst.get_node("World/BoundaryRoot").get_child_count() == 0)
	root.remove_child(inst)
	inst.free()

# —— WP-04-R1 新增：真实 Esc 暂停、HUD 布局、配置防御 ——
# SceneTree 脚本中没有 get_tree()：paused/menu 直接用 self/节点属性。

func _test_wp04_r1_pause_and_layout() -> void:
	var ps: PackedScene = load("res://scenes/main/main.tscn")
	if ps == null:
		for n in ["pause_mode_always", "real_esc_pauses", "pause_can_process_when_paused",
				"real_esc_second_resumes", "hud_layout_disjoint", "hud_layout_in_view"]:
			_check(n, false, "主场景不可加载")
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	var pc: Node = inst.get_node("Ui/PauseController")
	var menu: Control = inst.get_node("Ui/PauseMenu")
	_check("pause_mode_always",
		pc.process_mode == Node.PROCESS_MODE_ALWAYS and menu.process_mode == Node.PROCESS_MODE_ALWAYS,
		"pc=%d menu=%d always=%d" % [pc.process_mode, menu.process_mode, Node.PROCESS_MODE_ALWAYS])
	var ev := InputEventAction.new()
	ev.action = "cancel"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	_check("real_esc_pauses", paused and menu.visible,
		"paused=%s menu=%s" % [str(paused), str(menu.visible)])
	_check("pause_can_process_when_paused", pc.can_process() and menu.can_process())
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	_check("real_esc_second_resumes", not paused and not menu.visible)
	paused = false # 测试退出前强制恢复，不污染后续用例

	var title: Control = inst.get_node("Ui/Hud/TitleLabel")
	var hint: Control = inst.get_node("Ui/Hud/ControlHintLabel")
	var prompt: Control = inst.get_node("Ui/Hud/InteractionPrompt")
	var toast: Control = inst.get_node("Ui/Hud/ToastLabel")
	var prompt_prev: bool = prompt.visible
	var toast_prev: bool = toast.visible
	prompt.visible = true
	toast.visible = true
	await process_frame # 完成至少一帧布局
	var rects: Array = [title.get_global_rect(), hint.get_global_rect(), prompt.get_global_rect(), toast.get_global_rect()]
	var disjoint := true
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				disjoint = false
	_check("hud_layout_disjoint", disjoint, str(rects))
	var vp := Rect2(0, 0, 1280, 720)
	var in_view := true
	for r in rects:
		if not vp.encloses(r):
			in_view = false
	_check("hud_layout_in_view", in_view, str(rects))
	prompt.visible = prompt_prev
	toast.visible = toast_prev
	root.remove_child(inst)
	inst.free()

func _test_config_defense() -> void:
	var ctl := IsometricCameraController.new()
	ctl.configure({"near": 0.0, "far": 1.0, "zoom_min": -5.0, "zoom_max": 1.0, "zoom_step": 0.0,
		"offset": {"x": INF, "y": 12, "z": 12}, "follow_smoothing_seconds": -1.0,
		"rotation_tween_seconds": -2.0, "rotation_step_degrees": -90.0})
	_check("camera_config_defense",
		ctl.near > 0.0 and ctl.far > ctl.near
		and ctl.zoom_min > 0.0 and ctl.zoom_max >= ctl.zoom_min and ctl.zoom_step > 0.0
		and ctl.offset.x == 12.0 and is_finite(ctl.offset.x) and is_finite(ctl.offset.y) and is_finite(ctl.offset.z)
		and ctl.follow_smoothing >= 0.0 and ctl.rotation_tween_seconds >= 0.0 and ctl.rotation_step_deg > 0.0,
		"near=%f far=%f zmin=%f zmax=%f step=%f off=%s" % [ctl.near, ctl.far, ctl.zoom_min, ctl.zoom_max, ctl.zoom_step, ctl.offset])
	ctl.free()

	var player_scene: PackedScene = load("res://scenes/actors/player.tscn")
	if player_scene == null:
		_check("player_config_defense", false, "玩家场景不可加载")
		_check("selection_ring_present", false, "玩家场景不可加载")
		_check("name_label_font_range", false, "玩家场景不可加载")
		return
	var pl = player_scene.instantiate()
	root.add_child(pl)
	pl.configure(null, Vector3i(1, 0, 1), Vector2i(20, 20),
		{"player_speed_m_per_second": INF, "gravity_m_per_second_squared": -5.0})
	_check("player_config_defense", absf(pl.move_speed - 4.5) < 0.001 and absf(pl.gravity - 20.0) < 0.001,
		"speed=%f gravity=%f" % [pl.move_speed, pl.gravity])
	var ring: MeshInstance3D = pl.get_node_or_null("VisualRoot/SelectionRing")
	var lbl: Label3D = pl.get_node("VisualRoot/NameLabel")
	_check("selection_ring_present", ring != null and ring.mesh != null)
	_check("name_label_font_range", lbl.font_size >= 18 and lbl.font_size <= 22, str(lbl.font_size))
	root.remove_child(pl)
	pl.free()
