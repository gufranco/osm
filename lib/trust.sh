osm_trust_store() {
  local dir="${XDG_CONFIG_HOME:-${HOME}/.config}/osm"
  mkdir -p "$dir"
  chmod 700 "$dir" 2>/dev/null || true
  printf '%s/known_recipients\n' "$dir"
}

osm_trust_known() {
  awk -v target="$1" '$1 == target { print $2 }' "$2" | sort | tr '\n' ' '
}

osm_trust_record() {
  local target="$1" fps="$2" store="$3"
  awk -v target="$target" 'NF > 0 { print target" "$0 }' "$fps" >>"$store"
}

osm_trust_forget() {
  local target="$1" store="$2"
  local kept="${store}.kept"
  awk -v target="$target" '$1 != target' "$store" >"$kept"
  mv "$kept" "$store"
}

osm_trust_check() {
  local target="$1" fps="$2" accept_new="$3"
  local store known current line
  store=$(osm_trust_store)
  if [ ! -f "$store" ]; then
    : >"$store"
    chmod 600 "$store" 2>/dev/null || true
  fi
  known=$(osm_trust_known "$target" "$store")
  current=$(sort "$fps" | tr '\n' ' ')
  if [ -z "$known" ]; then
    osm_trust_record "$target" "$fps" "$store"
    osm_warn "first message to '${target}'. verify these fingerprints out of band:"
    while IFS= read -r line; do
      if [ -n "$line" ]; then
        printf '  %s\n' "$line" >&2
      fi
    done <"$fps"
    return 0
  fi
  if [ "$known" = "$current" ]; then
    return 0
  fi
  if [ "$accept_new" -eq 1 ]; then
    osm_trust_forget "$target" "$store"
    osm_trust_record "$target" "$fps" "$store"
    osm_warn "accepted new keys for '${target}'."
    return 0
  fi
  printf 'osm: the keys published by %s changed since you last messaged them.\n' "$target" >&2
  printf '  pinned:  %s\n' "$known" >&2
  printf '  current: %s\n' "$current" >&2
  printf '  a key rotation looks exactly like an account takeover from here.\n' >&2
  printf '  verify the fingerprint with them out of band, then re-run with --accept-new-key\n' >&2
  exit 1
}
