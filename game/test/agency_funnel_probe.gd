extends SceneTree
## Read-only diagnostic over the declared pilot seeds. No economy or action overrides.
var _out := ""
var _seeds := 10
var _ticks := 1000

func _initialize() -> void:
	call_deferred("_run")

func _count(table: Dictionary, key: String, amount: int = 1) -> void:
	table[key] = int(table.get(key, 0)) + amount

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg.begins_with("--seeds="): _seeds = arg.trim_prefix("--seeds=").to_int()
		elif arg.begins_with("--ticks="): _ticks = arg.trim_prefix("--ticks=").to_int()
		else:
			quit(1)
			return
	if _out == "" or FileAccess.file_exists(_out) or _seeds < 1 or _seeds > 30 or _ticks < 1 or _ticks > 3000:
		quit(1)
		return
	var rows: Array = []
	for offset in _seeds:
		var created := SimulationBootstrap.create(61000 + offset, "framework")
		if not created.get("ok", false):
			quit(1)
			return
		var sim: IslandSimulation = created["sim"]
		var stats := {"seed": 61000 + offset, "decision_opportunities": 0,
			"adoption_reasons": {}, "proposed_rule_status": {}, "blocker_reasons": {},
			"current_step_kinds": {}, "adopted_step_kinds": {}, "known_source_opportunities": {},
			"known_recipe_opportunities": {}, "hunger_buckets_actor_ticks": {},
			"acquire_craft_main_ready_opportunities": 0, "acquire_craft_main_adopted_opportunities": 0,
			"causal_uplift_candidates": 0, "plan_switches": 0, "examples": []}
		for i in _ticks:
			sim.step()
			for id in sim.actors:
				var actor: Dictionary = sim.actors[id]
				var hunger: int = actor["needs"]["hunger"]
				_count(stats["hunger_buckets_actor_ticks"], str(int(hunger / 100) * 100))
				var adoption: Dictionary = actor.get("last_plan_adoption", {})
				if int(adoption.get("tick", -1)) != sim.tick: continue
				stats["decision_opportunities"] += 1
				_count(stats["adoption_reasons"], str(adoption.get("reason", "")))
				var context := AgencyContextBuilder.build(sim, actor)
				for tag in context["known_source_tags"]: _count(stats["known_source_opportunities"], str(tag))
				for recipe in context["known_recipe_refs"]: _count(stats["known_recipe_opportunities"], str(recipe))
				# Read the exact cached proposals evaluated at this opportunity.
				for plan in sim._agency_cache.get(id, {}).get("proposals", []):
					_count(stats["proposed_rule_status"], str(plan.get("via_rule", "")) + ":" + str(plan["status"]))
					for blocker in plan.get("blockers", []):
						_count(stats["blocker_reasons"], str(blocker.get("reason_code", "")) + ":" + str(blocker.get("item_id", "")) + ":" + str(blocker.get("capability", "")))
					var kinds: Array = []
					for step in plan["steps"]:
						if not kinds.has(step["kind"]): kinds.append(step["kind"])
					var chain := kinds.has("ACQUIRE") and kinds.has("CRAFT") and kinds.has("MAIN")
					if plan["status"] == "READY" and chain: stats["acquire_craft_main_ready_opportunities"] += 1
					if str(plan["plan_id"]) == str(adoption.get("selected_plan_id", "")):
						for kind in kinds: _count(stats["adopted_step_kinds"], kind)
						if chain: stats["acquire_craft_main_adopted_opportunities"] += 1
					if plan.get("via_rule", "") == "fish_food" and stats["examples"].size() < 3:
						stats["examples"].append({"actor_id": id, "tick": sim.tick,
							"plan": plan.duplicate(true), "subjective_context": context.duplicate(true),
							"adoption": adoption.duplicate(true)})
				var run := sim.agency_plan_run(id)
				for step in run.get("steps", []):
					if step.get("step_id", "") == run.get("current_step_id", ""):
						_count(stats["current_step_kinds"], str(step["kind"]))
				var trace: Dictionary = actor.get("last_decision_trace", {}).get("agency_execution", {})
				if int(trace.get("decision_tick", -1)) == sim.tick:
					for value in trace.get("candidate_values", []):
						if float(value.get("utility_delta", 0.0)) > 0.0: stats["causal_uplift_candidates"] += 1
		for transition in sim.agency_execution_trace():
			if transition.get("event", "") == "RUN_CANCELLED" and transition.get("reason_code", "") == "COMMITMENT_RECONSIDERED":
				stats["plan_switches"] += 1
		stats["final_fingerprint"] = SimulationAudit.fingerprint(sim)
		rows.append(stats)
		print("FUNNEL_SEED " + JSON.stringify(stats).substr(0, 350))
		await process_frame
	var output := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify({"meta": {"profile": "framework", "first_seed": 61000,
		"seeds": _seeds, "ticks": _ticks, "economy_overrides": {},
		"count_unit": "actor decision opportunities unless field says actor_ticks",
		"note": "Read-only diagnosis; repeated cached proposals are counted at each decision opportunity."}, "rows": rows}, "\t"))
	file.close()
	print("FUNNEL_RESULT saved=" + output)
	quit(0)
