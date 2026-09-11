# AIWorld repository instructions

## Product intent

AIWorld is a deterministic world simulation that produces stories from state changes. Characters act from their own perceptions, beliefs, goals, relationships and memories. The simulation owns facts and consequences. LLM components may compile inputs, propose bounded candidates and render explanations; they do not directly mutate world truth.

## Current delivery order

1. Complete the simulation framework and causal agent loops.
2. Validate deterministic replay, evidence lineage and long-running reliability.
3. Add observation UI and art after the framework gates are met.

The current implementation line is P7. Information subgoals come before material requests, conditional commitments and UI work.

## Architecture invariants

- Keep world truth separate from actor knowledge.
- Decision code may read only the actor view and structured subjective context.
- World truth may enter an actor belief through a perception or message event.
- A plan, request or report cannot complete an action by itself. Execution evidence must confirm the result.
- Every new stochastic subsystem uses a namespace-derived RNG stream and participates in deterministic replay diagnostics.
- Existing profiles remain stable. New behavior starts behind an explicit profile or feature flag.
- Fixed-seed natural experiments are observational. Do not tune seeds, resources, timeout values or acceptance thresholds to manufacture a pass.
- Additive traces are preferred. Diagnostic reads must not mutate simulation state.

## Validation

Use Godot 4.7.2 and Python 3.10 or newer.

```bash
python3 scripts/run-strict-regression.py \
  --godot /path/to/Godot_v4.7.2-stable_linux.x86_64 \
  --evidence .tmp/strict-new

python3 scripts/run-simulation.py \
  --godot /path/to/Godot_v4.7.2-stable_linux.x86_64 \
  --profile information --seed 61003 --ticks 1000 \
  --verify-replay --out .tmp/information-61003.json
```

Evidence paths must be new. Retain failed evidence and rerun into another directory after a repair. Record actual pass counts and skipped checks.

## Git workflow

- `main` is the latest validated baseline.
- Develop one bounded stage on `work/<stage-name>`.
- Commit code, tests and validation documentation together.
- Open a Pull Request to `main` and wait for repository CI.
- Keep local secrets, engine binaries, caches and generated evidence outside Git.

## Documentation

Update `docs/ROADMAP.md`, `docs/RUNNING.md` and the matching file under `game/docs/validation/` when a stage changes. State product gaps separately from unit-test success.
