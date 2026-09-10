class_name PlanAdoptionPolicy
extends RefCounted
## P6.4: a pure, subjective plan-level decision. Execution remains in the tracker.
## Input is an explicit self-state projection, never the world or another actor.
## RNG belongs to this actor's plan deliberation stream, separate from physical outcomes.

const NEEDS := {"HUNGER": "hunger", "THIRST": "thirst", "ISOLATION": "social"}
const GATES := {"HUNGER": 400.0, "THIRST": 400.0, "ISOLATION": 650.0}
const ESTIMATES := ["expected_benefit", "estimated_cost", "estimated_risk", "confidence"]

static func assess(plan: Dictionary, self_state: Dictionary, current_run: Dictionary = {}) -> Dictionary:
	var row := {"plan_id": str(plan.get("plan_id", "")), "root_goal": str(plan.get("root_goal", "")),
		"eligible": false, "reason": "", "value": 0.0, "probability": 0.0}
	if row["plan_id"] == "" or str(plan.get("status", "")) != "READY":
		row["reason"] = "PLAN_NOT_READY"
		return row
	var steps: Variant = plan.get("steps", null)
	if typeof(steps) != TYPE_ARRAY or steps.is_empty() or not PlanStepSpec.validate_plan_steps(steps):
		row["reason"] = "INVALID_STEPS"
		return row
	for field in ESTIMATES:
		var number: Variant = plan.get(field, null)
		if typeof(number) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(number)) or float(number) < 0.0:
			row["reason"] = "INVALID_ESTIMATES"
			return row
	var root := str(row["root_goal"])
	if not NEEDS.has(root):
		row["reason"] = "UNSUPPORTED_PROBLEM"
		return row
	var need := _finite(self_state.get("needs", {}).get(NEEDS[root], 0.0), 0.0)
	if need < float(GATES[root]):
		row["reason"] = "PROBLEM_RESOLVED"
		return row
	var traits: Dictionary = self_state.get("traits", {})
	var caution := clampf(_finite(traits.get("caution", 0.5), 0.5), 0.0, 1.0)
	var pragmatism := clampf(_finite(traits.get("pragmatism", 0.5), 0.5), 0.0, 1.0)
	var pressure := clampf(need / 1000.0, 0.0, 1.0)
	var benefit := clampf(float(plan["expected_benefit"]), 0.0, 1.0)
	var confidence := clampf(float(plan["confidence"]), 0.0, 1.0)
	if confidence <= 0.0 or benefit <= 0.0:
		row["reason"] = "NO_EXPECTED_BENEFIT"
		return row
	var remaining_fraction := 1.0
	if str(current_run.get("plan_id", "")) == str(row["plan_id"]):
		var old_steps: Array = current_run.get("steps", [])
		for i in old_steps.size():
			if str(old_steps[i].get("step_id", "")) == str(current_run.get("current_step_id", "")):
				remaining_fraction = float(old_steps.size() - i) / float(maxi(old_steps.size(), 1))
				break
	# Remaining effort can shrink after progress. Already spent effort earns no bonus.
	var remaining_cost := float(plan["estimated_cost"]) * remaining_fraction
	var cost_weight := 0.5 + pragmatism
	var risk_weight := 0.5 + 2.0 * caution
	var value := pressure * benefit * pow(confidence, 1.0 + caution) \
		/ (1.0 + remaining_cost * cost_weight + float(plan["estimated_risk"]) * risk_weight)
	row.merge({"eligible": true, "reason": "VALUED", "value": value,
		"problem_pressure": pressure, "expected_benefit": benefit, "confidence": confidence,
		"remaining_fraction": remaining_fraction, "remaining_cost": remaining_cost,
		"estimated_risk": float(plan["estimated_risk"]), "cost_weight": cost_weight,
		"risk_weight": risk_weight}, true)
	return row

