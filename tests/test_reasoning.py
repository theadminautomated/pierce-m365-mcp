import unittest
from src.python.internal_reasoning_engine import InternalReasoningEngine

class ReasoningTests(unittest.TestCase):
    def setUp(self):
        self.engine = InternalReasoningEngine()

    def test_validation_correction(self):
        issue = {
            "Type": "ValidationFailure",
            "ValidationResult": {
                "Errors": ["user bob.smiht not found"]
            }
        }
        ctx = {"KnownUsers": ["bob.smith@piercecountywa.gov"]}
        res = self.engine.resolve(issue, ctx)
        self.assertTrue(res.resolved)
        self.assertIn("Corrections", res.updated_request)

    def test_unknown_issue(self):
        issue = {"Type": "Other", "Error": "boom"}
        res = self.engine.resolve(issue, {})
        self.assertFalse(res.resolved)
        self.assertIn("Escalation", res.resolution)


if __name__ == '__main__':
    unittest.main()
