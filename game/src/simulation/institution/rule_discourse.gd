class_name RuleDiscourse
extends RefCounted
## P2b 公共性与规则提议（Institutional Cognition 第二层）：
## 核心科研假设——制度的真正产生点不是"多数人支持"，
## 而是私人信念跨过 Publicness 变成 Shared Expectation 的那一刻：
##   "我知道你会这么做，而且我知道你知道我也会这么做。"
##
## PublicEvent：≥2 人共同目击的社会事件（提案/公开支持）——
## 与"分别私下告诉"强度完全不同。
## PerceivedGroupBelief：每个 NPC 对"其他人怎么看这条规则"的主观估计——
## 薇拉以为大家都知道 .88，欧恩可能以为只有 .41。绝不全局同步。

## 规则的结构化 Schema（自然语言只是 Renderer）
static func build_rule(proposer: String, object_id: String, fraction: float) -> Dictionary:
	return {
		"rule_id": "rule_%s_%d" % [object_id, int(fraction * 100)],
		"proposer": proposer,
		"condition": "ACQUIRE",
		"object": object_id,
		"prescribed": "CONTRIBUTE",
		"fraction": fraction,
	}

## 提案条件：制度目标存在 + 火边有同伴（公共讨论需要共同在场）
static func can_propose(actor: Dictionary, world: Dictionary) -> bool:
	var goals: Array = actor.get("institutional_goals", [])
	if goals.is_empty():
		return false
	var nearby: Array = actor.get("others_nearby", [])
	return nearby.size() >= 1  # 至少一人在场——没有公众就没有 PublicEvent

## 目击公开支持/反对 → 更新我的 PerceivedGroupBelief（shared expectation 的来源）
## publicity：公开表态（多人在场）权重远大于私下说（传话经 Claim 通道，这里只处理公开）
static func witness_stance(actor: Dictionary, rule: Dictionary, speaker: String, stance: int, public_witnesses: int, tick: int) -> void:
	var rid := str(rule.get("rule_id", ""))
	var pgb: Dictionary = actor.get("perceived_group_beliefs", {})
	if not pgb.has(rid):
		pgb[rid] = {
			"rule": rule,
			"member_stance": {},       # 我以为每个人的立场
			"publicity": 0.0,          # 我以为多少人知道这场讨论
			"shared_expectation": 0.0, # 我以为"我们都认同"的程度
				"recognition": 1.0,       # 我知道这条规则存在（P2.1 与期待分离）
			"last_tick": -1,
		}
	var b: Dictionary = pgb[rid]
	var val := 1.0 if stance > 0 else (-1.0 if stance < 0 else 0.0)
	b["member_stance"][speaker] = val
	# 公开度：目击者越多，我越确信"大家都知道"
	b["publicity"] = clampf(float(b["publicity"]) + 0.2 * public_witnesses, 0.0, 1.0)
	# 共同期望：支持者比例 × 公开度（"我知道你支持，也知道大家都知道"）
	var stances: Array = b["member_stance"].values()
	var sum := 0.0
	for s in stances:
		sum += float(s)
	var avg: float = sum / maxf(float(stances.size()), 1.0)
	b["shared_expectation"] = clampf((avg + 1.0) * 0.5 * float(b["publicity"]), 0.0, 1.0)
	b["last_tick"] = tick
	actor["perceived_group_beliefs"] = pgb

## 我自己表态也写入（我知道我自己的立场）
static func self_stance(actor: Dictionary, rule: Dictionary, stance: int, public_witnesses: int, tick: int) -> void:
	witness_stance(actor, rule, str(actor.get("id", "")), stance, public_witnesses, tick)

## 对提案的立场评估（P2 第十一条）：个人价值×预期他人遵守×与提案者关系×预期执行
## 返回 {stance: -1/0/1, counter_fraction: float, reason}
static func evaluate_proposal(actor: Dictionary, rule: Dictionary, relationships) -> Dictionary:
	var object_id := str(rule.get("object", "food"))
	var fraction: float = float(rule.get("fraction", 0.5))
	var p: PersonalityProfile = actor.get("personality", null)
	if p == null:
		return {"stance": 0, "counter_fraction": fraction, "reason": "?"}
	var personal: float = float(actor.get("norms", {}).get("personal", {}).get("sharing", 0.5))
	# 预期他人遵守：来自我对大家的约定观察
	var expected_compliance := ConventionSystem.expectation_of(actor, "GIVE:" + object_id)
	# 饥荒经历者可能认为统一储备更安全（个人资源保护 vs 集体稳定冲突）
	var scarcity_sens: float = float(actor.get("sensitivities", {}).get("food_loss_sensitivity", 0.0))
	var collective_security := scarcity_sens * 0.3
	# 负担感：上交比例越高，越抗拒（除非集体安全动机强）
	var burden := clampf(fraction * 1.2 - collective_security, 0.0, 1.0)
	# 与提案者关系
	var proposer_trust := 0.0
	if relationships != null:
		proposer_trust = clampf(float(relationships.composite_trust(str(actor.get("id", "")), str(rule.get("proposer", "")))) / 400.0, -1.0, 1.0)
	var score := personal * 0.4 + expected_compliance * 0.25 + proposer_trust * 0.2 + collective_security - burden * 0.5
	var stance := 1 if score > 0.15 else (-1 if score < -0.15 else 0)
	# 反提案：不接受但也不彻底拒绝 → 谈判（更低比例）
	var counter := clampf(fraction * 0.5, 0.1, 0.5)
	return {"stance": stance, "counter_fraction": counter, "reason": "太重了" if stance < 0 else "有道理"}
