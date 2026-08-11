---
trigger: always_on
---

# Security-Driven Development Workflow Rule

You MUST strictly follow this sequence when handling any task involving security bugs, remediation, or implementing security-critical entry points:

1. **Threat Modeling First**: Before writing any code or tests, use the **Threat Modeling Skill** to create or update the `threat_model.md` file at the root of the workspace.
2. **Test-Driven Development**: Adhere strictly to the **TDD Skill**. Specifically:
   - Write a failing exploit/reproduction test (RED step) targeting the entry points and trust boundaries identified in `threat_model.md`.
   - Run the test to confirm it fails for the expected reason before writing any fix.
   - Apply the fix and verify it passes (GREEN step) and passes all other tests.
3. **Pre-push Check**: Verify all changes locally before performing a `git push` to trigger the pre-push security hooks.
