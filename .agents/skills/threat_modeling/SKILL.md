# Security Threat Model Skill

## Overview
Use this skill at the start of a security review or component planning to map entry points, trust boundaries, and sensitive data paths.

The primary output of this skill is a **Threat Model Artifact** (`threat_model.md`) that documents these security vectors. This artifact is directly consumed by the **Test-Driven Development (TDD) Skill** to guide the creation of security-hardening tests.

## Steps
1. **Identify Purpose**: Understand what the component does and what assets it protects.
2. **Map Entry Points**: Document all user inputs and interfaces (HTTP endpoints, CLI parameters, config files, environment variables).
3. **Identify Trust Boundaries**: Map authentication barriers, access control levels, and privilege transitions (e.g., user vs. admin, public internet vs. internal service).
4. **Map Sensitive Data Paths**: Trace where credentials, keys, PII, and critical application state flow and are stored.
5. **Generate Threat Model Artifact**: Write a `threat_model.md` file listing the identified risks, entry points, and trust boundaries.

## Target Output Structure (`threat_model.md`)
Your generated threat model should include:
- **Entry Points**: A list of inputs and endpoints that must be validated.
- **Trust Boundaries**: A list of checks required to enforce authentication and authorization.
- **Threat Matrix**: A mapping of potential vulnerabilities (e.g., SQL Injection at `/user`, Path Traversal at `/read_file`).
