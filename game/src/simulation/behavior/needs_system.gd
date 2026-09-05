class_name NeedsSystem
extends RefCounted
## NPC 需求系统（阶段 A，M06 扩展）：hunger/energy/social 数值衰减与效用计算。
## 每 tick：hunger+1（越饿越高）、energy-1（越累越低）、social+1（越孤越高）。
## 需求超过阈值时产生压倒性目标（吃饭/休息/找人聊天）。
## 所有数值 0~1000 整数，确定性衰减，不影响 04 号规格的 seed 派生。

const HUNGER_WARN := 700
const ENERGY_WARN := 250
const SOCIAL_WARN := 700
const EAT_RECOVERY := 500
const REST_RECOVERY := 400
const TALK_RECOVERY := 250

## 每 tick 衰减；返回本 tick 因需求产生的压倒性活动（""=无）
static func tick_needs(actor: Dictionary) -> String:
	if not actor.has("needs"):
		return ""
	var n: Dictionary = actor["needs"]
	n["hunger"] = clampi(int(n.get("hunger", 0)) + 1, 0, 1000)
	n["energy"] = clampi(int(n.get("energy", 1000)) - 1, 0, 1000)
	n["social"] = clampi(int(n.get("social", 0)) + 1, 0, 1000)
	# 需求阈值 → 压倒性活动
	if int(n["hunger"]) >= HUNGER_WARN and actor.get("activity", "") != "eating":
		return "seek_food"
	if int(n["energy"]) <= ENERGY_WARN and actor.get("activity", "") != "resting":
		return "seek_rest"
	if int(n["social"]) >= SOCIAL_WARN and actor.get("activity", "") != "talking":
		return "seek_social"
	return ""

## 效用计算：多目标竞争时的优先级分数（整数，确定性）
static func utility_score(actor: Dictionary, action: String, target_dist: int) -> int:
	var n: Dictionary = actor.get("needs", {})
	var base := 100
	match action:
		"eat":
			base = 200 + int(n.get("hunger", 0)) / 2
		"rest":
			base = 200 + (1000 - int(n.get("energy", 1000))) / 2
		"talk":
			base = 150 + int(n.get("social", 0)) / 3
		"work":
			base = 120 # 工作有固定价值但低于紧急需求
		"inspect":
			base = 100
		"move":
			base = 80
	return base - target_dist * 2 # 距离惩罚

static func recover(actor: Dictionary, need: String) -> void:
	if not actor.has("needs"):
		return
	match need:
		"hunger":
			actor["needs"]["hunger"] = clampi(int(actor["needs"]["hunger"]) - EAT_RECOVERY, 0, 1000)
		"energy":
			actor["needs"]["energy"] = clampi(int(actor["needs"]["energy"]) + REST_RECOVERY, 0, 1000)
		"social":
			actor["needs"]["social"] = clampi(int(actor["needs"]["social"]) - TALK_RECOVERY, 0, 1000)
