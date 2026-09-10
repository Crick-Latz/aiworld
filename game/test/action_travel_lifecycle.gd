extends SceneTree
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, ok: bool, info := "") -> void:
	if ok:
		passed += 1; print("PASS " + label)
	else:
		failed += 1; print("FAIL " + label + "  " + str(info))

func _start(a: Dictionary, action: Dictionary) -> void:
	a["current_action"] = action.duplicate(true)
	a["action_ticks_left"] = int(action["duration"])
	a["action_travel_stall_ticks"] = 0

func _run() -> void:
	var scene = load("res://scenes/observer/observer_main.tscn").instantiate()
	root.add_child(scene)
	for i in 20: await physics_frame
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var mq = scene.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var configs: Array = scenario["actors"].duplicate(true)
	var start: Vector2i = mq.get_poi_tile("post_house")
	var target: Vector2i = mq.get_poi_tile("old_lighthouse")
	for cfg in configs: cfg["spawn"] = start

	var sim := IslandSimulation.new(mq, 43021, configs)
	var id: String = sim.actors.keys()[0]
	var a: Dictionary = sim.actors[id]
	sim.world["water_springs"] = [target]
	a["needs"]["thirst"] = 900
	_start(a, {"action":"drink_water", "target":target, "duration":1, "desc":"去喝水", "utility":1.0})
	var initial_thirst: int = a["needs"]["thirst"]
	var initial_distance := absi(start.x-target.x) + absi(start.y-target.y)
	sim._tick_actor(id, a, [])
	_check("travel_does_not_consume_work", a["action_ticks_left"] == 1 and a["needs"]["thirst"] == initial_thirst)
	_check("travel_makes_subjective_progress", absi(a["tile"].x-target.x) + absi(a["tile"].y-target.y) < initial_distance)
	var guard := 0
	while a.get("current_action") != null and guard < 300:
		sim.tick += 1
		sim._tick_actor(id, a, [])
		guard += 1
	_check("distant_work_only_succeeds_at_target", a["tile"] == target and a["needs"]["thirst"] == 0, "tile=%s target=%s" % [a["tile"], target])
	_check("travel_action_finishes", a.get("current_action") == null and guard < 300)

	# Immediate target retains the declared work duration.
	a["tile"] = target
	a["needs"]["thirst"] = 900
	_start(a, {"action":"drink_water", "target":target, "duration":1, "desc":"去喝水", "utility":1.0})
	sim._tick_actor(id, a, [])
	_check("immediate_target_completes", a.get("current_action") == null and a["needs"]["thirst"] == 0)

	# Fishing and shells cannot reward an actor while still travelling.
	a["tile"] = start
	a["inventory"]["food"] = 0
	_start(a, {"action":"fish", "target":target, "duration":2, "desc":"捕鱼", "utility":1.0})
	for i in 2: sim._tick_actor(id, a, [])
	_check("no_offsite_fish_reward", int(a["inventory"].get("food",0)) == 0 and a.get("current_action") != null)
	a["current_action"] = null
	a["inventory"]["shells"] = 0
	_start(a, {"action":"gather_shells", "target":target, "duration":1, "desc":"捡贝壳", "utility":1.0})
	sim._tick_actor(id, a, [])
	_check("no_offsite_shell_reward", int(a["inventory"].get("shells",0)) == 0 and a.get("current_action") != null)

	# An impossible target cancels after bounded consecutive no-progress ticks.
	var impossible := Vector2i(-50, -50)
	a["tile"] = start
	_start(a, {"action":"gather_shells", "target":impossible, "duration":1, "desc":"捡贝壳", "utility":1.0})
	var before_events := sim.events.size()
	var unreachable_ticks := 0
	while a.get("current_action") != null and unreachable_ticks < 300:
		sim.tick += 1
		sim._tick_actor(id, a, [])
		unreachable_ticks += 1
	var segment: Array = sim.events.slice(before_events)
	_check("unreachable_cancels_bounded", a.get("current_action") == null and unreachable_ticks < 300,
		"ticks=%d" % unreachable_ticks)
	_check("unreachable_has_explicit_event", segment.any(func(e): return e.get("type") == "action_target_unreachable"))
	_check("unreachable_never_rewards", int(a["inventory"].get("shells",0)) == 0)

	# Same inputs replay the travel path and result deterministically.
	var sim2 := IslandSimulation.new(mq, 43021, configs.duplicate(true))
	var id2: String = sim2.actors.keys()[0]
	var a2: Dictionary = sim2.actors[id2]
	sim2.world["water_springs"] = [target]
	a2["needs"]["thirst"] = 900
	_start(a2, {"action":"drink_water", "target":target, "duration":1, "desc":"去喝水", "utility":1.0})
	var path1: Array = []
	var replay := IslandSimulation.new(mq, 43021, configs.duplicate(true))
	var id3: String = replay.actors.keys()[0]
	var a3: Dictionary = replay.actors[id3]
	replay.world["water_springs"] = [target]
	a3["needs"]["thirst"] = 900
	_start(a3, {"action":"drink_water", "target":target, "duration":1, "desc":"去喝水", "utility":1.0})
	var path2: Array = []
	for i in 300:
		if a2.get("current_action") == null and a3.get("current_action") == null: break
		sim2.tick += 1; replay.tick += 1
		sim2._tick_actor(id2,a2,[]); replay._tick_actor(id3,a3,[])
		path1.append(a2["tile"]); path2.append(a3["tile"])
	_check("travel_replay_deterministic", path1 == path2 and a2["needs"]["thirst"] == a3["needs"]["thirst"])

	scene.queue_free()
	await process_frame
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
