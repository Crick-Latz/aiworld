class_name ComplianceSystem
extends RefCounted
## P2c/d 遵守·违规·检测·执行·合法性（Institutional Cognition 第三四层）
##
## 核心原则（GPT 第十六/二十二条）：
##   禁止 rule_exists → obey_bonus。行为路径必须是：
##   我信规则存在 → 我信他人期望我遵守 → 我估计被抓概率 → 我估计处罚
##   → 我评合法性 → 我评个人得失 → 我决定
##   执行是公共品：大家都知道有人违规但没人管，必须能自然发生。
##   违规可隐藏：世界知道 ≠ 人人知道（感知门天然支持——事件只被附近者目击）。

## 获取资源时的合规决策。返回 {mode: COMPLY/PARTIAL/VIOLATE, contribute: int}
## mode 由 认知链 决定，绝无 rule_exists 直通。
static func decide_on_acquisition(actor: Dictionary, object_id: String, amount: int) -> Dictionary:
	var rid := active_rule_id(actor, object_id)
	if rid == "":
		return {"mode": "NONE", "contribute": 0}  # 我不知道有任何规则（认知里没有）
	var b: Dictionary = actor["perceived_group_beliefs"][rid]
	var rule: Dictionary = b["rule"]
	var fraction: float = float(rule.get("fraction", 0.5))
	var need: float = clampf(float(actor.get("needs", {}).get(str(ResourceSpec.spec(object_id)["need"]), 0)) / 1000.0, 0.0, 1.0)
	# 认知链（十六条件路径的压缩实现，各项独立可溯）：
	var belief_exists: float = float(b.get("shared_expectation", 0.0))       # 我信"我们都认同"
	var legitimacy: float = legitimacy_of(actor, rid, object_id)              # 我认不认同
	var detection := estimate_detection(actor)                                # 我估被抓概率
	var enforcement: float = float(b.get("perceived_enforcement", 0.5))       # 我估会被罚
	var sanction_risk := detection * enforcement * 0.6
	# 遵守意愿 = 认同 + 社会期望 + 制裁风险 − 生存压力（饿到极限的人什么都做得出来）
	var comply_will := legitimacy * 0.4 + belief_exists * 0.3 + sanction_risk - need * 0.5
	var mode := "COMPLY"
	if comply_will < 0.0:
		mode = "VIOLATE"
	elif comply_will < 0.25:
		mode = "PARTIAL"
	var contribute := 0
	if mode == "COMPLY":
		contribute = maxi(1, int(round(float(amount) * fraction)))
	elif mode == "PARTIAL":
		contribute = maxi(0, int(round(float(amount) * fraction * 0.4)))
	return {"mode": mode, "contribute": contribute, "rule_id": rid}

## 检测估计：附近有人（我感知到的）→ 高；独处 → 低（隐藏违规的来源）
static func estimate_detection(actor: Dictionary) -> float:
	var nearby: Array = actor.get("others_nearby", [])
	return clampf(0.15 + float(nearby.size()) * 0.3, 0.0, 0.95)

## 合法性（每人每规则独立）：个人价值对齐 + 提案者信任 − 负担
static func legitimacy_of(actor: Dictionary, rid: String, object_id: String) -> float:
	var b: Dictionary = actor.get("perceived_group_beliefs", {}).get(rid, {})
	if b.is_empty():
		return 0.0
	var personal: float = float(actor.get("norms", {}).get("personal", {}).get("sharing", 0.5))
	var base := clampf(personal * 0.8 + 0.1, 0.0, 1.0)
	# 提案者关系（讨厌提案者→合法性降，GPT 第二十五条件）
	var proposer_trust: float = 0.0
	if actor.has("_relationships_hint") and actor["_relationships_hint"] != null:
		proposer_trust = clampf(float(actor["_relationships_hint"].composite_trust(str(actor.get("id", "")), str(b["rule"].get("proposer", "")))) / 600.0, -0.5, 0.5)
	return clampf(base + proposer_trust, 0.0, 1.0)

## 我知道的、对此资源有效的规则（认知里没有 = 不存在，测试 V 的延续）
static func active_rule_id(actor: Dictionary, object_id: String) -> String:
	for rid in actor.get("perceived_group_beliefs", {}):
		var b: Dictionary = actor["perceived_group_beliefs"][rid]
		if str(b["rule"].get("object", "")) == object_id and float(b.get("shared_expectation", 0.0)) > 0.35:
			return str(rid)
	return ""

## ── P2d 目击违规后的反应：执行是公共品（管不管都有成本）──
## 返回 {reaction: CONFRONT/IGNORE, reason}——由人格与关系决定
static func react_to_violation(observer: Dictionary, violator_id: String, rid: String) -> Dictionary:
	var p: PersonalityProfile = observer.get("personality", null)
	if p == null:
		return {"reaction": "IGNORE", "reason": ""}
	var b: Dictionary = observer.get("perceived_group_beliefs", {}).get(rid, {})
	var legitimacy: float = float(b.get("legitimacy", legitimacy_of(observer, rid, str(b.get("rule", {}).get("object", "food")))))
	b["legitimacy"] = legitimacy  # 缓存
	var conflict_avoid := p.effective_trait("conflict_avoidance", observer.get("needs", {}))
	var courage := p.effective_trait("action_bias", observer.get("needs", {}))
	# 面子成本 vs 公共品收益：怕冲突者更可能沉默（"大家都知道但没人管"）
	var confront_will := legitimacy * 0.6 + courage * 0.3 - conflict_avoid * 0.5
	# 关系折扣：不愿当众指责亲近之人
	var bene: int = 0
	if observer.has("_relationships_hint") and observer["_relationships_hint"] != null:
		bene = observer["_relationships_hint"].get_dim(str(observer.get("id", "")), violator_id, "benevolence")
	confront_will -= clampf(float(bene) / 1000.0, 0.0, 0.5) * 0.3
	return {"reaction": "CONFRONT" if confront_will > 0.25 else "IGNORE", "reason": ""}

## ── P2d-3 PerceivedEnforcement 学习（测试 Y）：违规→被罚？→ 期望更新 ──
static func learn_enforcement(actor: Dictionary, rid: String, sanctioned: bool, tick: int) -> void:
	var pgb: Dictionary = actor.get("perceived_group_beliefs", {})
	if not pgb.has(rid):
		return
	var b: Dictionary = pgb[rid]
	var cur: float = float(b.get("perceived_enforcement", 0.5))
	b["perceived_enforcement"] = clampf(cur + (0.25 if sanctioned else -0.12), 0.05, 1.0)
	b["last_enforcement_tick"] = tick

## ── P2d-5 修订触发（测试 AA）：违规多 + 合法性低 → 修规则目标 ──
static func should_amend(actor: Dictionary, rid: String) -> bool:
	var b: Dictionary = actor.get("perceived_group_beliefs", {}).get(rid, {})
	if b.is_empty():
		return false
	var enforcement: float = float(b.get("perceived_enforcement", 0.5))
	var legitimacy: float = float(b.get("legitimacy", 0.5))
	return enforcement < 0.35 and legitimacy < 0.5

## 违规对目击者的认知冲击（经既有管线：可靠度证据 + 敌意倾向）
static func violation_evidence_weight(observer_dyn: Dictionary) -> float:
	return clampf(0.3 + float(observer_dyn.get("betrayal_learning_rate", 0.4)) * 0.3, 0.0, 0.8)
