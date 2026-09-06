class_name PlaceBelief
extends RefCounted
## P1.7a 地点信念与地点评价（内生社会生态）：
## NPC 不天然知道地图哪里好——只知道自己去过/看过的地点，且每个人评价不同。
##   薇拉眼里的营地：资源中等、卡德加常在、安全 0.73
##   欧恩眼里的营地：太挤、存粮人人看得见、安全 0.62
## PlaceValue 全部输入来自角色自己的认知（ToM/关系/需求/人格），无世界真值直读。

## 每个角色的地点信念表：place_key -> {known_resources, safety, familiarity, last_visited, seen_tick}
var _places := {}   # actor 内嵌使用（this 挂在 actor["place_beliefs"]）

static func key_of(tile: Vector2i) -> String:
	return "p%d_%d" % [tile.x, tile.y]

func observe_place(tile: Vector2i, resources: Array, tick: int) -> void:
	var k := key_of(tile)
	if not _places.has(k):
		_places[k] = {"tile": tile, "resources": [], "safety": 0.6, "familiarity": 0.0, "last_visited": -1}
	var p: Dictionary = _places[k]
	for r in resources:
		if not p["resources"].has(r):
			p["resources"].append(r)
	p["familiarity"] = clampf(float(p["familiarity"]) + 0.1, 0.0, 1.0)
	p["last_visited"] = tick

func note_shelter(tile: Vector2i, tick: int) -> void:
	observe_place(tile, ["shelter"], tick)

func note_fire(tile: Vector2i, tick: int) -> void:
	observe_place(tile, ["fire", "warmth"], tick)

func get_place(tile: Vector2i) -> Dictionary:
	return _places.get(key_of(tile), {})

func known_places() -> Array:
	return _places.values()

## ── PlaceEvaluation（P1.7 第三条）：所有输入来自 actor 自己的认知 ──
## place_value = 资源 + 安全 + 庇护 + 社交(基于关系的心算) + 信息 + 熟悉
##             − 路程 − 社交不适(敌意者在场) − 隐私损失(高自立人格在拥挤地)
static func evaluate_place(actor: Dictionary, place: Dictionary, people_there: Array, relationships) -> float:
	var p: PersonalityProfile = actor.get("personality", null)
	if p == null:
		return 0.0
	var needs: Dictionary = actor.get("needs", {})
	var beliefs: PlaceBelief = actor.get("place_beliefs", null)

	# 资源价值：我缺什么，这里就有什么（需求驱动，非世界真值）
	var res: Array = place.get("resources", [])
	var resource_v := 0.0
	if needs.get("hunger", 0) > 500 and (res.has("food") or res.has("berries")):
		resource_v += 0.3
	if needs.get("thirst", 0) > 400 and res.has("water"):
		resource_v += 0.35
	if res.has("fire"):
		resource_v += 0.1 + float(p.emotions.get("fear", 0.0)) * 0.15
	if res.has("shelter"):
		resource_v += 0.12

	# 安全：自身信念的 safety 估计 + 受伤时放大庇护需求
	var safety_v: float = float(place.get("safety", 0.5)) * 0.25
	if bool(actor.get("physical", {}).get("injured", false)) and res.has("shelter"):
		safety_v += 0.2

	# 社交价值：在场的人与我的关系（心算，非脚本）
	# 喜欢的人/亏欠的人在 → 想去；恐惧/敌意在 → 想避；但都是权重不是规则
	var social_v := 0.0
	var discomfort := 0.0
	var tom: TheoryOfMind = actor.get("tom", null)
	var stance: Dictionary = actor.get("social_stance", {})
	for person_id in people_there:
		if str(person_id) == str(actor.get("id", "")):
			continue
		var trust: int = relationships.composite_trust(str(actor.get("id", "")), str(person_id)) if relationships != null else 0
		var bene: int = relationships.get_dim(str(actor.get("id", "")), str(person_id), "benevolence") if relationships != null else 0
		var oblig: int = relationships.get_dim(str(actor.get("id", "")), str(person_id), "obligation") if relationships != null else 0
		var fear_dim: int = relationships.get_dim(str(actor.get("id", "")), str(person_id), "fear") if relationships != null else 0
		social_v += clampf(float(bene) / 800.0, -0.5, 0.5) * 0.4
		social_v += clampf(float(oblig) / 800.0, 0.0, 0.4) * 0.3  # 亏欠 → 想找机会还
		discomfort += clampf(-float(trust) / 800.0, 0.0, 0.5) * 0.5
		discomfort += clampf(float(fear_dim) / 800.0, 0.0, 0.5) * 0.6
		discomfort += clampf(float(stance.get(str(person_id), 0.0)), 0.0, 1.0) * 0.3  # 回避倾向
	# 人格调制：社交性高的人社交价值放大；高自立的人在场人多反而难受
	var sociability := p.effective_trait("sociability", needs)
	var self_rel: float = float(actor.get("norms", {}).get("personal", {}).get("self_reliance", 0.5))
	social_v *= (0.5 + sociability * 0.8)
	discomfort += self_rel * 0.15 * maxf(0.0, float(people_there.size()) - 1.0) * 0.2  # 隐私损失

	# 信息价值：认识问题没解决时，有人的地方有信息
	var info_v := 0.0
	if not (actor.get("open_questions", []) as Array).is_empty() and people_there.size() > 0:
		info_v += 0.15

	# P2.1 第 11 条：制度压力 → 地点不适（低合法性规则+人多监督的营地让违规者难受）
	for prid in actor.get("perceived_group_beliefs", {}):
		var pb: Dictionary = actor["perceived_group_beliefs"][prid]
		if float(pb.get("recognition", 0.0)) > 0.5:
			var leg: float = 1.0 - float(pb.get("legitimacy", ComplianceSystem.legitimacy_of(actor, str(prid), str(pb.get("rule", {}).get("object", "food")))))
			discomfort += leg * 0.25 * maxf(0.0, float(people_there.size()) - 1.0) * 0.15
		# 熟悉感 + 路程成本
	var familiarity: float = float(place.get("familiarity", 0.0))
	var my_tile: Vector2i = actor.get("tile", Vector2i.ZERO)
	var dist := absi(my_tile.x - place["tile"].x) + absi(my_tile.y - place["tile"].y)
	var travel_cost := clampf(float(dist) / 30.0, 0.0, 0.6)

	return resource_v + safety_v + social_v + info_v + familiarity * 0.15 - travel_cost - discomfort
