# Takt Setup Guide (CLI OAuth, Interactive-first)

Last updated: 2026-02-14

## 1. Goal

Set up TAKT with:

- CLI OAuth only (no direct API key operation)
- Interactive mode as the default workflow
- Project-local `dual-core` piece:
  - Plan (Claude) -> Audit (Codex) -> Implement (Claude) -> Fix (Codex)

This document also captures approvals required before production use.

## 2. Selected Decisions (Approved)

- Authentication mode: `CLI OAuth only`
- Primary execution mode: `interactive mode`
- Piece location: `project-local .takt/pieces`
- Approval scope before production: `all configuration changes`

## 3. Preflight Checks (Executed)

Commands run and outcomes:

1. CLI availability
   - `takt`: found
   - `codex`: found
   - `claude`: found
   - `gh`: found
2. Version check
   - `codex-cli 0.101.0`
   - `claude 2.1.42`
   - `takt 0.13.0`
3. Environment variable safety check
   - `OPENAI_API_KEY`: empty
   - `ANTHROPIC_API_KEY`: empty
   - `TAKT_OPENAI_API_KEY`: empty
   - `TAKT_ANTHROPIC_API_KEY`: empty
   - `TAKT_OPENCODE_API_KEY`: empty
4. Login status check
   - `codex login status`: Logged in using ChatGPT
   - `claude auth status`: logged in (`orgName: spot-cyberagent`)

## 4. Changes Applied

1. Created piece file: `.takt/pieces/dual-core.yaml`
2. Enforced least-privilege movement design:
   - `plan`, `audit`: readonly + read tools only
   - `implement`, `fix`: edit + bash allowed
3. Routing configured:
   - `plan -> audit -> implement -> fix -> COMPLETE`

## 5. Approval Register (Production Gate)

All items below must stay approved before production tasks:

1. CLI OAuth only operation (no API key fallback): `APPROVED`
2. API key environment variables remain unset: `APPROVED`
3. `dual-core` piece permissions and movement order: `APPROVED`
4. Interactive-first operation (`/go` to execute piece): `APPROVED`

## 6. Runbook

### Standard interactive run

```bash
takt -w dual-core
```

Then:

1. Choose or confirm interactive mode.
2. Refine task in chat.
3. Execute with `/go`.

### Direct execution (optional)

```bash
takt --task "Create PLAN.md, audit it, implement changes, and fix until checks pass" --piece dual-core
```

## 7. Validation Scenarios

1. Piece load check
   - Command: `takt prompt dual-core`
   - Expectation: prompt preview starts and shows movements in order.
   - Note: in `takt 0.13.0`, preview may still print `reportContent is required for report-based judgment` even with valid pieces.
2. Interactive piece execution
   - Command: `takt -w dual-core`
   - Expectation: after `/go`, movements follow configured providers and permissions.
3. Safety guard check
   - Ensure API key variables are still empty before execution.

## 8. Rollback / Recovery

If `dual-core` causes issues:

1. Run with built-in piece temporarily:
   - `takt` and choose default piece
2. Or bypass project piece by explicitly selecting another piece:
   - `takt -w default`
3. Disable this piece by renaming file:
   - `.takt/pieces/dual-core.yaml` -> `.takt/pieces/dual-core.yaml.disabled`

## 9. Notes

- `takt` emitted an update-check permission warning for `~/.config`; this does not block normal execution.
- `takt prompt` currently emits a status-judgment error in this environment (`takt 0.13.0`), including for built-in pieces.
- Keep this guide updated whenever piece permissions, auth policy, or execution mode changes.