static func deliberate(self_state: Dictionary, proposals: Array, current_run: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var out := {"mode": "SUBJECTIVE", "decision": "DEFER", "reason": "NO_ELIGIBLE_PLAN",
		"selected_plan_id": "", "candidates": [], "rng_consumed": false}
	var rows: Array = []
	var seen := {}
	for proposal in proposals:
		if typeof(proposal) != TYPE_DICTIONARY:
			continue
		var row := assess(proposal, self_state, current_run)
		var pid := str(row["plan_id"])
		if seen.has(pid):
			# Ambiguous identity fails closed for all copies, independent of input order.
			row["eligible"] = false
			row["reason"] = "DUPLICATE_PLAN_ID"
			for previous in rows:
				if str(previous["plan_id"]) == pid:
					previous["eligible"] = false
					previous["reason"] = "DUPLICATE_PLAN_ID"
		seen[pid] = true
		rows.append(row)
	rows.sort_custom(func(a, b): return str(a["plan_id"]) < str(b["plan_id"]))
	out["candidates"] = rows
	var viable: Array = []
	var current := {}
	var active := str(current_run.get("state", "")) in ["ACTIVE", "SUSPENDED"]
	for row in rows:
		row["disposition"] = "DEFER" if row["eligible"] else "REJECT"
		if row["eligible"]:
			viable.append(row)
			if active and str(row["plan_id"]) == str(current_run.get("plan_id", "")):
				current = row
	if viable.is_empty():
		return out
	var traits: Dictionary = self_state.get("traits", {})
	var caution := clampf(_finite(traits.get("caution", 0.5), 0.5), 0.0, 1.0)
	var curiosity := clampf(_finite(traits.get("curiosity", 0.5), 0.5), 0.0, 1.0)
	var strength := clampf(_finite(self_state.get("commitment_strength", 0.7), 0.7), 0.0, 1.0)
	var margin := 0.025 + 0.04 * strength
	var best := 0.0
	for row in viable:
		best = maxf(best, float(row["value"]))
	out["switch_margin"] = margin
	if not current.is_empty() and best - float(current["value"]) <= margin:
		out["decision"] = "RETAIN"
		out["reason"] = "COMMITMENT_RETAINED"
		out["selected_plan_id"] = current["plan_id"]
		current["disposition"] = "RETAIN"
		current["probability"] = 1.0
		return out
	var energy := clampf(_finite(self_state.get("needs", {}).get("energy", 800), 800) / 1000.0, 0.0, 1.0)
	var defer_value := 0.02 + (1.0 - energy) * 0.06
	var tau := clampf(0.04 + curiosity * 0.04 - caution * 0.02, 0.025, 0.1)
	out["temperature"] = tau
	out["defer_value"] = defer_value
	var max_value := maxf(best, defer_value)
	var denominator := exp((defer_value - max_value) / tau)
	for row in viable:
		row["probability"] = exp((float(row["value"]) - max_value) / tau)
		denominator += float(row["probability"])
	for row in viable:
		row["probability"] = float(row["probability"]) / denominator
	out["defer_probability"] = exp((defer_value - max_value) / tau) / denominator
	if rng == null:
		out["reason"] = "RNG_UNAVAILABLE"
		return out
	var roll := rng.randf()
	out["rng_consumed"] = true
	out["roll"] = roll
	var cumulative := 0.0
	for row in viable:
		cumulative += float(row["probability"])
		if roll < cumulative:
			out["selected_plan_id"] = row["plan_id"]
			out["decision"] = "RETAIN" if not current.is_empty() and current["plan_id"] == row["plan_id"] else "ADOPT"
			out["reason"] = "RECONSIDERED" if active else "SUBJECTIVE_VALUE_SELECTION"
			row["disposition"] = out["decision"]
			return out
	out["reason"] = "DEFER_OUTCOMPETED_PLANS"
	return out

static func _finite(value: Variant, fallback: float) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return fallback
	return float(value)
