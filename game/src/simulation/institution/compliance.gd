class_name ComplianceSystem
extends RefCounted
## P2c/d 合规系统（P2.1 加固版）：
## 六项独立输入——我认识规则 / 我信大家期待 / 我信大家实际会守 / 检测概率 /
## 执行概率(给定被发现) / 制裁严重度 / 合法性 / 个人得失。
## 禁止 shared_expectation 同时承担 recognition 与 expectation 双职责（P2.1 第 1 条）。
## 制裁期望 = P(detected) × P(enforced|detected) × ExpectedSeverity（第 4 条）。
## 执行学习 = 预测误差比例更新（第 6 条），不是固定 ±。

## 规则价值映射（第 5 条）：规则语义 → 相关个人价值。语义通用，零专属函数。
const RULE_VALUE_MAPPING := {
	"CONTRIBUTE": {"sharing": 1.0, "reciprocity": 0.5, "self_reliance": -0.7},
	"OBEY": {"self_reliance": 0.3, "reciprocity": 0.4},
	"DISCLOSE": {"reciprocity": 0.8, "self_reliance": -0.2},
}

## PerceivedInstitution 正式结构（第 2 条）：各字段独立演化，绝不联动同步
static func perceived_institution(actor: Dictionary, rid: String) -> Dictionary:
	var pgb: Dictionary = actor.get("perceived_group_beliefs", {})
	if not pgb.has(rid):
		return {}
	var b: Dictionary = pgb[rid]
	# 缺省字段补全（结构升级兼容）
	if not b.has("recognition"):
		b["recognition"] = 0.5          # 我知道这条规则存在（≠期待大家守）
	if not b.has("descriptive_compliance"):
		b["descriptive_compliance"] = 0.5  # 我信大家实际会守（≠应该守）
	if not b.has("sanction_severity"):
		b["sanction_severity"] = 0.4    # 被罚有多痛
	return b

## 我知道的、对此资源有效的规则：只看 recognition（第 1 条修复）
static func active_rule_id(actor: Dictionary, object_id: String) -> String:
	for rid in actor.get("perceived_group_beliefs", {}):
		var b := perceived_institution(actor, str(rid))
		if str(b["rule"].get("object", "")) == object_id and float(b["recognition"]) > 0.5:
			return str(rid)
	return ""

## 合规决策：六项独立输入链
static func decide_on_acquisition(actor: Dictionary, object_id: String, amount: int) -> Dictionary:
	var rid := active_rule_id(actor, object_id)
	if rid == "":
		return {"mode": "NONE", "contribute": 0}
	var b := perceived_institution(actor, rid)
	var rule: Dictionary = b["rule"]
	var fraction: float = float(rule.get("fraction", 0.5))
	var need: float = clampf(float(actor.get("needs", {}).get(str(ResourceSpec.spec(object_id)["need"]), 0)) / 1000.0, 0.0, 1.0)
	# 独立输入：
	var shared_exp: float = float(b.get("shared_expectation", 0.0))     # 我信"我们都认同"
	var desc_compliance: float = float(b.get("descriptive_compliance", 0.5))  # 我信大家实际会守
	var detection := estimate_detection(actor)
	var enforced_given: float = float(b.get("perceived_enforcement", 0.5))
	var severity: float = float(b.get("sanction_severity", 0.4))
	var legitimacy := legitimacy_of(actor, rid, object_id)
	# 制裁期望成本（三因子分离，第 4 条）
	var sanction_cost := detection * enforced_given * severity
	var comply_will := legitimacy * 0.3 + shared_exp * 0.2 + desc_compliance * 0.2 + sanction_cost - need * 0.5
	var mode := "COMPLY" if comply_will >= 0.25 else ("PARTIAL" if comply_will >= 0.0 else "VIOLATE")
	var contribute := 0
	if mode == "COMPLY":
		contribute = maxi(1, int(round(float(amount) * fraction)))
	elif mode == "PARTIAL":
		contribute = maxi(0, int(round(float(amount) * fraction * 0.4)))
	return {"mode": mode, "contribute": contribute, "rule_id": rid}

static func estimate_detection(actor: Dictionary) -> float:
	var nearby: Array = actor.get("others_nearby", [])
	return clampf(0.15 + float(nearby.size()) * 0.3, 0.0, 0.95)

