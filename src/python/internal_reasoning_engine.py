from __future__ import annotations
import logging
import re
import difflib
import json
from typing import Any, Dict, List, Optional

class ReasoningResult:
    """Represents the outcome of a reasoning attempt."""

    def __init__(
        self,
        resolved: bool = False,
        resolution: str = "",
        updated_request: Optional[Dict[str, Any]] = None,
        actions: Optional[List[str]] = None,
    ) -> None:
        self.resolved = resolved
        self.resolution = resolution
        self.updated_request = updated_request or {}
        self.actions = actions or []
        self.suggested_plan: Optional[Dict[str, Any]] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "resolved": self.resolved,
            "resolution": self.resolution,
            "updated_request": self.updated_request,
            "actions": self.actions,
            "suggested_plan": self.suggested_plan,
        }

class InternalReasoningEngine:
    """Python implementation of the MCP internal reasoning tool.

    This module analyzes context, validation results and tool failures to
    determine automatic remediation steps. It is designed to be called from
    PowerShell via `python -m` execution or as a REST microservice.
    """

    def __init__(self, logger: Optional[logging.Logger] = None, max_iterations: int = 5) -> None:
        self.logger = logger or logging.getLogger(__name__)
        self.max_iterations = max_iterations

    def _suggest_match(self, value: str, candidates: List[str]) -> Optional[str]:
        """Return the closest match using fuzzy matching."""
        if not value or not candidates:
            return None
        matches = difflib.get_close_matches(value.lower(), [c.lower() for c in candidates], n=1, cutoff=0.7)
        return matches[0] if matches else None

    def _extract_identifier(self, text: str) -> str:
        """Extract probable identifier (email or word) from validation text."""
        match = re.search(r"[\w.-]+@[\w.-]+", text)
        if match:
            return match.group(0)
        tokens = re.findall(r"[A-Za-z0-9._-]+", text)
        return tokens[-1] if tokens else text

    def aggregate_context(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Aggregate known context into a normalized dictionary.

        This method performs defensive checks and removes empty or
        redundant values so reasoning routines have a consistent view of
        the session state.
        """

        aggregated: Dict[str, Any] = {}
        for key, value in context.items():
            if value is None:
                continue
            if isinstance(value, list):
                unique_vals = list(dict.fromkeys(value))
                aggregated[key] = unique_vals[-50:]
            elif isinstance(value, dict) and not value:
                continue
            else:
                aggregated[key] = value
        return aggregated

    def _validate_inputs(self, issue: Dict[str, Any], context: Dict[str, Any]) -> None:
        if not isinstance(issue, dict):
            raise ValueError("issue must be a dictionary")
        if not isinstance(context, dict):
            raise ValueError("context must be a dictionary")

    def _root_cause_analysis(self, issue: Dict[str, Any]) -> str:
        msg = str(issue.get("Error", ""))
        if "timeout" in msg.lower():
            return "Timeout"
        if "network" in msg.lower():
            return "NetworkError"
        if "permission" in msg.lower():
            return "PermissionDenied"
        return "Unknown"

    def resolve(self, issue: Dict[str, Any], context: Dict[str, Any]) -> ReasoningResult:
        result = ReasoningResult()
        try:
            self._validate_inputs(issue, context)
            normalized_context = self.aggregate_context(context)
            issue_type = issue.get("Type")
            self.logger.info("Internal reasoning triggered", extra={"issue": issue_type})
            if issue_type == "ValidationFailure":
                result = self._resolve_validation_failure(issue, normalized_context)
            elif issue_type == "ToolError":
                result = self._resolve_tool_error(issue, normalized_context)
            elif issue_type == "LowConfidence":
                result = self._resolve_low_confidence(issue, normalized_context)
            else:
                result.resolution = "Unknown issue type"
        except Exception as exc:  # pragma: no cover - defensive
            self.logger.exception("Internal reasoning failure: %s", exc)
            result.resolution = str(exc)
        return result

    def _resolve_validation_failure(self, issue: Dict[str, Any], context: Dict[str, Any]) -> ReasoningResult:
        res = ReasoningResult()
        errors = issue.get("ValidationResult", {}).get("Errors", [])

        if not errors and issue.get("ValidationResult", {}).get("Warnings"):
            res.resolved = True
            res.resolution = "Validation warnings acknowledged"
            return res

        suggestions: Dict[str, str] = {}
        for err in errors:
            lowered = err.lower()
            identifier = self._extract_identifier(err)
            if "user" in lowered:
                match = self._suggest_match(identifier, context.get("KnownUsers", []))
                if match:
                    suggestions[identifier] = match
            elif "mailbox" in lowered:
                match = self._suggest_match(identifier, context.get("KnownMailboxes", []))
                if match:
                    suggestions[identifier] = match

        if suggestions:
            res.resolved = True
            res.resolution = "Entity corrections applied"
            res.updated_request = {"Corrections": suggestions}
            res.actions.append(f"Applied corrections: {suggestions}")
        else:
            res.resolution = "Unable to auto-resolve validation errors"
            res.actions.append("Validation errors: {}".format("; ".join(errors)))

        return res

    def _resolve_tool_error(self, issue: Dict[str, Any], context: Dict[str, Any]) -> ReasoningResult:
        res = ReasoningResult()
        res.resolution = "Tool execution error analyzed"
        res.actions.append(f"Error: {issue.get('Error')}")
        cause = self._root_cause_analysis(issue)
        res.actions.append(f"RootCause: {cause}")
        return res

    def _resolve_low_confidence(self, issue: Dict[str, Any], context: Dict[str, Any]) -> ReasoningResult:
        res = ReasoningResult()
        metrics = issue.get("Metrics", {})
        stage = issue.get("Stage", "")
        res.resolution = f"Low confidence detected at {stage}"
        lb = metrics.get("LowerBound")
        if lb is not None:
            res.actions.append(f"LowerBound: {lb}")
        res.actions.append("Reanalyzing context and suggesting improvements")
        return res


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Run MCP internal reasoning")
    parser.add_argument("--issue", required=True, help="JSON string describing the issue")
    parser.add_argument("--context", required=True, help="JSON string describing context")
    args = parser.parse_args()

    engine = InternalReasoningEngine()
    issue = json.loads(args.issue)
    context = json.loads(args.context)
    result = engine.resolve(issue, context)
    print(json.dumps(result.to_dict()))

