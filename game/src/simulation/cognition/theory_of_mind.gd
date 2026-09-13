class_name TheoryOfMind
extends RefCounted
## 心智模型 v2（P1.5）：
##   1. 信念不再由事件类型固定增量更新，而是证据累积——每条证据带方向/权重/事件号，
##      置信度随证据量增长，证据可被后续证据削弱（允许"我误解了他"）。
##   2. 新增 response_model（响应预测）：我对"他被打拒绝后会怎样"持概率预测，
##      由预测误差更新——这是 Predict → Observe → Learn 的闭环。
## 旧 observe() 固定增量路径已删除；所有更新经由 CognitiveTransition。

const EVIDENCE_CAP := 12

# other_id -> { has_food: Entry, generous: Entry, reliable: Entry, last_updated: int }
# Entry = { value: -1..1, evidence_pos: [seq], evidence_neg: [seq] }
var _models := {}

# other_id -> { asks_me_again: 0..1, asks_other: 0..1, avoids_me: 0..1, shares_with_me: 0..1 }
# 这些是"我预测他的行为倾向"，初始 0.5（不确定），由预测误差修正
var _response_models := {}

# 预测误差历史（观察者维度）：[{tick, about, error}]，供长期验证误差是否下降
var prediction_errors: Array = []

# P1.7: 我最后一次知道某人在哪里（SEEK_PERSON 的目的地来源）
var last_seen := {}   # other_id -> {tile: Vector2i, tick: int}

func _entry(other_id: String, key: String) -> Dictionary:
	if not _models.has(other_id):
		_models[other_id] = {"last_updated": -1}
	if not _models[other_id].has(key):
		_models[other_id][key] = {"value": 0.0, "evidence_pos": [], "evidence_neg": []}  # 任意属性：has_water/has_spear/thirsty…无需预定义槽（P1.6 #15）
	return _models[other_id][key]

## 证据式更新：direction ∈ {-1,+1}，weight ∈ 0..1（由解释权重×学习速率决定）。
## value 向 direction 移动 weight 比例；置信度由证据量隐式决定（belief_about 折算）。
func add_evidence(other_id: String, key: String, direction: float, weight: float, seq: int, tick: int) -> void:
	var e := _entry(other_id, key)
	var w := clampf(weight, 0.0, 1.0)
	var d := 1.0 if direction >= 0.0 else -1.0
	e["value"] = clampf(float(e["value"]) + d * w * (1.0 - absf(float(e["value"])) * 0.5), -1.0, 1.0)
	# P1.7d Evidence 一等对象：{event_id, tick, kind(知觉/声明/社会/承诺)}——以后制度层靠它追溯"谁告诉我规则"
	var evidence := {"event_id": seq, "tick": tick, "kind": "percept"}
	if seq < 0:
		evidence["kind"] = "claim"  # 来自声明（-1 序号）
	if d > 0.0:
		e["evidence_pos"].append(evidence)
		if e["evidence_pos"].size() > EVIDENCE_CAP:
			e["evidence_pos"].pop_front()
	else:
		e["evidence_neg"].append(evidence)
		if e["evidence_neg"].size() > EVIDENCE_CAP:
			e["evidence_neg"].pop_front()
	_models[other_id]["last_updated"] = tick

## 置信度 = 证据量函数：无证据 0；1 条 0.4，3 条 0.78，6+ 条接近 1（边际递减）
func confidence_of(other_id: String, key: String) -> float:
	if not _models.has(other_id):
		return 0.0
	var e: Dictionary = _models[other_id].get(key, {})
	if e.is_empty():
		return 0.0
	var n := (e["evidence_pos"] as Array).size() + (e["evidence_neg"] as Array).size()
	return 1.0 - pow(0.6, n) if n > 0 else 0.0

func last_evidence_tick(other_id: String, key: String) -> int:
	if not _models.has(other_id):
		return -1
	var e: Dictionary = _models[other_id].get(key, {})
	if e.is_empty():
		return -1
	var newest := -1
	for collection in [e.get("evidence_pos", []), e.get("evidence_neg", [])]:
		for evidence in collection:
			if typeof(evidence) == TYPE_DICTIONARY:
				newest = maxi(newest, int(evidence.get("tick", -1)))
	return newest

