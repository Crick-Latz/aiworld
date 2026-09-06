class_name SpeechAct
extends RefCounted
## P3b-1 结构化言语行为（SpeechAct Schema）：
## 认知系统决定"是否说/对谁说/想达到什么/说真话还是撒谎"——
## LLM 唯一职责是把已决定的结构化行为渲染成一句人话（Surface Realization）。
##
## 三层分离（GPT P3b 第 2 条）：
##   Layer A — Speaker Belief（说话者的真实信念）
##   Layer B — Communicated Claim（系统决定传达的命题，可能是谎言）
##   Layer C — Surface Utterance（LLM 生成的台词）
##   三层绝不能互相代替。
##
## 接收方收到的是 Layer B 的结构化 Claim + 本 SpeechAct 元数据——
## 绝不重新 NLP 解析 LLM 文本。

const SCHEMA_VERSION := "speech-act-1.0"

## 第一版 Act Types：只接当前系统真实存在的社会行为（GPT 第 4 条）
const ACT_TYPES := [
	"ASK_REASON", "ANSWER_REASON", "DEFLECT",
	"REQUEST", "ACCEPT_REQUEST", "REFUSE_REQUEST",
	"THANK", "PROMISE", "REMIND_PROMISE",
	"PROPOSE_RULE", "SUPPORT_RULE", "OPPOSE_RULE", "COUNTER_PROPOSE_RULE",
	"CONFRONT", "WARN", "REPORT_INFORMATION",
]

## 从模拟事件构建 SpeechAct（确定性适配器——每个已有社会事件→一个言语行为）
static func from_event(e: Dictionary, speaker: Dictionary) -> Dictionary:
	var t := str(e.get("type", ""))
	var speaker_id := str(e.get("actor_id", ""))
	var audience: Array = []
	var to_id := str(e.get("to_id", str(e.get("target_id", str(e.get("proposer_id", ""))))))
	if to_id != "":
		audience.append(to_id)
	var act := ""
	var goal := ""
	var props: Array = []
	var sincerity := "SINCERE"  # 第一版全部真诚（欺骗由 simulation 未来决定）
	var stance := 0
	var tone: Dictionary = {}
	match t:
		"reason_asked":
			act = "ASK_REASON"
			goal = "寻求解释"
		"reason_claimed":
			act = "ANSWER_REASON"
			goal = "给出解释"
			props.append({"predicate": "HAS_LOW_FOOD", "subject": speaker_id,
				"source_event_ids": [int(e.get("seq", 0))]})
		"reason_deflected":
			act = "DEFLECT"
			goal = "回避"
		"food_requested", "water_requested", "tool_requested":
			act = "REQUEST"
			goal = "请求资源"
			props.append({"predicate": "NEEDS_RESOURCE", "subject": speaker_id,
				"object": str(e.get("object", "food")), "source_event_ids": [int(e.get("seq", 0))]})
		"food_request_accepted", "water_request_accepted", "tool_request_accepted":
			act = "ACCEPT_REQUEST"
			goal = "同意请求"
			stance = 1
		"food_request_refused", "water_request_refused", "tool_request_refused":
			act = "REFUSE_REQUEST"
			goal = "拒绝请求"
			stance = -1
			props.append({"predicate": "REFUSAL_REASON", "subject": speaker_id,
				"reason": str(e.get("reason", "")), "source_event_ids": [int(e.get("seq", 0))]})
		"promise_made":
			act = "PROMISE"
			goal = "承诺回报"
			props.append({"predicate": "WILL_REPAY", "subject": speaker_id,
				"source_event_ids": [int(e.get("seq", 0))]})
		"promise_kept":
			act = "THANK"
			goal = "表达感谢"
			stance = 1
		"rule_proposed":
			act = "PROPOSE_RULE"
			goal = "提议规则"
			props.append({"predicate": "PROPOSES_RULE", "subject": speaker_id,
				"object": str(e.get("object", "")), "source_event_ids": [int(e.get("seq", 0))]})
		"rule_supported":
			act = "SUPPORT_RULE"
			goal = "公开支持"
			stance = 1
		"rule_opposed":
			act = "OPPOSE_RULE"
			goal = "公开反对"
			stance = -1
		"confronted_violation":
			act = "CONFRONT"
			goal = "当面对质"
			stance = -1
		"shared_food":
			act = "THANK"
			goal = "分享关怀"
			stance = 1
		_:
			return {}  # 无对应结构化行为 → 不生成台词（GPT 第 4 条）

	# 情绪/风格参数从说话者当前状态提取（仅影响表面——不影响 DecisionEngine）
	var p: PersonalityProfile = speaker.get("personality", null)
	if p != null:
		tone = {
			"anger": clampf(float(p.emotions.get("anger", 0.0)), 0.0, 1.0),
			"sadness": clampf(float(p.emotions.get("sadness", 0.0)), 0.0, 1.0),
			"expressiveness": float(p.traits.get("expressiveness", 0.5)),
			"directness": float(p.traits.get("action_bias", 0.5)),
			"politeness": float(p.traits.get("conflict_avoidance", 0.5)),
		}
	return {
		"speech_id": "SP_%d_%s" % [int(e.get("seq", 0)), speaker_id],
		"schema_version": SCHEMA_VERSION,
		"speaker_id": speaker_id,
		"audience_ids": audience,
		"act_type": act,
		"communicative_goal": goal,
		"propositions": props,
		"sincerity": sincerity,
		"stance": stance,
		"emotional_tone": tone,
		"publicness": "PUBLIC" if audience.size() > 1 else "PRIVATE",
		"source_event_ids": [int(e.get("seq", 0))],
		"source_trace_ids": [],
		"tick": int(e.get("tick", 0)),
	}
