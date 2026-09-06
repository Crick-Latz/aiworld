class_name ActionRegistry
extends RefCounted
## 行动清单（阶段 B）：NPC 可选的所有行为。
## 每个"行动构建器"返回一个行动字典或 null（不可用）。
## 没有 `-> Dictionary` 类型标注是因为条件路径返回 null 是合法的。

static func get_available_actions(actor: Dictionary, world: Dictionary) -> Array:
	var actions: Array = []
	var p: PersonalityProfile = actor.get("personality", null)
	if p == null:
		return actions
	var needs: Dictionary = actor.get("needs", {})
	var phys: Dictionary = actor.get("physical", {})
	var inv: Dictionary = actor.get("inventory", {})
	var pos: Vector2i = actor.get("tile", Vector2i.ZERO)

	var a1 = _forage(p, needs, inv, pos, world)
	if a1 != null: actions.append(a1)
	var a2 = _drink(p, needs, pos, world)
	if a2 != null: actions.append(a2)
	var a3 = _fish(p, needs, inv, pos, world)
	if a3 != null: actions.append(a3)
	var a4 = _shells(p, needs, pos, world)
	if a4 != null: actions.append(a4)
	var a5 = _shelter(p, phys, inv, pos, world)
	if a5 != null: actions.append(a5)
	var a6 = _craft(p, phys, inv, pos, world)
	if a6 != null: actions.append(a6)
	var a7 = _fire(p, phys, inv, pos, world)
	if a7 != null: actions.append(a7)
	var a8 = _explore(p, needs, pos, world, actor)
	if a8 != null: actions.append(a8)
	var a9 = _ruins(p, needs, pos, world)
	if a9 != null: actions.append(a9)
	var a10 = _socialize(p, needs, actor, world)
	if a10 != null: actions.append(a10)
	var a11 = _share(p, needs, inv, pos, world)
	if a11 != null: actions.append(a11)
	for a13 in _request(p, needs, actor, world):
		actions.append(a13)
	var a19 = _repay_debt(p, actor, world)
	if a19 != null: actions.append(a19)
	var a18 = _epistemic_actions(p, actor, world)
	for ea in a18: actions.append(ea)
	var a16 = _gather_wood(p, needs, inv, pos, world)
	if a16 != null: actions.append(a16)
	var a17 = _sit_by_fire(p, needs, pos, world)
	if a17 != null: actions.append(a17)
	var a15 = _keep_distance(p, actor)
	if a15 != null: actions.append(a15)
	var a14 = _eat(p, needs, inv)
	if a14 != null: actions.append(a14)
	var a12 = _rest(p, needs)
	if a12 != null: actions.append(a12)
	actions.append(_wait())
	return actions

static func _forage(p: PersonalityProfile, needs: Dictionary, inv: Dictionary, pos: Vector2i, world: Dictionary):
	var bushes: Array = world.get("resources", {}).get("berry_bushes", [])
	if bushes.is_empty():
		return null
	var nearest: Vector2i = _nearest(pos, bushes)
	if nearest.x < 0:
		return null
	var hunger := _n(needs.get("hunger", 0), 200, 800)
	var prag := p.effective_trait("pragmatism", needs)
	var score := UtilityCurves.quadratic(hunger) * (0.6 + prag * 0.4) * _dp(pos, nearest)
	return {"action": "forage_berries", "target": nearest, "utility": score, "desc": "去采浆果", "duration": 1}

static func _drink(p: PersonalityProfile, needs: Dictionary, pos: Vector2i, world: Dictionary):
	var springs: Array = world.get("resources", {}).get("water_springs", [])
	if springs.is_empty():
		return null
	var nearest: Vector2i = _nearest(pos, springs)
	if nearest.x < 0:
		return null
	var thirst := _n(needs.get("thirst", 0), 300, 800)
	var score := UtilityCurves.exponential(thirst, 6.0) * _dp(pos, nearest)
	return {"action": "drink_water", "target": nearest, "utility": score, "desc": "去喝水", "duration": 1}

