---
name: test-driven-development
description: Test-driven development workflow (PLAN-RED-GREEN-REFACTOR-PUSH), including the Prove-It pattern for security remediations. Use before writing or fixing any production code, especially bug fixes and security fixes, to write a failing test first.
---

# Test-Driven Development (TDD) Skill

## Overview
Write a failing test before writing the code that makes it pass. For bug fixes and security remediations, reproduce the issue with a test before attempting a fix.

This skill is based on classic TDD methodologies (such as Kent Beck's *Test-Driven Development: By Example* and Uncle Bob's *Three Laws of TDD*) adapted for AI Coding Agents.

## The Three Laws of Agent TDD
1. **No Production Code without a Failing Test**: Do not write or modify any production code unless it is to make a failing unit test or reproduction test pass.
2. **Write Minimal Tests to Fail**: Write only enough of a test to fail or assert the expected bug/vulnerability. A compilation or import error in the test does not count as a valid failure for the logic under test.
3. **Write Minimal Production Code to Pass**: Write only the simplest production code that makes the failing test pass. Do not write extra features or speculative code.

## The TDD Cycle (PRGR-P)
1. **PLAN**:
   - Outline the design, functional requirements, and testing strategy.
   - Once the design plan is established, if the component handles untrusted input or security boundaries, utilize the **threat-modeling skill** to produce a `threat_model.md` artifact at the root of the workspace.
2. **RED**:
   - Write functional unit tests to assert the designed behaviors.
   - Write security edge-case tests targeting each entry point (input validation checks) and trust boundary (authentication/authorization checks) identified in the `threat_model.md` artifact.
   - Run the test suite and verify that the tests fail.
   - **Crucial**: Ensure the tests fail for the *expected reason* (assertion failure or expected exception) and not due to a syntax/import error in the test files.
3. **GREEN**:
   - Write or apply the minimal production code to make the tests pass.
   - **Crucial**: When writing the implementation, refer to and follow the **secure-coding skill** (e.g. input validation, parameterized queries, path canonicalization).
   - Run the tests to confirm they are now green.
4. **REFACTOR**:
   - Clean up the code, remove duplication, and improve names/structures.
   - Re-run the tests after every change to ensure no regressions are introduced.
5. **PUSH**:
   - Once all tests are green and the refactoring is complete, run `git push` to trigger the pre-push security verification hook.

## The Prove-It Pattern (Security Remediations)
When addressing a security vulnerability:
1. **Identify**: Trace the vulnerability to the source file.
2. **PLAN**: Establish a plan to resolve the issue. Run the **threat-modeling skill** to outline the entry points and threat matrix in the `threat_model.md` artifact.
3. **RED Step**:
   - Refer to the `threat_model.md` entry points.
   - Write a test or script reproducing the exploit (e.g. attempting SQL injection or path traversal) and confirm that the vulnerability is triggered (test fails).
4. **GREEN Step**:
   - Apply the security patch (manually or via `cm fix`). Ensure the implementation adheres to the **secure-coding skill**.
   - Verify that the exploit test now fails to compromise the system and all other tests pass (green).
5. **PUSH Step**: Run `git push` to trigger the pre-push security verification hook.
