"""P7.2B-R1.1 analyzer aggregation regression tests.

Locks the two aggregation bugs found in review:
1. lifetime averages must be pooled from raw samples, never summed per-run
   (run A [10,20] + run B [30] -> pooled avg 20, never 15+30=45).
2. unique asked actors must be a global set union, never a per-run sum
   (run A asks {B,C}, run B asks {B} -> global unique 2, never 3).
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import analyze_p7_2b_natural as az  # noqa: E402


def _run_with_lifetimes(lifetimes):
    """Synthesize a holder_lifecycle_samples result for pooling tests."""
    return {"created": len(lifetimes), "lifetimes": list(lifetimes),
            "cancel_reasons": {}, "resolved": 0, "surviving": 0}


def _run_with_asks(events):
    return {"events": events}


class TestPooledLifetime(unittest.TestCase):
    def test_pooled_average_not_sum_of_averages(self):
        run_a = _run_with_lifetimes([10, 20])   # avg 15
        run_b = _run_with_lifetimes([30])       # avg 30
        pooled = az.pooled_stats([run_a, run_b])
        self.assertEqual(pooled["count"], 3)
        self.assertAlmostEqual(pooled["avg"], 20.0)
        self.assertNotAlmostEqual(pooled["avg"], 45.0)

    def test_pooled_median_and_p90(self):
        run_a = _run_with_lifetimes([2, 16, 48])
        run_b = _run_with_lifetimes([16, 30])
        pooled = az.pooled_stats([run_a, run_b])
        self.assertEqual(pooled["count"], 5)
        self.assertEqual(pooled["median"], 16)
        self.assertEqual(pooled["min"], 2)
        self.assertEqual(pooled["max"], 48)
        self.assertEqual(pooled["le1"], 0)
        self.assertEqual(pooled["gt1"], 5)

    def test_empty_pool(self):
        pooled = az.pooled_stats([])
        self.assertEqual(pooled["count"], 0)
        self.assertIsNone(pooled["avg"])


class TestGlobalUniqueAsked(unittest.TestCase):
    def test_global_unique_is_set_union(self):
        run_a = _run_with_asks([
            {"type": "holder_information_requested", "target_id": "B"},
            {"type": "holder_information_requested", "target_id": "C"},
        ])
        run_b = _run_with_asks([
            {"type": "holder_information_requested", "target_id": "B"},
        ])
        global_ids = az.asked_actor_ids(run_a) | az.asked_actor_ids(run_b)
        self.assertEqual(len(global_ids), 2)
        self.assertEqual(global_ids, {"B", "C"})
        per_run_sum = len(az.asked_actor_ids(run_a)) + len(az.asked_actor_ids(run_b))
        self.assertEqual(per_run_sum, 3)  # the old, wrong "unique"


class TestHolderAttribution(unittest.TestCase):
    def test_prefix_and_query_kind_attribution(self):
        self.assertTrue(az.is_holder({"goal_id": "INFO:HOLDER:a:1:shells"}))
        self.assertTrue(az.is_holder({"goal_id": "whatever", "query_kind": "HOLDER"}))
        self.assertFalse(az.is_holder({"goal_id": "INFO:a:1:shells", "query_kind": "SOURCE"}))
        self.assertFalse(az.is_holder({"goal_id": ""}))

    def test_terminal_counted_once_per_goal(self):
        data = {"information_subgoal_trace": [
            {"event": "HOLDER_GOAL_CREATED", "goal_id": "INFO:HOLDER:a:1:x", "tick": 5},
            {"event": "GOAL_CANCELLED", "goal_id": "INFO:HOLDER:a:1:x", "tick": 9,
             "reason_code": "PARENT_RUN_CHANGED"},
            {"event": "HOLDER_GOAL_CANCELLED", "goal_id": "INFO:HOLDER:a:1:x", "tick": 9,
             "reason_code": "PARENT_RUN_CHANGED"},
            {"event": "GOAL_CREATED", "goal_id": "INFO:a:2:x", "tick": 5},
            {"event": "GOAL_CANCELLED", "goal_id": "INFO:a:2:x", "tick": 6,
             "reason_code": "PARENT_BLOCKER_REMOVED"},
        ]}
        s = az.holder_lifecycle_samples(data)
        self.assertEqual(s["created"], 1)
        self.assertEqual(s["lifetimes"], [4])
        self.assertEqual(dict(s["cancel_reasons"]), {"PARENT_RUN_CHANGED": 1})


if __name__ == "__main__":
    unittest.main()
