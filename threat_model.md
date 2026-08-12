# Threat Model: Security Gate Hook

Scope: the pre-push security gate hook itself (`security_gate_hook.sh` /
`security_gate_hook_semgrep.sh`, in both the `antigravity/` and
`claude-code/` ports). This is a security-critical entry point per
`CLAUDE.md` / `.agents/rules/security_workflow.md` — it is the one
component in this repo that makes an automated allow/deny trust decision,
so it gets its own threat model rather than inheriting the sample app's.

## Purpose / assets protected

Gate a `git push` on the result of a SAST scan (CodeMender or Semgrep) of
the files changed in that push, so known vulnerability classes don't reach
the remote unreviewed. Secondary asset: an honest audit trail of what was
found and what decision was made about it (needed for the ADVISORY model —
see below).

## Entry points

| Input | Source | Trust level |
|---|---|---|
| `tool_input.command` (stdin JSON) | Claude Code harness, echoing the Bash command the agent/user ran | Semi-trusted — shape is controlled by the harness, but content is whatever string the session produced |
| `git diff --name-only` output | Local git repo state | Trusted shape (git-controlled), but filenames are attacker-influenceable in principle (e.g. spaces, unusual chars) |
| `cm report --format json` / `semgrep scan --json` output | External scanner CLI | Trusted *if the tool ran successfully* — see T1 |
| `SECURITY_GATE_*` env vars (config: block severity, log path, notify command, fail-on-error policy, large-fix-diff threshold) | Shell environment / `.claude/settings.json` | Trusted only as much as the local machine is — anyone with write access to the dev's shell profile or repo can change these |
| `.security-gate/findings-log.ndjson` | Local file this hook appends to | Not tamper-evident — see T5 |

## Trust boundaries

- **B1 — Agent-mediated push vs. any other push.** The hook only fires when
  `git push` runs *through* the agent's Bash tool. A plain terminal push,
  a different git client, CI, or a hand-edited/removed hook config bypasses
  it entirely. **This hook is not a security boundary by itself** — it is
  local, fast feedback. The actual boundary must be enforced server-side
  (branch protection + a required CI check running the same scan). Treat
  everything below as "best-effort local gate," not "the control."
- **B2 — Scanner ran vs. scanner failed.** The decision is only meaningful
  if the scan actually executed. This must be distinguishable from "scan
  ran and found nothing" (T1).
- **B3 — Blocking severity vs. advisory severity.** Findings at/above
  `SECURITY_GATE_BLOCK_SEVERITY` require a resolution (auto-fix confirmed
  closed by a fast rescan, or an explicit human decision at escalation)
  before the push proceeds. Findings below it are logged/notified but do
  not block — this is the intentional fail-open path requested for false
  positives and cross-team hand-off.
- **B4 — Automated fix vs. verified-and-committed fix.** `cm fix`
  succeeding and tests passing is not sufficient evidence the finding is
  resolved *in what actually gets pushed* (T2) — but confirming it must
  stay cheap (T7), since exploitability verification is expensive.
- **B5 — Cheap re-scan vs. expensive exploitability check.** `cm find` /
  `cm report` (re-scan) is the default way to confirm a fix landed.
  `cm verify` (exploitability check) is measured in minutes per finding
  and is reserved for escalation only — see T7.

## Threat matrix

| ID | Threat | Mitigation in this change |
|---|---|---|
| T1 | Scanner binary missing, crashes, or auth/quota fails → previously produced the same "0 findings" output as a clean scan (silent fail-open, indistinguishable from a real pass). | Explicit `ERROR` outcome, logged + notified loudly, blocks by default (`SECURITY_GATE_ALLOW_ON_ERROR=false`), independent of the findings-severity fail-open policy. |
| T2 | Auto-fix loop declares success from tests-passing alone, without (a) re-confirming the finding is actually closed, or (b) committing the fix into the ref being pushed — vulnerable code ships while the log says "fixed." | Fix loop re-runs `cm find`/`cm report` (fast) for the same finding ID after `cm fix`; only treated as resolved if it's actually gone *and* the working-tree fix is staged and committed before the push proceeds. No `cm verify` call on this path. |
| T3 | Advisory/error/escalation decisions are made but never reach anyone but the developer, who could just ignore terminal output — defeats the "let another team collaborate post-push" goal. | `SECURITY_GATE_NOTIFY_CMD` hook + append-only local log give an automatable, non-interactive notification path. A `cm verify`-confirmed exploitable finding explicitly notifies as "help needed," not just a bare deny. |
| T4 | A developer weakens `SECURITY_GATE_BLOCK_SEVERITY` (or unsets `SECURITY_GATE_NOTIFY_CMD`) locally to silence findings entirely. | Inherent to B1 (local-only enforcement); out of scope to fully mitigate here — flagged as the reason a server-side/CI mirror of this gate is still required. |
| T5 | The local ndjson log / notify command is not tamper-evident and delivery isn't guaranteed (offline, notify command itself fails). | Documented as best-effort telemetry, not a compliance record. Notify failures are caught and logged locally rather than aborting the hook. |
| T6 | Unquoted filenames from `git diff` (spaces, globs) break word-splitting loops in the Semgrep variant. | File list is iterated with NUL-safe/quoted handling instead of unquoted `for file in $MODIFIED_FILES`. |
| T7 (design constraint) | `cm verify` takes minutes per finding — calling it routinely (e.g. on every successful auto-fix, or every blocking finding) would make the common-case push unusably slow, and devs would route around the hook entirely. | `cm verify` is called *only* at escalation: retries exhausted (fix couldn't be made to pass tests) or the auto-fix diff exceeds `SECURITY_GATE_LARGE_FIX_LINES` (default 50 changed lines) and warrants human judgment before trusting it. It is never invoked automatically on the happy path. When it *is* run and confirms exploitability, the push blocks and the notify path fires with an explicit "help needed" reason. |

## Out of scope for this change

Server-side/CI enforcement of the same gate (B1), dependency/secret/IaC
scanning, and suppression governance (who can approve a waiver) are real
gaps but are not addressed by this hook-script change — see the repo's
`README.md` for the broader comparison.
