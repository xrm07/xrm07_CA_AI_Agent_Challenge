# Takt Setup Guide (CLI OAuth, Interactive-first)

Last updated: 2026-02-14

## 1. Goal

Set up TAKT with:

- CLI OAuth only (no direct API key operation)
- Interactive mode as the default workflow
- A hard approval gate that always stops before implementation
- Project-local dual-core pieces:
  - Phase 1: Plan (Claude) -> Audit (Codex) -> Approval (Claude) -> STOP
  - Phase 2: Implement (Claude) -> Fix (Codex)

This document also captures approvals required before production use.

## 2. Selected Decisions (Approved)

- Authentication mode: `CLI OAuth only`
- Primary execution mode: `interactive mode`
- Piece location: `project-local .takt/pieces`
- Approval scope before production: `all configuration changes`
- Interactive mode in pieces: `persona`
- Network access policy: `allowed in all movements`
- Approval packet policy: `APPROVAL.md required before implement`
- max movement policy: `max_movements = 12`, stop on limit with manual follow-up
- Hard gate policy: `approval phase always completes and requires explicit human Y/y before phase 2`

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

1. Added phase-1 piece: `.takt/pieces/dual-core-approval.yaml`
2. Added phase-2 piece: `.takt/pieces/dual-core-apply.yaml`
3. Added wrapper: `scripts/takt-run-approved.sh`
4. Kept legacy piece: `.takt/pieces/dual-core.yaml` (for backward compatibility)
5. Runtime safeguards:
   - `interactive_mode: persona`
   - `max_movements: 12`
   - `network_access: true`
6. Pinned movement models:
   - Claude movements: `claude-opus-4-6[1m]`
   - Codex movements: `gpt-5.3-codex`

## 5. Approval Register (Production Gate)

All items below must stay approved before production tasks:

1. CLI OAuth only operation (no API key fallback): `APPROVED`
2. API key environment variables remain unset: `APPROVED`
3. piece permissions and movement order: `APPROVED`
4. Interactive-first operation (`/go` to execute piece): `APPROVED`
5. Approval packet requirement (`APPROVAL.md` before implement): `APPROVED`
6. Movement limit policy (`max_movements=12`, fail-stop): `APPROVED`
7. Hard stop at approval before implementation: `APPROVED`

## 6. Runbook

### Recommended one-command run (hard approval gate)

```bash
./scripts/takt-run-approved.sh --create-worktree yes --auto-pr
```

Behavior:

1. Runs phase 1 (`dual-core-approval`) and always stops after `approval` movement.
2. Resolves the phase-1 execution directory:
   - If worktree was created, resolve from `.takt/clone-meta/*.json`.
   - Otherwise use current directory.
3. Reads `APPROVAL.md` from phase-1 execution directory root.
4. Verifies `APPROVAL.md` contains approved status and required fields.
5. Prompts: `Proceed with implementation? (y/N)`.
6. Runs phase 2 (`dual-core-apply`) only when the user explicitly enters `Y` or `y`.

Notes:

- `-w/--piece` is optional for the wrapper, but if provided it must be `dual-core`.
- `--create-worktree` accepts `yes|no|true|false`; wrapper normalizes to `yes|no` before invoking `takt`.
- If multiple updated clone metadata files are found, wrapper stops instead of guessing.
- If `--create-worktree yes` is set but no updated clone metadata is found, wrapper stops.

### Manual two-step run (optional)

```bash
takt -w dual-core-approval --create-worktree yes
```

Then verify approval packet and confirm in terminal:

```bash
cat APPROVAL.md
read -r -p "Proceed with implementation? (y/N): " yn
```

If explicitly approved (`Y`/`y`):

```bash
takt -w dual-core-apply --create-worktree no --auto-pr
```

## 7. Approval Gate (`APPROVAL.md`)

Phase 1 must create `APPROVAL.md` at repository root before implementation.

Required sections:

