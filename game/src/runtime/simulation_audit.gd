class_name SimulationAudit
extends RefCounted
## Diagnostic fingerprints, not a save-file codec. No object is deserialized.
## Script state is traversed at the end of a run; rendering/map-query objects are excluded.
## RNG seed/state are strings so 64-bit values survive JSON consumers exactly.

static func fingerprint(sim: IslandSimulation) -> Dictionary:
	return {
		"events_sha256": AgencyMeasure.canon(sim.events).sha256_text(),
		"execution_sha256": AgencyMeasure.canon(sim.agency_execution_trace()).sha256_text(),
		"adoption_sha256": AgencyMeasure.canon(sim.agency_adoption_trace()).sha256_text(),
		"information_sha256": AgencyMeasure.canon(sim.agency_information_trace()).sha256_text(),
		"information_rng_states": sim.agency_information_rng_states(),
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
	return {"tick": sim.tick, "actors": sim.actors.size(), "event_counts": events,
		"execution_counts": executions, "execution_reasons": reasons, "adoption_counts": adoption,
		"information_counts": information,
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
				if key == "map_query" or (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
					continue
				object["state"][key] = _encode(value.get(key), active)
			active.erase(identity)
			return object
	return value