static func _fish(p: PersonalityProfile, needs: Dictionary, inv: Dictionary, pos: Vector2i, world: Dictionary):
	if int(inv.get("fish_spear", 0)) < 1:
		return null
	var spots: Array = world.get("resources", {}).get("fish_spots", [])
	if spots.is_empty():
		return null
	var nearest: Vector2i = _nearest(pos, spots)
	if nearest.x < 0:
		return null
	var hunger := _n(needs.get("hunger", 0), 300, 800)
	var action := p.effective_trait("action_bias", needs)
	var score := UtilityCurves.quadratic(hunger) * (0.7 + action * 0.3) * _dp(pos, nearest)
	return {"action": "fish", "target": nearest, "utility": score, "desc": "去捕鱼", "duration": 2}

static func _shells(p: PersonalityProfile, needs: Dictionary, pos: Vector2i, world: Dictionary):
	var beaches: Array = world.get("resources", {}).get("shell_beaches", [])
	if beaches.is_empty():
		return null
	var nearest: Vector2i = _nearest(pos, beaches)
	if nearest.x < 0:
		return null
	var curiosity := p.effective_trait("curiosity", needs)
	var hunger := _n(needs.get("hunger", 0), 400, 800)
	var score := (0.3 + curiosity * 0.4 + hunger * 0.12) * _dp(pos, nearest)
	return {"action": "gather_shells", "target": nearest, "utility": score, "desc": "去捡贝壳", "duration": 1}

static func _shelter(p: PersonalityProfile, phys: Dictionary, inv: Dictionary, pos: Vector2i, world: Dictionary):
	if int(inv.get("wood", 0)) < 2:
		return null
	if world.get("shelters", {}).get(str(pos), false):
		return null
	var prag := p.effective_trait("pragmatism", phys)
	var caution := p.effective_trait("caution", phys)
	var fear: float = p.emotions.get("fear", 0.0)
	var score := 0.3 + prag * 0.3 + caution * 0.2 + fear * 0.3
	return {"action": "build_shelter", "target": pos, "utility": score, "desc": "搭建庇护所", "duration": 3}

static func _craft(p: PersonalityProfile, phys: Dictionary, inv: Dictionary, pos: Vector2i, world: Dictionary):
	if int(inv.get("shells", 0)) < 1 or int(inv.get("wood", 0)) < 1 or int(inv.get("fish_spear", 0)) > 0:
		return null
	var prag := p.effective_trait("pragmatism", phys)
	var curiosity := p.effective_trait("curiosity", phys)
	var score := 0.3 + prag * 0.3 + curiosity * 0.2
	return {"action": "craft_fish_spear", "target": pos, "utility": score, "desc": "制作鱼叉", "duration": 2}

static func _fire(p: PersonalityProfile, phys: Dictionary, inv: Dictionary, pos: Vector2i, world: Dictionary):
	if int(inv.get("wood", 0)) < 1:
		return null
	if world.get("fires", {}).get(str(pos), false):
		return null
	var fear: float = p.emotions.get("fear", 0.0)
	var darkness := 0.3 if world.get("is_night", false) else 0.0
	var score := 0.2 + fear * 0.3 + darkness
	return {"action": "make_fire", "target": pos, "utility": score, "desc": "生火", "duration": 1}

static func _explore(p: PersonalityProfile, needs: Dictionary, pos: Vector2i, world: Dictionary, actor: Dictionary):
	var curiosity := p.effective_trait("curiosity", needs)
	var fear: float = p.emotions.get("fear", 0.0)
	if fear > 0.7:
		return null
	var visited: Dictionary = actor.get("visited_tiles", {})
	var target := _pick_unvisited(pos, visited)
	if target.x < 0:
		return null
	# 习惯化：走过的路不再新鲜——探索欲随已知区域扩大自然衰减
	var novelty := 1.0 if not visited.has(str(target)) else 0.55
	var score := (0.2 + curiosity * 0.6) * _dp(pos, target) * novelty
	return {"action": "explore", "target": target, "utility": score, "desc": "探索未知区域", "duration": 1}

