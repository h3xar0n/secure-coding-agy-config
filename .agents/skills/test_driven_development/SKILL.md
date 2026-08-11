# Test-Driven Development Skill

## Overview
Write a failing test before writing the code that makes it pass. For bug fixes, reproduce the bug with a test before attempting a fix.

## The TDD Cycle (PRGR)
1. **PLAN**: Plan the design. If security fixes are involved, use the **Threat Modeling Skill** first.
2. **RED**: Write a test that fails (or asserts the vulnerability).
3. **GREEN**: Write the minimal code to make the test pass (or resolve the vulnerability).
4. **REFACTOR**: Improve the code structure while ensuring tests remain green.
5. **PUSH**: Once all tests are green and the refactoring is complete, run `git push` to trigger the pre-push security verification hook.

## The Prove-It Pattern
1. When a vulnerability is identified, **do not apply a fix immediately**.
2. **RED Step**: Write a test reproducing the vulnerability and confirm it fails.
3. **GREEN Step**: Apply the fix (manually or via `cm fix`) and verify the test passes.
4. **PUSH Step**: Run `git push` to trigger the pre-push security verification hook.
