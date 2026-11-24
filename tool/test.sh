#!/usr/bin/env bash
# Apply the series to a fresh mihomo checkout and run the packages it changes.
#
# Usage:
#   tool/test.sh [--keep]
#
# The checkout is temporary; --keep prints its path and leaves it in place.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/base.env"

keep=0
case "${1:-}" in
  --keep) keep=1 ;;
  '') ;;
  *) printf 'usage: %s [--keep]\n' "$0" >&2; exit 2 ;;
esac

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
printf 'base: %s (%s)\n' "$MIHOMO_TAG" "$MIHOMO_COMMIT"
"$ROOT/tool/patch.sh" apply "$tmp/mihomo" >/dev/null
printf 'applied %d patches\n' "$(grep -vc '^[[:space:]]*#' "$ROOT/patches/order.txt")"

cd "$tmp/mihomo"
# Patch 0006 imports metacubex/mldsa. The consuming application module carries
# this requirement; the scratch checkout does the same here.
go mod edit -require=github.com/metacubex/mldsa@v0.1.1
export GOFLAGS=-mod=mod
go mod download github.com/metacubex/mldsa

# shellcheck disable=SC2046
go test -tags with_gvisor -count=1 -timeout 600s $(cat "$ROOT/tool/packages.txt")
printf 'series ok\n'
