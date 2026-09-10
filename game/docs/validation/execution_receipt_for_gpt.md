# Fresh execution receipt — 2026-09-09

## Implemented, not yet checkpointed

Built on the pending intention utility revision at HEAD 655f930. No utility, RNG, resource, timeout or personality tuning. No real LLM API. Execution remains opt-in.

DecisionEngine now produces a separate `_execution_receipt` at both softmax and intention-continuation returns, using the current adapter match. It does not invent a new cognitive DecisionTrace for continuation. The actor-view receipt is copied at the actual action-start boundary and consumed once by simulation. Actor, tick, chosen key, mode, run and step must match before tracker invocation; old cognitive traces cannot authorize attempts. Tracker retains its existing monotonic attempt IDs and real-result completion validation.

New unrelated continued actions can now suspend a plan with fresh evidence; matching ones can resume it. This changes execution bookkeeping and subsequent run selection, not the chosen action's score or RNG draw.

## Verification

- Existing execution suite: 27/27, including old completion identity and stale-trace protections. This run preceded the final additional run/step precheck; the new receipt suite exercises that precheck directly.
- New receipt suite: 6/6. Invalid actor/tick/run/step/key/mode preserves run and inflight identity; consumed receipt; fresh continuation; no fabricated deliberation; OFF clears stale receipt; real simulation continuation has identity.
- Mutation: disabling continuation receipt production yields 3 pass / 3 fail, exit 1. Restored implementation yields 6/6. Temporary mutation removed.
- Module boundary tests 6/6, literal-load scanner passes; editor import and whitespace checks pass.
- Bridge 33/33; intention utility 6/6 and intention revalidation 14/14 passed. Bridge log in `.tmp/review-CODEX-receipt/`; intention results returned in terminal.

Full strict regression completed on continuation: **29 suites / 779 pass / 1 fail**, 780 expected assertions, no count mismatch. Actual strict exit 1. Evidence `.tmp/review-CODEX-receipt/full/`, console `full.log`. Only failure is the unchanged P1.5 `g_context_adapts`: TVD 0.075067 against >0.15. All receipt, execution, bridge, narrative and other gates passed. No new gate failure relative to the preceding utility revision. This is not full acceptance.

## Same-seed natural result

Evidence before: `.tmp/review-CODEX-completion/audit.json`; after: `.tmp/review-CODEX-receipt/after.json`. 1000 ticks each, same map/config/seeds. Instrumented/plain behavior digests and final fingerprints match in each version.

| Seed | Missing-identity matching continuation boundaries before → after | Completed runs before → after | Timeouts before → after |
| --- | --- | --- | --- |
| 61000 | 0 → 0 | 0 → 0 | 13 → 13 |
| 61009 | 15 → 0 | 0 → 3 | 68 → 68 |

The same three success events now advance MAIN and complete their run:

- Oun run #6, tick 234, drank seq 276.
- Oun run #10, tick 405, foraged seq 501.
- Oun run #18, tick 755, drank seq 935.

These are single-MAIN goals, NOT natural ACQUIRE→CRAFT→MAIN success. Eleven matching continued attempts and five softmax-selected attempts still produced no success event in seed 61009; a valid receipt does not pretend they succeeded. No violations reported by the pilot. Both seeds retain identical reported fresh/continued decision counts relative to before, but that alone is not a proof of every cross-version world-state field being identical.

## Next work

Before checkpoint, resolve or explicitly adjudicate the remaining strict failure without silently lowering the gate. Next separate lack of selection (61000) from premature action completion before arrival (61009; see action_arrival_audit_for_gpt.md). Do not compensate by scoring bonuses or increasing resource abundance without evidence. Earlier product environment-adaptation failure remains unresolved.

No staged changes, commit or evidence deletion. Keep previous pending files and reports; this report supersedes the previous audit's proposed receipt design only where implemented above.