static func _ruins(p: PersonalityProfile, needs: Dictionary, pos: Vector2i, world: Dictionary):
	var ruins: Array = world.get("resources", {}).get("ruins", [])
	var unsearched: Array = []
	for r in ruins:
		if typeof(r) == TYPE_DICTIONARY and not bool(r.get("searched", false)):
			if typeof(r.get("pos", null)) == TYPE_VECTOR2I:
				unsearched.append(r["pos"])
	if unsearched.is_empty():
		return null
	var nearest: Vector2i = _nearest(pos, unsearched)
	if nearest.x < 0:
		return null
	var curiosity := p.effective_trait("curiosity", needs)
	var caution := p.effective_trait("caution", needs)
	var score := (0.3 + curiosity * 0.5 - caution * 0.2) * _dp(pos, nearest)
	return {"action": "search_ruins", "target": nearest, "utility": score, "desc": "搜索废弃营地", "duration": 2}

## 社交：孤独时主动走向同伴（不是原地干聊）——人的聚集是一切社交剧情的前提。
static func _socialize(p: PersonalityProfile, needs: Dictionary, actor: Dictionary, world: Dictionary):
	var social := _n(needs.get("social", 0), 300, 700)  # 孤独感更早生效——半天没说话就想找人
	var sociability := p.effective_trait("sociability", needs)
	var sadness: float = p.emotions.get("sadness", 0.0)
	var score := UtilityCurves.quadratic(social) * (0.4 + sociability * 0.6) + sadness * 0.2
	var pos: Vector2i = actor.get("tile", Vector2i.ZERO)
	var target := pos
	var nearby: Array = actor.get("others_nearby", [])
	if nearby.is_empty():
		# 附近没人：走向最近的同伴（孤独的人会去找人）
		var all: Array = actor.get("others_all", [])
		var nearest := _nearest(pos, all.map(func(o): return o.get("tile", pos)))
		if nearest.x >= 0:
			target = nearest
			score *= 0.8  # 要走过去，稍微降低点吸引力
	else:
		pass  # 人在身边（others_nearby 非空）＝聊天条件最好，无惩罚
		# 历史 bug：曾在此乘 0.3，但 someone_nearby 从未被设置——有人在场时社交被系统性压低
	return {"action": "socialize", "target": target, "utility": score, "desc": "找人聊天", "duration": 2}

static func _share(p: PersonalityProfile, needs: Dictionary, inv: Dictionary, pos: Vector2i, world: Dictionary):
	if int(inv.get("food", 0)) < 2:
		return null
	var altruism := p.effective_trait("altruism", needs)
	var empathy := p.effective_trait("empathy", needs)
	var hunger := _n(needs.get("hunger", 0), 300, 700)
	var generosity := altruism * 0.6 + empathy * 0.4
	var score := generosity * (1.0 - UtilityCurves.quadratic(hunger)) * 0.8
	if world.get("someone_hungry_nearby", false):
		score *= 1.5
	return {"action": "share_food", "target": pos, "utility": score, "desc": "分享食物", "duration": 1}

