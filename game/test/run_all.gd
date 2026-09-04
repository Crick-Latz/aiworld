extends SceneTree
## WP-02 离线测试（headless）。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/run_all.gd
## 退出码：全部通过 = 0；任一失败 = 1。全程零网络、零存档。

var passed := 0
var failed := 0
var _tests_done := false

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
# 因此测试推迟到首个 _process 帧执行，随后返回 true 请求退出。
func _initialize() -> void:
	print("WP-02 test harness: tests deferred to first frame")

func _process(_delta: float) -> bool:
	if not _tests_done:
		_tests_done = true
		_run_all_tests()
	return true

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
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
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
			and inst.get_node_or_null("World/PreviewGround") != null \
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
