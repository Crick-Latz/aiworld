class_name ConventionSystem
extends RefCounted
## P2a 约定涌现（Institutional Cognition 第一层）：
## 行为规律自己出现——没人提议规则，但"大家通常这么做"逐渐被每个 NPC
## 从【自己的局部观察】中提炼出来（PerceivedRegularity），并反过来影响行为。
##
## 禁止：if 70% agents share → global_norm = sharing（全局统计魔法）
## 每个 NPC 的 observed_regularities 只含自己目击/听说的事件。
##
## ConventionCandidate 语义通用：context=ACQUIRE(food)/ACQUIRE(water)/...，
## 未来任何资源/劳动/信息复用同一条链（禁止 FoodSharingConvention 这类具体类）。

const SAMPLES_NEEDED := 3        # 样本量门槛（少于此不成规律）
const PREVALENCE_THRESHOLD := 0.6  # 我看到的行为出现率超过此值 → 形成约定候选
const CONVENTION_CAP := 6

## 目击行为 → 规律登记。behavior_key 例："GIVE:food"、"REQUEST_REFUSED:food"
static func observe(actor: Dictionary, behavior_key: String, did_happen: bool, tick: int) -> void:
	var regs: Dictionary = actor.get("observed_regularities", {})
	if not regs.has(behavior_key):
		regs[behavior_key] = {"pro": 0, "total": 0, "first_tick": tick}
	regs[behavior_key]["pro"] = int(regs[behavior_key]["pro"]) + (1 if did_happen else 0)
	regs[behavior_key]["total"] = int(regs[behavior_key]["total"]) + 1
	actor["observed_regularities"] = regs
	_try_form_convention(actor, behavior_key, tick)

## 从规律形成约定候选（期望强度随出现率与样本量增长）
static func _try_form_convention(actor: Dictionary, behavior_key: String, tick: int) -> void:
	var r: Dictionary = actor.get("observed_regularities", {}).get(behavior_key, {})
	if int(r.get("total", 0)) < SAMPLES_NEEDED:
		return
	var prevalence: float = float(r["pro"]) / float(r["total"])
	if prevalence < PREVALENCE_THRESHOLD:
		return
	var convs: Array = actor.get("conventions", [])
	for c in convs:
		if str(c.get("behavior", "")) == behavior_key:
			c["prevalence"] = prevalence
			c["expectation"] = clampf(prevalence * (1.0 - 0.5 / float(r["total"])), 0.0, 1.0)
			c["tick"] = tick
			return
	if convs.size() >= CONVENTION_CAP:
		return
	# 个人偏好独立于观察（讨厌分享的人也能观察到"大家通常分享"）
	convs.append({
		"behavior": behavior_key,
		"prevalence": prevalence,
		"expectation": clampf(prevalence * (1.0 - 0.5 / float(r["total"])), 0.0, 1.0),
		"personal_preference": _personal_pref(actor, behavior_key),
		"tick": tick,
	})
	actor["conventions"] = convs

static func _personal_pref(actor: Dictionary, behavior_key: String) -> float:
	if behavior_key.begins_with("GIVE"):
		return float(actor.get("norms", {}).get("personal", {}).get("sharing", 0.5))
	return 0.5

## 我对某行为的期望强度（没观察过 → 0.5 中性）
static func expectation_of(actor: Dictionary, behavior_key: String) -> float:
	for c in actor.get("conventions", []):
		if str(c.get("behavior", "")) == behavior_key:
			return float(c.get("expectation", 0.5))
	return 0.5

## 约定 → 行为反馈：我对"大家通常分享"的期望，轻微提高我的分享效用
## （期望不是规则——低个人偏好者可以完全抵抗，见禁止事项 7）
static func share_utility_feedback(actor: Dictionary, object_id: String) -> float:
	var e := expectation_of(actor, "GIVE:" + object_id)
	return (e - 0.5) * 0.3

## 制度目标形成（P2b 入口）：约定与个人价值冲突 + 协调摩擦（被拒/争议）→ "我们需要个规矩"
static func should_seek_rule(actor: Dictionary, object_id: String, friction: float) -> bool:
	var e := expectation_of(actor, "GIVE:" + object_id)
	var pref := _personal_pref(actor, "GIVE:" + object_id)
	# 冲突条件：要么我看到大家分享但我不认同（被搭便车焦虑），
	# 要么我认同分享但看到大家都不分（协调失败）
	var conflict := absf(e - pref) > 0.25
	return conflict and friction > 0.35 and not _has_rule_goal(actor, object_id)

static func _has_rule_goal(actor: Dictionary, object_id: String) -> bool:
	for g in actor.get("institutional_goals", []):
		if str(g.get("object", "")) == object_id:
			return true
	return false
