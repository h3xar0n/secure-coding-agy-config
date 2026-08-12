# Secure Coding Guidelines

This document outlines the mandatory secure coding practices for Python applications and AI agents built using an Agent Development Kit (ADK). These guidelines are designed to comply with typical corporate and cloud governance concerns, preventing common vulnerabilities (such as OWASP Top 10, OWASP Top 10 LLM) and ensuring system integrity.

---

## Part 1: Python Application Security (AppSec)

### 1. Input Validation and Sanitization
- **Strict Allow-lists**: Validate all inputs (API requests, file uploads, CLI arguments, environment variables, environment configs) against strict allow-lists of expected formats, sizes, and character sets.
- **Type Checking**: Enforce type constraints using Python type hinting and runtime validation libraries (e.g., `pydantic` or `marshmallow`).
- **Parsing instead of Regex**: Prefer robust parsing libraries (e.g., `urllib.parse` for URLs, `email.utils` for emails) over complex custom regular expressions which are prone to ReDoS (Regular Expression Denial of Service).

### 2. Preventing Injection Vulnerabilities
- **SQL Injection**:
  - **Never** construct SQL queries using string concatenation, formatting (f-strings), or interpolation.
  - **Always** use parameterized queries / prepared statements (e.g., `cursor.execute("SELECT * FROM users WHERE username = %s", (username,))`) or a secure ORM (e.g., SQLAlchemy, Django ORM).
- **Command Injection**:
  - Avoid invoking shell commands via `os.system`, `subprocess.Popen(..., shell=True)`, or `eval`/`exec`.
  - If execution is unavoidable, pass arguments as a list to `subprocess.run(..., shell=False)` and validate both the executable path and arguments against a strict, hardcoded allow-list.
- **Path Traversal / Arbitrary File Access**:
  - Never trust user-provided paths or filenames directly.
  - Use `os.path.basename()` to strip directory traversal sequences.
  - Resolve paths to their canonical absolute forms using `os.path.realpath()` (or `pathlib.Path.resolve()`).
  - Strict Boundary Check: Verify that the resolved absolute path starts with the allowed sandbox directory path + directory separator (e.g., `os.path.realpath(target_path).startswith(os.path.realpath(sandbox_dir) + os.sep)`). This prevents partial path matching bypasses (e.g., `/sandbox-malicious` matching `/sandbox`).

### 3. Safe Serialization and Deserialization
- **Insecure Deserialization**:
  - **Never** use `pickle`, `marshal`, or `shelve` to deserialize untrusted data, as they allow arbitrary code execution.
  - For data serialization, use safe formats such as JSON (`json.loads`) or safe YAML loading (`yaml.safe_load`, **never** `yaml.load`).
  - For XML parsing, use `defusedxml` to prevent XML External Entity (XXE) and XML Entity Expansion attacks.

### 4. Cryptography and Hashing
- **Hashing**:
  - **Never** use insecure hashing algorithms (e.g., MD5, SHA-1) for sensitive data, signatures, or password hashing.
  - Use established, memory-hard hashing functions (e.g., Argon2, bcrypt, or PBKDF2) for passwords and credential storage.
  - Use SHA-256 or SHA-3 for general cryptographic hashes/integrity checks.
- **Encryption**:
  - Use authenticated encryption (e.g., AES-GCM or ChaCha20-Poly1305 via `cryptography.hazmat.primitives.ciphers.aead`).
- **Randomness**:
  - Use `secrets` (cryptographically secure pseudo-random number generator) for tokens, keys, and security-sensitive values.
  - **Never** use the standard `random` module for security-sensitive operations.

### 5. Dependency Management
- **Scan Dependencies**: Run dependency scanning tools (e.g., `pip-audit` or `safety`) to identify known vulnerabilities in third-party libraries.
- **Pin Versions**: Pin exact versions in `requirements.txt` or `pyproject.toml` to prevent supply chain attacks (dependency confusion, malicious updates).
- **Internal Repositories**: Use private artifact registries (e.g., Artifact Registry) for internal dependencies.

---

## Part 2: Securing AI/LLM Agents in ADK (Agentic Security & Governance)

AI Agents built with an Agent Development Kit (ADK) run autonomously and can perform actions via tools. This requires strict security and governance measures to prevent vulnerabilities like **Excessive Agency** (OWASP LLM08), **Insecure Output Handling** (OWASP LLM02), and **Prompt Injection** (OWASP LLM01).

### 1. Principle of Least Privilege & Excessive Agency
- **Granular Tool Access**: Only equip the agent with the minimum set of tools required to perform its specific task. Do not grant a generic agent access to administrative or system tools.
- **Fine-Grained Permissions**: Ensure the credentials or API keys used by the agent's tools have restricted permissions. For example, a database tool should connect with a read-only user if the agent only needs to query data.
- **Sandboxed Execution**: Any code execution tool (e.g., Python interpreter, bash runner) MUST run in an isolated, sandboxed environment (e.g., gVisor, Docker container, microVM) with strict resource limits, network egress filtering, and no access to the host filesystem.

### 2. Tool & Plugin Input Validation
- **Do Not Trust LLM Output**: The arguments generated by the LLM to invoke a tool must be treated as untrusted user input.
- **Validate Arguments**: Validate tool parameters strictly (e.g., check types, enforce schema validation using Pydantic, validate parameter formats, ensure paths are canonical and sandboxed).
- **Sanitize Commands & Queries**: If an agent uses a database tool or a command-line tool, parameterize queries and restrict allowed commands rather than allowing arbitrary execution.

### 3. Prompt Injection Defense
- **System Instructions Integrity**: Protect the agent's system instructions from being overridden. Use structural delimiters (e.g., `<system_instructions>...</system_instructions>`) to clearly separate system directives from user inputs.
- **Indirect Prompt Injection**: Treat all retrieved documents, emails, search results, web pages, and database records as untrusted sources of instructions. The agent must parse them as data, not as directives.
- **Dual-LLM / Guardrail Pattern**: Consider using a secondary, lightweight LLM or a regex-based guardrail to classify and filter out prompt injection payloads from both incoming inputs and outgoing outputs.

### 4. Human-in-the-Loop (HITL) for Governance
- **State-Changing Actions**: Require explicit human approval (HITL) before executing any high-risk or state-changing action. This includes:
  - Writing or deleting database records.
  - Making financial transactions.
  - Sending external emails or notifications.
  - Deploying code or configuration changes.
  - Executing system commands or scripts.
- **Approval Mechanisms**: Implement interactive approval modals, Slack/email confirmations, or explicit CLI confirmations.

### 5. Audit Logging and Traceability
- **Comprehensive Logging**: Log all aspects of the agent's lifecycle:
  - User prompts and system instructions.
  - LLM raw inputs and outputs.
  - Tool calls, including target tool, arguments, execution status, and raw tool output.
  - Model decisions and reasoning paths.
- **PII and Secret Masking**: Prior to logging or storing traces, mask sensitive data, including PII, credentials, API keys, and session tokens.
- **Immutable Log Storage**: Store audit logs in a centralized, read-only, tamper-evident logging service (e.g., Cloud Logging with restricted IAM access) to ensure audit compliance.

### 6. Secrets and Credential Management
- **No Hardcoding**: Never hardcode API keys (e.g., OpenAI, Gemini, GitHub tokens) or database passwords in agent code, prompts, or configuration files.
- **Environment and KMS**: Load secrets dynamically from environment variables or a Secret Manager (e.g., Google Cloud Secret Manager).
- **Ephemeral Credentials**: Where possible, use short-lived credentials, IAM workload identity federation, or OAuth tokens instead of long-lived keys.
