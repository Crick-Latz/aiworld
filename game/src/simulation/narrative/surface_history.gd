class_name SurfaceHistory
extends RefCounted
## P3c-3 表面历史 + 称呼策略（均为 presentation-only）：
##   SurfaceHistory——最近几句台词的表面记录（避免连续重复，保持节奏）
##     禁止：SurfaceHistory → Belief / Decision / Relationship
##   AddressPolicy——确定性称呼选择（随关系变化，LLM 不得发明昵称/侮辱性称呼）

const MAX_HISTORY := 5

# ── SurfaceHistory（每 actor 独立；presentation-only）──
static func record(actor: Dictionary, text: String, tick: int) -> void:
	var hist: Array = actor.get("surface_history", [])
	hist.append({"text": text, "tick": tick})
	if hist.size() > MAX_HISTORY:
		hist.pop_front()
	actor["surface_history"] = hist

static func recent(actor: Dictionary, count := 3) -> Array:
	var hist: Array = actor.get("surface_history", [])
	return hist.slice(maxi(0, hist.size() - count), hist.size())

static func is_repetition(actor: Dictionary, new_text: String) -> bool:
	for h in recent(actor, 2):
		if str(h.get("text", "")) == new_text:
			return true
	return false

# ── AddressPolicy（确定性；第 14-15 条）──
# 状态：USE_NAME / USE_ROLE / SECOND_PERSON / OMIT
static func address_mode(speaker: Dictionary, target_id: String, relationships, speech_act: Dictionary) -> String:
	if target_id == "":
		return "OMIT"
	var speaker_id := str(speaker.get("id", ""))
	var trust := 0
	if relationships != null:
		trust = relationships.composite_trust(speaker_id, target_id)
	var fear_dim := 0
	if relationships != null:
		fear_dim = relationships.get_dim(speaker_id, target_id, "fear")
	var act := str(speech_act.get("act_type", ""))
	# 高冲突/恐惧 → 冷漠第二人称（"你"）
	if fear_dim > 300 or trust < -200:
		return "SECOND_PERSON"
	# 公开正式行为 → 角色称呼
	if ["PROPOSE_RULE", "SUPPORT_RULE", "OPPOSE_RULE", "CONFRONT"].has(act):
		return "USE_NAME"
	# 高信任/温暖 → 名字
	if trust > 200:
		return "USE_NAME"
	# 中性 → 名字（比第二人称温和）
	return "USE_NAME"

## 称呼文本渲染（确定性——不用 LLM）
static func address_text(mode: String, target_name: String) -> String:
	match mode:
		"USE_NAME":
			return target_name
		"SECOND_PERSON":
			return "你"
		_:
			return ""