## 读出的信念 = 方向 × 置信度（证据少 → 接近中性，不敢下结论）
func belief_about(other_id: String, key: String) -> float:
	if not _models.has(other_id):
		return 0.0
	var e: Dictionary = _models[other_id].get(key, {})
	if e.is_empty():
		return 0.0
	var conf := confidence_of(other_id, key)
	var n := (e["evidence_pos"] as Array).size() + (e["evidence_neg"] as Array).size()
	if n == 0:
		return 0.0
	return float(e["value"]) * clampf(conf, 0.3, 1.0)

# ── P7.2B：持有谓词统一 + 报告证据（claim provenance + 防重复放大） ──

## 全工程唯一的持有谓词（P7.1 与信息系统共用，禁止再造 owns/holder/possesses 变体）。
static func possession_predicate(item_id: String) -> String:
	return "has_item:" + item_id

## 报告式证据：保留"事实多旧（observed_tick）"与"我何时听说（received_tick）"两个时间，
## last_evidence_tick() 因此返回 observed_tick（防 stale laundering），
## _models.last_updated 使用 received_tick。同一 event_seq 只计一次（防重复放大）。
func add_reported_evidence(other_id: String, key: String, direction: float, weight: float,
		event_seq: int, observed_tick: int, received_tick: int, reporter_id: String) -> bool:
	var e := _entry(other_id, key)
	if event_seq >= 0:
		for collection in [e["evidence_pos"], e["evidence_neg"]]:
			for evidence in collection:
				if typeof(evidence) == TYPE_DICTIONARY \
						and int(evidence.get("event_id", -2)) == event_seq:
					return false  # 重复报告——不增计数、不抬置信度
	var w := clampf(weight, 0.0, 1.0)
	var d := 1.0 if direction >= 0.0 else -1.0
	e["value"] = clampf(float(e["value"]) + d * w * (1.0 - absf(float(e["value"])) * 0.5), -1.0, 1.0)
	var evidence := {"event_id": event_seq, "tick": observed_tick, "kind": "claim",
		"reporter_id": reporter_id, "received_tick": received_tick}
	if d > 0.0:
		e["evidence_pos"].append(evidence)
		if e["evidence_pos"].size() > EVIDENCE_CAP:
			e["evidence_pos"].pop_front()
	else:
		e["evidence_neg"].append(evidence)
		if e["evidence_neg"].size() > EVIDENCE_CAP:
			e["evidence_neg"].pop_front()
	_models[other_id]["last_updated"] = received_tick
	return true

## 只读查询：我自己 ToM 里对某谓词持有证据的全部主体（不含全局 actor 扫描）。
## P7.2B-R1：行内附 positive/negative 支持证据的最新 tick——正判断的新鲜度读
## 正证据、负判断读负证据，防止"新鲜反证刷新旧正证"的极性洗白。
func subjects_with_evidence(key: String) -> Array:
	var out: Array = []
	for other_id in _models:
		var e: Dictionary = _models[other_id].get(key, {})
		if e.is_empty():
			continue
		var n := (e["evidence_pos"] as Array).size() + (e["evidence_neg"] as Array).size()
		if n == 0:
			continue
		out.append({
			"actor_id": str(other_id),
			"belief": belief_about(str(other_id), key),
			"confidence": confidence_of(str(other_id), key),
			"last_evidence_tick": last_evidence_tick(str(other_id), key),
			"positive_evidence_tick": latest_supporting_tick(str(other_id), key, 1.0),
			"negative_evidence_tick": latest_supporting_tick(str(other_id), key, -1.0),
		})
	out.sort_custom(func(a, b):
		var as_ := absf(float(a["belief"])) * float(a["confidence"])
		var bs := absf(float(b["belief"])) * float(b["confidence"])
		if not is_equal_approx(as_, bs):
			return as_ > bs
		return str(a["actor_id"]) < str(b["actor_id"]))
	return out

