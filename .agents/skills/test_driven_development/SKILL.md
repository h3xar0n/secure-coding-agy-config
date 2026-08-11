# Test-Driven Development (TDD) Skill

## Overview
Write a failing test before writing the code that makes it pass. For bug fixes and security remediations, reproduce the issue with a test before attempting a fix.

This skill is based on classic TDD methodologies (such as Kent Beck's *Test-Driven Development: By Example* and Uncle Bob's *Three Laws of TDD*) adapted for AI Coding Agents.

## The Three Laws of Agent TDD
1. **No Production Code without a Failing Test**: Do not write or modify any production code unless it is to make a failing unit test or reproduction test pass.
2. **Write Minimal Tests to Fail**: Write only enough of a test to fail or assert the expected bug/vulnerability. A compilation or import error in the test does not count as a valid failure for the logic under test.
3. **Write Minimal Production Code to Pass**: Write only the simplest production code that makes the failing test pass. Do not write extra features or speculative code.

## The TDD Cycle (PRGR-P)
1. **PLAN**: Outline the design, requirements, and test scenarios. If fixing a security vulnerability, utilize the **Threat Modeling Skill** first to locate all entry points and trust boundaries.
2. **RED**: 
   - Write a unit test (or integration test) that asserts the desired behavior, edge cases, or vulnerability.
   - Run the test suite and verify that the test fails.
   - **Crucial**: Ensure the test fails for the *expected reason* (e.g., assertion failure or expected exception) and not due to a syntax/import error in the test file.
3. **GREEN**: 
   - Write or apply the minimal code (manually or via tool automation like `cm fix`) to make the test pass.
   - Run the tests to confirm the test is now green.
4. **REFACTOR**: 
   - Clean up the code, remove duplication, and improve names/structures.
   - Re-run the tests after every change to ensure no regressions are introduced.
5. **PUSH**: 
   - Once all tests are green and the refactoring is complete, run `git push` to trigger the pre-push security verification hook.

## The Prove-It Pattern (Security Remediations)
When addressing a security vulnerability:
1. **Identify**: Trace the vulnerability to the source file.
2. **RED Step**: Write a test or script reproducing the exploit (e.g. attempting SQL injection or path traversal) and confirm that the vulnerability is triggered (test fails).
3. **GREEN Step**: Apply the security patch (manually or via `cm fix`) and verify that the exploit test now fails to compromise the system (test passes).
4. **PUSH Step**: Run `git push` to trigger the pre-push security verification hook.
