#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out="${root}/dist/osm"
entrypoint="${root}/lib/main.sh"

if [[ ! -f "$entrypoint" ]]; then
  printf 'missing entrypoint %s\n' "$entrypoint" >&2
  exit 1
fi

mkdir -p "${root}/dist"

{
  printf '#!/usr/bin/env bash\n'
  printf 'set -euo pipefail\n'
  for part in "${root}"/lib/*.sh; do
    if [[ "$part" == "$entrypoint" ]]; then
      continue
    fi
    printf '\n'
    cat "$part"
  done
  printf '\n'
  cat "$entrypoint"
} >"$out"

chmod 0755 "$out"
printf 'built %s (%s lines)\n' "$out" "$(wc -l <"$out" | tr -d ' ')"
