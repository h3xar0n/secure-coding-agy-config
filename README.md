# Secure Coding Configuration with Antigravity & CodeMender

This repository contains the configuration, custom skills, and lifecycle hook script to set up a secure coding environment using the Antigravity agentic coding assistant and the CodeMender CLI (`cm`).

This setup automatically acts as a first line of defense in your software development lifecycle by scanning modified files for vulnerabilities before they are pushed, guiding automatic remediation, and enforcing test-driven development (TDD).

> [!IMPORTANT]
> **CodeMender Access is Limited:** Access to the CodeMender API and artifacts is currently restricted. Ensure your Google Cloud account has been granted authorization and is associated with a project where the CodeMender API is enabled before attempting to run scans.

---

## Workspace Structure

For Antigravity to discover and execute your security rules and hooks, place the files in this repository under the `.agents/` folder at the root of your workspace:

```none
your-workspace/
├── .agents/
│   ├── hooks.json
│   ├── security_gate_hook.sh
│   └── skills/
│       ├── test_driven_development/
│       │   └── SKILL.md
│       ├── threat_modeling/
│       │   └── SKILL.md
│       └── secure_coding/
│           └── SKILL.md
└── sample_app/ (for testing/practice)
```

---

## Installation & Setup

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

## Features & Configurations Injected

### 1. Security-Focused Agent Skills
Located under `.agents/skills/`:
- **Threat Modeling Skill**: Guides the agent to identify components, map entry points, trust boundaries, and trace data paths before making design or security decisions.
- **Test-Driven Development (TDD) / Prove-It Skill**: Enforces writing a failing reproduction test (RED) before fixing a bug, and verifying that the fix successfully passes the test (GREEN) without breaking regressions.
- **Secure Coding Guidelines**: Guides the agent to validate inputs against allow-lists, prevent SQL injection via parameterized queries, and resolve absolute paths using canonicalization.

### 2. Lifecyle Hooks
Defined in `.agents/hooks.json`, the hook intercepts `git push` commands:
```json
{
  "codemender-security-gate": {
    "PreToolUse": [
      {
        "matcher": "git push*",
        "hooks": [
          {
            "type": "command",
            "command": "./.agents/security_gate_hook.sh",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

### 3. Hook Script (`security_gate_hook.sh`)
When the agent executes `git push`, the script interceptor:
1. Discovers modified files in the commit.
2. Runs CodeMender scan (`cm find`) on those files.
3. If open vulnerabilities are detected, blocks the push and runs a **RED-GREEN Remediate & Test Loop**:
   - Requests a failing reproduction test.
   - Attempts to automatically fix the vulnerability using `cm fix`.
   - Runs unit tests to verify the fix works and has no regressions.
4. Escalates to human-in-the-loop (HITL) for unresolved failures, offering the option to mute with justification or run exploitability checks (`cm verify`).

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
