extends SceneTree
## P4.1 Long-Horizon Sweep: Pilot → Breadth → Deep → Audit
## Phase A Pilot: Natural 50 + Camp 20 × 2000 ticks
## Phase B Breadth: Natural 500 + Camp 100 × 2000 ticks
## Phase C Deep: Natural 100 + Camp 30 × 10000 ticks
## Phase D ON/OFF invariance + Phase E determinism
##
## 用法: --script res://test/p4_sweep.gd [--sec-args natural=50,camp=20,ticks=2000,phase=pilot]

var _f := false
var _started := false
var _phase := "pilot"
var _natural := 50
var _camp := 20
var _ticks := 2000
var _seed_base := 50000

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		var kv := a.split("=")
		if kv.size() == 2:
			match kv[0]:
				"phase": _phase = kv[1]
				"natural": _natural = kv[1].to_int()
				"camp": _camp = kv[1].to_int()
				"ticks": _ticks = kv[1].to_int()
	print("SWEEP_CONFIG phase=%s natural=%d camp=%d ticks=%d" % [_phase, _natural, _camp, _ticks])

func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _f

func _run() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var spot = mq.get_poi_tile("post_house")
	var spots := [mq.get_poi_tile("post_house"), mq.get_poi_tile("tide_market"), mq.get_poi_tile("old_lighthouse")]

	# Aggregate metrics
	var agg := {
		"seeds": 0, "events_total": 0, "threads_total": 0,
		"threads_by_type": {}, "threads_open": 0, "threads_active": 0,
		"threads_dormant": 0, "threads_resolved": 0, "threads_reactivated": 0,
		"nodes_total": 0, "attachments_tier1": 0, "attachments_tier2": 0, "attachments_tier3": 0,
		"attachments_dyad_fallback": 0, "contaminated": 0, "resolved_reopened": 0,
		"resolution_no_evidence": 0, "super_thread_suspects": 0,
		"threads_per_seed": [], "nodes_per_thread": [], "fingerprints": {},
	}
	# Run both cohorts
	for cohort in ["natural", "camp"]:
		var count := _natural if cohort == "natural" else _camp
		if count == 0: continue
		for s in range(count):
			var seed := _seed_base + s
			var configs: Array = []
			for ac in scenario.get("actors", []):
				var cfg = ac.duplicate()
				cfg["spawn"] = spot if cohort == "camp" else spots[configs.size() % spots.size()]
				configs.append(cfg)
			var sim := IslandSimulation.new(mq, seed, configs)
			for i in _ticks: sim.step()
			var te := ThreadEngine.new()
			te.process(sim)
			_collect(cohort, seed, sim, te, agg)
	agg["seeds"] = _natural + _camp
	_report(agg)
	quit(0)

