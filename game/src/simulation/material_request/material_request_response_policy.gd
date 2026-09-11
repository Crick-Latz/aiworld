extends RefCounted
class_name MaterialRequestResponsePolicy

const Contract = preload("res://src/simulation/material_request/material_request_contract.gd")

func evaluate(request: Dictionary, recipient_context: Dictionary, roll: float) -> Dictionary:
	var requested := maxi(1, int(request.get("requested_quantity", 1)))
	var inventory_quantity := maxi(0, int(recipient_context.get("inventory_quantity", 0)))
	var reserve_quantity := maxi(0, int(recipient_context.get("reserve_quantity", 0)))
	var surplus := maxi(0, inventory_quantity - reserve_quantity)
	var relationship := clampf((float(recipient_context.get("relationship", 0.0)) + 1.0) * 0.5, 0.0, 1.0)
	var trust := clampf(float(recipient_context.get("trust", relationship)), 0.0, 1.0)
	var generosity := clampf(float(recipient_context.get("generosity", 0.5)), 0.0, 1.0)
	var own_need := clampf(float(recipient_context.get("own_need_pressure", 0.0)), 0.0, 1.0)
	var risk_aversion := clampf(float(recipient_context.get("risk_aversion", 0.5)), 0.0, 1.0)
	var commitment_load := clampf(float(recipient_context.get("commitment_load", 0.0)), 0.0, 1.0)
	var request_urgency := clampf(float(request.get("urgency", 0.5)), 0.0, 1.0)
	var offer_value := clampf(float(recipient_context.get("exchange_offer_value", 0.0)), 0.0, 1.0)
	var bounded_roll := clampf(roll, 0.0, 1.0)

	if surplus <= 0:
		return _result(
			Contract.OUTCOME_REFUSE,
			"NO_TRANSFERABLE_SURPLUS",
			0,
			0.0,
			surplus,
			{}
		)

	var coverage := minf(1.0, float(surplus) / float(requested))
	var cooperation_value := (
		trust * 0.24
		+ relationship * 0.14
		+ generosity * 0.20
		+ request_urgency * 0.12
		+ offer_value * 0.20
		+ coverage * 0.10
		- own_need * 0.23
		- risk_aversion * 0.08
		- commitment_load * 0.09
	)
	var accept_probability := clampf(0.12 + cooperation_value, 0.02, 0.95)

	if surplus < requested:
		# Partial stock creates an option, not an obligation. The holder still
		# evaluates cooperation and can keep the available surplus when the
		# request conflicts with their needs, risk or commitments.
		if bounded_roll <= accept_probability or offer_value >= 0.35 or relationship >= 0.65:
			var counter_quantity := surplus
			return _result(
				Contract.OUTCOME_COUNTER,
				"PARTIAL_SURPLUS_COUNTER",
				counter_quantity,
				accept_probability,
				surplus,
				{
					"quantity": counter_quantity,
					"requires_exchange": offer_value < 0.35 and own_need > 0.35,
				}
			)
		return _result(
			Contract.OUTCOME_REFUSE,
			"PARTIAL_SURPLUS_WITHHELD",
			0,
			accept_probability,
			surplus,
			{}
		)

	if bounded_roll <= accept_probability:
		return _result(
			Contract.OUTCOME_ACCEPT,
			"COOPERATION_THRESHOLD_MET",
			requested,
			accept_probability,
			surplus,
			{}
		)

	if offer_value >= 0.35 or relationship >= 0.65:
		var counter: Dictionary = {
			"quantity": requested,
			"requires_exchange": true,
			"minimum_offer_value": minf(1.0, maxf(0.35, bounded_roll - accept_probability)),
		}
		return _result(
			Contract.OUTCOME_COUNTER,
			"COOPERATION_REQUIRES_CONDITION",
			requested,
			accept_probability,
			surplus,
			counter
		)

	return _result(
		Contract.OUTCOME_REFUSE,
		"COOPERATION_THRESHOLD_NOT_MET",
		0,
		accept_probability,
		surplus,
		{}
	)

func _result(
	outcome: String,
	reason: String,
	quantity: int,
	accept_probability: float,
	surplus: int,
	counter: Dictionary
) -> Dictionary:
	return {
		"outcome": outcome,
		"reason": reason,
		"accepted_quantity": quantity,
		"accept_probability": accept_probability,
		"surplus": surplus,
		"counter": counter.duplicate(true),
		"mutated_inventory": false,
	}
