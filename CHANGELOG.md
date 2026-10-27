# Changelog

## 0.9.0 — 2026-10-27

- Add a display-only OpenCode card with OpenRouter usage today/this week (UTC) and remaining key spending allowance. An unset allowance is explicit; it is not the account balance.
- Count local Zen free-model tokens today/this week, including Big Pickle, through a read-only SQLite connection. Show missing/unreadable history explicitly.
- Keep ZCode no-plan and login-required cards with observation times.
- Exclude OpenCode from launch selection, overall capacity status and MCP capacity verdicts; retain its data in `quota_status`.
- Show credit details in the web dashboard as well as CLI/menu panel.
- Fix explicit import requirements in existing Python test scripts.

Verification: four fixture test scripts, Python 3.9 syntax check, release Swift build, live metering, browser and native panel rendering, independent review SUPPORT. Claude's expired login was renewed by the owner and current collection verified; no Claude code change was needed.

Request mapping: OpenCode card → implemented in CLI/web/native panel/MCP status; ZCode no-plan status → explicit empty quota state; Claude collection → restored through owner login. No contract drift remains in this scope. No container service or CDH data contract changed.
