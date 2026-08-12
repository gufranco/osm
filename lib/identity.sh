osm_find_identity() {
  local wanted=$1
  local pub priv fingerprint
  for pub in "$HOME"/.ssh/*.pub; do
    if [[ ! -f "$pub" ]]; then
      continue
    fi
    fingerprint=$(ssh-keygen -lf "$pub" 2>/dev/null | awk '{print $2}')
    priv="${pub%.pub}"
    if [[ "$fingerprint" == "$wanted" && -f "$priv" ]]; then
      printf '%s\n' "$priv"
      return 0
    fi
  done
  return 1
}

osm_resolve_identity() {
  local keyfile=$1 override=$2
  local fingerprint identity
  if [[ -n "$override" ]]; then
    if [[ ! -f "$override" ]]; then
      osm_die "identity file '${override}' does not exist."
    fi
    printf '%s\n' "$override"
    return 0
  fi
  while IFS= read -r fingerprint; do
    if identity=$(osm_find_identity "$fingerprint"); then
      printf '%s\n' "$identity"
      return 0
    fi
  done <"$keyfile"
  printf 'osm: no local private key matches this message. it was addressed to:\n' >&2
  sed 's/^/  /' "$keyfile" >&2
  exit 1
}
