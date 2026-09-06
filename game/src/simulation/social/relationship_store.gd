class_name RelationshipStore
extends RefCounted
## 社会关系 v2（P1.5 第十七条）：trust 不再承担所有意义。
## 底层是四个独立维度——善意愿/可靠性/亏欠/畏惧；
## trust 成为综合显示值（供旧接口与观察者 UI），不再是唯一底层状态。
## 所有数值变化只能由 CognitiveTransition 调用 adjust（带解释权重的连续量），
## 不再提供"事件→固定数值"的便捷方法。

# 维度: benevolence(善意) / reliability(可靠) / obligation(亏欠) / fear(畏惧)
# 范围 -1000..1000

var _edges := {} # "from->to" -> {benevolence, reliability, obligation, fear, last_interaction_tick}

func _edge(from_id: String, to_id: String) -> Dictionary:
	var key := "%s->%s" % [from_id, to_id]
	if not _edges.has(key):
		_edges[key] = {"benevolence": 0, "reliability": 0, "obligation": 0, "fear": 0, "last_interaction_tick": 0}
	return _edges[key]

func adjust(from_id: String, to_id: String, dim: String, delta: float) -> void:
	var e := _edge(from_id, to_id)
	if not e.has(dim):
		return
	e[dim] = clampi(int(e[dim]) + int(round(delta)), -1000, 1000)

func get_dim(from_id: String, to_id: String, dim: String) -> int:
	var key := "%s->%s" % [from_id, to_id]
	if _edges.has(key):
		return int(_edges[key].get(dim, 0))
	return 0

## 综合信任：善意为主，可靠次之，畏惧减分，亏欠微加（有交情但非好感）
func composite_trust(from_id: String, to_id: String) -> int:
	var e := _edge(from_id, to_id)
	return int(round(
		float(e["benevolence"]) * 0.45
		+ float(e["reliability"]) * 0.35
		+ float(e["obligation"]) * 0.1
		- float(e["fear"]) * 0.3))

## 旧接口兼容（决策阈值/观察者显示用综合值）
func get_trust(from_id: String, to_id: String) -> int:
	return composite_trust(from_id, to_id)

func set_trust(from_id: String, to_id: String, value: int) -> void:
	var e := _edge(from_id, to_id)
	e["benevolence"] = clampi(int(round(float(value) / 0.45 * 0.45)), -1000, 1000)  # 粗略映射回善意维

const TRUST_THRESHOLD_LOW := -200
const TRUST_THRESHOLD_HIGH := 200

## 信任对接受意愿的加权（旧 HelpRules/StorySimulation 用；深度不信任 → 拒绝）
static func trust_weighted_accept(base_accept: bool, helper_trust_toward_requester: int) -> bool:
	if not base_accept:
		return false
	return helper_trust_toward_requester > TRUST_THRESHOLD_LOW

# ── 旧便捷接口：仅供遗留 StorySimulation（灯塔演示）使用。
## 岛模拟（IslandSimulation）一律经 CognitiveTransition 更新关系，禁止调用这些。──
func on_help_accepted(helper_id: String, requester_id: String) -> void:
	adjust(requester_id, helper_id, "benevolence", 220)  # ×0.45 ≈ 旧 +100 综合信任
	adjust(helper_id, requester_id, "benevolence", 110)

func on_help_declined(helper_id: String, requester_id: String) -> void:
	adjust(requester_id, helper_id, "benevolence", -180)  # ×0.45 ≈ 旧 -80

func on_transfer_complete(from_id: String, to_id: String) -> void:
	adjust(to_id, from_id, "benevolence", 110)

## 求助时选择最优目标：优先综合信任高、距离近的
static func pick_best_helper(candidates: Array, store: RelationshipStore, requester_id: String) -> String:
	var best := ""
	var best_score := -99999
	for c in candidates:
		var id := str(c["id"])
		if id == requester_id:
			continue
		var trust := store.composite_trust(requester_id, id)
		if trust <= TRUST_THRESHOLD_LOW:
			continue
		var dist: int = c.get("distance", 999)
		var score := trust - dist * 3
		if score > best_score:
			best_score = score
			best = id
	return best

func snapshot() -> Dictionary:
	var out := {}
	for key in _edges:
		var e: Dictionary = _edges[key].duplicate()
		e["trust"] = int(round(
			float(e["benevolence"]) * 0.45 + float(e["reliability"]) * 0.35
			+ float(e["obligation"]) * 0.1 - float(e["fear"]) * 0.3))
		out[key] = e
	return out
