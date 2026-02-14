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
4. Pinned movement models:
   - Claude movements (`plan`, `implement`): `claude-opus-4-6[1m]`
   - Codex movements (`audit`, `fix`): `gpt-5.3-codex`

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

## 7. Model Override Policy

Model/provider choices are controlled with this policy:

1. CLI override (`--provider`, `--model`) for one-off runs
2. Movement-level `provider` and `model` in piece YAML
3. Custom agent `provider` and `model` (if used)
4. Global/project config defaults
5. Provider defaults

Project default is movement pinning in `.takt/pieces/dual-core.yaml`.

## 8. Fallback Procedure (`gpt-5.3-codex` unavailable)

If Codex movement fails because `gpt-5.3-codex` is unavailable in the current route/account:

1. Try one-off execution override:

```bash
takt --task "..." --piece dual-core --provider codex --model codex
```

2. If still blocked, temporarily switch the Codex movement model in
`.takt/pieces/dual-core.yaml` from `gpt-5.3-codex` to `codex`, run the task,
then restore the original model string.

3. Record the fallback reason and command used in the run report.

## 9. Validation Scenarios

1. Piece load check
   - Command: `takt prompt dual-core`
   - Expectation: prompt preview starts and shows movements in order.
   - Note: in `takt 0.13.0`, preview may still print `reportContent is required for report-based judgment` even with valid pieces.
2. Model pinning check
   - Command: `rg -n "model:" .takt/pieces/dual-core.yaml`
   - Expectation: four model entries exist (2 Claude, 2 Codex).
3. Interactive piece execution
   - Command: `takt -w dual-core`
   - Expectation: after `/go`, movements follow configured providers and permissions.
4. Safety guard check
   - Ensure API key variables are still empty before execution.

## 10. Rollback / Recovery

If `dual-core` causes issues:

1. Run with built-in piece temporarily:
   - `takt` and choose default piece
2. Or bypass project piece by explicitly selecting another piece:
   - `takt -w default`
3. Disable this piece by renaming file:
   - `.takt/pieces/dual-core.yaml` -> `.takt/pieces/dual-core.yaml.disabled`

## 11. Notes

- `takt` emitted an update-check permission warning for `~/.config`; this does not block normal execution.
- `takt prompt` currently emits a status-judgment error in this environment (`takt 0.13.0`), including for built-in pieces.
- `gpt-5.3-codex` and `[1m]` model behavior can depend on provider-side account and route availability.
- Keep this guide updated whenever piece permissions, auth policy, or execution mode changes.
