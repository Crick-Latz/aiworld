# P7.1A Material Request Foundation

## Scope

This checkpoint establishes the causal request core that P7.1 runtime integration will use.

A missing prerequisite can now be represented as a material request with a parent-plan link. Target selection consumes only the requester's subjective holder beliefs. The recipient evaluates the request from its own inventory reserve, needs, relationship, trust, generosity, risk and commitment load. A request reaches `RESOLVED` only after a matching `ITEM_TRANSFER_COMPLETED` world-mutation event is recorded.

## Included modules

- `MaterialRequestContract`
- `MaterialRequestTracker`
- `MaterialRequestPolicy`
- `MaterialRequestResponsePolicy`
- `MaterialTransferService`
- `MaterialRequestCoordinator`
- standalone Godot regression coverage

## Invariants

1. A dialogue acceptance cannot satisfy a material prerequisite.
2. Target selection cannot inspect authoritative world inventory.
3. Recipient response policy does not mutate inventory.
4. Transfer is all-or-nothing for the accepted quantity.
5. Inventory changes produce explicit evidence containing giver, receiver, item and quantity.
6. Parent-plan revalidation becomes available only after accepted transfer evidence and is consumed once.
7. Refusal returns the request to active target search; counteroffers remain explicit.

## Explicit exclusions

This checkpoint does not yet wire material requests into the island simulation decision loop. It does not add UI, art, resource placement changes, seed changes or fixed utility bonuses. P7.1B will connect the foundation to missing-prerequisite detection, social visibility, actor inventory and plan revalidation.

## Verification

The branch workflow runs:

1. the dedicated P7.1 material-request test;
2. the full strict regression;
3. stable `framework` deterministic replay;
4. P7.0 `information` deterministic replay.

The workflow also checks that P7.0 is present in the branch before accepting this checkpoint.
