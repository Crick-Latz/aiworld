class_name RelationshipStore
extends RefCounted
## 社会关系（阶段 A，M08）：有向信任/好恶/债务。
## A 信任 B 不等于 B 信任 A。事件驱动更新；数值 -1000..1000。
## 信任影响求助决策权重（HelpRules.decide_request 的扩展参数）。

const TRUST_ACCEPT_BONUS := 50
const TRUST_REJECT_PENALTY := -80
const TRUST_HELP_REWARD := 100
const TRUST_THRESHOLD_LOW := -200
const TRUST_THRESHOLD_HIGH := 200

var _relationships := {} # "from_id->to_id" -> {trust, affection, debt, last_interaction_tick}

func get_trust(from_id: String, to_id: String) -> int:
	var key := "%s->%s" % [from_id, to_id]
	if _relationships.has(key):
		return int(_relationships[key]["trust"])
	return 0

func set_trust(from_id: String, to_id: String, value: int) -> void:
	var key := "%s->%s" % [from_id, to_id]
	if not _relationships.has(key):
		_relationships[key] = {"trust": 0, "affection": 0, "debt": 0, "last_interaction_tick": 0}
	_relationships[key]["trust"] = clampi(value, -1000, 1000)

func adjust_trust(from_id: String, to_id: String, delta: int) -> void:
	set_trust(from_id, to_id, get_trust(from_id, to_id) + delta)

func on_help_accepted(helper_id: String, requester_id: String) -> void:
	adjust_trust(requester_id, helper_id, TRUST_HELP_REWARD) # 求助者感谢帮助者
	adjust_trust(helper_id, requester_id, TRUST_ACCEPT_BONUS) # 帮助者略增好感

func on_help_declined(helper_id: String, requester_id: String) -> void:
	adjust_trust(requester_id, helper_id, TRUST_REJECT_PENALTY) # 求助者失望
	# 帮助者不惩罚自己

func on_transfer_complete(from_id: String, to_id: String) -> void:
	adjust_trust(to_id, from_id, TRUST_HELP_REWARD / 2) # 额外信任加成

## 求助时选择最优目标：优先信任高、距离近的
static func pick_best_helper(candidates: Array, store: RelationshipStore, requester_id: String) -> String:
	var best := ""
	var best_score := -99999
	for c in candidates:
		var id := str(c["id"])
		if id == requester_id:
			continue
		var trust := store.get_trust(requester_id, id)
		if trust <= TRUST_THRESHOLD_LOW:
			continue # 深度不信任的人不找
		var dist: int = c.get("distance", 999)
		var score := trust - dist * 3
		if score > best_score:
			best_score = score
			best = id
	return best

## 信任对接受意愿的加权（扩展 HelpRules）
static func trust_weighted_accept(base_accept: bool, helper_trust_toward_requester: int) -> bool:
	if not base_accept:
		return false
	if helper_trust_toward_requester <= TRUST_THRESHOLD_LOW:
		return false # 深度不信任 → 即使库存够也拒绝
	return true

func snapshot() -> Dictionary:
	return _relationships.duplicate(true)
