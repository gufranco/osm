osm_emit_armor() {
  local alg="$1" tofile="$2" selected_fps="$3" ciphertext="$4" from="${5:-}" signature="${6:-}" encoding="${7:-}" expires="${8:-}"
  local fingerprint recipient
  printf '%s\n' "$OSM_ARMOR_BEGIN"
  printf 'v: %s\n' "$OSM_FORMAT_VERSION"
  printf 'alg: %s\n' "$alg"
  if [ -n "$from" ]; then
    printf 'from: %s\n' "$from"
  fi
  if [ -n "$signature" ]; then
    printf 'sig: %s\n' "$signature"
  fi
  if [ -n "$encoding" ]; then
    printf 'enc: %s\n' "$encoding"
  fi
  if [ -n "$expires" ]; then
    printf 'exp: %s\n' "$expires"
  fi
  while IFS= read -r recipient; do
    printf 'to: %s\n' "$recipient"
  done <"$tofile"
  while IFS= read -r fingerprint; do
    printf 'key: %s\n' "$fingerprint"
  done <"$selected_fps"
  printf '\n'
  openssl base64 -A -in "$ciphertext" | fold -w 64
  printf '\n%s\n' "$OSM_ARMOR_END"
}

# shellcheck disable=SC2016
OSM_AWK_FIELD='BEGIN{p=want": "} /^-----BEGIN OSM MESSAGE-----$/{s=1;b=0;next} !s{next} $0=="-----END OSM MESSAGE-----"{exit} /^$/{b=1} !b&&index($0,p)==1{print substr($0,length(p)+1)}'
OSM_AWK_BODY='/^-----BEGIN OSM MESSAGE-----$/{s=1;next} !s{next} /^-----END OSM MESSAGE-----$/{exit} b{print} /^$/{b=1}'

osm_armor_field() {
  awk -v want="$2" "$OSM_AWK_FIELD" "$1"
}

osm_armor_body() {
  awk "$OSM_AWK_BODY" "$1"
}

osm_require_armor() {
  local file="$1"
  if ! grep -q -- "$OSM_ARMOR_BEGIN" "$file"; then
    osm_die "input does not contain an osm message. expected a block starting with ${OSM_ARMOR_BEGIN}"
  fi
  if ! grep -q -- "$OSM_ARMOR_END" "$file"; then
    osm_die "the osm message is truncated. the closing ${OSM_ARMOR_END} line is missing."
  fi
}

osm_json_array() {
  awk 'BEGIN{printf "["} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); printf "%s\"%s\"", (NR>1 ? "," : ""), $0} END{printf "]"}' "$1"
}

osm_emit_json() {
  local alg="$1" tofile="$2" selected_fps="$3" armor="$4"
  printf '{"version":"%s","alg":"%s","to":%s,"keys":%s,"armor":"%s"}\n' \
    "$OSM_FORMAT_VERSION" "$alg" \
    "$(osm_json_array "$tofile")" \
    "$(osm_json_array "$selected_fps")" \
    "$(awk '{gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); printf "%s\\n", $0}' "$armor")"
}

osm_parse_duration() {
  local value="$1" number unit
  number=$(printf '%s' "$value" | sed -n 's/^\([0-9][0-9]*\).*$/\1/p')
  unit=$(printf '%s' "$value" | sed -n 's/^[0-9][0-9]*\(.*\)$/\1/p')
  if [ -z "$number" ]; then
    osm_die "cannot read '${value}' as a duration. use forms like 30m, 6h or 7d."
  fi
  case "$unit" in
  "" | s) printf '%s\n' "$number" ;;
  m) printf '%s\n' "$((number * 60))" ;;
  h) printf '%s\n' "$((number * 3600))" ;;
  d) printf '%s\n' "$((number * 86400))" ;;
  *) osm_die "unknown duration unit '${unit}'. use s, m, h or d." ;;
  esac
}

osm_expiry_stamp() {
  local seconds
  seconds=$(osm_parse_duration "$1") || exit 1
  printf '%s\n' "$(($(date -u +%s) + seconds))"
}

osm_format_stamp() {
  date -u -r "$1" '+%Y-%m-%d %H:%M UTC' 2>/dev/null && return 0
  date -u -d "@$1" '+%Y-%m-%d %H:%M UTC' 2>/dev/null && return 0
  printf '%s\n' "$1"
}

osm_check_expiry() {
  local stamp="$1" ignore="$2"
  local now
  if [ -z "$stamp" ]; then
    return 0
  fi
  now=$(date -u +%s)
  if [ "$now" -le "$stamp" ]; then
    return 0
  fi
  if [ "$ignore" -eq 1 ]; then
    osm_warn "this message expired, opening it anyway because --ignore-expiry was given."
    return 0
  fi
  osm_die "this message expired. the sender marked it valid until $(osm_format_stamp "$stamp"). re-run with --ignore-expiry to open it regardless."
}

osm_banner_enabled() {
  case "$OSM_BANNER" in
  0 | no | off | false) return 1 ;;
  *) return 0 ;;
  esac
}

osm_emit_banner() {
  cat <<'BANNER'
This is an encrypted message. Only the intended recipient can read it.
To open it, install osm and pipe this whole block into it:

  brew tap gufranco/osm https://github.com/gufranco/osm && brew install gufranco/osm/osm
  pbpaste | osm read

What it is: https://github.com/gufranco/osm
BANNER
}
