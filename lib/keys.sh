osm_fetch_keys() {
  local user="$1" dest="$2"
  local code
  if ! code=$(curl -sS -o "$dest" -w '%{http_code}' --max-time "$OSM_HTTP_TIMEOUT" "${OSM_GITHUB_BASE}/${user}.keys" 2>/dev/null); then
    osm_die "could not reach ${OSM_GITHUB_BASE}. check your network connection."
  fi
  case "$code" in
  200) ;;
  404) osm_die "GitHub account '${user}' was not found." ;;
  *) osm_die "unexpected HTTP ${code} while fetching keys for '${user}'." ;;
  esac
}

osm_supported_keys() {
  awk '$1 == "ssh-ed25519" || $1 == "ssh-rsa" { print }' "$1"
}

osm_unsupported_types() {
  awk 'NF > 1 && $1 != "ssh-ed25519" && $1 != "ssh-rsa" { print $1 }' "$1" | sort -u | tr '\n' ' '
}

osm_fingerprints() {
  ssh-keygen -lf "$1" 2>/dev/null | awk '{print $2}'
}

osm_require_keys() {
  local user="$1" raw="$2" supported="$3"
  local unsupported
  if [ ! -s "$raw" ]; then
    osm_die "GitHub account '${user}' has no SSH keys configured. ask them to add one at https://github.com/settings/keys"
  fi
  if [ ! -s "$supported" ]; then
    unsupported=$(osm_unsupported_types "$raw")
    osm_die "GitHub account '${user}' publishes no key osm can encrypt to. found: ${unsupported}only ssh-ed25519 and ssh-rsa are supported."
  fi
}

osm_fingerprint_matches() {
  local fingerprint="$1" prefix="$2"
  if [ -z "$prefix" ]; then
    return 0
  fi
  case "$fingerprint" in
  "$prefix"*) return 0 ;;
  "SHA256:$prefix"*) return 0 ;;
  *) return 1 ;;
  esac
}

osm_select_keys() {
  local supported="$1" prefix="$2" selected="$3" selected_fps="$4"
  local line index=0
  local all_fps="${selected_fps}.all"
  : >"$selected"
  : >"$selected_fps"
  osm_fingerprints "$supported" >"$all_fps"
  while IFS= read -r line; do
    index=$((index + 1))
    if osm_fingerprint_matches "$line" "$prefix"; then
      sed -n "${index}p" "$supported" >>"$selected"
      printf '%s\n' "$line" >>"$selected_fps"
    fi
  done <"$all_fps"
}

osm_reject_bad_pin() {
  local user="$1" prefix="$2" supported="$3" selected_fps="$4"
  local count
  count=$(wc -l <"$selected_fps" | tr -d ' ')
  if [ "$count" -eq 0 ]; then
    printf 'osm: no key of %s matches fingerprint prefix %s. available:\n' "$user" "$prefix" >&2
    osm_fingerprints "$supported" >&2
    exit 1
  fi
  if [ "$count" -gt 1 ]; then
    printf 'osm: fingerprint prefix %s is ambiguous for %s. it matches:\n' "$prefix" "$user" >&2
    cat "$selected_fps" >&2
    exit 1
  fi
}

osm_key_type() {
  awk 'NR == 1 { print $1 }' "$1"
}
