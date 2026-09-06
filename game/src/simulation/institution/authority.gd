class_name AuthoritySystem
extends RefCounted
## P2e authority (P2.1 hardened): proposals are NOT competence evidence;
## Competence vs Influence separated; SelfIdentity from 3 sources.

const DOMAINS := {
		"crafted": "construction",
		"shelter_built": "construction",
		"fire_lit": "construction",
		"fished": "food",
		"foraged": "food",
		"explored": "navigation",
		"explored_found": "navigation",
}

static func observe_competence(observer: Dictionary, event_type: String, actor_id: String, seq: int, tick: int) -> void:
	var domain := str(DOMAINS.get(event_type, ""))
	if domain == "" or actor_id == str(observer.get("id", "")):
		return
	observer["tom"].add_evidence(actor_id, "competence_" + domain, 1.0, 0.12, seq, tick)

static func public_endorsement(observer: Dictionary, proposer: String, seq: int, tick: int) -> void:
	observer["tom"].add_evidence(proposer, "influence_coordination", 1.0, 0.2, seq, tick)

static func observe_followership(observer: Dictionary, follower_id: String, leader_id: String, seq: int, tick: int) -> void:
	observer["tom"].add_evidence(leader_id, "influence_coordination", 1.0, 0.15, seq, tick)

static func perceived_authority(observer: Dictionary, other_id: String, domain: String) -> float:
	var competence: float = observer["tom"].belief_about(other_id, "competence_" + domain)
	var influence: float = observer["tom"].belief_about(other_id, "influence_" + domain)
	if domain == "coordination":
		return influence
	return clampf(competence * 0.6 + influence * 0.2, -1.0, 1.0)

static func self_identity(actor: Dictionary, event_type: String) -> void:
	var domain := str(DOMAINS.get(event_type, ""))
	if domain == "":
		return
	var self_id: Dictionary = actor.get("self_identity", {})
	self_id["performance_" + domain] = int(self_id.get("performance_" + domain, 0)) + 1
	actor["self_identity"] = self_id

static func social_recognition(actor: Dictionary, domain: String) -> void:
	var self_id: Dictionary = actor.get("self_identity", {})
	self_id["recognition_" + domain] = int(self_id.get("recognition_" + domain, 0)) + 1
	actor["self_identity"] = self_id

static func commitment(actor: Dictionary, domain: String) -> void:
	var self_id: Dictionary = actor.get("self_identity", {})
	self_id["commitment_" + domain] = int(self_id.get("commitment_" + domain, 0)) + 1
	actor["self_identity"] = self_id

static func self_identity_boost(actor: Dictionary, domain: String) -> float:
	var sid: Dictionary = actor.get("self_identity", {})
	var perf := int(sid.get("performance_" + domain, 0))
	var recog := int(sid.get("recognition_" + domain, 0))
	var commit := int(sid.get("commitment_" + domain, 0))
	return clampf(float(perf + recog * 1.5 + commit * 0.5) * 0.03, 0.0, 0.2)

static func authority_violation(observer: Dictionary, violator: String, seq: int, tick: int) -> void:
	observer["tom"].add_evidence(violator, "influence_coordination", -1.0, 0.4, seq, tick)
	observer["tom"].add_evidence(violator, "reliable", -1.0, 0.25, seq, tick)