1. Purpose
2. Changed files list (planned)
3. Change summary (3-7 bullets)
4. Impact scope
5. Commands to run and expected results
6. Risk and unresolved items
7. Rollback plan
8. Approval fields (`Approved: Y/N`, `Reason`, `Timestamp`)

Wrapper validation requires all of the following:

- `Approved: Y` (or `Approved (Y/N): Y`)
- Non-empty `Reason`
- Non-empty `Timestamp`
- `APPROVAL.md` exists at phase-1 execution directory root
- `APPROVAL.md` is updated by phase 1 (stale packet is rejected)

If any check fails, phase 2 is blocked.
Blank approval input is treated as rejection; phase 2 proceeds only on explicit `Y`/`y`.

## 8. Model Override Policy

Model/provider choices are controlled with this policy:

1. CLI override (`--provider`, `--model`) for one-off runs
2. Movement-level `provider` and `model` in piece YAML
3. Custom agent `provider` and `model` (if used)
4. Global/project config defaults
5. Provider defaults

Project default is movement pinning in `.takt/pieces/dual-core-approval.yaml` and `.takt/pieces/dual-core-apply.yaml`.

## 9. Fallback Procedure (`gpt-5.3-codex` unavailable)

If Codex movement fails because `gpt-5.3-codex` is unavailable in the current route/account:

1. Try one-off execution override:

```bash
takt --task "..." --piece dual-core-apply --provider codex --model codex
```

2. If still blocked, temporarily switch the Codex movement model in:

- `.takt/pieces/dual-core-approval.yaml`
- `.takt/pieces/dual-core-apply.yaml`

from `gpt-5.3-codex` to `codex`, run the task, then restore the original model string.

3. Record the fallback reason and command used in the run report.

## 10. Validation Scenarios

1. Piece load checks
   - `takt prompt dual-core-approval`
   - `takt prompt dual-core-apply`
2. Model pinning checks
   - `rg -n "model:" .takt/pieces/dual-core-approval.yaml`
   - `rg -n "model:" .takt/pieces/dual-core-apply.yaml`
3. Wrapper syntax check
   - `bash -n scripts/takt-run-approved.sh`
4. Hard gate check
   - Phase 1 ends before implementation starts.
   - Wrapper asks `Proceed with implementation? (y/N)`.
5. Approval packet check
   - Wrapper fails if `APPROVAL.md` does not exist in phase-1 execution directory root.
   - Wrapper fails if `APPROVAL.md` exists but is stale (not updated by phase 1).
6. Worktree resolution check
   - With `--create-worktree yes`, wrapper resolves phase-1 run directory from clone metadata.
   - With `--create-worktree no`, wrapper does not use clone metadata.
   - With `--create-worktree true|false`, wrapper normalizes and forwards `yes|no` to `takt`.
   - Wrapper fails if multiple updated clone metadata files are found.
7. Piece-flag check
   - `./scripts/takt-run-approved.sh -w dual-core` succeeds.
   - `./scripts/takt-run-approved.sh -w not-dual-core` fails with validation error.
8. Movement limit check
   - Confirm both piece files have `max_movements: 12`.

## 11. Rollback / Recovery

If this hard-gate flow causes issues:

1. Use legacy piece temporarily:
   - `takt -w dual-core`
2. Or run built-in default:
   - `takt -w default`
3. Disable new pieces and wrapper by removing:
   - `.takt/pieces/dual-core-approval.yaml`
   - `.takt/pieces/dual-core-apply.yaml`
   - `scripts/takt-run-approved.sh`

## 12. Notes

- `takt` may emit an update-check permission warning for `~/.config`; this does not block normal execution.
- `takt prompt` may still print `reportContent is required for report-based judgment` in `takt 0.13.0`.
- `gpt-5.3-codex` and `[1m]` behavior depends on provider-side account and route availability.
- Legacy `.takt/pieces/dual-core.yaml` is kept for backward compatibility, but production runs should use the hard-gate wrapper.
