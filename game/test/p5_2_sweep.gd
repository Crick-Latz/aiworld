extends SceneTree
## P5.2 — Food Ecology Calibration（GPT 指令 2026-09-07）
## 归因问题：食物来自"真实发现过的资源"还是"explore RNG"？四组配置 A/B/C/D 对照。
## 只动 berry_count / berry_regrow_days / explore_food_prob（其余全部固定，§3/§15）。
var _config := "K1"
var _natural := 20
var _camp := 10
var _ticks := 5000
var _seed_base := 60000
var _started := false
var _done := false

const CONFIGS := {
	"K1": {"berry_count": 4, "bush_capacity": 2, "berry_regrow_days": 5, "explore_food_prob": 0.015},
	"K2": {"berry_count": 5, "bush_capacity": 2, "berry_regrow_days": 5, "explore_food_prob": 0.01},
	"K3": {"berry_count": 6, "bush_capacity": 2, "berry_regrow_days": 6, "explore_food_prob": 0.01},
	"K4": {"berry_count": 5, "bush_capacity": 3, "berry_regrow_days": 7, "explore_food_prob": 0.008},
}

func _initialize() -> void:
	print("P52_CONFIG name=%s natural=%d camp=%d ticks=%d overrides=%s" % [_config, _natural, _camp, _ticks, JSON.stringify(CONFIGS[_config])])

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
	var overrides: Dictionary = CONFIGS[_config]
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
			var rec := _run_one(mq, seed, configs, map_cells, overrides)
			rec["cohort"] = cohort
			rec["seed"] = seed
			print("P52SEED " + JSON.stringify(rec))
			_accumulate(agg, rec)
	agg["seeds"] = _natural + _camp
	_finalize_agg(agg)
	print("P52AGG " + JSON.stringify(agg))
	_done = true
	quit(0)

func _new_agg() -> Dictionary:
	return {
		"seeds": 0, "explore": 0.0, "food_explore": 0.0, "food_berry": 0.0, "food_fish": 0.0, "food_share": 0.0,
		"foraged": 0.0, "foraged_empty": 0.0, "ate_food": 0.0, "movement_blocked": 0.0,
		"person_not_found": 0.0, "found_person": 0.0, "accepted": 0.0, "refused": 0.0,
		"promise_made": 0.0, "promise_kept": 0.0, "promise_broken": 0.0, "claims": 0.0,
		"epistemic": 0.0, "threads_total": 0.0, "threads_resolved": 0.0,
		"foraged_per": {}, "stale_per": {}, "known_berry_max": {}, "revisit_per": {},
		"hunger_p50": {}, "hunger_p90": {}, "starving": {}, "desperate": {},
		"cov_end": {}, "day_steps": 0.0, "night_steps": 0.0, "fished": 0.0, "shells": 0.0,
		"ck": {},
	}

