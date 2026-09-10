# Action arrival audit — 2026-09-09

Diagnostic only, on the fresh-execution-receipt working revision. No production edits in this audit. Complete regression separately finished: 29 suites, 779 pass / 1 fail, strict exit 1. Only failure is unchanged P1.5 g_context_adapts (TVD 0.075067). Evidence `.tmp/review-CODEX-receipt/full/`. Do not substitute this probe for acceptance.

## Reproducible result

`plan_completion_audit.gd` now records actual tile at completion and aggregate action/arrival/result categories. Run headless with a new `--out=` path. Evidence: `.tmp/review-CODEX-receipt/locations.json` and `locations.log`. Same seeds 61000/61009, 1000 ticks; instrumented/plain equality passes for both. Counts include all matching-step completions, while detailed examples remain capped at 12.

Seed 61000: no matching-step completed action. This remains a candidate-selection issue, not an arrival conclusion.

Seed 61009:

| Action | Before arrival, no success | At target, success |
| --- | --- | --- |
| drink_water | 14 | 2 |
| forage_berries | 2 | 1 |

All 16 observed matching attempts without success occurred before reaching their selected target. This is not evidence of empty resources or failed fishing probability. It does not prove every failure in every seed has the same cause.

## Source-level mechanism

`IslandSimulation._tick_actor` decrements action_ticks_left while moving, then calls `_complete_action` at zero without an arrival check. A duration-1 action can finish after only a small part of a longer journey. Repeated intentions move the actor incrementally over several separate physical attempts.

`_do_drink` emits nothing unless standing on a spring. `_do_forage` emits `foraged_empty` whenever its local-tile search fails, including when still en route. Thus the current event wording can imply depletion that has not actually been observed at the selected target. Do not let a narrative renderer infer target depletion from that event alone.

Other action executors differ: `_do_fish` rolls success and `_do_shells` awards shells without a destination check. These deserve location-precondition tests before expanding travel behavior. This audit did not demonstrate a specific off-site fishing/shell collection event, so this is a source-level risk, not a measured incidence.

## Next bounded implementation

Design explicit travel/work lifecycle for fixed-location resource actions first, not a global multiplier on duration:

1. Travel consumes simulation time and uses existing subjective navigation, not world-truth teleportation or hidden routing.
2. Begin work duration only after reaching the required interaction location; completion requires real arrival.
3. Unreachable/stalled/invalidated targets need explicit outcomes and bounded cancellation. Do not silently claim resource depletion before arrival.
4. Do not grant inventory or successful events while travelling. Do not automatically keep the plan alive forever: distinguish movement progress from actual goal completion and evaluate timeout semantics explicitly.
5. Preserve current attempt identity throughout one physical trip/work action, consume it once, and assign a new identity only on another real action start.
6. Test distant target, immediate target, interrupted journey, blocked path, target invalidation, no off-site rewards, failed arrival and deterministic replay. Preserve OFF/SHADOW and existing receipt protections as appropriate; travel itself is an explicit simulation behavior change requiring a fresh baseline comparison.

No berry-placement tuning, score bonus, or arbitrary timeout extension is justified by this result. Avoid bundling this behavior change into the currently running receipt regression.
