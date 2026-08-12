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

man_dir=${OSM_MAN_DIR:-${target_dir%/bin}/share/man/man1}
if mkdir -p "$man_dir" 2>/dev/null && install -m 0644 "${root}/man/osm.1" "${man_dir}/osm.1" 2>/dev/null; then
  printf 'installed %s\n' "${man_dir}/osm.1"
fi

completion_dir=${OSM_COMPLETION_DIR:-${target_dir%/bin}/share/bash-completion/completions}
if mkdir -p "$completion_dir" 2>/dev/null && install -m 0644 "${root}/completions/osm.bash" "${completion_dir}/osm" 2>/dev/null; then
  printf 'installed %s\n' "${completion_dir}/osm"
fi

zsh_dir=${OSM_ZSH_COMPLETION_DIR:-${target_dir%/bin}/share/zsh/site-functions}
if mkdir -p "$zsh_dir" 2>/dev/null && install -m 0644 "${root}/completions/_osm" "${zsh_dir}/_osm" 2>/dev/null; then
  printf 'installed %s\n' "${zsh_dir}/_osm"
fi

case ":${PATH}:" in
*":${target_dir}:"*) ;;
*)
  printf '\n%s is not on your PATH. add this to your shell profile:\n' "$target_dir"
  # shellcheck disable=SC2016
  printf '  export PATH="%s:$PATH"\n' "$target_dir"
  ;;
esac
