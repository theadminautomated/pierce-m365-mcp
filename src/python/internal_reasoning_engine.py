from __future__ import annotations
import logging
import re
import difflib
import json
import os
from typing import Any, Dict, List, Optional, Tuple

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

    def __init__(self, logger: Optional[logging.Logger] = None, max_iterations: int = 3) -> None:
        self.logger = logger or logging.getLogger(__name__)
        # clamp the iteration count to a sane range
        self.max_iterations = max(1, min(max_iterations, 10))

    def _suggest_match(self, value: str, candidates: List[str]) -> Optional[str]:
        """Return the closest match using fuzzy matching."""
        if not value or not candidates:
            return None
        lower_candidates = [c.lower() for c in candidates]
        matches = difflib.get_close_matches(value.lower(), lower_candidates, n=1, cutoff=0.7)
        if matches:
            return matches[0]
        # fallback to match against the local part of email addresses
        local_parts = [c.split('@')[0] for c in lower_candidates]
        match = difflib.get_close_matches(value.lower(), local_parts, n=1, cutoff=0.7)
        if match:
            idx = local_parts.index(match[0])
            return lower_candidates[idx]
        return None

    def _extract_identifier(self, text: str) -> str:
        """Extract a likely identifier such as an email or token from text."""
        email_pattern = r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"
        match = re.search(email_pattern, text)
        if match:
            return match.group(0)

        tokens = re.findall(r"[A-Za-z0-9._-]+", text)
        for tok in tokens:
            if (
                len(tok) >= 3
                and not tok.isdigit()
                and ("." in tok or "_" in tok)
                and re.search(r"[A-Za-z]", tok)
            ):
                return tok
        return tokens[-1] if tokens else text

    def collect_environment_context(self) -> Dict[str, Any]:
        """Return minimal environment context for diagnostics."""
        try:
            return {
                "cwd": os.getcwd(),
                "user": os.environ.get("USER", "unknown"),
                "hostname": os.uname().nodename,
            }
        except Exception:  # pragma: no cover - environment may not expose uname
            return {"cwd": os.getcwd()}

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
            elif isinstance(value, dict):
                if value:
                    aggregated[key] = value
            else:
                aggregated[key] = value

        aggregated["environment"] = self.collect_environment_context()
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
        if "rate" in msg.lower() and "limit" in msg.lower():
            return "RateLimit"

    def _suggest_next_steps(self, cause: Optional[str]) -> Tuple[bool, List[str]]:
        """Return suggested remediation actions based on root cause."""
        actions: List[str] = []
        if cause == "Timeout":
            actions.append("Retry operation with backoff")
            return True, actions
        if cause == "NetworkError":
            actions.append("Check network connectivity and retry")
            return True, actions
        if cause == "PermissionDenied":
            actions.append("Verify permissions or escalate")
        elif cause == "RateLimit":
            actions.append("Wait before retrying to respect rate limits")
        else:
            actions.append("Escalate to human operator")
        return False, actions

    def _dispatch(self, issue: Dict[str, Any], context: Dict[str, Any]) -> ReasoningResult:
        """Route issue types to the correct handler."""
        issue_type = issue.get("Type")
        if issue_type == "ValidationFailure":
            return self._resolve_validation_failure(issue, context)
        if issue_type == "ToolError":
            return self._resolve_tool_error(issue, context)
        if issue_type == "LowConfidence":
            return self._resolve_low_confidence(issue, context)
        res = ReasoningResult()
        res.resolution = "Unknown issue type"
        return res

    def resolve(self, issue: Dict[str, Any], context: Dict[str, Any]) -> ReasoningResult:
        result = ReasoningResult()
        try:
            self._validate_inputs(issue, context)
            normalized_context = self.aggregate_context(context)
            self.logger.info("Internal reasoning triggered", extra={"issue": issue.get("Type")})

            current_issue = issue
            for attempt in range(self.max_iterations):
                if attempt:
                    self.logger.debug("Reasoning reattempt %s", attempt + 1)
                result = self._dispatch(current_issue, normalized_context)
                if result.resolved:
                    break
                if result.updated_request:
                    current_issue.update(result.updated_request)

            if not result.resolved:
                result.resolution = "Escalation required after max iterations"
                result.actions.append("Escalated to human review")
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
        resolved, actions = self._suggest_next_steps(cause)
        res.actions.extend(actions)
        res.resolved = resolved
        if resolved:
            res.resolution = "Automatic remediation suggested"
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
        res.resolved = False
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

