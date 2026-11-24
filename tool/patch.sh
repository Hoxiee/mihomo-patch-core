#!/usr/bin/env bash
# Apply, revert, and inspect the mihomo-patch-core series.
#
# Usage:
#   tool/patch.sh <list|status|check|apply|revert> [target] [--target DIR]
#
# The target is a mihomo git checkout. It defaults to $MIHOMO_DIR.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ORDER="$ROOT/patches/order.txt"

die() {
  printf 'mihomo-patch-core: %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
}

cmd=${1:-status}
shift || true

target=''
while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || die '--target needs a directory'
      target=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      [ -z "$target" ] || die "unexpected argument: $1"
      target=$1
      shift
      ;;
  esac
done
target=${target:-${MIHOMO_DIR:-}}

mapfile -t patches < <(grep -v '^[[:space:]]*#' "$ORDER" | grep -v '^[[:space:]]*$')

patch_path() {
  printf '%s/patches/%s' "$ROOT" "$1"
}

needs_target() {
  [ -n "$target" ] || die 'no target: pass a mihomo checkout or set MIHOMO_DIR'
  [ -d "$target" ] || die "target is not a directory: $target"
  git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    die "target is not a git worktree: $target"
}

is_applied() {
  git -C "$target" apply --reverse --check "$(patch_path "$1")" >/dev/null 2>&1
}

is_pending() {
  git -C "$target" apply --check "$(patch_path "$1")" >/dev/null 2>&1
}

case "$cmd" in
  list)
    printf '%s\n' "${patches[@]}"
    ;;

  status)
    needs_target
    conflicts=0
    for p in "${patches[@]}"; do
      if is_applied "$p"; then
        printf 'applied  %s\n' "$p"
      elif is_pending "$p"; then
        printf 'pending  %s\n' "$p"
      else
        printf 'CONFLICT %s\n' "$p"
        conflicts=$((conflicts + 1))
      fi
    done
    [ "$conflicts" -eq 0 ] || exit 1
    ;;

  check)
    needs_target
    conflicts=0
    for p in "${patches[@]}"; do
      if ! is_applied "$p" && ! is_pending "$p"; then
        printf 'CONFLICT %s\n' "$p" >&2
        conflicts=$((conflicts + 1))
      fi
    done
    if [ "$conflicts" -ne 0 ]; then
      die "$conflicts patch(es) do not apply to $target"
    fi
    printf 'all %d patches apply or are already applied\n' "${#patches[@]}"
    ;;

  apply)
    needs_target
    for p in "${patches[@]}"; do
      if is_applied "$p"; then
        printf 'already  %s\n' "$p"
        continue
      fi
      if is_pending "$p"; then
        git -C "$target" apply "$(patch_path "$p")"
        printf 'applied  %s\n' "$p"
        continue
      fi
      printf 'FAILED   %s\n' "$p" >&2
      printf '\nResolve it on top of the current tree:\n' >&2
      printf '  git -C %q apply --3way %q\n' "$target" "$(patch_path "$p")" >&2
      printf 'Fix the conflicts, commit the result, then regenerate the patch\n' >&2
      printf 'against the new parent (see README, "When a patch stops applying").\n' >&2
      exit 1
    done
    ;;

  revert)
    needs_target
    for ((i=${#patches[@]}-1; i>=0; i--)); do
      p=${patches[$i]}
      if is_applied "$p"; then
        git -C "$target" apply --reverse "$(patch_path "$p")"
        printf 'reverted %s\n' "$p"
      else
        printf 'skipped  %s\n' "$p"
      fi
    done
    ;;

  *)
    usage
    die "unknown command: $cmd"
    ;;
esac
