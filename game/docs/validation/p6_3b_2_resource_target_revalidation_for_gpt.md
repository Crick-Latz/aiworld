# P6.3B-2 — Subjective resource-target revalidation

Date: 2026-09-10
Baseline: `5779dc980288c4335af1a60e68b551e159f3bb50`

## Product problem

A resource action was validated only when selected. If the actor later perceived
that the destination had been depleted or searched, a busy travel/work action
continued toward the stale target. That created avoidable empty trips and delayed
the existing planner's chance to use another source.

This task does not optimize berry placement, resource abundance, utility scores,
RNG, personality, plan timeouts, or acceptance seeds. It adds a general execution
lifecycle contract shared by current resource actions.

## Contract

`ActionRegistry` resource candidates carry `target_source_key`, identifying the
actor-facing `known_resources` collection that justified the target. The field is
attached to forage, water, fish, shell, ruin and wood actions through
`ActionTargetContract`.

While a resource action is busy, `IslandSimulation` asks the contract whether the
actor's latest knowledge view explicitly disconfirms that target:

- missing knowledge or malformed knowledge = UNKNOWN, so the action is not
  cancelled;
- the target still in the actor's known available-source list = continue;
- an originally grounded target absent from that list = observed invalidation.

The check does not read world resource truth and does not share one actor's belief
with another actor. On invalidation the simulation stops before movement/work,
clears the stale intention, emits `action_target_invalidated`, awards no resource,
and sends the failed attempt through the existing execution-receipt path.

The tracker consumes that attempt without advancing the step. If the same plan is
still valid because another subjective source exists, the same run can offer that
alternate candidate on the next decision. If no source remains, existing proposal
disappearance/blocker logic handles cancellation or later recovery.

## Tests and red/green evidence

New suite: `game/test/resource_target_revalidation.gd`, 15 assertions:

- UNKNOWN is not treated as absence;
- present/absent and per-actor belief isolation;
- immediate cancellation before movement;
- no reward and explicit grounded failure event;
- stale intention cleared;
- pending attempt consumed without false step advancement;
- same plan run remains recoverable;
- Registry metadata and alternate-source selection;
- the same run can match the alternate source on retry.

Mutation: the single runtime invalidation branch was temporarily disabled while
the test stayed unchanged. Result: **9 pass / 6 fail, exit 1**. Production was then
restored and the suite returned **15 pass / 0 fail, exit 0**. The temporary mutation
is not present in the working tree.

Targeted compatibility gates:

- P5 spatial: 15/15;
- P6.2 AgencyActionBridge: 33/33;
- P6.3B execution: 27/27;
- intention revalidation: 14/14;
- travel/work lifecycle: 11/11;
- module boundary unit tests: 6/6 and `BOUNDARY_OK`.

Final strict regression:

`STRICT_REGRESSION PASS suites=31 assertions=806`

Evidence was written under `.tmp/review-CODEX-P6.3B-2/strict` and is not intended
for Git.

## Files

- new `game/src/simulation/decision/action_target_contract.gd` (+ Godot uid);
- new `game/test/resource_target_revalidation.gd` (+ Godot uid);
- modified `action_registry.gd`, `island_simulation.gd`, `modules.json`, and strict
  regression manifest.

## Honest limits

1. This gate proves an observed-invalid target can be abandoned and another known
   source can be retried. It does not claim that softmax will always select that
   retry or that unrestricted runs will always complete a multi-step plan.
2. Perception occurs once at the start of each simulation tick. Two actors reaching
   a one-unit resource in the same tick may still produce one success and one
   grounded empty result; that is a legitimate race, not hidden-state leakage.
3. Only current resource candidates carry the contract. Social pursuit, building,
   fire use and future item actions need their own validity metadata rather than
   being silently classified as resources.
4. Resource-regrowth memory is handled by existing perception: revisiting or seeing
   a regrown source makes it available again. No new memory expiry policy was added.
5. Busy-action preemption for urgent danger/needs remains a separate lifecycle
   feature and was not introduced here.
