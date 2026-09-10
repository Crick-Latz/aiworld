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

	var a1 = _forage(p, needs, inv, pos, world, actor)
	if a1 != null: actions.append(a1)
	var a2 = _drink(p, needs, pos, world, actor)
	if a2 != null: actions.append(a2)
	var a3 = _fish(p, needs, inv, pos, world, actor)
	if a3 != null: actions.append(a3)
	var a4 = _shells(p, needs, pos, world, actor)
	if a4 != null: actions.append(a4)
	var a5 = _shelter(p, phys, inv, pos, world)
	if a5 != null: actions.append(a5)
	var a6 = _craft(p, phys, inv, pos, world, actor)
	if a6 != null: actions.append(a6)
	var a7 = _fire(p, phys, inv, pos, world)
	if a7 != null: actions.append(a7)
	var a8 = _explore(p, needs, pos, world, actor)
	if a8 != null: actions.append(a8)
	var a9 = _ruins(p, needs, pos, world, actor)
	if a9 != null: actions.append(a9)
	var a10 = _socialize(p, needs, actor, world)
	if a10 != null: actions.append(a10)
	var a11 = _share(p, needs, inv, pos, world, actor)
	if a11 != null: actions.append(a11)
	for a13 in _request(p, needs, actor, world):
		actions.append(a13)
	var a22 = _propose_rule(actor, world)
	if a22 != null: actions.append(a22)
	var a20 = _seek_person(p, actor)
	if a20 != null: actions.append(a20)
	var a21 = _settle(p, actor, world)
	if a21 != null: actions.append(a21)
	var a19 = _repay_debt(p, actor, world)
	if a19 != null: actions.append(a19)
	var a18 = _epistemic_actions(p, actor, world)
	for ea in a18: actions.append(ea)
	var a16 = _gather_wood(p, needs, inv, pos, world, actor)
	if a16 != null: actions.append(a16)
	var a17 = _sit_by_fire(p, needs, pos, world, actor)
	if a17 != null: actions.append(a17)
	var a15 = _keep_distance(p, actor)
	if a15 != null: actions.append(a15)
	var a14 = _eat(p, needs, inv)
	if a14 != null: actions.append(a14)
	var a12 = _rest(p, needs)
	if a12 != null: actions.append(a12)
	actions.append(_wait())
	return actions

## P5.1 SK（fail-closed）：决策只读自己见过的资源（actor.known_resources）。
## 键缺失 = 不知道——绝不回退世界真值（missing knowledge ≠ omniscience）。
## 测试 fixture 需要资源知识时必须显式传入 known_resources。
static func _known_sources(actor: Dictionary, key: String) -> Array:
	var kr: Dictionary = actor.get("known_resources", {})
	if kr.has(key):
		return kr[key]
	return []

static func _forage(p: PersonalityProfile, needs: Dictionary, inv: Dictionary, pos: Vector2i, world: Dictionary, actor: Dictionary = {}):
	var bushes: Array = _known_sources(actor, "berry_bushes")
	if bushes.is_empty():
		return null
	var nearest: Vector2i = _nearest(pos, bushes)
	if nearest.x < 0:
		return null
	var hunger := _n(needs.get("hunger", 0), 200, 800)
	var prag := p.effective_trait("pragmatism", needs)
	var score := UtilityCurves.quadratic(hunger) * (0.6 + prag * 0.4) * _dp(pos, nearest)
	return ActionTargetContract.with_source(
		{"action": "forage_berries", "target": nearest, "utility": score, "desc": "去采浆果", "duration": 1},
		"berry_bushes")

static func _drink(p: PersonalityProfile, needs: Dictionary, pos: Vector2i, world: Dictionary, actor: Dictionary = {}):
	var springs: Array = _known_sources(actor, "water_springs")
	if springs.is_empty():
		return null
	var nearest: Vector2i = _nearest(pos, springs)
	if nearest.x < 0:
		return null
	var thirst := _n(needs.get("thirst", 0), 300, 800)
	var score := UtilityCurves.exponential(thirst, 6.0) * _dp(pos, nearest)
	return ActionTargetContract.with_source(
		{"action": "drink_water", "target": nearest, "utility": score, "desc": "去喝水", "duration": 1},
		"water_springs")

