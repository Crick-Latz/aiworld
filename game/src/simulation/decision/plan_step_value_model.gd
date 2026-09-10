class_name PlanStepValueModel
extends RefCounted
## P6.3B-4：把根问题的因果价值有限度地传播到当前计划步骤。
##
## 设计边界：
## - Registry utility 仍是局部行为价值，也是下限；这里不覆盖 Registry 的判断。
## - 只使用角色自己的 needs + 已采用计划的公开估计，不读取世界真值。
## - 不给固定 plan bonus。价值随根问题压力、收益、置信度、成本、风险连续变化。
## - 输出纯数据，便于 DecisionTrace 解释、paired run 对照与确定性重放。

static func assess(actor: Dictionary, execution_step: Dictionary, candidate: Dictionary) -> Dictionary:
	var original := float(candidate.get("utility", 0.0))
	var root_goal := str(execution_step.get("root_goal", ""))
	var step: Dictionary = execution_step.get("step", {})
	var step_kind := str(step.get("kind", ""))
	var propagation_eligible := step_kind in ["ACQUIRE", "CRAFT"]
	var valuation: Dictionary = execution_step.get("valuation_context", {})
	var pressure := _root_pressure(root_goal, actor.get("needs", {}))
	var benefit := clampf(float(valuation.get("expected_benefit", 0.0)), 0.0, 1.0)
	var confidence := clampf(float(valuation.get("confidence", 0.0)), 0.0, 1.0)
	var cost := maxf(float(valuation.get("estimated_cost", 0.0)), 0.0)
	var risk := maxf(float(valuation.get("estimated_risk", 0.0)), 0.0)
	var step_count := maxi(int(valuation.get("step_count", 0)), 1)
	var step_index := maxi(int(valuation.get("step_index", 0)), 0)

	# estimated_cost 是整条计划成本。除以步骤数得到平均步骤负担，使不同长度计划
	# 在同一尺度上比较，同时仍保留成本对前置步骤价值的抑制。
	var mean_step_cost := cost / float(step_count)
	var causal_value := 0.0
	if propagation_eligible and pressure > 0.0 and benefit > 0.0 and confidence > 0.0:
		causal_value = clampf(
			pressure * benefit * confidence / (1.0 + mean_step_cost + risk),
			0.0, 1.0)

	# 概率并集式合成：局部 utility 越高，可被补足的空间越小；因果价值只补足，
	# 不会把 Registry 已给出的价值压低。负值视为局部 veto，>1 视为强本地价值，均原样保留。
	var effective := original
	if causal_value > 0.0 and original >= 0.0 and original < 1.0:
		var bounded_local := clampf(original, 0.0, 1.0)
		effective = maxf(original, 1.0 - (1.0 - bounded_local) * (1.0 - causal_value))

	return {
		"root_goal": root_goal,
		"step_kind": step_kind,
		"propagation_eligible": propagation_eligible,
		"problem_pressure": pressure,
		"expected_benefit": benefit,
		"confidence": confidence,
		"estimated_cost": cost,
		"estimated_risk": risk,
		"mean_step_cost": mean_step_cost,
		"step_index": step_index,
		"step_count": step_count,
		"causal_value": causal_value,
		"original_utility": original,
		"effective_utility": effective,
		"utility_delta": effective - original,
	}

static func _root_pressure(root_goal: String, needs: Dictionary) -> float:
	# ProblemActivationAdapter 已负责阈值门控；这里只度量已激活问题的当前压力，
	# 因而不复制另一套 activation threshold。
	match root_goal:
		"HUNGER":
			return clampf(float(needs.get("hunger", 0.0)) / 1000.0, 0.0, 1.0)
		"THIRST":
			return clampf(float(needs.get("thirst", 0.0)) / 1000.0, 0.0, 1.0)
		"ISOLATION":
			return clampf(float(needs.get("social", 0.0)) / 1000.0, 0.0, 1.0)
	return 0.0
