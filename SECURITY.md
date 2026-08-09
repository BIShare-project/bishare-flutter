# Security Policy

BIShare moves people's files and encrypts them end-to-end, so we take security
seriously. Thank you for helping keep it safe.

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Instead, report privately via one of:

- 📧 Email **support@billiongroup.net** with the subject `SECURITY: <short summary>`
- 🔒 GitHub's [private vulnerability reporting](https://github.com/BIShare-project/bishare-flutter/security/advisories/new)
  (Security → Report a vulnerability)

Please include:

- A clear description of the issue and its impact
- Steps to reproduce (a proof of concept if possible)
- The platform / app version affected

We'll acknowledge your report, keep you updated on the fix, and credit you (if
you'd like) once it's resolved. Please give us a reasonable window to release a
fix before any public disclosure.

## Scope

Especially interested in issues around:

- The end-to-end encryption (X25519 key exchange, AES-256-GCM, per-file keys)
- The transfer protocol / framing (`rust/bishare-protocol`)
- The local receiver server (`lib/core/server/`)
- Anything that could expose a file to a party other than the intended recipient

## Supported versions

We support the latest released version. Please make sure you can reproduce an
issue on the current `main` before reporting.
