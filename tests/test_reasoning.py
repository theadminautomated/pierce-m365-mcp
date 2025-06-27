import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
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

    def test_tool_error_root_cause(self):
        issue = {"Type": "ToolError", "Error": "Network timeout"}
        res = self.engine.resolve(issue, {})
        self.assertTrue(res.resolved)
        self.assertIn("Retry operation", " ".join(res.actions))

if __name__ == '__main__':
    unittest.main()
