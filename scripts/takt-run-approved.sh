#!/usr/bin/env bash
set -euo pipefail

PHASE1_PIECE="dual-core-approval"
PHASE2_PIECE="dual-core-apply"

auto_pr=false
create_worktree=""
common_args=()
piece_value=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--piece)
      if [[ $# -lt 2 ]]; then
        echo "[gate] ERROR: missing value for -w/--piece" >&2
        exit 1
      fi
      piece_value="$2"
      shift 2
      ;;
    --piece=*)
      piece_value="${1#*=}"
      shift
      ;;
    --auto-pr)
      auto_pr=true
      shift
      ;;
    --create-worktree)
      if [[ $# -lt 2 ]]; then
        echo "[gate] ERROR: missing value for --create-worktree" >&2
        exit 1
      fi
      create_worktree="$2"
      shift 2
      ;;
    --create-worktree=*)
      create_worktree="${1#*=}"
      shift
      ;;
    *)
      common_args+=("$1")
      shift
      ;;
  esac
done

if [[ -n "$piece_value" && "$piece_value" != "dual-core" ]]; then
  echo "[gate] ERROR: wrapper only accepts piece 'dual-core' (received: $piece_value)" >&2
  exit 1
fi

marker_file="$(mktemp)"
# Keep marker slightly in the past to avoid same-timestamp misses on coarse filesystems.
touch -d '1 second ago' "$marker_file" 2>/dev/null || true
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
  find "$PWD" -maxdepth 4 -type f -name APPROVAL.md -newer "$marker_file" 2>/dev/null
)

if [[ ${#approval_candidates[@]} -eq 0 ]]; then
  echo "[gate] ERROR: no updated APPROVAL.md found under $PWD after phase 1." >&2
  exit 2
fi

if [[ ${#approval_candidates[@]} -gt 1 ]]; then
  echo "[gate] ERROR: multiple updated APPROVAL.md files found; refusing to guess." >&2
  printf '  - %s\n' "${approval_candidates[@]}" >&2
  exit 2
fi

approval_file="${approval_candidates[0]}"
echo "[gate] Approval packet: $approval_file"
echo "---------------- APPROVAL.md ----------------"
cat "$approval_file"
echo "---------------------------------------------"

if ! grep -Eiq '^[[:space:]-]*Approved([[:space:]]*\(Y/N\))?[[:space:]]*:[[:space:]]*Y([[:space:]]|$)' "$approval_file"; then
  echo "[gate] ERROR: APPROVAL.md is not marked as approved (Y)." >&2
  exit 3
fi

if ! grep -Eiq '^[[:space:]-]*Reason[[:space:]]*:[[:space:]]*[^[:space:]].*' "$approval_file"; then
  echo "[gate] ERROR: APPROVAL.md missing non-empty Reason." >&2
  exit 3
fi

if ! grep -Eiq '^[[:space:]-]*Timestamp[[:space:]]*:[[:space:]]*[^[:space:]].*' "$approval_file"; then
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