static func _fish(p: PersonalityProfile, needs: Dictionary, inv: Dictionary, pos: Vector2i, world: Dictionary, actor: Dictionary = {}):
	_craft_catalogs()
	# P6.3A：FISH 能力由 ItemCatalog 派生（不再硬编码 fish_spear 字段名）
	if not InventoryOps.capabilities_of_inventory(inv, _craft_items).has("FISH"):
		return null
	var spots: Array = _known_sources(actor, "fish_spots")
	if spots.is_empty():
		return null
	var nearest: Vector2i = _nearest(pos, spots)
	if nearest.x < 0:
		return null
	var hunger := _n(needs.get("hunger", 0), 300, 800)
	var action := p.effective_trait("action_bias", needs)
	var score := UtilityCurves.quadratic(hunger) * (0.7 + action * 0.3) * _dp(pos, nearest)
	return ActionTargetContract.with_source(
		{"action": "fish", "target": nearest, "utility": score, "desc": "去捕鱼", "duration": 2},
		"fish_spots")

static func _shells(p: PersonalityProfile, needs: Dictionary, pos: Vector2i, world: Dictionary, actor: Dictionary = {}):
	var beaches: Array = _known_sources(actor, "shell_beaches")
	if beaches.is_empty():
		return null
	var nearest: Vector2i = _nearest(pos, beaches)
	if nearest.x < 0:
		return null
	var curiosity := p.effective_trait("curiosity", needs)
	var hunger := _n(needs.get("hunger", 0), 400, 800)
	# P5：贝壳只能做工具——捡够就停（此前无上限，饿死也在捡第 272 个贝壳）
	var shells_have := int(actor.get("inventory", {}).get("shells", 0)) + int(actor.get("inventory", {}).get("fish_spear", 0)) * 2
	var saturation := clampf(1.0 - float(shells_have) * 0.15, 0.0, 1.0)
	if saturation <= 0.0:
		return null
	var score := (0.3 + curiosity * 0.4 + hunger * 0.12) * _dp(pos, nearest) * saturation
	return ActionTargetContract.with_source(
		{"action": "gather_shells", "target": nearest, "utility": score, "desc": "去捡贝壳", "duration": 1},
		"shell_beaches")

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

static var _craft_items: ItemCatalog = null
static var _craft_recipes: RecipeCatalog = null

static func _craft_catalogs() -> void:
	if _craft_items == null:
		_craft_items = ItemCatalog.load_default()
		_craft_recipes = RecipeCatalog.load_default(_craft_items)

## P6.3A：制作候选经 CraftingResolver（主观已知 refs + 库存 + 能力）——数据驱动，鱼叉不再是硬编码
static func _craft(p: PersonalityProfile, phys: Dictionary, inv: Dictionary, pos: Vector2i, world: Dictionary, actor: Dictionary = {}):
	_craft_catalogs()
	var known_refs: Array = actor.get("known_recipe_refs", [])
	var caps: Array = actor.get("possessed_capabilities", [])
	var candidates: Array = CraftingResolver.craft_candidates(inv, known_refs, caps, _craft_recipes, _craft_items)
	# P6.3A-R2 §二：已拥有非 stackable 产出→不重复制作；primary_output 稳定排序；描述从 ItemCatalog 生成
	var first := {}
	for c in candidates:
		var out_item := _craft_recipes.primary_output(_craft_recipes.spec(str(c.get("recipe_id", ""))))
		if out_item == "":
			continue
		if int(inv.get(out_item, 0)) > 0 and not bool(_craft_items.spec(out_item).get("stackable", true)):
			continue
		first = c
		break
	if first.is_empty():
		return null
	var prag := p.effective_trait("pragmatism", phys)
	var curiosity := p.effective_trait("curiosity", phys)
	var score := 0.3 + prag * 0.3 + curiosity * 0.2
	var craft_rid := str(first.get("recipe_id", ""))
	var craft_recipe := _craft_recipes.spec(craft_rid)
	var craft_out := _craft_recipes.primary_output(craft_recipe)
	var craft_name := str(_craft_items.spec(craft_out).get("display_name", craft_out))
	return {"action": str(first.get("compat_action", "craft")), "target": pos, "utility": score,
		"desc": "制作" + craft_name, "duration": int(first.get("duration_ticks", 2)),
		"recipe_id": craft_rid}

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
	# P5 绝望搜索（GPT 第 13 节 SEARCH_FOR_UNKNOWN）：急需且【我所知】没有来源时，
	# 逼自己去远处未知区碰运气——只用自己的信念和需求，不读世界真值。
	# 身边有人时压掉远行加成：开口求助是比瞎逛更近的活路（softmax 里让两者竞争）
	var desperation := _desperation(needs, actor)
	if not (actor.get("others_visible", []) as Array).is_empty():
		desperation = 0.0
	var target := _pick_unvisited(pos, visited, desperation > 0.0)
	if target.x < 0:
		return null
	# 习惯化：走过的路不再新鲜——探索欲随已知区域扩大自然衰减
	var novelty := 1.0 if not visited.has(str(target)) else 0.55
	var score := (0.2 + curiosity * 0.6) * _dp(pos, target) * novelty
	if desperation > 0.0:
		score = maxf(score, desperation * 0.8)  # 饿/渴到极处，找来源压过闲逛的效用衰减
		return {"action": "explore", "target": target, "utility": score, "desc": "出去找活路", "duration": 1}
	return {"action": "explore", "target": target, "utility": score, "desc": "探索未知区域", "duration": 1}

