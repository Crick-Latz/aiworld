class_name IntentionManager
extends RefCounted
## 意图承诺系统（阶段 C，BDI Intention）：NPC 不应该每个 tick 重新算一遍所有行为。
## 人形成"我已经决定做什么"的承诺，然后持续执行，除非出现足够大的原因打断。
## 这解决了"NPC 像机器一样每秒换主意"的问题。

var current_intention: Dictionary = {} # { "action": str, "commitment": float, "started_tick": int, "target": Vector2i }
var switching_threshold := 0.15 # 新选项要超过当前承诺 + 此值才切换

func has_intention() -> bool:
	return not current_intention.is_empty()

func set_intention(action: Dictionary, tick: int) -> void:
	# 意图保留完整执行载荷；不与 Registry/调用者共享可变字典。
	current_intention = action.duplicate(true)
	current_intention["commitment"] = 0.8
	current_intention["started_tick"] = tick

## 仅匹配本次 actor-facing Registry 候选，不读取世界真值。
## 展示/时长/效用不是身份；其余执行字段（配方、对象、地点、数量等）必须相同。
func matching_candidate(candidates: Array) -> Dictionary:
	var identity := _execution_identity(current_intention)
	for candidate in candidates:
		if identity == _execution_identity(candidate):
			return candidate
	return {}

static func _execution_identity(action: Dictionary) -> Dictionary:
	var identity := action.duplicate(true)
	for key in ["utility", "desc", "duration", "commitment", "started_tick"]:
		identity.erase(key)
	return identity

func continue_action(candidate: Dictionary) -> Dictionary:
	var previous := current_intention
	current_intention = candidate.duplicate(true)
	# 承诺历史延续，但效用必须来自当前候选，不能冻结饥饿等旧状态。
	for key in ["commitment", "started_tick"]:
		current_intention[key] = previous[key]
	reinforce()
	return current_intention.duplicate(true)

func clear_intention() -> void:
	current_intention = {}

## 决定是否切换：新效用 > 当前效用 + 阈值 时才换
## commitment_strength 来自人格（高韧性的人更不容易换）
func should_switch(new_action: Dictionary, personality: PersonalityProfile) -> bool:
	if not has_intention():
		return true
	var commitment_strength: float = personality.traits.get("resilience", 0.5)
	var effective_threshold := switching_threshold * (0.5 + commitment_strength)
	var new_util := float(new_action.get("utility", 0.0))
	var current_util := float(current_intention.get("utility", 0.0))
	return new_util > current_util + effective_threshold

## 执行意图时增加承诺度（越做越坚定）
func reinforce() -> void:
	if has_intention():
		current_intention["commitment"] = clampf(float(current_intention["commitment"]) + 0.05, 0.0, 1.0)

## 强制中断（危险/重大信息/情绪冲击/资源危机）
func force_interrupt(reason: String) -> void:
	if has_intention():
		current_intention = {}
