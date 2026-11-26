#!/usr/bin/env bash
# Apply a profile to a fresh mihomo checkout and run the packages it changes.
#
# Usage:
#   tool/test.sh [--keep] [--profile NAME]
#
# The checkout is temporary; --keep prints its path and leaves it in place.
# The profile defaults to $MIHOMO_PROFILE, then reclash.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/base.env"

profile=${MIHOMO_PROFILE:-reclash}
keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) keep=1 ;;
    --profile)
      [ $# -ge 2 ] || { printf 'usage: %s [--keep] [--profile NAME]\n' "$0" >&2; exit 2; }
      profile=$2
      shift
      ;;
    *)
      printf 'usage: %s [--keep] [--profile NAME]\n' "$0" >&2
      exit 2
      ;;
  esac
  shift
done

tmp=$(mktemp -d)
cleanup() {
  if [ "$keep" -eq 0 ]; then
    rm -rf "$tmp"
  else
    printf 'kept: %s\n' "$tmp/mihomo"
  fi
}
trap cleanup EXIT

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$MIHOMO_TAG" "$MIHOMO_URL" "$tmp/mihomo"
printf 'base: %s (%s), profile: %s\n' "$MIHOMO_TAG" "$MIHOMO_COMMIT" "$profile"
"$ROOT/tool/patch.sh" apply "$tmp/mihomo" --profile "$profile" >/dev/null
printf 'applied %d patches\n' "$("$ROOT/tool/patch.sh" list --profile "$profile" | wc -l)"

cd "$tmp/mihomo"
# Patch 0006 imports metacubex/mldsa. The consuming application module carries
# this requirement; the scratch checkout does the same here.
go mod edit -require=github.com/metacubex/mldsa@v0.1.1
export GOFLAGS=-mod=mod
go mod download github.com/metacubex/mldsa

# shellcheck disable=SC2046
go test -tags with_gvisor -count=1 -timeout 600s $(cat "$ROOT/tool/packages.txt")
# mux.cool is the one transport whose closes, timers and pools run on several
# goroutines; repetition under the race detector is what catches a close that
# only sometimes re-enters, or a session that leaks its goroutine.
go test -race -count=20 -timeout 600s ./transport/muxcool/
printf 'series ok\n'