## 急迫度：饿/渴高 且 所知的可用来源为空（含自身库存）→ 0..1；否则 0
static func _desperation(needs: Dictionary, actor: Dictionary) -> float:
	var hunger := _n(needs.get("hunger", 0), 650, 950)
	var thirst := _n(needs.get("thirst", 0), 650, 950)
	var kr: Dictionary = actor.get("known_resources", {})
	var inv: Dictionary = actor.get("inventory", {})
	var food_known := int(kr.get("berry_bushes", []).size()) + int(kr.get("fish_spots", []).size()) + int(inv.get("food", 0))
	var water_known := int(kr.get("water_springs", []).size()) + int(inv.get("water", 0))
	var out := 0.0
	if hunger > 0.05 and food_known == 0:
		out = maxf(out, hunger)
	if thirst > 0.05 and water_known == 0:
		out = maxf(out, thirst)
	return out

static func _ruins(p: PersonalityProfile, needs: Dictionary, pos: Vector2i, world: Dictionary, actor: Dictionary = {}):
	var unsearched: Array = _known_sources(actor, "ruins")
	if unsearched.is_empty():
		return null
	# 遗留回退：世界 ruins 是字典数组——信念路径供给的已是 Vector2i 列表
	for r in unsearched.duplicate():
		if typeof(r) == TYPE_DICTIONARY:
			unsearched.erase(r)
			if not bool(r.get("searched", false)) and typeof(r.get("pos", null)) == TYPE_VECTOR2I:
				unsearched.append(r["pos"])
	if unsearched.is_empty():
		return null
	var nearest: Vector2i = _nearest(pos, unsearched)
	if nearest.x < 0:
		return null
	var curiosity := p.effective_trait("curiosity", needs)
	var caution := p.effective_trait("caution", needs)
	var score := (0.3 + curiosity * 0.5 - caution * 0.2) * _dp(pos, nearest)
	return ActionTargetContract.with_source(
		{"action": "search_ruins", "target": nearest, "utility": score, "desc": "搜索废弃营地", "duration": 2},
		"ruins")

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