## P1.5：开口求助的效用 = 预测后果的期望效用（ActionForecaster），
## 不是"我现在多想求助"。预测错了（以为他会给，结果被拒）是故事。
## P1.6 泛化求助：所有资源（food/water/fish_spear）经 ResourceSpec 数据接入——
## 没有 resource-specific 分支，只有"挑最痛的需求×最可能给的人"。
static func _request(p: PersonalityProfile, needs: Dictionary, actor: Dictionary, world: Dictionary) -> Array:
	var out: Array = []
	var visible: Array = actor.get("others_visible", actor.get("others_nearby", []))
	if visible.is_empty():
		return out
	var trust_of: Dictionary = actor.get("trust_of", {})
	var recip: float = float(actor.get("norms", {}).get("personal", {}).get("reciprocity", 0.5))
	var inv: Dictionary = actor.get("inventory", {})
	for object_id in ResourceSpec.SPECS:
		var spec: Dictionary = ResourceSpec.SPECS[object_id]
		var need_raw := float(needs.get(str(spec["need"]), 0))
		var gate := float(spec["request_gate"])
		if bool(spec.get("is_tool", false)):
			if int(inv.get("fish_spear", 0)) >= 1:
				continue  # 有鱼叉的人不求鱼叉
			gate = 400.0  # 饿着又没工具时想借
		if need_raw < gate:
			continue

		# 自己能解决就不求人（公共资源距离门：水泉 8 格内自己走过去）
		if spec.has("self_source"):
			var sources: Array = world.get("resources", {}).get(str(spec["self_source"]), world.get(str(spec["self_source"]), []))
			if not sources.is_empty():
				var nearest_src := _nearest(actor.get("tile", Vector2i.ZERO), sources)
				if nearest_src.x >= 0 and absi(nearest_src.x - actor.get("tile", Vector2i.ZERO).x) + absi(nearest_src.y - actor.get("tile", Vector2i.ZERO).y) <= int(spec.get("self_serve_dist", 8)):
					continue
		var target_id := SocialSystem.pick_request_target(actor, visible, trust_of, str(spec["predicate"]))
		if target_id == "":
			continue
		var target_tile := Vector2i(10, 10)
		for o in visible:
			if str(o.get("id", "")) == target_id:
				target_tile = o.get("tile", target_tile)
		var need_norm := _n(need_raw, gate - 150.0, gate + 250.0)
		var score := ActionForecaster.request_expected_utility(actor, p, need_norm, target_id, str(spec["predicate"]))
		if score <= 0.0:
			continue
		var action_name: String = {"food": "request_share", "water": "request_water", "fish_spear": "request_tool"}.get(object_id, "request_share")
		out.append({"action": action_name, "target": target_tile, "target_actor": target_id, "object": object_id,
			"offers_promise": recip >= 0.55 and need_raw > gate + 100,
			"utility": score, "desc": "求" + str(spec["verb"]), "duration": 4})
	return out

## P1.6 还债：兑现承诺——这是互惠弧的闭环（help→promise→repay→reliability）
static func _repay_debt(p: PersonalityProfile, actor: Dictionary, world: Dictionary):
	var obligations: Array = actor.get("my_obligations", [])
	if obligations.is_empty():
		return null
	var inv: Dictionary = actor.get("inventory", {})
	for ob in obligations:
		var obj := str(ob.get("object", "food"))
		var spec: Dictionary = ResourceSpec.spec(obj)
		if int(inv.get(obj, 0)) >= int(spec["give_min"]) + 1:
			return {"action": "repay_debt", "target": null, "target_actor": str(ob.get("creditor", "")),
				"object": obj, "obligation": ob,
				"utility": 0.3 + float(actor.get("norms", {}).get("personal", {}).get("reciprocity", 0.5)) * 0.25,
				"desc": "兑现承诺", "duration": 1}
	return null