func _run_one(mq, seed: int, configs: Array, map_cells: int, overrides: Dictionary) -> Dictionary:
	var sim := IslandSimulation.new(mq, seed, configs, overrides)
	var actor_ids: Array = []
	for id in sim.actors:
		actor_ids.append(str(id))
	var per := {}
	for id in actor_ids:
		per[id] = {"hunger": [], "starve": 0, "desperate": 0, "foraged": 0, "stale": 0,
			"known_berry_max": 0}
	var ck_days := [1, 5, 10, 30, 60, 100]
	if _ticks < 2500:
		ck_days = [1, 5, 10]
	var ck_set := {}
	for d in ck_days:
		ck_set[int(d * 24)] = d
	var ck := {}
	var ticks_run := 0
	while ticks_run < _ticks:
		sim.step()
		ticks_run = sim.tick
		if sim.tick % 24 == 0:
			for id in actor_ids:
				var a: Dictionary = sim.actors[id]
				var p: Dictionary = per[id]
				p["hunger"].append(int(a["needs"]["hunger"]))
				if int(a["needs"]["hunger"]) >= 950:
					p["starve"] += 1
				var belief: SpatialBeliefMap = a["spatial"]
				var kb: int = belief.resource_tiles("berry").size()
				if kb > int(p["known_berry_max"]):
					p["known_berry_max"] = kb
				var fk: int = kb + belief.resource_tiles("fish").size() + int(a["inventory"].get("food", 0))
				var wk: int = belief.resource_tiles("water").size() + int(a["inventory"].get("water", 0))
				if (int(a["needs"]["hunger"]) > 650 and fk == 0) or (int(a["needs"]["thirst"]) > 650 and wk == 0):
					p["desperate"] += 1
			if ck_set.has(sim.tick):
				var cov_sum := 0
				var day_ckpt := {}
				for id in actor_ids:
					var kc: int = (sim.actors[id]["spatial"] as SpatialBeliefMap).known_cell_count()
					day_ckpt[id] = kc
					cov_sum += kc
				day_ckpt["_avg"] = float(cov_sum) / float(actor_ids.size())
				ck[str(ck_set[sim.tick])] = day_ckpt
	# 食物来源归因（食物单位，读事件 extras）
	var food_explore := 0
	var food_berry := 0
	var food_fish := 0
	var food_share := 0
	var ev := {}
	for e in sim.events:
		var t := str(e.get("type", ""))
		ev[t] = int(ev.get(t, 0)) + 1
		if t == "explored_found":
			food_explore += int(e.get("food", 1))
		elif t == "foraged":
			food_berry += int(e.get("food", 1))
			var aid := str(e.get("actor_id", ""))
			per[aid]["foraged"] = int(per[aid]["foraged"]) + 1
		elif t == "foraged_empty":
			var aid2 := str(e.get("actor_id", ""))
			per[aid2]["stale"] = int(per[aid2]["stale"]) + 1
		elif t == "fished":
			food_fish += int(e.get("food", 1))
		elif t == "shared_food" or t.ends_with("_request_accepted"):
			food_share += 1
	# 每 actor 派生
	var derived := {}
	for id in actor_ids:
		var p2: Dictionary = per[id]
		var trips: int = int(p2["foraged"]) + int(p2["stale"])
		var revisit: int = maxi(0, trips - int(p2["known_berry_max"]))
		var hs: Array = p2["hunger"]
		var srt := hs.duplicate()
		srt.sort()
		derived[id] = {
			"foraged": int(p2["foraged"]), "stale": int(p2["stale"]),
			"known_berry_max": int(p2["known_berry_max"]), "trips": trips, "revisit": revisit,
			"starve": int(p2["starve"]), "desperate": int(p2["desperate"]),
			"hunger_p50": int(srt[int(float(srt.size() - 1) * 0.5)]) if not srt.is_empty() else 0,
			"hunger_p90": int(srt[int(float(srt.size() - 1) * 0.9)]) if not srt.is_empty() else 0,
		}
	# 线程生态
	var te := ThreadEngine.new()
	te.process(sim)
	var th_types := {}
	var th_res := 0
	for th in te.engine.threads:
		var tt := str(th.get("thread_type", ""))
		th_types[tt] = int(th_types.get(tt, 0)) + 1
		if str(th.get("status", "")) == "RESOLVED":
			th_res += 1
	var cov_end := {}
	for id in actor_ids:
		cov_end[id] = (sim.actors[id]["spatial"] as SpatialBeliefMap).known_cell_count()
	return {
		"ticks": ticks_run, "map_cells": map_cells,
		"food": {"explore": food_explore, "berry": food_berry, "fish": food_fish, "share": food_share},
		"per": derived, "cov_end": cov_end, "ck": ck, "ev": ev, "threads": {
			"total": te.engine.threads.size(), "by_type": th_types, "resolved": th_res},
	}

