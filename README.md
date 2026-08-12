# Secure Coding Configuration with Antigravity & CodeMender

This repository contains the configuration, custom skills, and lifecycle hook script to set up a secure coding environment using the Antigravity agentic coding assistant and the CodeMender CLI (`cm`). A parallel **Claude Code** port of the same setup lives in [`claude-code/`](claude-code/) — see [Setup: Claude Code](#installation--setup-claude-code) below.

This setup automatically acts as a first line of defense in your software development lifecycle by scanning modified files for vulnerabilities before they are pushed, guiding automatic remediation, and enforcing test-driven development (TDD).

> **Which agent should I use this with?** Both, but each is self-contained in its own directory — you only copy the one you need into your workspace:
> - [`antigravity/`](antigravity/) — the original Antigravity configuration (`.agents/`)
> - [`claude-code/`](claude-code/) — the equivalent Claude Code configuration (`CLAUDE.md` + `.claude/`)
>
> They implement the same workflow with the same skill content — pick whichever CLI you run, or keep both checked in if your team uses different agents.

> [!IMPORTANT]
> **CodeMender Access is Limited:** Access to the CodeMender API and artifacts is currently restricted. Ensure your Google Cloud account has been granted authorization and is associated with a project where the CodeMender API is enabled before attempting to run scans.
> 
> *If you do not have access to CodeMender, you can use the alternate Semgrep-based configuration (see the Lifecycle Hooks section below) to run local, open-source security scans.*

---

## Workspace Structure

### This repository

Each agent's config is self-contained under its own top-level directory, so you only ever copy the one you need — nothing from `antigravity/` is required to use `claude-code/`, or vice versa:

```none
secure-coding-agy-config/
├── antigravity/
│   └── .agents/                       # copy this whole folder to your workspace root
│       ├── hooks.json
│       ├── hooks_semgrep.json
│       ├── security_gate_hook.sh
│       ├── security_gate_hook_semgrep.sh
│       ├── rules/
│       │   └── security_workflow.md
│       └── skills/
│           ├── test_driven_development/SKILL.md
│           ├── threat_modeling/SKILL.md
│           └── secure_coding/SKILL.md
├── claude-code/
│   ├── CLAUDE.md                      # copy this file...
│   └── .claude/                       # ...and this whole folder, both to your workspace root
│       ├── settings.json
│       ├── settings.semgrep.json
│       ├── hooks/
│       │   ├── security_gate_hook.sh
│       │   └── security_gate_hook_semgrep.sh
│       └── skills/
│           ├── test-driven-development/SKILL.md
│           ├── threat-modeling/SKILL.md
│           └── secure-coding/SKILL.md
└── README.md
```

### Once copied into your workspace

**Antigravity** — copy the contents of `antigravity/.agents/` from this repo to a `.agents/` folder at the root of your workspace, so Antigravity can discover it:

```none
your-workspace/
├── .agents/
│   ├── hooks.json                     # CodeMender hooks config
│   ├── hooks_semgrep.json             # (Alternate) Semgrep hooks config
│   ├── security_gate_hook.sh          # CodeMender security hook script
│   ├── security_gate_hook_semgrep.sh  # (Alternate) Semgrep security hook script
│   ├── rules/
│   │   └── security_workflow.md
│   └── skills/
│       ├── test_driven_development/
│       │   └── SKILL.md
│       ├── threat_modeling/
│       │   └── SKILL.md
│       └── secure_coding/
│           └── SKILL.md
└── sample_app/ (for testing/practice)
```

**Claude Code** — copy `claude-code/CLAUDE.md` and `claude-code/.claude/` from this repo to the root of your workspace, flattening them so `CLAUDE.md` and `.claude/` sit directly at your workspace root. Claude Code uses the same three primitives as Antigravity, just under different names and paths; `rules/` has no direct equivalent, so the always-on instruction lives in `CLAUDE.md` instead, which Claude Code loads into every session automatically:

```none
your-workspace/
├── CLAUDE.md                          # always-on workflow rule (replaces .agents/rules/)
├── .claude/
│   ├── settings.json                  # CodeMender hooks + permissions config
│   ├── settings.semgrep.json          # (Alternate) Semgrep hooks + permissions config
│   ├── hooks/
│   │   ├── security_gate_hook.sh          # CodeMender security hook script
│   │   └── security_gate_hook_semgrep.sh  # (Alternate) Semgrep security hook script
│   └── skills/
│       ├── test-driven-development/
│       │   └── SKILL.md
│       ├── threat-modeling/
│       │   └── SKILL.md
│       └── secure-coding/
│           └── SKILL.md
└── sample_app/ (for testing/practice)
```

Key differences from the Antigravity layout:
- **Skills** are a direct port — same `SKILL.md` format (frontmatter + markdown body), just with `name`/`description` frontmatter added and directories renamed to kebab-case (`secure-coding`, `threat-modeling`, `test-driven-development`) per Claude Code convention. Claude invokes them automatically when relevant, or explicitly via `/secure-coding`, `/threat-modeling`, `/test-driven-development`.
- **Rules** (`trigger: always_on`) become plain **`CLAUDE.md`** content — there's no separate "rules" config in Claude Code.
- **Hooks** move from a standalone `.agents/hooks.json` to the `"hooks"` key inside `.claude/settings.json`. The matcher targets the `Bash` tool (there's no dedicated `git push` tool), and an `if: "Bash(git push*)"` filter on the hook handler restricts it to push commands specifically. See [Installation & Setup: Claude Code](#installation--setup-claude-code) for the full config and the I/O differences this creates for the hook script.

---

## Installation & Setup: Antigravity

Copy this repo's `antigravity/.agents/` folder to a `.agents/` folder at the root of your workspace (the layout shown above under *Workspace Structure → Once copied into your workspace → Antigravity*):
```bash
cp -r antigravity/.agents /path/to/your-workspace/.agents
```

### 1. Install Antigravity CLI (`agy`)

The Antigravity CLI is used to manage workspace permissions, inspect agent state, and register lifecycle hooks.

#### Step 1: Download the Binary
Download the `agy` binary corresponding to your platform (e.g., macOS or Linux):
```bash
# For macOS (Apple Silicon / ARM64)
gcloud artifacts generic download \
    --project=antigravity-prod \
    --location=us \
    --repository=antigravity-cli-production \
    --package=agy \
    --version=stable \
    --name=agy-darwin-arm64.zip \
    --destination=./

# For Linux (x86_64)
gcloud artifacts generic download \
    --project=antigravity-prod \
    --location=us \
    --repository=antigravity-cli-production \
    --package=agy \
    --version=stable \
    --name=agy-linux-amd64.zip \
    --destination=./
```

#### Step 2: Install and Verify
Extract the binary and move it to your system path:
```bash
unzip agy-*.zip
chmod +x agy
sudo mv agy /usr/local/bin/agy

# Verify the installation
agy --help
```

---

### 2. Install CodeMender CLI (`cm`)

The CodeMender CLI scans your codebase for common security issues like SQL Injection, Command Injection, and Path Traversal.

#### Step 1: Authentication
Ensure the Google Cloud SDK is authenticated with your credentials:
```bash
gcloud auth application-default login
```

#### Step 2: Download and Install the CLI
```bash
# For macOS (Apple Silicon / ARM64)
gcloud artifacts generic download \
    --project=cmoc-prod \
    --location=us \
    --repository=codemender-cli-production \
    --package=cm \
    --version=stable \
    --name=cm-darwin-arm64.zip \
    --destination=./

# For Linux (x86_64)
gcloud artifacts generic download \
    --project=cmoc-prod \
    --location=us \
    --repository=codemender-cli-production \
    --package=cm \
    --version=stable \
    --name=cm-linux-amd64.zip \
    --destination=./

unzip cm-*.zip
chmod +x cm
sudo mv cm /usr/local/bin/cm

# Verify the installation
cm --help
```

---

## Configuring Workspace & Permissions

### Initialize CodeMender Workspace
To run scans, initialize CodeMender in the root of your workspace:
```bash
cm init
```
This generates a `.codemender` directory containing `config.yaml`. Set `sandbox.enabled: false` if running local tests directly, or customize your extension inclusion filters. Verify the initialization using:
```bash
cm init --verify
```

### Granting Antigravity Permissions
Antigravity executes commands inside a sandboxed environment. Since the `security_gate_hook.sh` script executes the `cm` command, you must explicitly grant Antigravity permission to run the `cm` command prefix.

You can do this by running:
```bash
agy /permissions
```
Or by manually adding `"command(cm)"` to your settings file at:
`~/.gemini/antigravity-cli/settings.json`

---

## Installation & Setup: Claude Code

### 1. Install Claude Code

Follow the [Claude Code installation instructions](https://code.claude.com/docs/en/quickstart) for your platform, then verify:
```bash
claude --version
```

### 2. Install CodeMender CLI (`cm`)

Same as the Antigravity setup above: authenticate with `gcloud auth application-default login`, download and install the `cm` binary, then initialize the workspace:
```bash
cm init
cm init --verify
```
(If you don't have CodeMender access, use the Semgrep alternative in step 4 instead — `pip install semgrep` or `brew install semgrep`.)

### 3. Copy the config into your workspace

Copy this repo's `claude-code/CLAUDE.md` and `claude-code/.claude/` folder to the root of your workspace, flattening them so `CLAUDE.md` and `.claude/` sit directly at your workspace root (the layout shown above under *Workspace Structure → Once copied into your workspace → Claude Code*):
```bash
cp -r claude-code/CLAUDE.md claude-code/.claude /path/to/your-workspace/
```

### 4. Activate the CodeMender or Semgrep hook

Only one hook config can be active at a time, since both live at `.claude/settings.json`:
- **CodeMender (default)**: nothing to do — `.claude/settings.json` already wires up `security_gate_hook.sh`.
- **Semgrep (alternate)**: replace it with the Semgrep variant:
  ```bash
  mv .claude/settings.json .claude/settings.codemender.json
  mv .claude/settings.semgrep.json .claude/settings.json
  ```

Make both hook scripts executable:
```bash
chmod +x .claude/hooks/security_gate_hook.sh .claude/hooks/security_gate_hook_semgrep.sh
```

### 5. Grant permission to run `cm` / `semgrep`

Claude Code's Bash tool asks for approval before running commands it hasn't seen before — this is the equivalent of Antigravity's `agy /permissions` step. `.claude/settings.json` already pre-allows the relevant prefix (`Bash(cm:*)` or `Bash(semgrep:*)`) under `"permissions": { "allow": [...] }`, so no manual step is needed unless you've overridden permissions elsewhere (e.g. in `~/.claude/settings.json`).

### How the hook differs from Antigravity's

Claude Code hooks and Antigravity hooks are the same *concept* (a `PreToolUse` handler with a `matcher`, invoking a `command`), but two details had to change when porting `security_gate_hook.sh`:
- **Matching `git push` specifically**: Antigravity's matcher accepted a shell glob (`"git push*"`) directly. Claude Code's `matcher` only filters by tool name (`Bash`, `Edit`, etc.); to filter by the command's *content* you add an `if: "Bash(git push*)"` field on the individual hook handler.
- **Blocking a push**: Antigravity's script printed `{"allow_tool": false, "reason": "..."}`. Claude Code expects `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "..."}}` on stdout (or a plain `exit 2`). The ported scripts in `.claude/hooks/` use small `allow()` / `deny()` helpers for this.
- **Interactive prompts**: Claude Code passes the hook's JSON payload on stdin, so the script's own `read -p` prompts (used in the CodeMender RED/GREEN escalation flow) had to be redirected to `/dev/tty` to still work in an interactive terminal session. This doesn't apply to the Semgrep script, which was already non-interactive.

---

## Features & Configurations Injected

> Each item below lists the Antigravity path and, where it differs, the Claude Code path.

### 1. Security-Focused Agent Skills
Antigravity: `antigravity/.agents/skills/` · Claude Code: `claude-code/.claude/skills/` (same `SKILL.md` format, kebab-case directory names):
- **Threat Modeling Skill**: Guides the agent to identify components, map entry points, trust boundaries, and trace data paths before making design or security decisions.
- **Test-Driven Development (TDD) / Prove-It Skill**: Enforces writing a failing reproduction test (RED) before fixing a bug, and verifying that the fix successfully passes the test (GREEN) without breaking regressions.
- **Secure Coding Guidelines**: Guides the agent to validate inputs against allow-lists, prevent SQL injection via parameterized queries, and resolve absolute paths using canonicalization.

### 2. Workflow Enforcement Rules
Antigravity: `antigravity/.agents/rules/security_workflow.md` · Claude Code: `claude-code/CLAUDE.md` (Claude Code has no separate "rules" primitive — always-on instructions live in `CLAUDE.md`, which is loaded into every session automatically):
- **Security-Driven Development Workflow Rule**: An always-on workspace rule that guarantees the agent follows the correct sequence: Planning -> Threat Modeling (producing `threat_model.md`) -> Writing functional & security tests (RED step) -> Implementing secure code (GREEN step, utilizing the Secure Coding Guidelines skill) -> Verification and pushing.

### 3. Lifecycle Hooks
There are two hooks configurations available for each agent:

**Antigravity** (`antigravity/.agents/`):
- **CodeMender Hook** (`hooks.json`): Intercepts `git push` to run the CodeMender-based security gate script.
- **Semgrep Hook** (`hooks_semgrep.json`): (Alternate) Use this if you do not have access to CodeMender. Intercepts `git push` to run the Semgrep-based security gate script. Rename this file to `hooks.json` to activate it.

Example `hooks_semgrep.json` configuration:
```json
{
  "semgrep-security-gate": {
    "PreToolUse": [
      {
        "matcher": "git push*",
        "hooks": [
          {
            "type": "command",
            "command": "./.agents/security_gate_hook_semgrep.sh",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

**Claude Code** (`claude-code/.claude/`):
- **CodeMender Hook** (`settings.json`, the default): Matches the `Bash` tool with an `if: "Bash(git push*)"` filter, running the CodeMender-based security gate script.
- **Semgrep Hook** (`settings.semgrep.json`): (Alternate) Same idea, running the Semgrep-based script. Rename this file to `settings.json` to activate it (see [Installation & Setup: Claude Code](#installation--setup-claude-code), step 4).

Example `settings.semgrep.json` configuration:
```json
{
  "permissions": {
    "allow": ["Bash(semgrep:*)"]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(git push*)",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/security_gate_hook_semgrep.sh",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

### 4. Hook Scripts
- **CodeMender Gate Script** (`antigravity/.agents/security_gate_hook.sh` / `claude-code/.claude/hooks/security_gate_hook.sh`): Runs CodeMender scan (`cm find`) on modified files. If findings exist, runs an automated RED-GREEN fix loop with `cm fix` and unittest discovery.
- **Semgrep Gate Script** (`antigravity/.agents/security_gate_hook_semgrep.sh` / `claude-code/.claude/hooks/security_gate_hook_semgrep.sh`): Runs Semgrep scan locally using its open-source config rules (`semgrep scan --config auto --json`). If findings are detected, the script blocks the push and returns the exact list of issues to the agent, which then uses the TDD and Secure Coding skills to write, test, and apply the fixes directly.

The two versions of each script are functionally identical; the Claude Code versions differ only in the stdin/stdout contract described above (reading `tool_input.command` from JSON, and emitting `hookSpecificOutput.permissionDecision` instead of `{"allow_tool": ...}`).

> [!NOTE]
> **Fixed bug in the CodeMender gate script's file-matching filter** (both `antigravity/.agents/security_gate_hook.sh` and `claude-code/.claude/hooks/security_gate_hook.sh`): the original `jq` filter used `.FilePath as $fp | any($mod_files[]; . != "" and ($fp | endswith(.)))`. Piping `$fp` into `endswith(.)` resets `.` to `$fp` before the argument is evaluated, so it actually ran `endswith($fp)` — "does the path end with itself," which is always true — rather than comparing against each modified file. This meant *every* open finding was included regardless of whether it was in your changed files, not just the ones actually touched by the push. It also silently depended on exact string matching, so `cm report`'s Windows-style `C:\...\file.py` paths would never have matched `git diff`'s forward-slash `file.py` paths even once the scoping bug was fixed. The filter now binds each candidate to `$mf` explicitly and normalizes backslashes to forward slashes before comparing:
> ```jq
> [ .[] | select((.FilePath | gsub("\\\\"; "/")) as $fp | any($mod_files[]; . as $mf | $mf != "" and ($fp | endswith($mf)))) ]
> ```
> Verified against a real `cm find` scan (see Testing Notes below): 4/4 genuine findings matched when the file was actually modified, 0/4 matched against an unrelated modified-files list.

---

## Walkthrough: CodeMender CLI Basics

> [!NOTE]
> **Agent Automation:** While this walkthrough covers how to run the CodeMender CLI commands manually to understand their behavior, these commands (`cm find`, `cm fix`, `cm verify`) are automatically run and managed by the Antigravity agent in the background via the pre-push hook configuration.

### Sample Application Setup
Create a file named `sample_app/data_service.py` to practice scanning:
```python
import os
import sqlite3
import hashlib
from flask import Flask, request, jsonify

app = Flask(__name__)

app.config['SECRET_KEY'] = 'SuperSecretKey123!@#'

@app.route('/user')
def get_user():
    username = request.args.get('username')
    conn = sqlite3.connect('users.db')
    cursor = conn.cursor()
    query = f"SELECT * FROM users WHERE username = '{username}'"
    cursor.execute(query)
    user = cursor.fetchone()
    conn.close()
    return jsonify(user)

@app.route('/read_file')
def read_file():
    filename = request.args.get('file')
    with open(os.path.join('/var/www/uploads', filename), 'r') as f:
        content = f.read()
    return content

@app.route('/ping')
def ping_host():
    ip = request.args.get('ip')
    cmd = f"ping -c 1 {ip}"
    os.system(cmd)
    return "Ping initiated"

def hash_password(password):
    return hashlib.md5(password.encode()).hexdigest()

if __name__ == '__main__':
    app.run(debug=True)
```

### Scanning for Vulnerabilities
Scan the file:
```bash
cm find sample_app/data_service.py
```
This discovers multiple critical vulnerabilities (SQL Injection, Path Traversal, Command Injection, Insecure Hashing).

### Querying Findings
View active scan findings locally:
```bash
cm report
```

### Verifying Findings (Exploitability Checks)
Verify if the path traversal can be actively exploited:
```bash
cm verify <finding_id>
```

### Remediating Findings
Fix a specific SQL Injection finding automatically:
```bash
cm fix <finding_id>
```
CodeMender generates the remediation patch, outputs a code diff, and updates your workspace files.

---

## Testing Notes (Claude Code port)

The Claude Code config in `claude-code/` was set up and exercised end-to-end (not just written) before being committed:

- **Skill discovery**: Copying `claude-code/.claude/skills/` into a workspace makes Claude Code auto-discover `secure-coding`, `test-driven-development`, and `threat-modeling` as soon as files under that directory are touched — confirmed live in-session.
- **Hook wiring**: `.claude/settings.json`'s `matcher: "Bash"` + `if: "Bash(git push*)"` correctly scopes the hook to push commands only; a simulated `PreToolUse` payload for `git status` was ignored (`permissionDecision: "allow"`, no scan run), confirming the filter doesn't fire on unrelated Bash commands.
- **Semgrep variant, full cycle**: with `settings.semgrep.json` active, a real `semgrep scan` against the README's vulnerable Flask sample app found all 11 documented issues (SQLi, path traversal, command injection, hardcoded secret, MD5, debug mode) and correctly returned `permissionDecision: "deny"` with the findings as `permissionDecisionReason`; the same file with the vulnerabilities fixed correctly returned `"allow"`.
- **CodeMender variant**: `cm init` / `cm init --verify` succeeded, and a real `cm find` scan (authenticated, project `code-mender-test`) found 4 genuine vulnerabilities (SQL injection, OS command injection, path traversal, weak MD5 hashing) in the sample app with 100% confidence — confirming CodeMender API access itself works for this project. This is also where the file-matching bug noted above was caught: the original filter's `endswith` comparison was verified broken against these real findings (always matched, regardless of input), and the fix was verified to correctly return 4/4 matches for the actually-modified file and 0/4 for an unrelated one.
- **Not exercised**: the CodeMender script's interactive RED/GREEN retry loop and HITL escalation (`cm fix`, `read -p` prompts, `git commit --amend`) weren't run live — they require a `tests/` directory and burn real CodeMender quota per attempt. The `allow()`/`deny()` JSON output and the `/dev/tty` redirection for the prompts were reviewed but not exercised against a live interactive terminal.

## Credits & References

- **Test-Driven Development (TDD) Skill**: Inspired by and adapted from classic TDD methodologies:
  - *Test-Driven Development: By Example* by Kent Beck.
  - *Three Laws of TDD* by Robert C. Martin (Uncle Bob).
