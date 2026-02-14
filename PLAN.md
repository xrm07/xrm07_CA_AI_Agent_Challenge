# PLAN

## 1. Purpose
- Execute a dual-core smoke flow (`plan -> audit -> approval -> implement -> fix`) with minimal repo impact.
- Make only a verification change by creating or updating `tmp/takt-smoke.txt`.

## 2. Requirements
- Keep implementation scope minimal and reversible.
- Produce `APPROVAL.md` before implementation.
- Include risk evaluation, execution commands, results, and rollback procedure in `APPROVAL.md`.
- Complete branch, commit, push, and GitHub PR creation.

## 3. Candidate Files
- `PLAN.md` (this file)
- `AUDIT.md`
- `APPROVAL.md`
- `tmp/takt-smoke.txt`

## 4. Implementation Steps
1. Confirm branch and workspace state.
2. Create planning artifacts (`PLAN.md`, `AUDIT.md`, `APPROVAL.md`) with required sections.
3. Implement minimal change: create/update `tmp/takt-smoke.txt` with smoke execution record.
4. Run lightweight verification commands (`git status`, `cat`, optional `ls`).
5. Perform fix-phase review and apply any minimal correction if needed.
6. Commit, push, and create a PR on GitHub.

## 5. Validation Criteria
- `tmp/takt-smoke.txt` exists and is non-empty.
- `APPROVAL.md` contains required sections and execution outcomes.
- `git diff --name-only` includes only planned files.
- PR is created successfully and points from the smoke branch to `main`.

## 6. Rollback Procedure
1. Close PR without merge.
2. Delete remote branch.
3. Delete local branch.
4. Remove local artifacts if branch cleanup is incomplete.

## 7. Risks
- Low risk: doc-only plus one `tmp/` file.
- Process risk: forgetting to update command results in `APPROVAL.md`.
- Operational risk: PR creation can fail if network/auth changes.
