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

    def test_extract_identifier_email(self):
        text = "Error: user alice.jones@example.com not found"
        ident = self.engine._extract_identifier(text)
        self.assertEqual(ident, "alice.jones@example.com")

    def test_extract_identifier_token(self):
        text = "Validation failed for mailbox shared_mailbox_01"
        ident = self.engine._extract_identifier(text)
        self.assertEqual(ident, "shared_mailbox_01")


if __name__ == '__main__':
    unittest.main()
