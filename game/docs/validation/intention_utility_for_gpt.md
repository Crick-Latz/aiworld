# Current intention utility — 2026-09-09

## Scope and baseline

Uncommitted work on HEAD `655f93087fee703f9347ca6dee4516d1873b6cd3`, building on the pending intention legality/payload and fixture revisions. This is an explicit behavior correction, not a claim of unchanged seeded trajectories. No resource, personality, softmax, urgency threshold (0.35), or execution-timeout tuning. Plan execution remains opt-in.

## Evidence before modification

`intention_utility_probe.gd` observes the same actor-facing candidates at real decision boundaries. Seeds 61000/61009, 1000 ticks each, identical configs before/after; every observed run is compared to an uninstrumented run. Both comparisons pass. Evidence: `.tmp/review-CODEX-utility/before.json`, `before-verified.log`.

A stale bypass means continued intention with best minus stored utility <= 0.35, while best minus current utility > 0.35. Counts: 64 / 80. Example seed 61000: Weila's eat_food retained 1.05 while current value reached zero and another candidate scored 0.8. Seed 61009: Oun's drink_water retained 1.0 while current value was zero and another candidate scored 0.74.

## Implementation

- DecisionEngine calculates its existing urgency gap against the matched current candidate.
- IntentionManager carries forward commitment and started_tick, but keeps the fresh candidate utility, duration, and payload. Deep-copy isolation remains.
- No forced winning action: an urgent gap only reaches the existing consideration/softmax path.
- No new continuation DecisionTrace; existing execution attempt identity semantics remain intact.
- Legacy `should_switch` is not the production decision entry point; this change does not redesign that API.

## Tests

New `intention_utility.gd`: 6 assertions, before 4 pass / 2 fail; after 6 / 0. Uses actual Registry rest scores, 32 deterministic decision seeds, and verifies reconsideration without requiring a particular winner. Also checks stable-value persistence, fresh persisted score, metadata, and copy isolation.

Existing intention revalidation: 14 / 0. Its legal-rest fixture now supplies low energy and an actual Registry score instead of an artificial stored utility 2.0. No gate removed or count reduced.

Module boundary tests: 6 / 0; boundary scanner passes (literal preload/load only); diff whitespace check passes with CRLF notices.

## Natural sample result — not a product acceptance substitute

| Seed | Stale bypass before → after | Timeouts before → after | Completed runs before → after | First scoped digest change |
| --- | --- | --- | --- | --- |
| 61000 | 64 → 0 | 10 → 13 | 0 → 0 | tick 24 |
| 61009 | 80 → 0 | 52 → 68 | 0 → 0 | tick 21 |

Both after runs retain zero unavailable-action continuations; instrumented/plain equality holds. Evidence: `after.json`, `after.log` in the same directory. First digest difference is not necessarily the first visible action difference: refreshed intention score is itself state.

This fixes stale urgency but does NOT establish improved plan completion or more interesting stories. Timeout counts increased; do not hide that with longer timeouts, resource tuning, or replacement seeds. A bounded next diagnosis is plan opportunity/selection/identity loss under competing actions, with source-linked traces, before proposing any policy change.

## Full regression

Completed in `.tmp/review-CODEX-utility/strict/`, console `strict.log`: **STRICT_REGRESSION FAIL**, 28 suites, 773 pass / 1 fail (774 expected assertions, no count mismatch).

Remaining failure: P1.5 `g_context_adapts`, seed 777, TVD 0.075067 versus unchanged >0.15 requirement (previous pending revision 0.135042). This is a worsened sample-level metric, not a solved product requirement.

P1.6's previous `k_refusals_happen` and `k_wild_epistemic_chain` now pass at the unchanged seed: refusals=4, epistemic=2, claims=2. All 27 P6.3B execution assertions pass, as do the 33 bridge, 45 items, 23 plan-step, 15 shadow, 78 narrative, 14 intention-revalidation and 6 new utility assertions. No seed or threshold was changed in this turn.

The strict script reports the failure correctly. The outer shell command printed the log afterward and therefore returned 0; that wrapper status is NOT a passing strict regression result.

## Handoff

No commit, staging, or evidence cleanup in this turn. Preserve before/after evidence until review. Historical story sample JSON describes the previous behavior version, not this revision.