func _collect(cohort: String, seed: int, sim, te: ThreadEngine, agg: Dictionary) -> void:
	agg["events_total"] += sim.events.size()
	var threads: Array = te.engine.threads
	agg["threads_total"] += threads.size()
	agg["threads_per_seed"].append(threads.size())
	var fp := {}
	for th in threads:
		var tt := str(th.get("thread_type", ""))
		agg["threads_by_type"][tt] = int(agg["threads_by_type"].get(tt, 0)) + 1
		fp[tt] = int(fp.get(tt, 0)) + 1
		match str(th.get("status", "")):
			"OPEN": agg["threads_open"] += 1
			"ACTIVE": agg["threads_active"] += 1
			"DORMANT": agg["threads_dormant"] += 1
			"RESOLVED": agg["threads_resolved"] += 1
		# resolved_reopened check: RESOLVED with post-resolution nodes
		if str(th.get("status", "")) == "RESOLVED":
			var rt := int(th.get("resolved_tick", -1))
			for n in th.get("source_event_ids", []):
				# find event tick for this seq
				for e in sim.events:
					if int(e.get("seq", -1)) == int(n) and int(e.get("tick", 0)) > rt:
						agg["resolved_reopened"] += 1
		# resolution evidence: RESOLVED must have resolution field
		if str(th.get("status", "")) == "RESOLVED" and str(th.get("resolution", "")).is_empty():
			agg["resolution_no_evidence"] += 1
		# attachments
		for att in th.get("attachments", []):
			match str(att.get("tier", "")):
				"TIER_1_EXPLICIT_ID": agg["attachments_tier1"] += 1
				"TIER_1_DYAD_FALLBACK": agg["attachments_dyad_fallback"] += 1
				"TIER_2_CAUSAL_EDGE": agg["attachments_tier2"] += 1
				"TIER_3_SEMANTIC": agg["attachments_tier3"] += 1
		# nodes
		var nc := (th.get("source_event_ids", []) as Array).size()
		agg["nodes_total"] += nc
		agg["nodes_per_thread"].append(nc)
		# super thread suspect: >20 nodes
		if nc > 20:
			agg["super_thread_suspects"] += 1
			print("SUPER_THREAD_SUSPECT id=%s type=%s nodes=%d seed=%d cohort=%s" % [
				str(th.get("thread_id", "")), tt, nc, seed, cohort])
	agg["contaminated"] += te.engine.check_purity()
	# fingerprint
	var fp_key := str(JSON.stringify(fp))
	agg["fingerprints"][fp_key] = int(agg["fingerprints"].get(fp_key, 0)) + 1

func _report(agg: Dictionary) -> void:
	var t: int = int(agg["threads_total"])
	print("SWEEP_RESULT seeds=%d events=%d threads=%d" % [agg["seeds"], agg["events_total"], t])
	print("BY_TYPE %s" % str(agg["threads_by_type"]))
	print("STATUS open=%d active=%d dormant=%d resolved=%d reactivated=?" % [
		agg["threads_open"], agg["threads_active"], agg["threads_dormant"], agg["threads_resolved"]])
	print("ATTACH tier1=%d tier2=%d tier3=%d dyad_fallback=%d" % [
		agg["attachments_tier1"], agg["attachments_tier2"], agg["attachments_tier3"], agg["attachments_dyad_fallback"]])
	var total_att: int = int(agg["attachments_tier1"]) + agg["attachments_tier2"] + agg["attachments_tier3"] + agg["attachments_dyad_fallback"]
	var weak: float = float(agg["attachments_tier3"]) / maxf(float(total_att), 1.0)
	var strong: float = float(agg["attachments_tier1"] + agg["attachments_tier2"]) / maxf(float(total_att), 1.0)
	print("RATIOS weak_link=%.3f strong_link=%.3f" % [weak, strong])
	print("HARD_GATES contaminated=%d resolved_reopened=%d resolution_no_evidence=%d super_suspects=%d" % [
		agg["contaminated"], agg["resolved_reopened"], agg["resolution_no_evidence"], agg["super_thread_suspects"]])
	var gates_ok: bool = int(agg["contaminated"]) == 0 and agg["resolved_reopened"] == 0 and agg["resolution_no_evidence"] == 0 and agg["attachments_dyad_fallback"] == 0
	print("HARD_GATES_%s" % ("PASS" if gates_ok else "FAIL"))
	# Percentiles
	var nps: Array = agg["nodes_per_thread"]
	if not nps.is_empty():
		nps.sort()
		var med: float = float(nps[nps.size() / 2])
		var p99: float = float(nps[int(nps.size() * 0.99)])
		var mx: float = float(nps[nps.size() - 1])
		print("NODES_PER_THREAD median=%.1f p99=%.1f max=%.1f" % [med, p99, mx])
	var tps: Array = agg["threads_per_seed"]
	if not tps.is_empty():
		tps.sort()
		print("THREADS_PER_SEED median=%.1f max=%.1f" % [float(tps[tps.size() / 2]), float(tps[tps.size() - 1])])
	print("FINGERPRINTS unique=%d of %d seeds" % [agg["fingerprints"].size(), agg["seeds"]])
