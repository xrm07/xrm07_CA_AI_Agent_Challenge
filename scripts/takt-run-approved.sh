#!/usr/bin/env bash
set -euo pipefail

PHASE1_PIECE="dual-core-approval"
PHASE2_PIECE="dual-core-apply"

auto_pr=false
create_worktree=""
create_worktree_takt=""
common_args=()
piece_value=""
worktree_mode="auto"

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

if [[ -n "$create_worktree" ]]; then
  case "$create_worktree" in
    yes|true)
      worktree_mode="yes"
      create_worktree_takt="yes"
      ;;
    no|false)
      worktree_mode="no"
      create_worktree_takt="no"
      ;;
    *)
      echo "[gate] ERROR: invalid --create-worktree value: $create_worktree (expected yes|no|true|false)" >&2
      exit 1
      ;;
  esac
fi

marker_file="$(mktemp)"
# Keep marker slightly in the past to avoid same-timestamp misses on coarse filesystems.
touch -d '1 second ago' "$marker_file" 2>/dev/null || true
cleanup() {
  rm -f "$marker_file"
}
trap cleanup EXIT

phase1_cmd=(takt "${common_args[@]}" -w "$PHASE1_PIECE")
if [[ -n "$create_worktree_takt" ]]; then
  phase1_cmd+=(--create-worktree "$create_worktree_takt")
fi

echo "[gate] Phase 1/2: running ${PHASE1_PIECE}"
echo "[gate] ${phase1_cmd[*]}"
"${phase1_cmd[@]}"

phase1_exec_root="$PWD"
clone_meta_dir="$PWD/.takt/clone-meta"
updated_clone_meta_files=()
if [[ "$worktree_mode" != "no" ]]; then
  mapfile -t updated_clone_meta_files < <(
    find "$clone_meta_dir" -maxdepth 1 -type f -name '*.json' -newer "$marker_file" 2>/dev/null | sort
  )
fi

if [[ ${#updated_clone_meta_files[@]} -gt 1 ]]; then
  echo "[gate] ERROR: multiple updated clone metadata files found; refusing to guess worktree path." >&2
  printf '  - %s\n' "${updated_clone_meta_files[@]}" >&2
  exit 2
fi

if [[ "$worktree_mode" == "yes" && ${#updated_clone_meta_files[@]} -eq 0 ]]; then
  echo "[gate] ERROR: --create-worktree yes was requested, but no updated clone metadata was found." >&2
  exit 2
fi

if [[ ${#updated_clone_meta_files[@]} -eq 1 ]]; then
  clone_meta_file="${updated_clone_meta_files[0]}"
  clone_path="$(node -e 'const fs=require("fs"); const p=process.argv[1]; const j=JSON.parse(fs.readFileSync(p,"utf8")); if(!j.clonePath){ process.exit(2); } process.stdout.write(j.clonePath);' "$clone_meta_file" 2>/dev/null || true)"
  if [[ -z "$clone_path" ]]; then
    echo "[gate] ERROR: failed to resolve clonePath from $clone_meta_file." >&2
    exit 2
  fi
  if [[ ! -d "$clone_path" ]]; then
    echo "[gate] ERROR: resolved clonePath does not exist: $clone_path" >&2
    exit 2
  fi
  phase1_exec_root="$clone_path"
fi

approval_file="$phase1_exec_root/APPROVAL.md"
if [[ ! -f "$approval_file" ]]; then
  echo "[gate] ERROR: APPROVAL.md was not found in phase-1 execution directory: $phase1_exec_root" >&2
  exit 2
fi

if [[ "$approval_file" -ot "$marker_file" ]]; then
  echo "[gate] ERROR: APPROVAL.md exists but was not updated by phase 1: $approval_file" >&2
  exit 2
fi

echo "[gate] Phase 1 execution directory: $phase1_exec_root"
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

if ! read -r -p "Proceed with implementation? (y/N): " yn; then
  echo "[gate] Implementation canceled: approval input was not provided."
  exit 4
fi

case "$yn" in
  Y|y) ;;
  *)
    echo "[gate] Implementation canceled: explicit 'Y' is required to continue."
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
