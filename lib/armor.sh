osm_emit_armor() {
  local alg="$1" tofile="$2" selected_fps="$3" ciphertext="$4" from="${5:-}" signature="${6:-}"
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
