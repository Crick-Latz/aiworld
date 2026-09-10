# P6.3B-3 — Decision-opportunity progress accounting

Date: 2026-09-10
Baseline: `d36ee158d584b935b8cd832de5ed05494ec5e97a`

## Why this was selected

A fixed 10-seed, 1000-tick read-only pilot on the P6.3B-2 checkpoint found 389
plan runs: 30 completed, 349 cancelled and 10 censored at the observation end.
Of the cancellations, 309 were `NO_PROGRESS_TIMEOUT`. There were no structural
violations and no blocked runs.

Source inspection showed that the tracker compared current world tick with the
last completed step tick. If an unrelated selected action took many ticks to
travel/work, the plan could be cancelled at the next decision even though it had
not received another decision opportunity. This is a lifecycle accounting bug,
not a resource-distribution or utility-balance problem.

## Implemented semantic correction

`PlanExecutionTracker` now counts actual missed decision opportunities:

- `prepare_decision` no longer expires a run merely because world time elapsed;
- a valid execution receipt with a matching step and an unselected available
  candidate increments `missed_opportunities`;
- selecting the plan step resets the counter;
- completing/advancing a step resets the counter;
- premise blockers continue to block immediately rather than being counted as a
  choice;
- exceeding the unchanged value 16 produces the existing
  `NO_PROGRESS_TIMEOUT` transition and the existing 16-tick cooldown.

The setting retains its compatibility name `no_progress_timeout`; its run-time
meaning is now missed opportunities, while the same value remains the cooldown in
world ticks after cancellation. No utility, RNG, personality, resource amount,
resource placement, seed, or acceptance threshold was changed.

## Test evidence

`p6_3b_execution.gd` increased from 27 to 28 assertions. The new gate jumps from
t1 to t100 without calling `on_decision` and proves the run remains active. It then
feeds five real unselected decision receipts under a limit of four and proves the
fifth opportunity cancels the run.

Existing timeout/cooldown and stale-run fixtures were rewritten to supply actual
missed decisions instead of assuming that calls to `prepare_decision` were choices.

Mutation evidence: the old elapsed-tick expiry branch was temporarily restored
while tests stayed unchanged. Result: **25 pass / 3 fail, exit 1**. Restoring the
new implementation returned **28 pass / 0 fail, exit 0**. No mutation remains.

Final strict result: **31 suites / 807 assertions PASS**, `BOUNDARY_OK`.

## Same-seed natural comparison

The same seeds 61000–61009, same terrain, same 1000 ticks, same execution setting,
and unchanged resources were run before and after. Both pilots reported zero
trace violations and `diff_tick=-1` for every seed: tracking did not alter the
scoped world behavior trajectory.

| Metric | Elapsed-tick timeout | Opportunity timeout | Delta |
|---|---:|---:|---:|
| runs started | 389 | 278 | -111 |
| runs completed | 30 | 43 | +13 |
| runs cancelled | 349 | 223 | -126 |
| `NO_PROGRESS_TIMEOUT` | 309 | 171 | -138 |
| `PLAN_DISAPPEARED` | 40 | 52 | +12 |
| `RUN_RESUMED` | 22 | 35 | +13 |
| active/suspended at end | 10 | 12 | +2 |
| high-hunger actor-ticks | 730 | 730 | 0 |

Completed steps after the change: spring-water MAIN 29, berry MAIN 13, FISH USE 9,
fish MAIN 1. No completion example contained a natural multi-stage
ACQUIRE→CRAFT→MAIN chain.

Pilot JSON files are temporary evidence under
`.tmp/review-CODEX-P6.3B-3/`; they are not product data and are not committed.

## Honest limits and next question

1. More plan runs now survive long unrelated actions and complete, but the planner
   still mostly observes choices the existing utility layer would make. It does not
   force knowledge-based steps to win softmax.
2. Zero natural multi-stage completions remains the next product bottleneck. Do
   not solve it by increasing berry counts, cherry-picking seeds, or adding a flat
   plan utility bonus.
3. `no_progress_timeout` now carries two units for compatibility: opportunity
   count before cancellation and tick count for cooldown. A future configuration
   cleanup may split the names, but no extra parameter is required for correctness.
4. The next investigation should ask whether a planned substep has contextual
   importance derived from its root need and expected causal contribution, rather
   than treating every step as an unrelated ordinary action or assigning an
   arbitrary bonus.