func _accumulate(agg: Dictionary, rec: Dictionary) -> void:
	var f: Dictionary = rec["food"]
	agg["food_explore"] += float(f["explore"])
	agg["food_berry"] += float(f["berry"])
	agg["food_fish"] += float(f["fish"])
	agg["food_share"] += float(f["share"])
	var ev: Dictionary = rec["ev"]
	for key in ["foraged", "foraged_empty", "movement_blocked", "person_not_found", "found_person",
			"promise_made", "promise_kept", "promise_broken", "claims", "fished", "shells", "ate_food"]:
		agg[key] += float(ev.get(key, 0))
	agg["explore"] += float(ev.get("explored", 0))
	for key in ["reason_asked", "observing_person", "asked_about"]:
		agg["epistemic"] += float(ev.get(key, 0))
	var acc := 0
	var ref := 0
	for t in ev:
		if str(t).ends_with("_request_accepted"):
			acc += int(ev[t])
		elif str(t).ends_with("_request_refused"):
			ref += int(ev[t])
	agg["accepted"] += float(acc)
	agg["refused"] += float(ref)
	var per: Dictionary = rec["per"]
	for id in per:
		var p: Dictionary = per[id]
		agg["foraged_per"][id] = float(agg["foraged_per"].get(id, 0.0)) + float(p["foraged"])
		agg["stale_per"][id] = float(agg["stale_per"].get(id, 0.0)) + float(p["stale"])
		agg["known_berry_max"][id] = float(agg["known_berry_max"].get(id, 0.0)) + float(p["known_berry_max"])
		agg["revisit_per"][id] = float(agg["revisit_per"].get(id, 0.0)) + float(p["revisit"])
		agg["hunger_p50"][id] = float(agg["hunger_p50"].get(id, 0.0)) + float(p["hunger_p50"])
		agg["hunger_p90"][id] = float(agg["hunger_p90"].get(id, 0.0)) + float(p["hunger_p90"])
		agg["starving"][id] = float(agg["starving"].get(id, 0.0)) + float(p["starve"])
		agg["desperate"][id] = float(agg["desperate"].get(id, 0.0)) + float(p["desperate"])
		agg["cov_end"][id] = float(agg["cov_end"].get(id, 0.0)) + float(rec["cov_end"][id])
	var ck: Dictionary = rec["ck"]
	for d in ck:
		if not agg["ck"].has(d):
			agg["ck"][d] = []
		agg["ck"][d].append(float(ck[d].get("_avg", 0.0)))
	var th: Dictionary = rec["threads"]
	agg["threads_total"] += float(th["total"])
	agg["threads_resolved"] += float(th["resolved"])

func _finalize_agg(agg: Dictionary) -> void:
	var n := maxf(1.0, float(agg["seeds"]))
	for key in ["food_explore", "food_berry", "food_fish", "food_share", "foraged", "foraged_empty",
			"explore", "movement_blocked", "person_not_found", "found_person", "accepted", "refused",
			"promise_made", "promise_kept", "promise_broken", "claims", "epistemic", "fished", "shells",
			"threads_total", "threads_resolved"]:
		agg[key] = agg.get(key, 0.0) / n
	for key in ["foraged_per", "stale_per", "known_berry_max", "revisit_per", "hunger_p50",
			"hunger_p90", "starving", "desperate", "cov_end"]:
		var d: Dictionary = agg[key]
		for k in d:
			d[k] = float(d[k]) / n
	var total_food: float = float(agg["food_explore"]) + float(agg["food_berry"]) + float(agg["food_fish"]) + float(agg["food_share"])
	if total_food > 0.0:
		agg["share_explore"] = agg["food_explore"] / total_food
		agg["share_persistent"] = (agg["food_berry"] + agg["food_fish"]) / total_food
		agg["share_social"] = agg["food_share"] / total_food
	var trips: float = float(agg["foraged"]) + float(agg["foraged_empty"])
	agg["stale_trip_rate"] = (agg["foraged_empty"] / trips) if trips > 0.0 else 0.0
	agg["explore_share_of_ticks"] = agg["explore"] / float(_ticks)
	agg["consumed"] = agg.get("ate_food", 0.0)
	var trips2: float = float(agg["foraged"]) + float(agg["foraged_empty"])
	agg["berry_success_rate"] = (float(agg["foraged"]) / trips2) if trips2 > 0.0 else 0.0
	agg["produced"] = float(agg["food_explore"]) + float(agg["food_berry"]) + float(agg["food_fish"])
	agg["transferred"] = float(agg["food_share"])
