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
	current_intention = {
		"action": str(action.get("action", "wait")),
		"desc": str(action.get("desc", "")),
		"target": action.get("target", null),
		"commitment": 0.8, # 初始承诺度
		"started_tick": tick,
		"utility": float(action.get("utility", 0.0)),
	}

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
