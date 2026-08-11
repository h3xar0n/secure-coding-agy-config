---
trigger: always_on
---

# Security-Driven Development Workflow Rule

You MUST strictly follow this sequence when handling any task involving security bugs, remediation, or implementing security-critical entry points:

1. **TDD Planning**: Start by planning the design, functional requirements, and testing strategy using the **TDD Skill**.
2. **Threat Modeling**: Once the plan is established, if the component handles untrusted input or security boundaries, use the **Threat Modeling Skill** to identify risks and create/update the `threat_model.md` artifact at the root of the workspace.
3. **Write Failing Tests (RED)**: Write failing functional unit tests and, if appropriate, security edge-case tests targeting the entry points and trust boundaries identified in `threat_model.md`. Verify they fail for the expected reason before writing any production code.
4. **Implement Secure Code (GREEN)**: Write the minimal production code to make the tests pass. You MUST reference and adhere to the **Secure Coding Guidelines Skill** during code implementation (e.g. input validation, parameterized queries, path canonicalization).
5. **Verify and Push**: Refactor code and re-run all tests to verify success. Verify changes locally before running `git push` to trigger the pre-push security gate.
