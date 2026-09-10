# Fixed-location action travel/work lifecycle — 2026-09-09

## Scope

Implemented on the uncommitted intention/receipt working revision at HEAD `655f93087fee703f9347ca6dee4516d1873b6cd3`. Applies only to fixed-location resource actions: forage_berries, drink_water, fish, gather_shells, search_ruins and gather_wood. It does not change social pursuit, utilities, RNG selection, resource abundance, personality, or plan scores.

## Behavior

- Travel and work are separate phases. While a fixed-location target has not been reached, the actor moves through the existing subjective navigator and the declared work duration does not decrement.
- On arrival, the original work countdown runs; only then may the existing executor emit success or alter inventory.
- Eight consecutive ticks with no movement cancel the physical action, clear its intention, emit `action_target_unreachable`, and send the failed attempt through the existing receipt/result path. Movement progress can continue for any distance; the bound is consecutive stall, not total journey length.
- `_complete_action` also fail-closes with `action_target_missed` if a fixed-location action reaches completion off target. This is defense in depth; it does not award resources.
- One execution identity remains attached to one trip/work action and is consumed by the existing completion path. No retrospective credit.

This is an explicit simulation behavior change. Long journeys now consume actual simulated ticks and can change downstream RNG timing and social opportunities. Determinism means same inputs replay identically, not that the old trajectory is preserved.

## Tests

New `action_travel_lifecycle.gd`: 11 assertions covering separated countdown, subjective movement progress, distant arrival, immediate target, no off-site fish/shell rewards, bounded unreachable cancellation, explicit failure event, no reward, and same-input replay.

Mutation evidence: forcing `_requires_fixed_location` false produced 5 pass / 6 fail, exit 1. After restoring production: 11/11, exit 0. Temporary mutation removed. P5 spatial 15/15, P6.3B execution 27/27, module-boundary tests 6/6 and boundary scanner pass. Evidence `.tmp/review-CODEX-travel/`.

## Natural fixed-seed comparison

Same diagnostic framework, seeds 61000/61009, 1000 ticks, LIVE_BRIDGE with execution enabled. Each instrumented run equals its plain run. Before is the fresh-receipt revision (`.tmp/review-CODEX-receipt/after.json`); after is `.tmp/review-CODEX-travel/natural.json`.

| Seed | Completed runs before → after | Started | Timeouts before → after | Successful matching completions after |
| --- | --- | --- | --- | --- |
| 61000 | 0 → 1 | 32 | 13 → 29 | drink_water at target ×1 |
| 61009 | 3 → 5 | 75 | 68 → 61 | drink_water ×4, forage ×1, craft ×1, all at target |

Seed 61009's craft success advanced a CRAFT step but did not produce a naturally completed ACQUIRE→CRAFT→MAIN chain in this sample. Seed 61000 now has one single-MAIN completion. No execution-trace violations were reported. The large changes in started runs/timeouts and decision counts are honestly retained; the behavior trajectory changed because travel occupies time.

The earlier 16 matching no-success resource attempts were all pre-arrival. After the lifecycle change, the audit recorded only successful matching completion callbacks in these two samples; it did not observe every action/resource type, so do not generalize this to all possible failures.

## Known limitations

- Busy actions are not generally preemptible by new decisions; interruption is a later lifecycle feature, not silently introduced here.
- Consecutive-stall limit 8 is a safety policy requiring broader sweep evidence before tuning.
- Resource invalidation by another actor is discovered at arrival by the existing executor. Event wording/knowledge updates for depleted targets remain separate work.
- Fish and shell executor functions themselves are legacy internal methods; production dispatch is protected by `_complete_action`. Direct internal calls are outside this gate.
- Full strict result belongs below; do not checkpoint while an unchanged strict gate remains unresolved.

## Full regression

First full run in `.tmp/review-CODEX-travel/full/`: production behavior gates including the formerly failing P1.5 `g_context_adapts` passed at unchanged seed 777 and unchanged >0.15 threshold. Two fixture-quality failures remained: P3 Narrative NR depended on a naturally occurring Weila interpretation memory; P6.2 PG/RU7 inspected only the last trace of a 600-tick simulation for a stochastic considered-but-not-selected case.

Both fixtures were repaired without changing their acceptance meaning:

- P3 NR co-locates Weila and Oun and emits a real `food_request_refused` through simulation `_emit`, which runs CognitiveTransition and writes the interpreted memory; NarrativeClaim still has to extract a positive bounded confidence. No hand-written Narrative Claim.
- P6.2 PG/RU7 runs the real DecisionEngine over 64 fixed RNG seeds and requires a grounded action both to enter consideration and to be unselected at least once. No forced winner and no long-run last-trace accident.

Targeted reruns: P3 Narrative 78/78 and P6.2 bridge 33/33. The known malformed-JSON parser ERROR remains an intentional negative test already documented by the strict harness.

Final full rerun completed in `.tmp/review-CODEX-travel/final-full/`: **STRICT_REGRESSION PASS, 30 suites / 791 assertions**. P1.5 `g_context_adapts` passed at the unchanged seed 777 and unchanged >0.15 threshold; all P1.6 gates also remained green. No berry counts, resource placement, utilities, RNG, personality values, plan timeout, or acceptance thresholds were changed to obtain the result.

This closes the combined intention revalidation, current-utility refresh, execution-receipt, and fixed-location travel/work gate on the pending revision. The natural two-seed audit above remains deliberately modest evidence: it proves real successful arrivals and improved completion in those runs, but does not claim that a complete multi-step ACQUIRE→CRAFT→MAIN chain now emerges reliably in unrestricted simulation.
