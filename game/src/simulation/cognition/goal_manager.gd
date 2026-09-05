class_name GoalManager
extends RefCounted
## 目标管理器（P0-3）：角色同时持有多个目标，有优先级和进展追踪。
## Goal ≠ Intention：Goal 是"我想要什么"（可多个并存），Intention 是"我已决定正在做什么"（同时只有一个）。
## 目标来自需求+信念+人生经历——不是开发者写死的任务。

var goals: Array = [] # [{ "id": str, "desc": str, "priority": float, "progress": float, "active": bool, "source": str }]

func add_goal(id: String, desc: String, priority: float, source: String = "need") -> void:
	if has_goal(id):
		return
	goals.append({
		"id": id, "desc": desc,
		"priority": clampf(priority, 0.0, 1.0),
		"progress": 0.0, "active": true, "source": source,
	})

func has_goal(id: String) -> bool:
	for g in goals:
		if str(g["id"]) == id:
			return true
	return false

func remove_goal(id: String) -> void:
	for i in range(goals.size() - 1, -1, -1):
		if str(goals[i]["id"]) == id:
			goals.remove_at(i)

func complete_goal(id: String) -> void:
	for g in goals:
		if str(g["id"]) == id:
			g["active"] = false
			g["progress"] = 1.0

func update_progress(id: String, delta: float) -> void:
	for g in goals:
		if str(g["id"]) == id:
			g["progress"] = clampf(float(g["progress"]) + delta, 0.0, 1.0)

## 最高优先级的活跃目标
func top_goal() -> Dictionary:
	var best: Dictionary = {}
	var best_p := -1.0
	for g in goals:
		if bool(g["active"]) and float(g["priority"]) > best_p:
			best_p = float(g["priority"])
			best = g
	return best

## 根据需求自动产生/清理目标（Utility AI 的上游）
static func auto_generate(actor: Dictionary) -> GoalManager:
	var gm := GoalManager.new()
	var needs: Dictionary = actor.get("needs", {})
	var p: PersonalityProfile = actor.get("personality", null)
	if p == null:
		return gm

	# 饥饿 → 找食物
	var hunger: float = float(needs.get("hunger", 0)) / 1000.0
	if hunger > 0.4:
		gm.add_goal("find_food", "寻找食物", 0.9, "need")
	# 口渴 → 找水
	var thirst: float = float(needs.get("thirst", 0)) / 1000.0
	if thirst > 0.4:
		gm.add_goal("find_water", "寻找水源", 0.95, "need")
	# 疲劳 → 休息
	var energy: float = float(needs.get("energy", 1000)) / 1000.0
	if energy < 0.3:
		gm.add_goal("rest", "休息恢复体力", 0.8, "need")
	# 孤独 → 社交
	var social: float = float(needs.get("social", 0)) / 1000.0
	if social > 0.5:
		gm.add_goal("socialize", "找人交流", 0.6 * float(p.traits.get("sociability", 0.5)) + 0.2, "need")
	# 好奇心 → 探索
	var curiosity := p.effective_trait("curiosity", needs)
	if curiosity > 0.6:
		gm.add_goal("explore", "探索未知区域", 0.4 * curiosity, "personality")
	# 谨慎 → 建庇护所
	var caution := p.effective_trait("caution", needs)
	if caution > 0.6:
		gm.add_goal("shelter", "搭建庇护所", 0.5 * caution, "personality")

	return gm

func snapshot() -> Array:
	return goals.duplicate(true)