## P1.6 认识行动：行动目的不是改变世界，而是获取信息。
## ActionValue = λ_epi × InfoGain × stakes − SocialRisk×人格 − 时机成本。
## 薇拉（好奇+敢问）直问；欧恩（多疑+怕冲突）暗中观察；卡德加（圆融）问第三人。
## 「不弄清楚」也是合法选择——λ_epi 低的人根本不会产生这些行动。
static func _epistemic_actions(p: PersonalityProfile, actor: Dictionary, world: Dictionary) -> Array:
	var out: Array = []
	var qs: Array = actor.get("open_questions", [])
	var visible: Array = actor.get("others_visible", [])
	if qs.is_empty() or visible.is_empty():
		return out
	var dyn := PersonalityDynamics.dynamics(p, actor.get("sensitivities", {}), actor.get("norms", {}))
	var drive: float = float(dyn["epistemic_drive"]) - float(dyn["uncertainty_tolerance"]) * 0.2
	if drive <= 0.2:
		return out  # 务实的人不在乎为什么——不确定是可忍受的
	var conflict: float = p.effective_trait("conflict_avoidance", actor.get("needs", {}))
	var sociability: float = p.effective_trait("sociability", actor.get("needs", {}))
	var q0: Dictionary = qs[0]
	var about := str(q0.get("about", ""))
	var stakes: float = float(q0.get("stakes", 0.5))
	var entropy: float = float(q0.get("entropy", 0.5))
	var about_visible := false
	var other_visible := ""
	for o in visible:
		var oid := str(o.get("id", ""))
		if oid == about:
			about_visible = true
		elif oid != str(actor.get("id", "")):
			other_visible = oid
	if not about_visible:
		return out
	# 直问：信息量最大，但当面质询有社交风险
	var express: float = p.effective_trait("expressiveness", actor.get("needs", {}))
	var u_ask: float = drive * (0.65 + express * 0.25) * stakes * (0.5 + entropy * 0.5) - conflict * 0.25
	if u_ask > 0.08:
		out.append({"action": "ask_reason", "target": null, "target_actor": about,
			"question_kind": str(q0.get("kind", "")), "utility": u_ask, "desc": "问个明白", "duration": 1})
	# 暗中观察：信息量中等、慢，但几乎零风险（多疑/谨慎者的首选）
	var u_watch: float = drive * 0.45 * stakes * (0.5 + entropy * 0.5) - conflict * 0.02
	if u_watch > 0.08:
		out.append({"action": "observe_person", "target": null, "target_actor": about,
			"question_kind": str(q0.get("kind", "")), "utility": u_watch, "desc": "留意他的一举一动", "duration": 4})
	# 问第三人：信息量中上，风险低，但需要有人在（圆融者首选）
	if other_visible != "":
		var u_third: float = drive * 0.45 * stakes * (0.5 + entropy * 0.5) - conflict * 0.08 + sociability * 0.12
		if u_third > 0.08:
			out.append({"action": "ask_third_party", "target": null, "target_actor": other_visible,
				"about_actor": about, "question_kind": str(q0.get("kind", "")), "utility": u_third, "desc": "找人间接打听", "duration": 1})
	return out

## P1.5：保持距离。不是 fallback——回避是合法的人类行为。
## 敌意解释主导（social_stance 高）+ 怕冲突/恐惧 → 主动拉开与某人的距离。
## 取木：树是材料来源——有了木才能生火，有了火才有营地
static func _gather_wood(p: PersonalityProfile, needs: Dictionary, inv: Dictionary, pos: Vector2i, world: Dictionary):
	if int(inv.get("wood", 0)) >= 2:
		return null
	var trees: Array = world.get("trees", [])
	if trees.is_empty():
		return null
	var nearest := _nearest(pos, trees)
	if nearest.x < 0:
		return null
	var prag := p.effective_trait("pragmatism", needs)
	var score := (0.25 + prag * 0.35) * _dp(pos, nearest)
	return {"action": "gather_wood", "target": nearest, "utility": score, "desc": "去收集木头", "duration": 2}

