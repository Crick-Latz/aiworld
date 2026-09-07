extends SceneTree
## P4.3 Live Smoke：3 条真实 Thread × TITLE/SUMMARY（glm-4-flash）
## 人工检查四问：加事实？过度动机？belief 写成 truth？比 template 可读？
var _f := false
var _s := false
func _initialize() -> void: pass
func _process(_d: float) -> bool:
	if not _s: _s = true; _run()
	return _f

func _run() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var spot = mq.get_poi_tile("post_house")
	var configs: Array = []
	for ac in scenario.get("actors", []):
		var cfg = ac.duplicate(); cfg["spawn"] = spot; configs.append(cfg)
	var sim := IslandSimulation.new(mq, 30014, configs)
	for i in 1500: sim.step()
	var te := ThreadEngine.new()
	te.process(sim)
	var config: Dictionary = LlmNarrativeRenderer.load_config()
	if config.is_empty():
		print("SMOKE_NO_CONFIG")
		_f = true
		quit(0)
		return
	var ev_lookup := ThreadSummaryRenderer.build_event_lookup(sim)
	var wanted := ["PROMISE_THREAD", "EPISTEMIC_THREAD", "INSTITUTION_CONFLICT"]
	var picked := {}
	var fallback_pool: Array = []
	for th in te.engine.threads:
		var tt := str(th.get("thread_type", ""))
		if (th.get("source_event_ids", []) as Array).size() >= 2:
			if wanted.has(tt) and not picked.has(tt):
				picked[tt] = th
			elif fallback_pool.size() < 3:
				fallback_pool.append(th)
	for th2 in fallback_pool:
		if picked.size() >= 3:
			break
		picked[str(th2.get("thread_type", "")) + "#" + str(th2.get("thread_id", ""))] = th2
	var render_list: Array = picked.values()
	for th in render_list:
		var ir: Dictionary = LlmThreadRenderer.build_render_ir(sim, th)
		print("=== [%s] %s status=%s claims=%d ===" % [str(th.get("thread_type", "")), str(th.get("thread_id", "")), str(th.get("status", "")), (ir.get("allowed_claims", []) as Array).size()])
		for depth in ["TITLE", "SUMMARY"]:
			var out: Dictionary = await LlmThreadRenderer.render(config, ir, depth, ev_lookup)
			print("[%s|%s|%s] %s" % [str(th.get("thread_type", "")), depth, str(out.get("renderer", "")), str(out.get("text", ""))])
			if str(out.get("renderer", "")) == "template":
				print("  fallback_reason=%s" % str(out.get("fallback_reason", "")))
			for sn in out.get("sentences", []):
				print("  DEBUG %s <- claims=%s -> events=%s" % [str(sn.get("text", "")).substr(0, 30), str(sn.get("claim_ids", [])), str(sn.get("source_event_ids", []))])
		var tmpl := ThreadSummaryRenderer.render_summary(te.build_thread_ir(sim, th), ev_lookup)
		print("[TEMPLATE] %s" % tmpl)
	_f = true
	quit(0)
