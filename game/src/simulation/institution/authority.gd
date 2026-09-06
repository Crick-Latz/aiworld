class_name AuthoritySystem
extends RefCounted
## P2e 涌现角色与领域权威（Institutional Cognition 第五层）
##
## 禁止 Khadgar.role = carpenter / leader = Vera。
## RoleBelief 与 DomainAuthority 全部是【每个观察者各自的】ToM 信念（schema-free 槽）：
##   authority_construction / authority_food / authority_navigation…
## "被听从"先于"职位"：提案被跟随且成功 → 权威证据；违背自己推动的规则 → 权威崩塌证据。

const DOMAINS := {
	"crafted": "construction",
	"shelter_built": "construction",
	"fire_lit": "construction",
	"fished": "food",
	"foraged": "food",
	"explored": "navigation",
	"explored_found": "navigation",
	"rule_proposed": "coordination",
}

## 目击他人行为 → 领域能力证据（我逐渐认为"修东西该找卡德加"）
static func observe_competence(observer: Dictionary, event_type: String, actor_id: String, seq: int, tick: int) -> void:
	var domain := str(DOMAINS.get(event_type, ""))
	if domain == "" or actor_id == str(observer.get("id", "")):
		return
	observer["tom"].add_evidence(actor_id, "authority_" + domain, 1.0, 0.12, seq, tick)

## P2e-4 公开角色承认：公开支持某人的提案 → 该领域权威证据更强（公开背书）
static func public_endorsement(observer: Dictionary, proposer: String, domain: String, seq: int, tick: int) -> void:
	observer["tom"].add_evidence(proposer, "authority_" + domain, 1.0, 0.2, seq, tick)

## P2e-2 自我身份反馈：反复做成某类事 → "我是修东西的人" → 相关行动效用微增
static func self_identity(actor: Dictionary, event_type: String) -> void:
	var domain := str(DOMAINS.get(event_type, ""))
	if domain == "":
		return
	var self_id: Dictionary = actor.get("self_identity", {})
	self_id[domain] = int(self_id.get(domain, 0)) + 1
	actor["self_identity"] = self_id

static func self_identity_boost(actor: Dictionary, event_type: String) -> float:
	var domain := str(DOMAINS.get(event_type, ""))
	if domain == "":
		return 0.0
	var n := int(actor.get("self_identity", {}).get(domain, 0))
	return clampf(float(n) * 0.03, 0.0, 0.15)

## AD 权威崩塌：提案者公开违背自己推动的规则 → 目击者的权威/可靠证据双降
static func authority_violation(observer: Dictionary, violator: String, seq: int, tick: int) -> void:
	observer["tom"].add_evidence(violator, "authority_coordination", -1.0, 0.4, seq, tick)
	observer["tom"].add_evidence(violator, "reliable", -1.0, 0.25, seq, tick)

## 领域权威查询（每人不同：薇拉认为卡德加建筑权威高，欧恩可能不这么认为）
static func perceived_authority(observer: Dictionary, other_id: String, domain: String) -> float:
	return observer["tom"].belief_about(other_id, "authority_" + domain)