## P7.2B-R1：极性感知新鲜度——指定方向支持证据的最新 tick。
## last_evidence_tick() 保持混合双方向最大值语义（旧调用方不变）；
## 持有判断（belief>0）的新鲜度必须走本函数 direction=+1。
func latest_supporting_tick(other_id: String, key: String, direction: float) -> int:
	if not _models.has(other_id):
		return -1
	var e: Dictionary = _models[other_id].get(key, {})
	if e.is_empty():
		return -1
	var collection: Array = e["evidence_pos"] if direction >= 0.0 else e["evidence_neg"]
	var newest := -1
	for evidence in collection:
		if typeof(evidence) == TYPE_DICTIONARY:
			newest = maxi(newest, int(evidence.get("tick", -1)))
	return newest

## 原始值（不折算置信度）——供解释系统判断"我以为他粮多还是粮少"
func raw_belief(other_id: String, key: String) -> float:
	if not _models.has(other_id):
		return 0.0
	var e: Dictionary = _models[other_id].get(key, {})
	if e.is_empty():
		return 0.0
	return float(e["value"])

## 证据削弱：新证据与既有结论矛盾时，把旧证据的分量挤掉（信念可以被推翻）
func weaken(other_id: String, key: String, amount: float) -> void:
	if not _models.has(other_id):
		return
	var e: Dictionary = _models[other_id].get(key, {})
	if e.is_empty():
		return
	e["value"] = float(e["value"]) * (1.0 - clampf(amount, 0.0, 1.0))

# ── 响应预测模型（Predict → Observe → Learn）──

func response_belief(other_id: String, dimension: String) -> float:
	if _response_models.has(other_id) and _response_models[other_id].has(dimension):
		return float(_response_models[other_id][dimension])
	return 0.5  # 不确定 = 均匀

func update_response(other_id: String, dimension: String, observed: float, learn_rate: float) -> void:
	if not _response_models.has(other_id):
		_response_models[other_id] = {"asks_me_again": 0.5, "asks_other": 0.5, "avoids_me": 0.5, "shares_with_me": 0.5}
	var cur: float = float(_response_models[other_id].get(dimension, 0.5))
	_response_models[other_id][dimension] = clampf(cur + (observed - cur) * clampf(learn_rate, 0.05, 1.0), 0.05, 0.95)

func record_prediction_error(tick: int, about: String, error: float) -> void:
	prediction_errors.append({"tick": tick, "about": about, "error": error})
	if prediction_errors.size() > 40:
		prediction_errors.pop_front()

func mean_prediction_error() -> float:
	if prediction_errors.is_empty():
		return 0.0
	var s := 0.0
	for pe in prediction_errors:
		s += float(pe["error"])
	return s / prediction_errors.size()

## 信念随时间衰减（旧印象淡忘）
func decay(before_tick: int, fade_days: int) -> void:
	for other_id in _models:
		var m: Dictionary = _models[other_id]
		if int(m["last_updated"]) < before_tick - fade_days * 24:
			for key in m:
				if key == "last_updated" or not (m[key] is Dictionary) or not m[key].has("value"):
					continue
				var fade_rate := 0.6 if key in ["hungry", "thirsty"] else 0.98  # 状态型感知快衰减，特质型慢衰减
				m[key]["value"] = float(m[key]["value"]) * fade_rate
				if absf(float(m[key]["value"])) < 0.02:
					m[key]["value"] = 0.0
## 指定他人的信念摘要（常用键）
func see_at(other_id: String, tile: Vector2i, tick: int) -> void:
	last_seen[other_id] = {"tile": tile, "tick": tick}

func last_seen_of(other_id: String) -> Dictionary:
	return last_seen.get(other_id, {})

func model_of(other_id: String) -> Dictionary:
	var out := {"has_food": belief_about(other_id, "has_food"), "generous": belief_about(other_id, "generous"),
		"reliable": belief_about(other_id, "reliable"), "last_updated": -1}
	if _models.has(other_id):
		out["last_updated"] = int(_models[other_id]["last_updated"])
	return out

## 全量快照（schema-free：任意属性键都导出）
func snapshot() -> Dictionary:
	var out := {}
	for other_id in _models:
		var entry: Dictionary = {}
		for key in _models[other_id]:
			if key == "last_updated" or not (_models[other_id][key] is Dictionary):
				continue
			entry[key] = belief_about(other_id, key)
		out[other_id] = entry
	return out
