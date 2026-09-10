import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("compile_cases", ROOT / "narrative-learning/compile_cases.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class CompileCasesTests(unittest.TestCase):
    def setUp(self):
        self.doc = json.loads((ROOT / "lore/cognition_fixture.cases.json").read_text(encoding="utf-8"))

    def check_rejected(self):
        with self.assertRaises(module.CaseError): module.compile_pack(self.doc, ROOT / "lore")

    def test_valid_pack_is_advisory(self):
        pack = module.compile_pack(self.doc, ROOT / "lore")
        self.assertEqual(pack["runtime_policy"], "ADVISORY_ONLY")
        self.assertEqual(pack["cases"][0]["origin"], "ENGINEERING_FIXTURE")

    def test_compilation_reproducible(self):
        self.assertEqual(module.compile_pack(self.doc, ROOT / "lore"), module.compile_pack(copy.deepcopy(self.doc), ROOT / "lore"))

    def test_draft_rejected(self):
        self.doc["cases"][0]["review"]["status"] = "DRAFT"; self.check_rejected()

    def test_hash_mismatch_rejected(self):
        self.doc["cases"][0]["source"]["sha256"] = "0" * 64; self.check_rejected()

    def test_path_escape_rejected(self):
        self.doc["cases"][0]["source"]["path"] = "../.git/config"; self.check_rejected()

    def test_bad_span_rejected(self):
        self.doc["cases"][0]["evidence"][0]["end"] = 999999; self.check_rejected()

    def test_quote_mismatch_rejected(self):
        self.doc["cases"][0]["evidence"][0]["quote"] = "fabricated"; self.check_rejected()

    def test_unknown_evidence_rejected(self):
        self.doc["cases"][0]["field_evidence"]["problem"] = ["absent"]; self.check_rejected()

    def test_world_writes_rejected(self):
        self.doc["cases"][0]["world_effects"] = {"king": "dead"}; self.check_rejected()

    def test_missing_tuple_field_rejected(self):
        del self.doc["cases"][0]["cognition"]["adaptation"]; self.check_rejected()

    def test_duplicate_case_rejected(self):
        self.doc["cases"].append(copy.deepcopy(self.doc["cases"][0])); self.check_rejected()

    def test_runtime_pack_omits_source_quotes(self):
        pack = module.compile_pack(self.doc, ROOT / "lore")
        self.assertNotIn("quote", pack["cases"][0]["evidence"][0])

    def test_malformed_enum_is_a_validation_error(self):
        self.doc["cases"][0]["origin"] = []; self.check_rejected()

    def test_malformed_problem_is_a_validation_error(self):
        self.doc["cases"][0]["retrieval"]["problem_id"] = {}; self.check_rejected()

    def test_nan_confidence_rejected(self):
        self.doc["cases"][0]["retrieval"]["confidence"] = float("nan"); self.check_rejected()

    def test_boolean_confidence_rejected(self):
        self.doc["cases"][0]["retrieval"]["confidence"] = True; self.check_rejected()

    def test_alternative_strategies_required(self):
        self.doc["cases"][0]["cognition"]["candidate_strategies"] = ["only one"]; self.check_rejected()

    def test_compiled_fixture_matches_checked_in_pack(self):
        actual = module.compile_pack(self.doc, ROOT / "lore")
        expected = json.loads((ROOT / "game/data/knowledge/cases/engineering_fixture.json").read_text(encoding="utf-8"))
        self.assertEqual(actual, expected)

if __name__ == "__main__": unittest.main()
