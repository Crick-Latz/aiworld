class_name BeliefStore
extends RefCounted
## 主观世界模型（阶段 C）：每个角色对世界的"信念"而非"知识"。
## World Truth ≠ Character Belief。同一事实，不同角色可以有不同信念、
## 不同置信度、不同来源、甚至完全错误的认知。
## 这是产生误解/谣言/欺骗/侦察/确认/误判的核心机制。

# belief 结构: { "董卓已死": { "confidence": 0.55, "source": "rumor", "learned_tick": 42 } }
var _beliefs := {} # statement -> belief info

func believe(statement: String, confidence: float, source: String, tick: int) -> void:
	_beliefs[statement] = {
		"confidence": clampf(confidence, 0.0, 1.0),
		"source": source,
		"learned_tick": tick,
	}

func disbelieve(statement: String) -> void:
	_beliefs.erase(statement)

func confidence_of(statement: String) -> float:
	if _beliefs.has(statement):
		return float(_beliefs[statement]["confidence"])
	return 0.0

func believes(statement: String, threshold := 0.5) -> bool:
	return confidence_of(statement) >= threshold

func source_of(statement: String) -> String:
	if _beliefs.has(statement):
		return str(_beliefs[statement]["source"])
	return ""

## 更新置信度（贝叶斯式）：新证据融合旧信念
func update_confidence(statement: String, new_evidence: float, evidence_weight: float = 0.5) -> void:
	if not _beliefs.has(statement):
		believe(statement, new_evidence, "direct", 0)
		return
	var old: float = float(_beliefs[statement]["confidence"])
	var blended := old * (1.0 - evidence_weight) + new_evidence * evidence_weight
	_beliefs[statement]["confidence"] = clampf(blended, 0.0, 1.0)

## 获取所有与关键词相关的信念
func beliefs_about(keyword: String) -> Dictionary:
	var out := {}
	for statement in _beliefs:
		if statement.find(keyword) >= 0:
			out[statement] = _beliefs[statement]
	return out

## 人格动力学：不同的人形成/放弃信念的速度不同
func learn(personality: PersonalityProfile, statement: String, confidence: float, source: String, tick: int) -> void:
	# trust_learning_rate 高 → 新信息更容易接受
	# 谨慎高 → 新信息接受度低
	var caution: float = personality.traits.get("caution", 0.5)
	var adjusted := confidence * (1.0 - caution * 0.3)
	believe(statement, adjusted, source, tick)

func forget_disconfirmed() -> void:
	# 移除置信度降到极低的信念
	var to_remove: Array = []
	for statement in _beliefs:
		if float(_beliefs[statement]["confidence"]) < 0.05:
			to_remove.append(statement)
	for s in to_remove:
		_beliefs.erase(s)

func snapshot() -> Dictionary:
	return _beliefs.duplicate(true)