## 火边休憩：篝火是营地的心脏——人会聚到火边，社交与分享在这里发生
static func _sit_by_fire(p: PersonalityProfile, needs: Dictionary, pos: Vector2i, world: Dictionary):
	var fires: Dictionary = world.get("fires", {})
	if fires.is_empty():
		return null
	var fire_tile := Vector2i(-1, -1)
	for key in fires:
		var parts: Array = key.replace("(", "").replace(")", "").split(", ")
		if parts.size() == 2:
			fire_tile = Vector2i(int(parts[0]), int(parts[1]))
		break
	if fire_tile.x < 0:
		return null
	var dist := absi(pos.x - fire_tile.x) + absi(pos.y - fire_tile.y)
	if dist > 14:
		return null
	var social := _n(needs.get("social", 0), 250, 650)
	var sociability := p.effective_trait("sociability", needs)
	var fear: float = p.emotions.get("fear", 0.0)
	var energy_low := 1.0 - _n(needs.get("energy", 1000), 100, 400)
	var score := 0.15 + social * 0.3 + sociability * 0.25 + fear * 0.2 + energy_low * 0.2
	if dist > 2:
		score *= 0.85  # 要走过去
	return {"action": "sit_by_fire", "target": fire_tile, "utility": score, "desc": "到火边坐坐", "duration": 2}

static func _keep_distance(p: PersonalityProfile, actor: Dictionary):
	var stance: Dictionary = actor.get("social_stance", {})
	var strongest_id := ""
	var strongest := 0.55  # 低于此值不构成"躲开"的动机
	for oid in stance:
		if float(stance[oid]) > strongest:
			strongest = float(stance[oid])
			strongest_id = oid
	if strongest_id == "":
		return null
	var fear: float = p.emotions.get("fear", 0.0)
	var conflict_avoid := p.effective_trait("conflict_avoidance", actor.get("needs", {}))
	var score := strongest * (0.4 + fear * 0.3 + conflict_avoid * 0.3)
	return {"action": "keep_distance", "target": null, "avoid_of": strongest_id,
		"utility": score, "desc": "和某人保持距离", "duration": 2}

static func _rest(p: PersonalityProfile, needs: Dictionary):
	var energy_low := 1.0 - _n(needs.get("energy", 1000), 100, 400)
	var score := UtilityCurves.quadratic(energy_low)
	return {"action": "rest", "target": null, "utility": score, "desc": "休息", "duration": 3}

## 吃库存食物。饿到极点还揣着存粮却不吃，是不可信的行为——
## 这条行动保证"饿死"只会发生在真的弹尽粮绝时。
static func _eat(p: PersonalityProfile, needs: Dictionary, inv: Dictionary):
	if int(inv.get("food", 0)) < 1:
		return null
	var hunger := _n(needs.get("hunger", 0), 250, 600)
	var prag := p.effective_trait("pragmatism", needs)
	var score := UtilityCurves.quadratic(hunger) * (0.9 + prag * 0.3)
	return {"action": "eat_food", "target": null, "utility": score, "desc": "吃点存粮", "duration": 1}

static func _wait():
	return {"action": "wait", "target": null, "utility": 0.05, "desc": "观察周围", "duration": 1}

# ── 工具 ──

static func _n(value, lo: float, hi: float) -> float:
	return UtilityCurves.inverse_lerp(float(value), lo, hi)

static func _dp(a: Vector2i, b: Vector2i) -> float:
	return UtilityCurves.inverse_lerp(float(absi(a.x - b.x) + absi(a.y - b.y)), 25.0, 3.0)

static func _nearest(pos: Vector2i, resources: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 99999
	for r in resources:
		if typeof(r) == TYPE_VECTOR2I:
			var d := absi(pos.x - r.x) + absi(pos.y - r.y)
			if d < best_d:
				best_d = d
				best = r
	return best

static func _pick_unvisited(pos: Vector2i, visited: Dictionary) -> Vector2i:
	var fallback := Vector2i(-1, -1)
	for delta in [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4), Vector2i(3, 3), Vector2i(-3, -3)]:
		var t := Vector2i(pos.x + delta.x, pos.y + delta.y)
		if t.x > 2 and t.y > 2:
			if not visited.has(str(t)):
				return t  # 优先没走过的方向
			if fallback.x < 0:
				fallback = t  # 都走过时退而求其次（配合 0.55 的习惯化衰减，不是禁止）
	return fallback