## 合法性（语义通用，第 5 条）：按规则 prescribed 动作查价值映射
static func legitimacy_of(actor: Dictionary, rid: String, object_id: String) -> float:
	var b := perceived_institution(actor, rid)
	if b.is_empty():
		return 0.0
	var rule: Dictionary = b["rule"]
	var values: Dictionary = RULE_VALUE_MAPPING.get(str(rule.get("prescribed", "CONTRIBUTE")), {"sharing": 1.0})
	var personal: Dictionary = actor.get("norms", {}).get("personal", {})
	var alignment := 0.0
	var wsum := 0.0
	for v in values:
		alignment += (float(personal.get(v, 0.5)) - 0.5) * float(values[v])
		wsum += absf(float(values[v]))
	var base := clampf(0.5 + alignment / maxf(wsum, 0.1), 0.0, 1.0)  # 中性价值=0.5；带符号：自立高→共享规则合法性降
	var proposer_trust: float = 0.0
	if actor.has("_relationships_hint") and actor["_relationships_hint"] != null:
		proposer_trust = clampf(float(actor["_relationships_hint"].composite_trust(str(actor.get("id", "")), str(rule.get("proposer", "")))) / 600.0, -0.5, 0.5)
	return clampf(base + proposer_trust, 0.0, 1.0)

## 执行反应（公共品困境不变）
static func react_to_violation(observer: Dictionary, violator_id: String, rid: String) -> Dictionary:
	var p: PersonalityProfile = observer.get("personality", null)
	if p == null:
		return {"reaction": "IGNORE", "reason": ""}
	var b := perceived_institution(observer, rid)
	var legitimacy: float = float(b.get("legitimacy", legitimacy_of(observer, rid, str(b.get("rule", {}).get("object", "food")))))
	b["legitimacy"] = legitimacy
	var conflict_avoid := p.effective_trait("conflict_avoidance", observer.get("needs", {}))
	var courage := p.effective_trait("action_bias", observer.get("needs", {}))
	var confront_will := legitimacy * 0.6 + courage * 0.3 - conflict_avoid * 0.5
	var bene: int = 0
	if observer.has("_relationships_hint") and observer["_relationships_hint"] != null:
		bene = observer["_relationships_hint"].get_dim(str(observer.get("id", "")), violator_id, "benevolence")
	confront_will -= clampf(float(bene) / 1000.0, 0.0, 0.5) * 0.3
	return {"reaction": "CONFRONT" if confront_will > 0.25 else "IGNORE", "reason": ""}

## 执行学习（第 6 条）：预测误差比例更新——预测 0.8 实际 0 的修正远大于预测 0.2
static func learn_enforcement(actor: Dictionary, rid: String, sanctioned: bool, tick: int) -> void:
	var pgb: Dictionary = actor.get("perceived_group_beliefs", {})
	if not pgb.has(rid):
		return
	var b := perceived_institution(actor, rid)
	var predicted: float = float(b.get("perceived_enforcement", 0.5))
	var actual := 1.0 if sanctioned else 0.0
	var error := actual - predicted
	var rate := clampf(0.3 + absf(error) * 0.3, 0.1, 0.7)  # 误差越大学得越快
	b["perceived_enforcement"] = clampf(predicted + rate * error, 0.05, 1.0)
	b["last_enforcement_tick"] = tick
	# P2.1.1：处罚与否≠大家守不守——descriptive_compliance 只从目击遵守/违规学习（observe_compliance），此处解耦

## P2.1.1：遵守观察链（独立于执法链）——目击贡献/违规 → 描述性遵守期望
static func observe_compliance(actor: Dictionary, rid: String, complied: bool, tick: int) -> void:
	var pgb: Dictionary = actor.get("perceived_group_beliefs", {})
	if not pgb.has(rid):
		return
	var b := perceived_institution(actor, rid)
	var cur: float = float(b.get("descriptive_compliance", 0.5))
	b["descriptive_compliance"] = clampf(cur + (0.15 if complied else -0.15), 0.05, 1.0)

static func should_amend(actor: Dictionary, rid: String) -> bool:
	var b := perceived_institution(actor, rid)
	if b.is_empty():
		return false
	return float(b.get("perceived_enforcement", 0.5)) < 0.35 and float(b.get("legitimacy", 0.5)) < 0.5

static func violation_evidence_weight(observer_dyn: Dictionary) -> float:
	return clampf(0.3 + float(observer_dyn.get("betrayal_learning_rate", 0.4)) * 0.3, 0.0, 0.8)
