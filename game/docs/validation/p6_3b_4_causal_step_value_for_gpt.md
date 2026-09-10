> 2026-09-10 后续验证补记：本阶段源码已用用户提供的 Linux Godot 完成 32 suites / 825 assertions 验证。自然对照的 causal uplift 为零，完整计划链仍为零。新实现与最终证据见 [P6.4 报告](p6_4_framework_for_gpt.md)。以下保留原阶段记录。

# P6.3B-4 — Root-goal causal value propagation into prerequisite steps

Date: 2026-09-10
Baseline: `498f55a07fc693f39caced22dbe7196c7e64d3fa`

## Why this is the next bottleneck

P6.3B-3 corrected plan lifetime accounting from elapsed world ticks to actual missed
decision opportunities. In the unchanged 61000–61009 / 1000-tick natural pilot,
completed runs rose from 30 to 43 and `NO_PROGRESS_TIMEOUT` fell from 309 to 171,
but there was still **zero natural ACQUIRE→CRAFT→MAIN completion**.

The remaining gap is decision semantics. A prerequisite such as gathering wood for a
fish spear is still scored as an unrelated `gather_wood` action. The already-adopted
HUNGER plan knows the step's causal purpose, but that purpose contributes nothing to
the choice probability.

This package addresses only that gap. It does not tune resources, pick favorable
seeds, change personality, force a selected action, or add a flat plan bonus.

## Implemented behavior

New pure decision helper:

`res://src/simulation/decision/plan_step_value_model.gd`

For an active **ACQUIRE** or **CRAFT** step it derives:

```text
problem_pressure = subjective_need / 1000
mean_step_cost  = estimated_plan_cost / step_count
causal_value    = pressure * expected_benefit * confidence
                  / (1 + mean_step_cost + estimated_risk)

effective_utility = 1 - (1 - registry_utility) * (1 - causal_value)
```

`effective_utility` is never below Registry utility. Negative Registry values are treated as local vetoes, and Registry values above 1 are
preserved. Missing plan estimates and unsupported root problems fail closed with
zero causal value.

The first supported roots are the same three roots currently activated by
`ProblemActivationAdapter`: HUNGER, THIRST, ISOLATION. This module reads only the
actor's own need state and the adopted plan snapshot; it does not inspect hidden
world truth.

### Why MAIN is excluded

MAIN actions already encode their immediate root need in the existing Registry
utility (`fish`/`forage_berries` use hunger, `drink_water` uses thirst). Reapplying
root pressure there would double-count the same motive. P6.3B-4 therefore propagates
value only to prerequisites: ACQUIRE and CRAFT.

## Runtime wiring

`IslandSimulation.agency_causal_step_value_enabled` is a new independent flag,
default `false`.

When all of the following are true:

- `agency_mode == "LIVE_BRIDGE"`
- `agency_plan_execution_enabled == true`
- `agency_causal_step_value_enabled == true`
- the tracker supplies a current execution step

`DecisionEngine` evaluates matching prerequisite candidates with
`PlanStepValueModel`. Candidate identity, target, duration, recipe, legality,
Consideration Set rules and softmax all remain unchanged. Only the utility seen by
the existing decision competition can be supplemented.

`PlanExecutionTracker.prepare_decision()` now carries a bounded
`valuation_context` copied from the adopted plan snapshot:

- expected_benefit
- estimated_cost
- estimated_risk
- confidence
- step_index
- step_count

No live hidden-world fields are added.

## Audit trace

`DecisionTrace.agency_execution` now includes:

- `utility_mode = REGISTRY_ONLY | CAUSAL_STEP_VALUE`
- `candidate_values[]`

Each causal row contains the candidate key, original/effective utility, delta,
root problem pressure, benefit, confidence, cost/risk and step position. This is
intended to support the observer question: “Why did this otherwise mundane action
matter to the character right now?”

## Gates added

`res://test/plan_step_value.gd` contains 18 assertions covering:

- subjective pressure input;
- positive prerequisite propagation;
- monotonic response to pressure, confidence, cost and risk;
- bounded/non-destructive utility composition;
- fail-closed unknown roots and missing estimates;
- Registry utility >1 preservation;
- deterministic repeatability;
- MAIN double-count prevention;
- DecisionEngine ON/OFF trace integration on a real `gather_wood` Registry candidate.

The strict regression manifest now includes this suite, so the expected aggregate
becomes 32 suites / 825 assertions when all prior gates remain unchanged.

## Paired natural experiment added

`res://test/p6_3b_causal_value_pilot.gd` compares, for the same fixed
61000–61009 seeds and 1000 ticks:

```text
baseline:  LIVE_BRIDGE + plan execution + causal step value OFF
treatment: LIVE_BRIDGE + plan execution + causal step value ON
```

Both arms use identical terrain, actor configs, resources, economy, timeout and RNG
seed. The pilot records:

- first scoped behavior divergence;
- plan run completion/cancellation/blocking;
- natural multi-stage runs containing ACQUIRE + CRAFT + MAIN completions;
- high-hunger actor-ticks;
- count and sum of positive utility uplifts;
- first-seed deterministic treatment replay;
- source fingerprints.

This pilot is deliberately observational and is not an acceptance threshold.

## Verification status in the current review environment

Completed here:

- `node scripts/check-module-boundaries.mjs` → `BOUNDARY_OK`
- `git diff --check` → clean
- architecture manifest updated for the new decision module and tests

Runtime Godot gates were **not executed in this Linux container**. The archive ships
a Windows Godot 4.7.2 binary, while this environment has neither Wine nor a Linux
Godot executable. Attempts to fetch the matching Linux binary were blocked by the
container network/runtime boundary. Therefore this checkpoint must not be described
as runtime-PASS until the 18-assertion gate and strict regression are run with Godot
4.7.2.

## What this intentionally does not solve

`PlanExecutionTracker._select_new_run()` still turns the first eligible READY plan
into the active run using deterministic goal/plan-id ordering. In other words,
**plan proposal and plan adoption are still too close together**. P6.3B-4 only makes
an already-active plan capable of assigning causal importance to its prerequisites.

If the paired pilot shows useful prerequisite execution without pathological
lock-in, the next semantic package should separate **plan proposal → plan valuation
→ plan adoption/commitment**, so competing plans can be chosen from subjective need,
expected value, confidence, risk, personality and existing commitments rather than
lexicographic order.
