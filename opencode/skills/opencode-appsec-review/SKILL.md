---
name: opencode-appsec-review
description: Perform authorization-aware application security review of source, configuration, dependencies, APIs, and web flows; use for AppSec audits and secure design reviews, not ordinary debugging.
---

# Application security review

Confirm the target and authorization boundary before active testing. Default to a read-only source/configuration review; do not scan, fuzz, exploit, or send attack payloads to a live service unless the user explicitly authorizes that exact target. Prefer local or staging environments.

Map entry points, trust boundaries, sensitive data, authentication, authorization, persistence, external integrations, deployment, and CI/CD. Review relevant OWASP risks: access control, cryptography and secrets, injection, insecure design, misconfiguration, vulnerable dependencies, authentication/session failures, software/data integrity, logging/monitoring, and SSRF.

For each finding provide:

- affected file, component, endpoint, or configuration;
- concrete evidence and realistic attack preconditions;
- impact and confidence, clearly separating confirmed issues from hypotheses;
- severity based on reachability and impact, not scanner wording;
- minimal remediation and a verification test.

Never print secret values, tokens, cookies, private keys, or authorization headers. Do not label an unverified pattern as an exploitable vulnerability. Finish with positive controls, coverage gaps, and a prioritized remediation plan.
