---
name: opencode-browser-qa
description: Verify a web app through the assigned browser MCP with reproducible evidence; use for E2E checks and browser diagnostics.
---

# Browser QA

Start from the developer handoff and changed surface; do not rediscover the entire project or repeat successful build/lint/test without a state change. Use Playwright for functional flows and Chrome DevTools only for console, network, DOM, and performance diagnosis. Do not run the same flow through both MCPs.

Do not read project source to reconstruct behavior already covered by the developer handoff. Browser QA validates observable behavior; it does not perform a second code review. Use the URL, PID, test hook, and startup command from the handoff. Do not improvise a local server when none was supplied: report the browser route as skipped with the missing prerequisite, avoiding orphan processes and unrelated infrastructure debugging.

## Games

Do not play through canvas, action, arcade, or real-time games and do not claim to assess difficulty, balance, controls, fairness, or fun. Tool-call latency is not representative of a player. Unless the user explicitly requested a bounded automated game check and the developer handoff supplies a ready URL and deterministic test hook, return `SKIPPED: MANUAL_GAMEPLAY_REQUIRED` with a short manual acceptance checklist. A permitted game browser smoke is limited to technical facts such as page load, console errors, non-empty/changing canvas, start action, and deterministic state transitions; it must not attempt level completion.

Use stable semantic locators and bounded waits. After two failed browser actions, stop changing click/input techniques and diagnose the DOM or console. Capture the URL, observable state, relevant console/network failures, and exact repro steps. Keep browser profiles isolated; do not retrieve credentials, cookies, tokens, or authorization headers.

Respect the assigned mode: `FAST` is one critical desktop flow without Lighthouse; `STANDARD` adds mobile, core regression, and scoped accessibility; `RELEASE` uses production preview, full regression, and one production Lighthouse run. Never run Lighthouse against a dev server.

Do not submit irreversible forms, make purchases, publish content, or alter accounts without explicit confirmation. Report every route as pass, fail, or skipped with a reason, then return a compact handoff and clean up test-owned processes and artifacts.