static func _share(p: PersonalityProfile, needs: Dictionary, inv: Dictionary, pos: Vector2i, world: Dictionary, actor: Dictionary = {}):
	if int(inv.get("food", 0)) < 2:
		return null
	var altruism := p.effective_trait("altruism", needs)
	var empathy := p.effective_trait("empathy", needs)
	var hunger := _n(needs.get("hunger", 0), 300, 700)
	var generosity := altruism * 0.6 + empathy * 0.4
	var score := generosity * (1.0 - UtilityCurves.quadratic(hunger)) * 0.8
	# P5（跨角色感知泄漏修复）：只信【我】的 ToM 判断——"我看见有人像饿了"，
	# 不再读全局聚合键（岛东的卡德加看见欧恩饿，不影响岛西的薇拉）
	if actor.get("appears_hungry_nearby", world.get("someone_hungry_nearby", false)):
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
			# P5：自己"知道哪里有"才走自助——不知道水在哪，只能求人
			var sources: Array = _known_sources(actor, str(spec["self_source"]))
			if not sources.is_empty():
				var nearest_src := _nearest(actor.get("tile", Vector2i.ZERO), sources)
				if nearest_src.x >= 0 and absi(nearest_src.x - actor.get("tile", Vector2i.ZERO).x) + absi(nearest_src.y - actor.get("tile", Vector2i.ZERO).y) <= int(spec.get("self_serve_dist", 8)):
					continue
		var target_id := SocialSystem.pick_request_target(actor, visible, trust_of, str(spec["predicate"]))
		if target_id == "":
			continue
		# P5 拒绝记忆：48 tick（约两天）内刚拒绝过我的人不再开口——窘迫是真实的
		var now_tick := int(world.get("tick", 0))
		var refused_recently := false
		for r in actor.get("refusal_memory", []):
			if str(r.get("by", "")) == target_id and int(r.get("tick", -999)) + 48 > now_tick:
				refused_recently = true
				break
		if refused_recently:
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
	var q0: Dictionary = {}
	var about := ""
	for q in qs:  # 找第一个「对方还在视野里」的问题——人走了就先搁置，不死磕
		var ab := str(q.get("about", ""))
		for o in visible:
			if str(o.get("id", "")) == ab:
				q0 = q
				about = ab
				break
		if about != "":
			break
	if about == "":
		return out
	var stakes: float = float(q0.get("stakes", 0.5))
	var entropy: float = float(q0.get("entropy", 0.5))
	var other_visible := ""
	for o in visible:
		var oid := str(o.get("id", ""))
		if oid != about and oid != str(actor.get("id", "")):
			other_visible = oid
	# 直问：信息量最大，但当面质询有社交风险
	var express: float = p.effective_trait("expressiveness", actor.get("needs", {}))
	var u_ask: float = drive * (0.65 + express * 0.25) * stakes * (0.5 + entropy * 0.5) - conflict * 0.25
	if u_ask > 0.08:
		out.append({"action": "ask_reason", "target": null, "target_actor": about,
			"question_kind": str(q0.get("kind", "")), "source_event_ids": (q0.get("source_event_ids", []) as Array).duplicate(),
			"utility": u_ask, "desc": "问个明白", "duration": 1})
	# 暗中观察：信息量中等、慢，但几乎零风险（多疑/谨慎者的首选）
	var u_watch: float = drive * 0.45 * stakes * (0.5 + entropy * 0.5) - conflict * 0.02
	if u_watch > 0.08:
		out.append({"action": "observe_person", "target": null, "target_actor": about,
			"question_kind": str(q0.get("kind", "")), "source_event_ids": (q0.get("source_event_ids", []) as Array).duplicate(),
			"utility": u_watch, "desc": "留意他的一举一动", "duration": 4})
	# 问第三人：信息量中上，风险低，但需要有人在（圆融者首选）
	if other_visible != "":
		var u_third: float = drive * 0.45 * stakes * (0.5 + entropy * 0.5) - conflict * 0.08 + sociability * 0.12
		if u_third > 0.08:
			out.append({"action": "ask_third_party", "target": null, "target_actor": other_visible,
				"about_actor": about, "question_kind": str(q0.get("kind", "")),
				"source_event_ids": (q0.get("source_event_ids", []) as Array).duplicate(),
				"utility": u_third, "desc": "找人间接打听", "duration": 1})
	return out

## P2b 规则提议：制度目标存在 + 有听众 → 提议结构化规则（自然语言只是 Renderer）
static func _propose_rule(actor: Dictionary, world: Dictionary):
	if not RuleDiscourse.can_propose(actor, world):
		return null
	var goals: Array = actor.get("institutional_goals", [])
	var g0: Dictionary = goals[0]
	var object_id := str(g0.get("object", "food"))
	# 提议比例来自我的个人规范（我认同多少就提议多少——人性如此）
	var my_pref: float = float(actor.get("norms", {}).get("personal", {}).get("sharing", 0.5))
	var fraction: float = clampf(0.25 + my_pref * 0.5, 0.2, 0.6)
	var goal_kind := str(g0.get("kind", "we_need_a_rule"))
	if goal_kind == "amend":
		fraction = 0.25
	var u: float = 0.3 + my_pref * 0.3  # 制度目标的效用：解决协调摩擦
	return {"action": "propose_rule", "target": null, "object": object_id, "fraction": fraction, "goal_kind": goal_kind,
			"utility": u, "desc": "提议立个规矩", "duration": 2}

