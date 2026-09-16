class_name SimulationAudit
extends RefCounted
## Diagnostic fingerprints, not a save-file codec. No object is deserialized.
## Script state is traversed at the end of a run; rendering/map-query objects are excluded.
## RNG seed/state are strings so 64-bit values survive JSON consumers exactly.

static func fingerprint(sim: IslandSimulation) -> Dictionary:
	# P7.2C-R1 B3：导出前闭合残留 residence episode（标 censored——纯诊断，
	# 不改 authoritative state；已在 _encode 排除表中）。
	sim._censor_open_residence_episodes()
	# P7.2C-R2-R1.3：encounter episode 同纪律闭合（censored 分类）。
	sim._censor_open_visual_encounters()
	return {
		"events_sha256": AgencyMeasure.canon(sim.events).sha256_text(),
		"execution_sha256": AgencyMeasure.canon(sim.agency_execution_trace()).sha256_text(),
		"adoption_sha256": AgencyMeasure.canon(sim.agency_adoption_trace()).sha256_text(),
		"information_sha256": AgencyMeasure.canon(sim.agency_information_trace()).sha256_text(),
		"material_request_sha256": AgencyMeasure.canon(sim.agency_material_request_trace()).sha256_text(),
		"commitment_sha256": AgencyMeasure.canon(sim.agency_commitment_trace()).sha256_text(),
		"information_rng_states": sim.agency_information_rng_states(),
		"material_request_rng_states": sim.agency_material_request_rng_states(),
		"commitment_rng_states": sim.agency_commitment_rng_states(),
		"state_sha256": AgencyMeasure.canon(_encode(sim, {})).sha256_text(),
		"adoption_rng_states": sim.agency_adoption_rng_states(),
	}

static func summary(sim: IslandSimulation) -> Dictionary:
	var events := {}
	for event in sim.events:
		var kind := str(event.get("type", ""))
		events[kind] = int(events.get(kind, 0)) + 1
	var executions := {}
	var reasons := {}
	for row in sim.agency_execution_trace():
		var event := str(row.get("event", ""))
		executions[event] = int(executions.get(event, 0)) + 1
		var reason := str(row.get("reason_code", ""))
		if reason != "": reasons[reason] = int(reasons.get(reason, 0)) + 1
	var adoption := {}
	for row in sim.agency_adoption_trace():
		var kind := str(row.get("decision", ""))
		adoption[kind] = int(adoption.get(kind, 0)) + 1
	var information := {}
	for row in sim.agency_information_trace():
		var info_event := str(row.get("event", ""))
		information[info_event] = int(information.get(info_event, 0)) + 1
	var material_requests := {}
	for row in sim.agency_material_request_trace():
		var material_event := str(row.get("event", ""))
		material_requests[material_event] = int(material_requests.get(material_event, 0)) + 1
	var holder_funnel: Dictionary = sim.agency_holder_funnel_diagnostics()
	var objective_audit: Dictionary = sim.agency_objective_material_audit()
	var commitments := {}
	for row in sim.agency_commitment_trace():
		var commitment_event := str(row.get("event", ""))
		commitments[commitment_event] = int(commitments.get(commitment_event, 0)) + 1
	return {"tick": sim.tick, "actors": sim.actors.size(), "event_counts": events,
		"execution_counts": executions, "execution_reasons": reasons, "adoption_counts": adoption,
		"information_counts": information, "material_request_counts": material_requests,
		"commitment_counts": commitments,
		"holder_funnel": holder_funnel,
		"objective_material_audit": objective_audit,
		"planner_calls": sim.agency_planner_calls, "planner_cache_hits": sim.agency_cache_hits}

static func _encode(value: Variant, active: Dictionary) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var dictionary := {}
			for key in value:
				dictionary[str(key)] = _encode(value[key], active)
			return dictionary
		TYPE_ARRAY:
			var array: Array = []
			for entry in value: array.append(_encode(entry, active))
			return array
		TYPE_OBJECT:
			if value == null: return null
			if value is RandomNumberGenerator:
				return {"type": "RandomNumberGenerator", "seed": str(value.seed), "state": str(value.state)}
			var script: Script = value.get_script()
			if script == null:
				return {"native_type": value.get_class()}
			var identity: int = value.get_instance_id()
			if active.has(identity): return {"cycle_type": script.resource_path}
			active[identity] = true
			var object := {"script": script.resource_path, "state": {}}
			for property in value.get_property_list():
				var key := str(property["name"])
				# P7.2：commitment 运行时桥与开关位不进入 state 编码——其权威状态在
				# obligations（仍被哈希），追加式历史由 commitment_sha256 单独覆盖；
				# 排除是为了旧 profile 与 P7.2 前基线保持逐位 state 兼容（map_query 同例）。
				# P7.2B-R1.1：_holder_funnel_diag 为纯加性诊断计数（只写不读、
				# 不参与行为/RNG/排序），同理排除；数值仅经 summary 输出。
				if key == "map_query" or key == "_commitment_runtime" \
						or key == "agency_commitment_consequences_enabled" \
						or key == "agency_holder_evidence_reachability_enabled" \
						or key == "_holder_funnel_diag" \
						or key == "_objective_material_audit" \
						or key == "_holder_arbitration_probe" \
						or key == "_holder_seek_arbitration_probe" \
						or key == "_material_residence_probe" \
					or key == "_visual_encounter_probe" \
					or key == "_visual_encounter_history" \
					or key == "_possession_observation_last_tick" \
					or key == "_possession_observation_history" \
						or key == "agency_holder_reachability_enabled" \
						or key == "agency_holder_possession_observation_enabled" \
						or key == "agency_holder_causal_arbitration_enabled" \
						or (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
					continue
				object["state"][key] = _encode(value.get(key), active)
			active.erase(identity)
			return object
	return value
