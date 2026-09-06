extends SceneTree
## FG-R1：Grounded Narrative IR 独立契约测试。

class FakeSimulation:
	extends RefCounted
	var events: Array = []
	var actors: Dictionary = {}
	var tick: int = 20

var passed := 0
var failed := 0

func _initialize() -> void:
	_run()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("PASS %s" % name)
	else:
		failed += 1
		print("FAIL %s  %s" % [name, detail])

func _run() -> void:
	var sim := FakeSimulation.new()
	var rule := {"rule_id": "rule:food:1", "proposer": "vera", "object": "food"}
	sim.events = [
		{"seq": 1, "tick": 1, "type": "food_request_refused", "actor_id": "oun", "proposer_id": "vera", "text": "欧恩拒绝了薇拉"},
		{"seq": 2, "tick": 2, "type": "ruins_loot", "actor_id": "kadga", "text": "卡德加秘密找到了工具"},
		{"seq": 3, "tick": 3, "type": "reason_asked", "actor_id": "vera", "to_id": "oun", "text": "薇拉追问原因", "source_event_ids": [1], "trace_id": "decision:vera:3"},
		{"seq": 4, "tick": 4, "type": "promise_made", "actor_id": "oun", "to_id": "vera", "text": "欧恩许诺归还"},
		{"seq": 5, "tick": 5, "type": "promise_kept", "actor_id": "oun", "to_id": "vera", "text": "欧恩兑现承诺", "source_event_ids": [4]},
		{"seq": 6, "tick": 6, "type": "reflected", "actor_id": "vera", "about_id": "oun", "text": "薇拉修正了判断", "reflection_kind": "belief_revision", "source_event_ids": [1, 3]},
		{"seq": 7, "tick": 7, "type": "rule_proposed", "actor_id": "vera", "text": "提出规则", "rule": rule},
		{"seq": 8, "tick": 8, "type": "institution_established", "actor_id": "vera", "text": "规则成立", "rule": rule, "source_event_ids": [7]},
		{"seq": 9, "tick": 9, "type": "socialized", "actor_id": "kadga", "text": "相邻但没有因果"},
		{"seq": 10, "tick": 10, "type": "reflected", "actor_id": "vera", "about_id": "oun", "text": "文字里写了错怪，但没有结构证据"},
	]
	sim.actors = {
		"vera": {"memories": [
			{"seq": 1, "tick": 1, "type": "food_request_refused", "text": "我被欧恩拒绝"},
			{"seq": 3, "tick": 3, "type": "reason_asked", "text": "我追问了原因"},
		]},
		"oun": {"memories": []},
		"kadga": {"memories": []},
	}

	var graph := NarrativeIR.build_causal_graph(sim.events)
	_check("graph_valid", graph.get("ok", false), str(graph))
	var node_ids := {}
	for node in graph.get("nodes", []):
		node_ids[str(node.get("id", ""))] = true
	var endpoints_valid := true
	var has_self_loop := false
	for edge in graph.get("edges", []):
		endpoints_valid = endpoints_valid and node_ids.has(str(edge.get("from", ""))) and node_ids.has(str(edge.get("to", "")))
		has_self_loop = has_self_loop or str(edge.get("from", "")) == str(edge.get("to", ""))
	_check("all_edge_endpoints_exist", endpoints_valid)
	_check("no_self_loops", not has_self_loop)
	_check("trace_node_is_typed", node_ids.has("trace:decision:vera:3"))
	_check("explicit_event_link_exists", _edge_exists(graph["edges"], "event:1", "event:3"))
	_check("promise_link_exists", _edge_exists(graph["edges"], "event:4", "event:5"))
	_check("institution_link_exists", _edge_exists(graph["edges"], "event:7", "event:8"))
	_check("adjacency_not_causality", not _edge_exists(graph["edges"], "event:2", "event:3"))

	var beats := NarrativeIR.extract_beats(sim.events, sim.actors)
	var misunderstanding_count := _beat_count(beats, "MISUNDERSTANDING")
	var revision_count := _beat_count(beats, "BELIEF_REVISION")
	_check("explicit_revision_creates_misunderstanding", misunderstanding_count == 1, str(beats))
	_check("explicit_revision_creates_revision", revision_count == 1, str(beats))
	_check("text_keyword_does_not_create_fact", misunderstanding_count == 1 and revision_count == 1)
	var grounded := true
	var stable_ids := true
	for beat in beats:
		grounded = grounded and not (beat.get("source_event_ids", []) as Array).is_empty()
		stable_ids = stable_ids and str(beat.get("beat_id", "")).begins_with("beat:") and beat.has("source_trace_ids")
	_check("all_beats_grounded", grounded)
	_check("all_beats_have_stable_ids", stable_ids)
	_check("beat_extraction_deterministic", str(beats) == str(NarrativeIR.extract_beats(sim.events, sim.actors)))

	var objective := NarrativeIR.build_ir(sim, "OBJECTIVE", "", 20)
	var character := NarrativeIR.build_ir(sim, "CHARACTER", "vera", 20)
	var retrospective := NarrativeIR.build_ir(sim, "RETROSPECTIVE", "vera", 20)
	_check("objective_sees_world_events", objective.get("ok", false) and (objective.get("known_facts", []) as Array).size() == 10)
	_check("character_has_no_objective_facts", character.get("ok", false) and (character.get("known_facts", []) as Array).is_empty())
	_check("character_only_uses_memory_ids", character.get("source_refs", {}).get("event_ids", []) == [1, 3], str(character.get("source_refs", {})))
	_check("hidden_event_has_no_character_beat", not (character.get("source_refs", {}).get("event_ids", []) as Array).has(2))
	_check("retrospective_adds_own_reflection", retrospective.get("ok", false) and (retrospective.get("source_refs", {}).get("event_ids", []) as Array).has(6))
	_check("forbidden_inferences_are_structured", typeof(character.get("forbidden_inferences", [])[0]) == TYPE_DICTIONARY)
	_check("ir_hash_deterministic", str(objective.get("ir_hash", "")) == str(NarrativeIR.build_ir(sim, "OBJECTIVE", "", 20).get("ir_hash", "")))
	_check("invalid_perspective_rejected", NarrativeIR.build_ir(sim, "GOSSIP", "vera", 5).get("code", "") == "E_NARRATIVE_PERSPECTIVE_INVALID")
	_check("missing_actor_rejected", NarrativeIR.build_ir(sim, "CHARACTER", "missing", 5).get("code", "") == "E_NARRATIVE_ACTOR_NOT_FOUND")
	var duplicate_events := sim.events.duplicate(true)
	duplicate_events.append(sim.events[0].duplicate(true))
	_check("duplicate_event_id_rejected", NarrativeIR.build_causal_graph(duplicate_events).get("code", "") == "E_NARRATIVE_EVENT_ID_DUPLICATE")

func _edge_exists(edges: Array, from_id: String, to_id: String) -> bool:
	for edge in edges:
		if str(edge.get("from", "")) == from_id and str(edge.get("to", "")) == to_id:
			return true
	return false

func _beat_count(beats: Array, type: String) -> int:
	var count := 0
	for beat in beats:
		if str(beat.get("type", "")) == type:
			count += 1
	return count
