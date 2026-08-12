#!/usr/bin/env bash
set -euo pipefail

version=${1:?version required}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
core="${root}/lib/core.sh"

if ! grep -q '^OSM_VERSION=' "$core"; then
  printf 'no OSM_VERSION assignment found in %s\n' "$core" >&2
  exit 1
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/osm-version-XXXXXX")
sed "s/^OSM_VERSION=\".*\"$/OSM_VERSION=\"${version}\"/" "$core" >"$tmp"
mv "$tmp" "$core"

bash "${root}/build.sh" >/dev/null

printf 'version set to %s\n' "$("${root}/dist/osm" version | head -1)"
