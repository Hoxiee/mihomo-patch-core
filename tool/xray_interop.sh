#!/usr/bin/env bash
# Run the mux.cool interop test against a real Xray-core release.
#
# Usage:
#   tool/xray_interop.sh [--target DIR] [--keep]
#
# Without --target the script clones the pinned mihomo base into a temporary
# directory, applies the core profile and runs the test there. With --target
# it uses an existing checkout that already carries the core profile (for
# example core/.mihomo in the ReClash tree).
#
# XRAY_VERSION and XRAY_SHA256 pin the release; the checksum is verified
# before the archive is extracted. Override them only together.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/base.env"

xray_version=${XRAY_VERSION:-26.11.9}
xray_sha256=${XRAY_SHA256:-b651f7e1d9966ee2c1b1ee1bf8b52c72771824d3065dce96bbc8bcc19ed95f82}

target=''
keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || { printf 'usage: %s [--target DIR] [--keep]\n' "$0" >&2; exit 2; }
      target=$2
      shift
      ;;
    --keep) keep=1 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'usage: %s [--target DIR] [--keep]\n' "$0" >&2
      exit 2
      ;;
  esac
  shift
done

cache=${XDG_CACHE_HOME:-$HOME/.cache}/mihomo-patches/xray
xray_dir="$cache/Xray-linux-64-$xray_version"
xray_bin="$xray_dir/xray"
if [ ! -x "$xray_bin" ]; then
  mkdir -p "$cache"
  archive="$cache/Xray-linux-64-$xray_version.zip"
  if [ ! -f "$archive" ]; then
    curl -fsSL --retry 3 -o "$archive" \
      "https://github.com/XTLS/Xray-core/releases/download/v${xray_version}/Xray-linux-64.zip"
  fi
  printf '%s  %s\n' "$xray_sha256" "$archive" | sha256sum -c -
  rm -rf "$xray_dir"
  mkdir -p "$xray_dir"
  unzip -q -o "$archive" -d "$xray_dir"
fi
[ -x "$xray_bin" ] || { printf 'xray binary missing: %s\n' "$xray_bin" >&2; exit 1; }

created=''
cleanup() {
  if [ -n "$created" ] && [ "$keep" -eq 0 ]; then
    rm -rf "$created"
  elif [ -n "$created" ]; then
    printf 'kept: %s\n' "$target"
  fi
}
trap cleanup EXIT

if [ -z "$target" ]; then
  created=$(mktemp -d)
  target="$created/mihomo"
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$MIHOMO_TAG" "$MIHOMO_URL" "$target"
  "$ROOT/tool/patch.sh" apply "$target" --profile core >/dev/null
fi

cd "$target"
export GOFLAGS=-mod=mod
go mod edit -require=github.com/metacubex/mldsa@v0.1.1
go mod download github.com/metacubex/mldsa

printf 'xray: %s (%s)\n' "$xray_version" "$xray_sha256"
MIHOMO_XRAY_BIN="$xray_bin" go test -tags with_gvisor -count=1 -timeout 600s \
  -run TestXrayInterop ./adapter/outbound/
