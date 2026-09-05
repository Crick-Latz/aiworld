class_name HelpRules
extends RefCounted
## 求助决策规则（OBS-02，M09）：请求/接受/拒绝的唯一决策函数。
## 基准与对照夹具走同一函数，差别只在场景初始 reserve——不允许按场景名写结果。

# 决策：可给 = clamp(库存 - 保留量, 0, 请求数)；可给 >= 请求数 才接受。
# 返回 {decision: "accept"|"decline", give: int, reason_text: String}
static func decide_request(helper_inventory: int, helper_reserve: int, amount: int,
		helper_name: String, item_name: String) -> Dictionary:
	var give: int = clampi(helper_inventory - helper_reserve, 0, amount)
	if give >= amount:
		return {
			"decision": "accept",
			"give": amount,
			"reason_text": "%s 有余力：库存 %d、保留 %d，可给 %d" % [helper_name, helper_inventory, helper_reserve, amount],
		}
	return {
		"decision": "decline",
		"give": 0,
		"reason_text": "%s 保留 %d 后最多可给 %d，不满足请求 %d" % [helper_name, helper_reserve, give, amount],
	}