## P1.7b 主动寻人：认识问题悬而未决而人不在视野 → 走向他最后已知的位置（跨空间认识行动）；
## 亏欠未还/亲近之人久未见 → 也去找。目的地是我【记忆里的】位置——人可能已经走了（扑空是真实的）。
static func _seek_person(p: PersonalityProfile, actor: Dictionary):
	var tom: TheoryOfMind = actor.get("tom", null)
	if tom == null:
		return null
	var dyn := PersonalityDynamics.dynamics(p, actor.get("sensitivities", {}), actor.get("norms", {}))
	var best_id := ""
	var best_u := 0.12
	var reason := ""
	# 1) 认识目标：我想弄清楚的那个人不在视野（视野内的由 ask_reason 等直接处理）
	var visible_ids := {}
	for o in actor.get("others_visible", []):
		visible_ids[str(o.get("id", ""))] = true
	for q in actor.get("open_questions", []):
		var about := str(q.get("about", ""))
		if about != "" and not visible_ids.has(about) and not tom.last_seen_of(about).is_empty():
			var u: float = (float(dyn["epistemic_drive"]) - float(dyn["uncertainty_tolerance"]) * 0.2) * float(q.get("stakes", 0.5)) * 0.5
			if u > best_u:
				best_u = u
				best_id = about
				reason = "找他问个清楚"
	# 2) 亲近/亏欠之人：高社交需求时想见喜欢的人；亏欠债主时想找机会还
	var social := _n(actor.get("needs", {}).get("social", 0), 350, 700)
	if best_id == "":
		for other_id in actor.get("trust_of", {}):
			if visible_ids.has(other_id):
				continue
			var ls := tom.last_seen_of(other_id)
			if ls.is_empty():
				continue
			var oblig: float = float(actor.get("_owed_hint", 0.0))  # 由视图供给的亏欠提示
			var u2: float = UtilityCurves.quadratic(social) * 0.35 + oblig * 0.2
			if u2 > best_u:
				best_u = u2
				best_id = other_id
				reason = "去找他"
	if best_id == "":
		# P5 生存寻人：饿/渴到极处且【我所知】没有任何来源——人本身就是最后的活路
		# （"也许薇拉有吃的"）。只去 last_seen 记忆位置——找不找得到是另一回事。
		var desp := _desperation(actor.get("needs", {}), actor)
		if desp <= 0.05:
			return null
		for other_id in actor.get("trust_of", {}):
			if visible_ids.has(other_id):
				continue
			var ls2: Dictionary = tom.last_seen_of(other_id)
			if ls2.is_empty():
				continue
			best_id = other_id
			best_u = desp * 0.7
			reason = "饿得发慌，去找人"
			break
		if best_id == "":
			return null
	var seen := tom.last_seen_of(best_id)
	return {"action": "seek_person", "target": seen["tile"], "target_actor": best_id,
			"utility": best_u, "desc": reason, "duration": 4}

## P1.7b 定居：用 PlaceEvaluation 评价已知地点，不满意现居地则迁移（迁移有成本——熟悉度清零）
static func _settle(p: PersonalityProfile, actor: Dictionary, world: Dictionary):
	var beliefs: PlaceBelief = actor.get("place_beliefs", null)
	if beliefs == null:
		return null
	var places: Array = beliefs.known_places()
	if places.size() < 2:
		return null  # 没得选
	var my_tile: Vector2i = actor.get("tile", Vector2i.ZERO)
	# 我当前所在地和已知最佳地的评价差（人物各不同：同营地薇拉觉得温馨、欧恩觉得挤）
	var best: Dictionary = {}
	var best_v := -99.0
	for pl in places:
		var v := PlaceBelief.evaluate_place(actor, pl, _who_is_at(actor, pl, world), actor.get("_relationships_hint", null))
		if v > best_v:
			best_v = v
			best = pl
	if best == null or best["tile"] == my_tile or best["tile"] == actor.get("base", Vector2i(-9, -9)):
		return null  # 现居地已是最佳
	var cur_v := PlaceBelief.evaluate_place(actor, beliefs.get_place(actor.get("base", my_tile)) if not beliefs.get_place(actor.get("base", my_tile)).is_empty() else {"tile": my_tile, "resources": [], "safety": 0.5, "familiarity": 0.3}, _who_is_at(actor, {"tile": my_tile}, world), actor.get("_relationships_hint", null))
	if best_v - cur_v < 0.25:  # 迁移成本门槛：不明显更好就凑合
		return null
	return {"action": "relocate", "target": best["tile"], "utility": best_v - cur_v, "desc": "换个地方住", "duration": 6}

