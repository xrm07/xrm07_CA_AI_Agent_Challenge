#!/usr/bin/env bash
set -euo pipefail

PHASE1_PIECE="dual-core-approval"
PHASE2_PIECE="dual-core-apply"

auto_pr=false
create_worktree=""
common_args=()
expect_piece_value=false
expect_create_worktree_value=false

for arg in "$@"; do
  if $expect_piece_value; then
    expect_piece_value=false
    continue
  fi
  if $expect_create_worktree_value; then
    create_worktree="$arg"
    expect_create_worktree_value=false
    continue
  fi

  case "$arg" in
    -w|--piece)
      expect_piece_value=true
      ;;
    --piece=*)
      ;;
    --auto-pr)
      auto_pr=true
      ;;
    --create-worktree)
      expect_create_worktree_value=true
      ;;
    --create-worktree=*)
      create_worktree="${arg#*=}"
      ;;
    *)
      common_args+=("$arg")
      ;;
  esac
done

if $expect_piece_value; then
  echo "[gate] ERROR: missing value for -w/--piece" >&2
  exit 1
fi

if $expect_create_worktree_value; then
  echo "[gate] ERROR: missing value for --create-worktree" >&2
  exit 1
fi

marker_file="$(mktemp)"
cleanup() {
  rm -f "$marker_file"
}
trap cleanup EXIT

phase1_cmd=(takt "${common_args[@]}" -w "$PHASE1_PIECE")
if [[ -n "$create_worktree" ]]; then
  phase1_cmd+=(--create-worktree "$create_worktree")
fi

echo "[gate] Phase 1/2: running ${PHASE1_PIECE}"
echo "[gate] ${phase1_cmd[*]}"
"${phase1_cmd[@]}"

mapfile -t approval_candidates < <(
  find "$PWD" "$(dirname "$PWD")" -maxdepth 4 -type f -name APPROVAL.md -newer "$marker_file" 2>/dev/null
)

if [[ ${#approval_candidates[@]} -eq 0 && -f APPROVAL.md ]]; then
  approval_candidates+=("$(pwd)/APPROVAL.md")
fi

if [[ ${#approval_candidates[@]} -eq 0 ]]; then
  echo "[gate] ERROR: APPROVAL.md was not found after phase 1." >&2
  exit 2
fi

approval_file=""
latest_mtime=0
for candidate in "${approval_candidates[@]}"; do
  [[ -f "$candidate" ]] || continue
  mtime="$(stat -c %Y "$candidate" 2>/dev/null || stat -f %m "$candidate")"
  if [[ "$mtime" -ge "$latest_mtime" ]]; then
    latest_mtime="$mtime"
    approval_file="$candidate"
  fi
done

if [[ -z "$approval_file" ]]; then
  echo "[gate] ERROR: failed to resolve APPROVAL.md path." >&2
  exit 2
fi

echo "[gate] Approval packet: $approval_file"
echo "---------------- APPROVAL.md ----------------"
cat "$approval_file"
echo "---------------------------------------------"

if ! grep -Eiq '^[[:space:]\-*]*Approved([[:space:]]*\(Y/N\))?[[:space:]]*:[[:space:]]*Y([[:space:]]|$)' "$approval_file"; then
  echo "[gate] ERROR: APPROVAL.md is not marked as approved (Y)." >&2
  exit 3
fi

if ! grep -Eiq '^[[:space:]\-*]*Reason[[:space:]]*:[[:space:]]*[^[:space:]].*' "$approval_file"; then
  echo "[gate] ERROR: APPROVAL.md missing non-empty Reason." >&2
  exit 3
fi

if ! grep -Eiq '^[[:space:]\-*]*Timestamp[[:space:]]*:[[:space:]]*[^[:space:]].*' "$approval_file"; then
  echo "[gate] ERROR: APPROVAL.md missing non-empty Timestamp." >&2
  exit 3
fi

read -r -p "Proceed with implementation? (Y/n): " yn
case "${yn:-Y}" in
  Y|y) ;;
  *)
    echo "[gate] Implementation canceled by user."
    exit 4
    ;;
esac

run_dir="$(dirname "$approval_file")"
phase2_cmd=(takt "${common_args[@]}" -w "$PHASE2_PIECE" --create-worktree no)
if $auto_pr; then
  phase2_cmd+=(--auto-pr)
fi

echo "[gate] Phase 2/2: running ${PHASE2_PIECE}"
echo "[gate] Working directory: $run_dir"
echo "[gate] ${phase2_cmd[*]}"
(
  cd "$run_dir"
  "${phase2_cmd[@]}"
)
