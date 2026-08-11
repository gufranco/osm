#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out="${root}/dist/osm"

mkdir -p "${root}/dist"

{
  printf '#!/usr/bin/env bash\n'
  printf 'set -euo pipefail\n'
  for part in "${root}"/lib/*.sh; do
    printf '\n'
    cat "$part"
  done
} >"$out"

chmod 0755 "$out"
printf 'built %s (%s lines)\n' "$out" "$(wc -l <"$out" | tr -d ' ')"
