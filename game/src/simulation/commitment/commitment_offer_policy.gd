class_name CommitmentOfferPolicy
extends RefCounted
## P7.2 §七/§八：承诺估值的纯函数层。所有输入只来自单一角色的主观上下文——
## B 端不读 A 的真实未来，A 端不读 B 的真实库存；两端都允许判断错误。

const DEFAULT_ACCEPT_THRESHOLD := 0.35

## B 对 "A 的承诺值多少" 的一般估计（offer 时机，尚无具体条款）。
## 单调性：reliable 信念↑ / 关系↑ / 互惠规范↑ → 估值不降；承诺负担↑ → 估值降。
static func estimate_promise_value(creditor_context: Dictionary) -> float:
	var reliability := clampf(float(creditor_context.get("debtor_reliability_belief", 0.5)), 0.0, 1.0)
	var relationship := clampf((float(creditor_context.get("relationship", 0.0)) + 1.0) * 0.5, 0.0, 1.0)
	var reciprocity := clampf(float(creditor_context.get("own_reciprocity_norm", 0.5)), 0.0, 1.0)
	var load := clampf(float(creditor_context.get("debtor_visible_commitment_load", 0.0)), 0.0, 1.0)
	return clampf(
		reliability * 0.45
		+ relationship * 0.15
		+ reciprocity * 0.10
		+ (1.0 - load) * 0.15,
		0.0, 1.0
	)

## B 验证 A 的具体承诺条款（counter 接受前）。
## 输出 offer_value 满足 §七 单调性：reliable↑ 不降、覆盖率↑ 不降、深度不信任→降低。
static func evaluate_commitment_offer(
	demanded_terms: Dictionary,
	offered_terms: Dictionary,
	creditor_context: Dictionary
) -> Dictionary:
	var reliability := clampf(float(creditor_context.get("debtor_reliability_belief", 0.5)), 0.0, 1.0)
	var relationship := clampf((float(creditor_context.get("relationship", 0.0)) + 1.0) * 0.5, 0.0, 1.0)
	var reciprocity := clampf(float(creditor_context.get("own_reciprocity_norm", 0.5)), 0.0, 1.0)
	var load := clampf(float(creditor_context.get("debtor_visible_commitment_load", 0.0)), 0.0, 1.0)
	var demanded_quantity := maxi(1, int(demanded_terms.get("quantity", 1)))
	var offered_quantity := maxi(0, int(offered_terms.get("quantity", 0)))
	var coverage := clampf(float(offered_quantity) / float(demanded_quantity), 0.0, 1.0)
	var due_slack := 0.0
	var demanded_due := int(demanded_terms.get("due_tick", 0))
	var offered_due := int(offered_terms.get("due_tick", 0))
	if demanded_due > 0 and offered_due > 0:
		# 提前兑现的承诺更值钱：越接近对方要求的期限折扣越少。
		due_slack = clampf(float(demanded_due - offered_due) / 240.0, -0.5, 0.5)
	var offer_value := clampf(
		reliability * 0.40
		+ coverage * 0.25
		+ relationship * 0.15
		+ reciprocity * 0.10
		- load * 0.20
		+ due_slack * 0.10,
		0.0, 1.0
	)
	return {
		"offer_value": offer_value,
		"coverage": coverage,
		"reliability_belief": reliability,
		"accepted": offer_value >= clampf(float(creditor_context.get("minimum_offer_value", 0.35)), 0.0, 1.0),
		"reason": "OFFER_VALUE_MET" if offer_value >= clampf(float(creditor_context.get("minimum_offer_value", 0.35)), 0.0, 1.0) else "OFFER_VALUE_BELOW_MINIMUM",
	}

## A 是否接受"未来回报"型交换条件（§八 请求者独立决策）。
## 确定性主观判断：可错性来自输入状态，不来自隐藏随机。
static func evaluate_requester_acceptance(requester_context: Dictionary) -> Dictionary:
	var urgency := clampf(float(requester_context.get("need_urgency", 0.5)), 0.0, 1.0)
	var reciprocity := clampf(float(requester_context.get("own_reciprocity_norm", 0.5)), 0.0, 1.0)
	var trust := clampf(float(requester_context.get("trust_in_creditor", 0.5)), 0.0, 1.0)
	var relationship := clampf((float(requester_context.get("relationship", 0.0)) + 1.0) * 0.5, 0.0, 1.0)
	var reobtainability := clampf(float(requester_context.get("subjective_reobtainability", 0.5)), 0.0, 1.0)
	var load := clampf(float(requester_context.get("active_commitment_load", 0.0)), 0.0, 1.0)
	var quantity_ratio := clampf(float(requester_context.get("promised_quantity_ratio", 1.0)), 0.0, 1.0)
	var willingness := clampf(
		urgency * 0.35
		+ reobtainability * 0.30
		+ reciprocity * 0.15
		+ trust * 0.10
		+ relationship * 0.10
		- load * 0.30
		- quantity_ratio * 0.10,
		0.0, 1.0
	)
	var threshold := clampf(float(requester_context.get("accept_threshold", DEFAULT_ACCEPT_THRESHOLD)), 0.0, 1.0)
	# A 自己的兑现期限估计：知道来源/知道谁持有时接近对方的窗口；
	# 完全无知时显著更长——如实报出即构成条款分歧（§十三 的自然来源）。
	var due_estimate := maxi(60, int(round(240.0 * (1.3 - 0.6 * reobtainability))))
	return {
		"accept": willingness >= threshold,
		"willingness": willingness,
		"reason": "WILLINGNESS_MET" if willingness >= threshold else "WILLINGNESS_BELOW_THRESHOLD",
		"offered_due_ticks": due_estimate,
	}

## P7.2 §十四：由权威台账派生承诺负担（0..1）。
static func commitment_load(active_count: int, capacity: int = 3) -> float:
	return clampf(float(active_count) / float(maxi(1, capacity)), 0.0, 1.0)
