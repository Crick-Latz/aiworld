class_name DialogueValidator
extends RefCounted
## P3b-3 台词安全验证器：
## 验证 LLM 台词输出不得改变 SpeechAct 语义（拒绝→接受、加承诺、加威胁、加事实）。
## 无法验证 → fallback TemplateDialogueRenderer。

static func validate(output, speech_act: Dictionary) -> Dictionary:
	if typeof(output) != TYPE_DICTIONARY:
		return {"ok": false, "code": "E_OUTPUT_NOT_DICT"}
	var o: Dictionary = output
	var text := str(o.get("text", ""))
	if text.strip_edges() == "":
		return {"ok": false, "code": "E_TEXT_EMPTY"}
	# speech_id 匹配
	if str(o.get("speech_id", "")) != str(speech_act.get("speech_id", "")):
		return {"ok": false, "code": "E_SPEECH_ID_MISMATCH"}
	var act := str(speech_act.get("act_type", ""))
	# DC：REFUSE 不得变 ACCEPT（关键词检测——保守拒绝比漏过安全）
	if act == "REFUSE_REQUEST" or act == "OPPOSE_RULE":
		if _has_accept_markers(text):
			return {"ok": false, "code": "E_STANCE_REVERSED",
				"message": "拒绝行为不得被渲染为同意：%s" % text.substr(0, 30)}
	# ACCEPT/THANK 不得变拒绝
	if act == "ACCEPT_REQUEST" or act == "SUPPORT_RULE" or act == "THANK":
		if _has_refuse_markers(text):
			return {"ok": false, "code": "E_STANCE_REVERSED",
				"message": "同意行为不得被渲染为拒绝：%s" % text.substr(0, 30)}
	# 不得添加新承诺
	if act != "PROMISE" and act != "REMIND_PROMISE":
		if _has_promise_markers(text):
			return {"ok": false, "code": "E_ADDED_PROMISE",
				"message": "台词不得添加未经系统决定的承诺"}
	# 不得添加威胁
	if act != "CONFRONT" and act != "WARN":
		if _has_threat_markers(text):
			return {"ok": false, "code": "E_ADDED_THREAT"}
	return {"ok": true, "code": "OK"}

static func _has_accept_markers(text: String) -> bool:
	return text.find("好的，我给") != -1 or text.find("当然，我给") != -1 \
		or text.find("拿去吧") != -1 or text.find("分给你") != -1 \
		or text.find("我同意") != -1

static func _has_refuse_markers(text: String) -> bool:
	return text.find("不行") != -1 or text.find("我拒绝") != -1 \
		or text.find("不能给") != -1 or text.find("我反对") != -1

static func _has_promise_markers(text: String) -> bool:
	return text.find("我答应") != -1 or text.find("我保证") != -1 \
		or text.find("以后一定") != -1 or text.find("我会还") != -1

static func _has_threat_markers(text: String) -> bool:
	return text.find("否则") != -1 or text.find("你等着") != -1 \
		or text.find("别怪我") != -1
