#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
artifact="${root}/dist/osm"
target_dir=${OSM_PREFIX:-$HOME/.local/bin}

if [[ ! -f "$artifact" ]]; then
  bash "${root}/build.sh"
fi

mkdir -p "$target_dir"
install -m 0755 "$artifact" "${target_dir}/osm"

printf 'installed %s\n' "${target_dir}/osm"

case ":${PATH}:" in
*":${target_dir}:"*) ;;
*)
  printf '\n%s is not on your PATH. add this to your shell profile:\n' "$target_dir"
  # shellcheck disable=SC2016
  printf '  export PATH="%s:$PATH"\n' "$target_dir"
  ;;
esac
