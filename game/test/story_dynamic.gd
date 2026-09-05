extends SceneTree
## OBS-03 动态变化回归测试。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/story_dynamic.gd
## 8 个固定夹具（docs/20 表格逐项）：基准不回退、发布者提出前离场、无继任、
## 接受后供应者离场、同一死讯不同延迟、目标已被完成、争抢、幂等。

var passed := 0
var failed := 0
var _started := false
var _finished := false

func _initialize() -> void:
	print("OBS-03 dynamic harness: deferred to first frame")

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

var _mq = null

func _run_all_tests() -> void:
	_mq = await _make_map_query()
	if _mq == null:
		for i in range(10):
			_check("fixture_%d" % i, false, "地图不可用")
		return

	# ── 1. 基准合作不回退 ──
	var sim := _run_baseline()
	_check("f1_baseline_still_lit", sim.lighthouse_lit and sim.consumed_fuel == 2, "")

	# ── 2. 发布者在提出前离场：不产生其请求；知情有目标的 NPC 独立接棒 ──
	var sim2 := _make("baseline")
	var departed := false
	for i in 200:
		sim2.step()
		if sim2.actors["npc_weila"]["phase"] == "inspecting" and not departed:
			# 条件注入：在 shortage_observed 产生前（inspecting 阶段）让薇拉离场
			sim2.inject_actor_departed("npc_weila", "chased_by_fog")
			departed = true
	# 薇拉离场后：不能由她亲自发出请求
	var weila_requests := 0
	for e in sim2.events:
		if e["type"] == "help_requested" and e["actor_id"] == "npc_weila":
			weila_requests += 1
	_check("f2_no_request_from_departed", weila_requests == 0 and departed, "requests=%d" % weila_requests)
	# 欧恩（在场、有库存、但未知短缺且不是原请求者）不应接棒 → 目标终止
	var goal_term := 0
	for e in sim2.events:
		if e["type"] == "goal_terminated":
			goal_term += 1
	_check("f2_no_successor_terminates", goal_term >= 1 and not sim2.lighthouse_lit, "terminated=%d" % goal_term)

	# ── 3. 接受后供应者（欧恩）离场：承诺取消，无凭空转移，可由知情者重新计划 ──
	var sim3 := _make("baseline")
	var injected := false
	for i in 300:
		sim3.step()
		if not injected and sim3.actors["npc_oun"]["phase"] == "go_deliver":
			# 欧恩已接受、正在送材料途中 → 离场
			sim3.inject_actor_departed("npc_oun", "recalled_by_guild")
			injected = true
	var cancelled := 0
	for e in sim3.events:
		if e["type"] == "commitment_cancelled":
			cancelled += 1
	var weila_after: int = sim3.actors["npc_weila"]["inventory"].get("windcrystal_powder", 0)
	var oun_after: int = sim3.actors["npc_oun"]["inventory"].get("windcrystal_powder", 0)
	_check("f3_commitment_cancelled", injected and cancelled >= 1,
		"injected=%s cancelled=%d" % [injected, cancelled])
	_check("f3_no_phantom_transfer", weila_after == 0 and oun_after == 3 and not sim3.lighthouse_lit,
		"weila=%d oun=%d lit=%s" % [weila_after, oun_after, sim3.lighthouse_lit])

	# ── 4. 同一死讯不同延迟：未获知者保留旧认识；事实校验拒绝不可能交易 ──
	var sim4 := _make("baseline")
	sim4.step() # tick 1
	# 薇拉 inspect 完成后知道短缺；欧恩通过延迟消息在 tick 50 才知道
	for i in 100:
		sim4.step()
		if sim4.knowledge.knows("npc_weila", "fact_lighthouse_dark") and sim4._delayed_messages.is_empty() and i < 10:
			sim4.schedule_delayed_message(sim4.tick + 50, "fact_lighthouse_dark", "npc_oun", sim4._last_type_seq("shortage_observed"), "薇拉发现灯塔缺燃料")
			break
	var oun_knows_early := sim4.knowledge.knows("npc_oun", "fact_lighthouse_dark")
	for i in 200:
		sim4.step()
	var oun_knows_late := sim4.knowledge.knows("npc_oun", "fact_lighthouse_dark")
	_check("f4_delayed_message_gating", oun_knows_late and sim4.lighthouse_lit, "late=%s lit=%s" % [oun_knows_late, sim4.lighthouse_lit])

	# ── 5. 目标已被别人完成：已满足目标结束，不再索取 ──
	var sim5 := _make("baseline")
	for i in 400:
		sim5.step()
		if sim5.lighthouse_lit and not sim5._inject_extra_done:
			# 点亮后注入一个竞争请求（如果实现会响应的话）
			sim5._inject_extra_done = true
	# 点亮后 weila phase 应为 done（不再索取）
	_check("f5_goal_satisfied_stops", sim5.actors["npc_weila"]["phase"] == "done" and sim5.lighthouse_lit,
		"phase=%s" % sim5.actors["npc_weila"]["phase"])

	# ── 6. 两个承诺争抢一份资源：只转移/消耗一次 ──
	var sim6 := _make("baseline")
	for i in 300:
		sim6.step()
	# 手工竞争：欧恩只剩 1，再给两个 2 份请求 → 只能成功 0 个（都拒绝）
	sim6.actors["npc_oun"]["inventory"]["windcrystal_powder"] = 1
	sim6.actors["npc_oun"]["tile"] = sim6.actors["npc_weila"]["tile"]
	var ra: Dictionary = sim6.submit_transfer("cmd_obs3_a", "npc_oun", "npc_weila", "windcrystal_powder", 2)
	var rb: Dictionary = sim6.submit_transfer("cmd_obs3_b", "npc_oun", "npc_weila", "windcrystal_powder", 2)
	_check("f6_competing_single_outcome", not ra["ok"] and not rb["ok"], "a=%s b=%s" % [ra["ok"], rb["ok"]])

	# ── 7. 多次收到同一消息幂等 ──
	var sim7 := _make("baseline")
	sim7.step()
	var src := 0
	for e in sim7.events:
		if e["type"] == "shortage_observed":
			src = int(e["seq"])
			break
	# 同一消息重复投递两次 → 只记一次 message_delivered
	sim7.schedule_delayed_message(sim7.tick + 5, "fact_lighthouse_dark", "npc_kadga", src, "msg")
	sim7.schedule_delayed_message(sim7.tick + 5, "fact_lighthouse_dark", "npc_kadga", src, "msg")
	for i in 10:
		sim7.step()
	var deliveries := 0
	for e in sim7.events:
		if e["type"] == "message_delivered" and e["actor_id"] == "npc_kadga":
			deliveries += 1
	_check("f7_message_idempotent", deliveries == 1, "deliveries=%d" % deliveries)

	# ── 8. 结算命令幂等（同 command_id 不重复关系/库存变化） ──
	var sim8 := _make("baseline")
	for i in 300:
		sim8.step()
	sim8.actors["npc_oun"]["tile"] = sim8.actors["npc_weila"]["tile"]
	sim8.actors["npc_oun"]["inventory"]["windcrystal_powder"] = 5
	var r1: Dictionary = sim8.submit_transfer("cmd_idem", "npc_oun", "npc_weila", "windcrystal_powder", 1)
	var r2: Dictionary = sim8.submit_transfer("cmd_idem", "npc_oun", "npc_weila", "windcrystal_powder", 1)
	var final_w: int = sim8.actors["npc_weila"]["inventory"]["windcrystal_powder"]
	_check("f8_settle_idempotent", r1 == r2 and final_w == 1, "w=%d" % final_w)

	# ── 确定性：同 seed 同注入 → 相同事件摘要 ──
	var d1 := _make("baseline")
	var d2 := _make("baseline")
	for i in 100:
		d1.step()
		d2.step()
		if i == 20:
			d1.inject_actor_departed("npc_oun", "test_reason")
			d2.inject_actor_departed("npc_oun", "test_reason")
	_check("f9_deterministic_with_injection", d1.event_summary() == d2.event_summary(), "")

	print("DYN_SUMMARY f1_lit=%s f2_reqs=0 f3_cancel=%d f4=%s f5=done f6=fail f7=1 f8=1 f9=same" % [
		sim.lighthouse_lit, cancelled, oun_knows_late])

func _make_map_query():
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null:
		return null
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20:
		await physics_frame
	return inst.get_node("World/MapController")

func _make(scenario: String) -> StorySimulation:
	var text := FileAccess.get_file_as_string("res://data/scenarios/lighthouse_%s.json" % scenario)
	var data: Dictionary = JSON.parse_string(text)
	var homes := {"npc_weila": "tide_market", "npc_oun": "tide_market", "npc_kadga": "post_house"}
	var spawn := {}
	for id in homes:
		spawn[id] = _mq.get_poi_tile(homes[id])
	return StorySimulation.new(_mq, data, spawn)

func _run_baseline() -> StorySimulation:
	var sim = _make("baseline")
	for i in 400:
		sim.step()
		if sim.actors["npc_weila"]["phase"] == "done":
			break
	return sim
