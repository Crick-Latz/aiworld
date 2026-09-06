class_name ResourceSpec
extends RefCounted
## 资源规格表（P1.6 #10/#18/#19）：水、工具、任何未来资源经【数据配置】接入，
## 认知层（Interpretation/CognitiveTransition/ActionForecaster/Reflection）
## 禁止出现任何 resource-specific 分支——测试 L 会 grep 强制这一点。
##
## 三类依赖形态（GPT 第 18 条）：
##   food  消耗型资源（给了就没了）
##   water 生存型资源（公共水泉+距离→携带者之间的依赖）
##   tool  能力/劳动依赖（鱼叉=生产力，借出=信任）

const SPECS := {
	"food": {
		"need": "hunger",              # 对应的需求槽
			"percept": "hungry",           # 需求的感知槽名
		"predicate": "has_food",       # ToM 信念谓词（任意属性，无需新槽）
		"request_gate": 450,           # 需求多痛才会开口
		"give_min": 2,                 # 低于此拥有量时"分享=威胁自身"
		"relief": 200,                 # 收到后缓解多少
		"verb": "食物",
	},
	"water": {
		"need": "thirst",
			"percept": "thirsty",
		"predicate": "has_water",
		"request_gate": 500,
		"give_min": 1,
		"relief": 400,
		"verb": "水",
	},
	"fish_spear": {
		"need": "hunger",              # 求鱼叉是因为饿了又没工具捕鱼
			"percept": "hungry",
		"predicate": "has_spear",
		"request_gate": 400,
		"give_min": 1,                 # 只有 1 把时给出=大让步（效用公式已含更高门槛）
		"relief": 0,                   # 工具不直接缓解需求——它改变生产能力
		"verb": "鱼叉",
		"is_tool": true,
	},
}

static func spec(object_id: String) -> Dictionary:
	return SPECS.get(object_id, SPECS["food"])

## 语义事件（P1.6 #10）：认知层读 act/response/object，不读 event_type 字符串
static func semantics_of(event: Dictionary) -> Dictionary:
	var t := str(event.get("type", ""))
	match t:
		"food_requested":
			return {"act": "REQUEST", "object": "food", "response": "PENDING"}
		"food_request_accepted":
			return {"act": "REQUEST", "object": "food", "response": "ACCEPT"}
		"food_request_refused":
			return {"act": "REQUEST", "object": "food", "response": "REFUSE"}
		"water_requested":
			return {"act": "REQUEST", "object": "water", "response": "PENDING"}
		"water_request_accepted":
			return {"act": "REQUEST", "object": "water", "response": "ACCEPT"}
		"water_request_refused":
			return {"act": "REQUEST", "object": "water", "response": "REFUSE"}
		"tool_requested":
			return {"act": "REQUEST", "object": "fish_spear", "response": "PENDING"}
		"tool_request_accepted":
			return {"act": "REQUEST", "object": "fish_spear", "response": "ACCEPT"}
		"tool_request_refused":
			return {"act": "REQUEST", "object": "fish_spear", "response": "REFUSE"}
		"drank":
			return {"act": "ACQUIRE", "object": "water", "response": "DONE"}
		"fished", "fished_empty", "crafted":
			return {"act": "ACQUIRE", "object": "fish_spear", "response": "DONE"}
		"foraged", "ruins_loot", "explored_found", "foraged_empty", "ruins_empty":
			return {"act": "ACQUIRE", "object": "food", "response": str(event.get("type", "")).find("empty") != -1 and "FAILED" or "DONE"}
		"shared_food":
			return {"act": "GIVE", "object": "food", "response": "DONE"}
		"promise_made":
			return {"act": "PROMISE", "object": str(event.get("object", "food")), "response": "PENDING"}
		"promise_kept":
			return {"act": "PROMISE", "object": str(event.get("object", "food")), "response": "FULFILLED"}
		"promise_broken":
			return {"act": "PROMISE", "object": str(event.get("object", "food")), "response": "VIOLATED"}
		_:
			return {}