## 谁在给定地点附近（8 格）——供 PlaceEvaluation 心算
static func _who_is_at(actor: Dictionary, place: Dictionary, world: Dictionary) -> Array:
	var out: Array = []
	var pt: Vector2i = place.get("tile", Vector2i.ZERO)
	for o in actor.get("others_all", []):
		var t2: Vector2i = o.get("tile", Vector2i(-99, -99))
		if absi(pt.x - t2.x) + absi(pt.y - t2.y) <= 8:
			out.append(str(o.get("id", "")))
	return out

## P1.5：保持距离。不是 fallback——回避是合法的人类行为。
## 敌意解释主导（social_stance 高）+ 怕冲突/恐惧 → 主动拉开与某人的距离。
## 取木：树是材料来源——有了木才能生火，有了火才有营地
static func _gather_wood(p: PersonalityProfile, needs: Dictionary, inv: Dictionary, pos: Vector2i, world: Dictionary, actor: Dictionary = {}):
	if int(inv.get("wood", 0)) >= 2:
		return null
	var trees: Array = _known_sources(actor, "trees")
	if trees.is_empty():
		return null
	var nearest := _nearest(pos, trees)
	if nearest.x < 0:
		return null
	var prag := p.effective_trait("pragmatism", needs)
	var score := (0.25 + prag * 0.35) * _dp(pos, nearest)
	return ActionTargetContract.with_source(
		{"action": "gather_wood", "target": nearest, "utility": score, "desc": "去收集木头", "duration": 2},
		"trees")

## 火边休憩：篝火是营地的心脏——人会聚到火边，社交与分享在这里发生
static func _sit_by_fire(p: PersonalityProfile, needs: Dictionary, pos: Vector2i, world: Dictionary, actor: Dictionary = {}):
	# P5：只去【我见过】的火堆（火灭了信念仍可能滞留——重访才发现）。
	# P5.1 SK：fail-closed——没有 known_resources 键就不去（绝不回退世界真值）
	var kr: Dictionary = actor.get("known_resources", {})
	if not kr.has("fires"):
		return null
	var fires: Dictionary = kr["fires"]
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

static func _tool_shell_equivalent(inv: Dictionary) -> int:
	# P6.3A 前原语义：每把已制鱼叉计 2 个贝壳当量（防止已满足时过度捡拾）——非配方派生，保留原始数值直到 P6.3B
	return int(inv.get("fish_spear", 0)) * 2

static func _pick_unvisited(pos: Vector2i, visited: Dictionary, wide: bool = false) -> Vector2i:
	var fallback := Vector2i(-1, -1)
	var deltas: Array = [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4), Vector2i(3, 3), Vector2i(-3, -3)]
	if wide:
		# P5 绝望搜索：走得远——未知方向才可能有活路（仍只是自己的方向猜测，非真值）
		deltas = [Vector2i(9, 0), Vector2i(-9, 0), Vector2i(0, 9), Vector2i(0, -9),
			Vector2i(7, 7), Vector2i(-7, -7), Vector2i(7, -7), Vector2i(-7, 7),
			Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4), Vector2i(3, 3), Vector2i(-3, -3)]
	for delta in deltas:
		var t := Vector2i(pos.x + delta.x, pos.y + delta.y)
		if t.x > 2 and t.y > 2:
			if not visited.has(str(t)):
				return t  # 优先没走过的方向
			if fallback.x < 0:
				fallback = t  # 都走过时退而求其次（配合 0.55 的习惯化衰减，不是禁止）
	return fallback
