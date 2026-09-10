# Plan completion identity audit — 2026-09-09

## Scope

Diagnostic-only continuation of the uncommitted intention utility revision on HEAD 655f930. No production change in this work package. Keep the previous strict result: 28 suites, 773 pass / 1 fail (P1.5 environment-adaptation TVD). No resource, scoring, timeout or seed changes.

## Reproduction

Run `game/test/plan_completion_audit.gd` via headless Godot with `-- --out=<new absolute JSON path>`. The script refuses existing output paths and missing output arguments. It subclasses the fixed-seed observer probe: seeds 61000 and 61009, 1000 ticks, LIVE_BRIDGE and execution enabled. Both are independently compared against plain simulation at every scoped behavior digest and final event/execution fingerprint. Both comparisons pass; diagnostic exit 0.

Evidence: `.tmp/review-CODEX-completion/audit.json` and `audit.log`. JSON contains per-tick digests, completion categories and bounded detailed examples. Examples are the first 12 matching completions, not exhaustive; category counts cover all observed completions.

## Results

| Seed | Matching completed actions with fresh selection identity | Matching continued actions without identity | Successful-result events among those continued actions |
| --- | --- | --- | --- |
| 61000 | 0 | 0 | 0 |
| 61009 | 5 (all without success event) | 14 | 3 |

One additional matching continuation was observed at a decision boundary but had not completed in the observation window (15 boundary matches versus 14 completion callbacks). Do not mix the denominators.

Exact examples from seed 61009:

- Oun `npc_oun#6`, goal THIRST, step `MAIN:rule:spring_water`: decision tick 233, completion tick 234, event seq 276 `drank`, identity empty. Before and after: ACTIVE, pending empty, last_progress_tick 225.
- Oun `npc_oun#10`, goal HUNGER, step `MAIN:rule:berry_patch_food`: decision tick 404, completion tick 405, event seq 501 `foraged`, identity empty. Before and after: ACTIVE, pending empty, last_progress_tick 400.

These match the actual candidate key recorded at the initiating boundary and the expected actor's real success event. They are not retrospective invented causes. They prove missed attribution for successful matching continuation actions, not that an entire crafting chain would have succeeded under a different implementation.

## Cause

`IslandSimulation._tick_actor` only selects the next action after the previous physical action is complete. `_plan_execution_on_complete` consumes the previous inflight identity. Yet the continuation path in DecisionEngine returns without a new selection receipt, and `_plan_execution_on_decision` rejects stale DecisionTrace timestamps. This correctly prevents replaying an old selection, but also leaves the newly initiated physical action without an identity. Comments describing continuation as the same unfinished physical attempt do not match this boundary lifecycle.

Do NOT remove the stale-trace guard, reuse the previous attempt ID, or attach identity after seeing a success event. Those changes would reintroduce old-run/old-attempt misattribution already covered by execution regression tests.

## Next bounded implementation contract

Introduce a fresh execution-selection receipt for the current decision boundary, distinct from the cognitive DecisionTrace. It must be produced from the current execution_step and current adapter match, whether selection used softmax or intention continuation. Preserve the distinction between those selection modes; do not fabricate a new deliberation or overwrite old causal reasoning with invented reasoning.

1. OFF/SHADOW behavior remains unchanged. No new random draws, utility bonuses, altered candidates, or timeout resets.
2. Receipt identifies actor, decision tick, run_id, step_id, candidate_key and selected/nonselected mode; no world-truth scan. Validate current run and step before tracker invocation.
3. Each newly started matching physical action receives a new monotonic attempt identity. An already-running action receives none. Pending completion remains consumed exactly once.
4. Nonmatching continuation can suspend the current run using fresh evidence; stale records alone cannot resume, suspend, or rehook anything.
5. Completion still requires matching identity AND the existing real result checks. No retrospective credit merely because an action name or place matches.
6. Add red/green tests for failed first attempt followed by successful continuation, fresh attempt sequence, wrong run/actor/step, duplicate completion, stale receipt, and SUSPENDED recovery. Preserve existing SR4/SR5 and OFF/LIVE/SHADOW gates.
7. Re-run the same two natural seeds. Report actual counts, including still-unselected plans and timeouts; do not promise a successful long plan.

This addresses an execution bookkeeping gap, not the full scarcity/adaptation or consideration-set policy issue. Seed 61000's absence of any selected step completion remains a separate decision-opportunity problem.

## Verification and handoff

Diagnostic/plain equality passed for both seeds. Boundary tests and static boundary scan are run separately. No full regression repeated because production behavior did not change in this diagnostic package. No staging, commit, or cleanup of review evidence.
