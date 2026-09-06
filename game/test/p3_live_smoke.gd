extends SceneTree
## P3a-3 Live 冒烟脚本（用户有 API 凭据时一键跑通全链）：
##   真实 600-tick 模拟 → IR → claim package → LLM API → 解析 → Validator → 输出对比
## 运行前提：game/config/ai.local.json 或 AIWORD_LLM_BASE_URL + AIWORD_LLM_API_KEY
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/p3_live_smoke.gd

var _f := false
func _initialize() -> void: pass
var _s := false
func _process(_d: float) -> bool:
	if not _s:
		_s = true
		_run()
	return _f

func _run() -> void:
	var cfg: Dictionary = LlmNarrativeRenderer.load_config()
	if cfg.is_empty():
		print("SMOKE_FAIL no_config")
		print("请创建 game/config/ai.local.json 或设置 AIWORD_LLM_BASE_URL + AIWORD_LLM_API_KEY")
		quit(1)
		return
	print("SMOKE_CONFIG model=%s base=%s" % [str(cfg.get("model", "?")), str(cfg.get("base_url", "?")).substr(0, 30)])

	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var spot = mq.get_poi_tile("post_house")
	var configs: Array = []
	for ac in scenario.get("actors", []):
		var cfg2 = ac.duplicate()
		cfg2["spawn"] = spot
		configs.append(cfg2)
	var sim := IslandSimulation.new(mq, 43001, configs)
	for i in 600:
		sim.step()
	print("SMOKE_SIM tick=%d events=%d" % [sim.tick, sim.events.size()])

	# IR 构建
	var ir: Dictionary = NarrativeIR.build_ir(sim, "OBJECTIVE", "", 6)
	if not bool(ir.get("ok", false)):
		print("SMOKE_FAIL ir_error %s" % str(ir.get("code", "")))
		quit(1)
		return
	print("SMOKE_IR beats=%d claims=%d hash=%s" % [
		(ir.get("selected_beats", []) as Array).size(),
		(ir.get("claims", []) as Array).size(),
		str(ir.get("ir_hash", "")).substr(0, 16)])

	# Template 对照组（确定性基线）
	var tmpl: Dictionary = TemplateNarrativeRenderer.render(ir, "neutral_chronicle", "zh", 3)
	print("SMOKE_TEMPLATE %s" % str(tmpl.get("text", "")).replace("\n", " | ").substr(0, 200))

	# LLM 调用（全链）
	var provider: Dictionary = LlmNarrativeRenderer.make_provider(cfg)
	var llm_out: Dictionary = await NarrativeRenderer.render(provider, ir, "neutral_chronicle", "zh", 3)
	# Debug: 直接看 claim package + 原始响应
	var pkg_dbg: Array = LlmNarrativeRenderer._build_claim_package(ir, 3)
	print("SMOKE_PKG %s" % str(pkg_dbg).substr(0, 400))
	var raw_dbg: String = await LlmNarrativeRenderer._call_api(cfg, pkg_dbg)
	print("SMOKE_RAW %s" % raw_dbg.substr(0, 500))
	if llm_out.has("fallback_reason"):
		print("SMOKE_FALLBACK reason=%s（LLM 失败，template 兜底）" % str(llm_out.get("fallback_reason", "")))
	else:
		print("SMOKE_LLM_OK renderer=%s" % str(llm_out.get("renderer", "")))
		print("SMOKE_LLM_TEXT %s" % str(llm_out.get("text", "")).replace("\n", " | ").substr(0, 300))
		var llm_sents: Array = llm_out.get("sentences", [])
		for sn in llm_sents:
			print("SMOKE_SENTENCE %s claims=%s" % [str(sn.get("text", "")).substr(0, 80), str(sn.get("claim_ids", []))])

	# Fidelity 检查：LLM 的 claims ⊆ Template 的 claims（同 IR 同 beat 选择）
	var t_events: Array = tmpl.get("source_event_ids", [])
	var l_events: Array = llm_out.get("source_event_ids", [])
	var overlap := 0
	for e in l_events:
		if t_events.has(e):
			overlap += 1
	print("SMOKE_FIDELITY llm_events=%d template_events=%d overlap=%d" % [l_events.size(), t_events.size(), overlap])
	print("SMOKE_DONE")
	quit(0)
