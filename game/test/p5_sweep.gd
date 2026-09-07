extends SceneTree
## P5.1 — Spatial Ecology & Navigation Sweep（GPT 指令 2026-09-07）
## 问的不是"ThreadEngine 有没有胡编"，而是"主观空间后 NPC 还活得好吗，空间错误在产故事吗"。
## 输出：P5SWEEP_CONFIG / P5SEED <json>（每种子）/ P5AGG <json>（聚合）——stdout 落盘由 bash tee。
var _phase := "pilot"
var _natural := 50
var _camp := 20
var _ticks := 3000
var _seed_base := 50000
var _detCheck := true
var _started := false
var _done := false

func _initialize() -> void:
	print("P5SWEEP_CONFIG phase=%s natural=%d camp=%d ticks=%d" % [_phase, _natural, _camp, _ticks])

func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done

func _run() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var camp_spot = mq.get_poi_tile("post_house")
	var spots := [mq.get_poi_tile("post_house"), mq.get_poi_tile("tide_market"), mq.get_poi_tile("old_lighthouse")]
	var map_cells := int(mq.get_map_rect().size.x) * int(mq.get_map_rect().size.y)
	var agg := _new_agg()
	for cohort in ["natural", "camp"]:
		var count := _natural if cohort == "natural" else _camp
		if count == 0:
			continue
		for s in range(count):
			var seed := _seed_base + s
			var configs: Array = []
			for ac in scenario.get("actors", []):
				var cfg = ac.duplicate()
				cfg["spawn"] = camp_spot if cohort == "camp" else spots[configs.size() % spots.size()]
				configs.append(cfg)
			var rec := _run_one(mq, seed, configs, map_cells)
			rec["cohort"] = cohort
			rec["seed"] = seed
			print("P5SEED " + JSON.stringify(rec))
			_accumulate(agg, rec)
	agg["seeds"] = _natural + _camp
	_finalize_agg(agg)
	print("P5AGG " + JSON.stringify(agg))
	# 确定性抽查（硬门）：同 seed 双跑事件流一致
	if _detCheck:
		var configs2: Array = []
		for ac in scenario.get("actors", []):
			var cfg = ac.duplicate()
			cfg["spawn"] = camp_spot
			configs2.append(cfg)
		var a1 := IslandSimulation.new(mq, _seed_base + 7, configs2)
		var a2 := IslandSimulation.new(mq, _seed_base + 7, configs2)
		for i in 400:
			a1.step()
			a2.step()
		var mism := 0
		if a1.events.size() != a2.events.size():
			mism += 1
		else:
			for i in a1.events.size():
				if str(a1.events[i].get("type", "")) != str(a2.events[i].get("type", "")) or int(a1.events[i].get("tick", -1)) != int(a2.events[i].get("tick", -1)):
					mism += 1
					break
		print("P5DETERMINISM mismatches=%d %s" % [mism, "PASS" if mism == 0 else "FAIL"])
	_done = true
	quit(0)

func _new_agg() -> Dictionary:
	return {
		"seeds": 0, "cov_end": {}, "cov_ratio": {}, "steps": {}, "unknown_steps": {},
		"day_steps": 0.0, "night_steps": 0.0, "blocked": 0.0, "blocked_unknown": 0.0, "blocked_stale": 0.0,
		"blocked_repeat_cells": 0.0, "person_not_found": 0.0, "found_person": 0.0, "request_missed": 0.0,
		"foraged": 0.0, "foraged_empty": 0.0, "wood": 0.0, "wood_empty": 0.0, "drank": 0.0, "fished": 0.0,
		"shells": 0.0, "ruins": 0.0, "ate": 0.0, "explore": 0.0, "hunger_p90": {}, "thirst_p90": {},
		"starving_ticks": {}, "socialize": {}, "req_made": {}, "req_recv": {}, "accepted": 0.0, "refused": 0.0,
		"desperate_ticks": {}, "threads_by_type": {}, "threads_resolved": 0.0, "threads_dormant": 0.0,
		"threads_total": 0.0, "promise_made": 0.0, "promise_kept": 0.0, "promise_broken": 0.0,
		"claims": 0.0, "epistemic": 0.0, "movement_blocked": 0.0, "replan_after_block": 0.0,
		"ck": {},  # day -> [known_cells avg]
	}

