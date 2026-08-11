# Secure Coding Guidelines

## Input Validation
- Validate inputs against strict allow-lists of expected formats.

## SQL Injection Prevention
- Never concatenate strings to build SQL queries. Use parameterized queries or ORMs.

## Path Traversal Prevention
- Resolve paths to their canonical absolute forms using `realpath` and ensure they remain within target sandbox directories.
