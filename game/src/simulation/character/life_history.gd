class_name LifeHistory
extends RefCounted
## 人生经历（P0 扩展）：角色不是只有 Persona，而是有一段人生。
## 经历塑造初始信念、价值观、情绪触发点和学习速率。
## LifeMem 启发：人格不是静态标签，是纵向经历压缩后的产物。

var events: Array = [] # [{ "age": int, "desc": str, "type": str, "impact": str }]

func _init(life_events: Array = []) -> void:
	events = life_events

## 经历 → 初始信念映射
func derived_beliefs() -> Dictionary:
	var beliefs := {}
	for e in events:
		var type := str(e.get("type", ""))
		match type:
			"famine":
				beliefs["食物是命"] = 0.95
				beliefs["食物短缺随时可能发生"] = 0.85
			"betrayal":
				beliefs["别人终究会背叛你"] = 0.7
			"rescue":
				beliefs["有人愿意无条件帮助"] = 0.6
			"loss":
				beliefs["重要的人会突然失去"] = 0.8
			"authority_abuse":
				beliefs["权力不可信"] = 0.7
			"cooperation_success":
				beliefs["合作能解决大问题"] = 0.8
			_:
				pass
	return beliefs

## 经历 → 学习速率修饰（欧恩经历饥荒 → 对食物损失的敏感度极高）
func derived_sensitivities() -> Dictionary:
	var s := {
		"trust_gain_rate": 0.5,
		"trust_loss_rate": 0.5,
		"food_loss_sensitivity": 0.5,
		"betrayal_sensitivity": 0.5,
		"authority_sensitivity": 0.5,
		"loss_aversion": 0.5,
		"fear_generalization": 0.5,
		"forgiveness_rate": 0.5,
	}
	for e in events:
		match str(e.get("type", "")):
			"famine":
				s["food_loss_sensitivity"] = 0.95
				s["loss_aversion"] = 0.8
			"betrayal":
				s["trust_gain_rate"] = 0.2
				s["trust_loss_rate"] = 0.9
				s["betrayal_sensitivity"] = 0.9
				s["forgiveness_rate"] = 0.15
			"rescue":
				s["trust_gain_rate"] = 0.8
			"loss":
				s["fear_generalization"] = 0.7
				s["loss_aversion"] = 0.75
			"cooperation_success":
				s["trust_gain_rate"] = 0.75
				s["forgiveness_rate"] = 0.7
	return s

## 生成人可读的背景故事摘要
func summary() -> String:
	var parts: Array = []
	for e in events:
		parts.append(str(e.get("desc", "")))
	if parts.is_empty():
		return "平凡的一生"
	return "、".join(parts)
