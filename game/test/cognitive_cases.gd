extends SceneTree
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
		print("PASS " + label)
	else:
		failed += 1
		print("FAIL " + label)

func _run() -> void:
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/knowledge/cases/engineering_fixture.json"))
	var library := CognitiveCaseLibrary.new()
	_check("compiled_evidence_pack_loads", library.load_pack(pack))
	var context := {"known_source_tags": ["FISH"], "known_recipe_refs": []}
	var before := AgencyMeasure.canon(context)
	var hints := library.retrieve("HUNGER", context, ["fish_food"])
	_check("matching_subjective_context_retrieves", hints.size() == 1)
	_check("advice_is_explicitly_non_executable", hints[0]["mode"] == "ADVISORY_ONLY" and not hints[0].has("world_effects"))
	_check("fixture_never_labeled_as_novel_training", hints[0]["origin"] == "ENGINEERING_FIXTURE")
	_check("advice_keeps_source_evidence", hints[0]["source_sha256"] == pack["cases"][0]["source_sha256"] and not hints[0]["evidence"].is_empty())
	_check("unknown_source_cannot_be_granted_by_fiction", library.retrieve("HUNGER", {}, ["fish_food"]).is_empty())
	_check("wrong_problem_is_filtered", library.retrieve("THIRST", context, ["fish_food"]).is_empty())
	_check("advice_cannot_invent_available_actions", library.retrieve("HUNGER", context, ["spring_water"]).is_empty())
	_check("returned_advice_is_defensive_copy", _check_copy(library, context))
	_check("retrieval_does_not_change_beliefs", before == AgencyMeasure.canon(context))
	var bad := pack.duplicate(true)
	bad["runtime_policy"] = "EXECUTE"
	_check("executable_pack_rejected", not library.load_pack(bad))
	_check("invalid_import_preserves_prior_library", library.retrieve("HUNGER", context, ["fish_food"]).size() == 1)
	bad = pack.duplicate(true)
	bad["cases"][0]["review"]["status"] = "DRAFT"
	_check("unreviewed_case_rejected", not library.load_pack(bad))
	bad = pack.duplicate(true)
	bad["cases"][0]["review"] = "APPROVED"
	_check("malformed_review_rejected_without_exception", not library.load_pack(bad))
	bad = pack.duplicate(true)
	bad["cases"].append(bad["cases"][0].duplicate(true))
	_check("duplicate_case_identity_rejected", not library.load_pack(bad))
	bad = pack.duplicate(true)
	bad["cases"][0]["evidence"] = []
	_check("evidence_free_case_rejected", not library.load_pack(bad))
	bad = pack.duplicate(true)
	bad["cases"][0]["retrieval"]["confidence"] = NAN
	_check("nonfinite_confidence_rejected", not library.load_pack(bad))
	bad = pack.duplicate(true)
	bad["cases"][0]["source_sha256"] = "z".repeat(64)
	_check("malformed_source_hash_rejected", not library.load_pack(bad))
	var recipe_pack := pack.duplicate(true)
	recipe_pack["cases"][0]["retrieval"]["required_recipe_refs"] = ["recipe:fish_spear"]
	var gated := CognitiveCaseLibrary.new()
	_check("recipe_preconditions_gate_retrieval", gated.load_pack(recipe_pack) and gated.retrieve("HUNGER", context, ["fish_food"]).is_empty())
	context["known_recipe_refs"] = ["recipe:fish_spear"]
	_check("known_recipe_unlocks_only_existing_rule", gated.retrieve("HUNGER", context, ["fish_food", "unrelated"]).size() == 1 and gated.retrieve("HUNGER", context, ["fish_food"])[0]["candidate_rule_ids"] == ["fish_food"])
	_check("malformed_context_fails_closed", library.retrieve("HUNGER", {"known_source_tags": 42}, ["fish_food"]).is_empty())
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check_copy(library: CognitiveCaseLibrary, context: Dictionary) -> bool:
	var hints := library.retrieve("HUNGER", context, ["fish_food"])
	hints[0]["evidence"].clear()
	return not library.retrieve("HUNGER", context, ["fish_food"])[0]["evidence"].is_empty()