func _run_one(mq, seed: int, configs: Array, map_cells: int) -> Dictionary:
	var sim := IslandSimulation.new(mq, seed, configs)
	var actor_ids: Array = []
	for id in sim.actors:
		actor_ids.append(str(id))
	var per := {}
	for id in actor_ids:
		per[id] = {
			"steps": 0, "day": 0, "night": 0, "unk": 0, "dist": 0,
			"hunger": [], "thirst": [], "starve": 0, "desperate": 0,
		}
	var ck_days := [1, 5, 10, 30]
	if _ticks >= 2400:
		ck_days = [1, 5, 10, 30, 60]
	if _ticks >= 5000:
		ck_days = [1, 5, 10, 30, 60, 100]
	var ck := {}
	var ck_set := {}
	for d in ck_days:
		ck_set[int(d * 24)] = d
	var food_known_cache := {}
	for id in actor_ids:
		food_known_cache[id] = _food_known(sim.actors[id])
	var ticks_run := 0
	while ticks_run < _ticks:
		sim.step()
		ticks_run = sim.tick
		var hour := int(sim.world_time["hour"])
		var night := hour >= 20 or hour < 6
		for id in actor_ids:
			var a: Dictionary = sim.actors[id]
			var p: Dictionary = per[id]
			if a["tile"] != a["prev_tile"]:
				p["steps"] += 1
				var d2 := absi(int(a["tile"].x) - int(a["prev_tile"].x)) + absi(int(a["tile"].y) - int(a["prev_tile"].y))
				p["dist"] += d2
				if night:
					p["night"] += 1
				else:
					p["day"] += 1
				if str(a.get("_p5_step_kind", "")) == "unknown":
					p["unk"] += 1
		if sim.tick % 24 == 0:
			var day := int(sim.world_time["day"])
			var hungry_sample := {}
			for id in actor_ids:
				var a: Dictionary = sim.actors[id]
				var p: Dictionary = per[id]
				p["hunger"].append(int(a["needs"]["hunger"]))
				p["thirst"].append(int(a["needs"]["thirst"]))
				hungry_sample[id] = int(a["needs"]["hunger"])
				if int(a["needs"]["hunger"]) >= 950:
					p["starve"] += 1
				# 绝望 tick（checkpoint 采样，24-tick 分辨率——文档已注明）
				var fk: int = _food_known(a)
				var wk: int = int((a["spatial"] as SpatialBeliefMap).resource_tiles("water").size()) + int(a["inventory"].get("water", 0))
				if (int(a["needs"]["hunger"]) > 650 and fk == 0) or (int(a["needs"]["thirst"]) > 650 and wk == 0):
					p["desperate"] += 1
			if ck_set.has(sim.tick):
				var day_ckpt := {}
				var cov_sum := 0
				for id in actor_ids:
					var kc: int = (sim.actors[id]["spatial"] as SpatialBeliefMap).known_cell_count()
					day_ckpt[id] = kc
					cov_sum += kc
				day_ckpt["_avg"] = float(cov_sum) / float(actor_ids.size())
				ck[str(ck_set[sim.tick])] = day_ckpt
	# 事件后处理
	var ev := {}
	for e in sim.events:
		var t := str(e.get("type", ""))
		ev[t] = int(ev.get(t, 0)) + 1
	var blocked_by_actor := {}
	var block_cells := {}
	for e in sim.events:
		if str(e.get("type", "")) == "movement_blocked":
			var aid := str(e.get("actor_id", ""))
			blocked_by_actor[aid] = int(blocked_by_actor.get(aid, 0)) + 1
			var cell_key := aid + "|" + str(e.get("pos", ""))
			block_cells[cell_key] = int(block_cells.get(cell_key, 0)) + 1
	var repeat_cells := 0
	for k in block_cells:
		if int(block_cells[k]) > 1:
			repeat_cells += 1
	# 线程生态
	var te := ThreadEngine.new()
	te.process(sim)
	var th_by_type := {}
	var th_resolved := 0
	var th_dormant := 0
	for th in te.engine.threads:
		var tt := str(th.get("thread_type", ""))
		th_by_type[tt] = int(th_by_type.get(tt, 0)) + 1
		var st := str(th.get("status", ""))
		if st == "RESOLVED":
			th_resolved += 1
		elif st == "DORMANT":
			th_dormant += 1
	var blocked_unknown := 0
	var blocked_stale := 0
	for e in sim.events:
		if str(e.get("type", "")) == "movement_blocked":
			if str(e.get("block_kind", "")) == "stale_free":
				blocked_stale += 1
			else:
				blocked_unknown += 1
	# 每 actor 汇总
	var cov_end := {}
	var req_made := {}
	var req_recv := {}
	var socialize := {}
	for id in actor_ids:
		var a: Dictionary = sim.actors[id]
		cov_end[id] = (a["spatial"] as SpatialBeliefMap).known_cell_count()
		req_made[id] = 0
		req_recv[id] = 0
		socialize[id] = 0
	for e in sim.events:
		var t := str(e.get("type", ""))
		if t.ends_with("_requested"):
			var aid2 := str(e.get("actor_id", ""))
			req_made[aid2] = int(req_made.get(aid2, 0)) + 1
		elif t.ends_with("_request_refused") or t.ends_with("_request_accepted"):
			var prop := str(e.get("proposer_id", ""))
			req_made[prop] = int(req_made.get(prop, 0))  # requested 已计
		if t == "socialized" or t == "sat_by_fire":
			var aid3 := str(e.get("actor_id", ""))
			socialize[aid3] = int(socialize.get(aid3, 0)) + 1
	# p90
	var hunger_p90 := {}
	var thirst_p90 := {}
	for id in actor_ids:
		hunger_p90[id] = _p90(per[id]["hunger"])
		thirst_p90[id] = _p90(per[id]["thirst"])
	return {
		"ticks": ticks_run, "map_cells": map_cells,
		"cov_end": cov_end,
		"ck": ck,
		"per": _strip(per, ["hunger", "thirst"]),
		"hunger_p90": hunger_p90, "thirst_p90": thirst_p90,
		"blocked_by_actor": blocked_by_actor, "repeat_cells": repeat_cells,
		"blocked_unknown": blocked_unknown, "blocked_stale": blocked_stale,
		"ev": ev,
		"req_made": req_made, "socialize": socialize,
		"threads": {"total": te.engine.threads.size(), "by_type": th_by_type,
			"resolved": th_resolved, "dormant": th_dormant},
	}

