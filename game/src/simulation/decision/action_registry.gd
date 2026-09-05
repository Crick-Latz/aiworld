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
	var a8 = _explore(p, needs, pos, world)
	if a8 != null: actions.append(a8)
	var a9 = _ruins(p, needs, pos, world)
	if a9 != null: actions.append(a9)
	var a10 = _socialize(p, needs, actor, world)
	if a10 != null: actions.append(a10)
	var a11 = _share(p, needs, inv, pos, world)
	if a11 != null: actions.append(a11)
	var a13 = _request(p, needs, actor, world)
	if a13 != null: actions.append(a13)
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
	var score := (0.3 + curiosity * 0.4 + hunger * 0.3) * _dp(pos, nearest)
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

static func _explore(p: PersonalityProfile, needs: Dictionary, pos: Vector2i, world: Dictionary):
	var curiosity := p.effective_trait("curiosity", needs)
	var fear: float = p.emotions.get("fear", 0.0)
	if fear > 0.7:
		return null
	var target := _pick_target(pos)
	if target.x < 0:
		return null
	var score := (0.2 + curiosity * 0.6) * _dp(pos, target)
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
	var social := _n(needs.get("social", 0), 400, 800)
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
		score *= 0.3 if not world.get("someone_nearby", false) else 1.0
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

## P1：开口求助。拉不下脸是真实的人性——不够饿不会求人；
## 向谁开口由 ToM（"他应该有食物"）+ 信任（"他不会羞辱我"）决定。
static func _request(p: PersonalityProfile, needs: Dictionary, actor: Dictionary, world: Dictionary):
	var hunger_raw := float(needs.get("hunger", 0))
	if hunger_raw < 450.0:
		return null  # 不够饿，开不了口
	var nearby: Array = actor.get("others_nearby", [])
	if nearby.is_empty():
		return null
	var trust_of: Dictionary = actor.get("trust_of", {})
	var target_id := SocialSystem.pick_request_target(actor, nearby, trust_of)
	if target_id == "":
		return null
	var target_tile := Vector2i(10, 10)
	for o in nearby:
		if str(o.get("id", "")) == target_id:
			target_tile = o.get("tile", target_tile)
	var hunger := _n(hunger_raw, 400, 700)
	var sociability := p.effective_trait("sociability", needs)
	var trust_f := clampf(float(trust_of.get(target_id, 0)) / 400.0, -1.0, 1.0)
	var pride_cost := 0.1  # 求助的心理成本：效用要盖过它才会开口
	var score := UtilityCurves.quadratic(hunger) * (0.5 + sociability * 0.3 + trust_f * 0.2) - pride_cost
	if score <= 0.0:
		return null
	return {"action": "request_share", "target": target_tile, "target_actor": target_id,
		"utility": score, "desc": "向同伴求助", "duration": 1}

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

static func _pick_target(pos: Vector2i) -> Vector2i:
	for delta in [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4), Vector2i(3, 3), Vector2i(-3, -3)]:
		var t := Vector2i(pos.x + delta.x, pos.y + delta.y)
		if t.x > 2 and t.y > 2:
			return t
	return Vector2i(-1, -1)