func _food_known(a: Dictionary) -> int:
	var belief: SpatialBeliefMap = a.get("spatial", null)
	if belief == null:
		return 0
	return belief.resource_tiles("berry").size() + belief.resource_tiles("fish").size() + int(a.get("inventory", {}).get("food", 0))

func _p90(arr: Array) -> int:
	if arr.is_empty():
		return 0
	var s := arr.duplicate()
	s.sort()
	return int(s[int(float(s.size() - 1) * 0.9)])

func _strip(per: Dictionary, drop: Array) -> Dictionary:
	var out := {}
	for k in per:
		var d: Dictionary = per[k].duplicate()
		for key in drop:
			d.erase(key)
		out[k] = d
	return out

func _accumulate(agg: Dictionary, rec: Dictionary) -> void:
	var ev: Dictionary = rec["ev"]
	agg["foraged"] += float(ev.get("foraged", 0))
	agg["foraged_empty"] += float(ev.get("foraged_empty", 0))
	agg["wood"] += float(ev.get("gathered_wood", 0))
	agg["wood_empty"] += float(ev.get("gather_wood_empty", 0))
	agg["drank"] += float(ev.get("drank", 0))
	agg["fished"] += float(ev.get("fished", 0))
	agg["shells"] += float(ev.get("gathered_shells", 0))
	agg["ruins"] += float(ev.get("ruins_loot", 0))
	agg["ate"] += float(ev.get("ate_food", 0))
	agg["explore"] += float(ev.get("explored", 0))
	agg["movement_blocked"] += float(ev.get("movement_blocked", 0))
	agg["person_not_found"] += float(ev.get("person_not_found", 0))
	agg["found_person"] += float(ev.get("found_person", 0))
	agg["request_missed"] += float(ev.get("request_missed", 0))
	agg["promise_made"] += float(ev.get("promise_made", 0))
	agg["promise_kept"] += float(ev.get("promise_kept", 0))
	agg["promise_broken"] += float(ev.get("promise_broken", 0))
	agg["claims"] += float(ev.get("reason_claimed", 0))
	agg["epistemic"] += float(ev.get("reason_asked", 0)) + float(ev.get("observing_person", 0)) + float(ev.get("asked_about", 0))
	var accepted := 0
	var refused := 0
	for t in ev:
		if str(t).ends_with("_request_accepted"):
			accepted += int(ev[t])
		elif str(t).ends_with("_request_refused"):
			refused += int(ev[t])
	agg["accepted"] += float(accepted)
	agg["refused"] += float(refused)
	agg["blocked_repeat_cells"] += float(rec["repeat_cells"])
	agg["blocked_unknown"] += float(rec.get("blocked_unknown", 0))
	agg["blocked_stale"] += float(rec.get("blocked_stale", 0))
	var per: Dictionary = rec["per"]
	for id in per:
		var p: Dictionary = per[id]
		agg["steps"][id] = float(agg["steps"].get(id, 0.0)) + float(p["steps"])
		agg["unknown_steps"][id] = float(agg["unknown_steps"].get(id, 0.0)) + float(p["unk"])
		agg["day_steps"] += float(p["day"])
		agg["night_steps"] += float(p["night"])
		agg["starving_ticks"][id] = float(agg["starving_ticks"].get(id, 0.0)) + float(p["starve"])
		agg["desperate_ticks"][id] = float(agg["desperate_ticks"].get(id, 0.0)) + float(p["desperate"])
		var cov: Dictionary = rec["cov_end"]
		agg["cov_end"][id] = float(agg["cov_end"].get(id, 0.0)) + float(cov.get(id, 0))
		var hp90: Dictionary = rec["hunger_p90"]
		agg["hunger_p90"][id] = float(agg["hunger_p90"].get(id, 0.0)) + float(hp90.get(id, 0))
		var tp90: Dictionary = rec["thirst_p90"]
		agg["thirst_p90"][id] = float(agg["thirst_p90"].get(id, 0.0)) + float(tp90.get(id, 0))
		var rm: Dictionary = rec["req_made"]
		agg["req_made"][id] = float(agg["req_made"].get(id, 0.0)) + float(rm.get(id, 0))
		var sc: Dictionary = rec["socialize"]
		agg["socialize"][id] = float(agg["socialize"].get(id, 0.0)) + float(sc.get(id, 0))
	var ck: Dictionary = rec["ck"]
	for d in ck:
		if not agg["ck"].has(d):
			agg["ck"][d] = []
		agg["ck"][d].append(float(ck[d].get("_avg", 0.0)))
	var th: Dictionary = rec["threads"]
	agg["threads_total"] += float(th["total"])
	agg["threads_resolved"] += float(th["resolved"])
	agg["threads_dormant"] += float(th["dormant"])
	for t in th["by_type"]:
		agg["threads_by_type"][t] = float(agg["threads_by_type"].get(t, 0.0)) + float(th["by_type"][t])

func _finalize_agg(agg: Dictionary) -> void:
	var n := maxf(1.0, float(agg["seeds"]))
	for key in ["foraged", "foraged_empty", "wood", "wood_empty", "drank", "fished", "shells", "ruins", "ate",
			"explore", "movement_blocked", "person_not_found", "found_person", "request_missed",
			"promise_made", "promise_kept", "promise_broken", "claims", "epistemic", "accepted", "refused",
			"day_steps", "night_steps", "blocked_repeat_cells", "blocked_unknown", "blocked_stale",
			"threads_total", "threads_resolved", "threads_dormant"]:
		agg[key] = agg.get(key, 0.0) / n
	for key in ["steps", "unknown_steps", "starving_ticks", "desperate_ticks", "cov_end", "hunger_p90", "thirst_p90", "req_made", "socialize"]:
		var d: Dictionary = agg[key]
		for k in d:
			d[k] = float(d[k]) / n
