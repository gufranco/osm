osm_sign_identity() {
  local target="$1" work="$2"
  local raw supported fingerprint identity
  raw="${work}/from.keys"
  supported="${work}/from.supported"
  osm_fetch_keys "$target" "$raw"
  osm_supported_keys "$raw" >"$supported"
  osm_require_keys "$target" "$raw" "$supported"
  osm_fingerprints "$raw" >"${work}/from.fps"
  while IFS= read -r fingerprint; do
    if identity=$(osm_find_identity "$fingerprint"); then
      printf '%s\n' "$identity"
      return 0
    fi
  done <"${work}/from.fps"
  osm_die "no local private key matches a key published by '${target}', so osm cannot sign as them."
}

osm_sign_ciphertext() {
  local identity="$1" ciphertext="$2" sigfile="$3"
  if ! ssh-keygen -Y sign -f "$identity" -n "$OSM_SIG_NAMESPACE" "$ciphertext" >/dev/null 2>&1; then
    osm_die "signing failed with identity '${identity}'."
  fi
  mv "${ciphertext}.sig" "$sigfile"
}

osm_allowed_signers() {
  local from="$1" raw="$2" allowed="$3"
  local line
  : >"$allowed"
  while IFS= read -r line; do
    if [ -n "$line" ]; then
      printf '%s %s\n' "$from" "$line" >>"$allowed"
    fi
  done <"$raw"
}

osm_verify_signature() {
  local from="$1" ciphertext="$2" sigfile="$3" work="$4"
  local raw allowed
  raw="${work}/signer.keys"
  allowed="${work}/allowed_signers"
  osm_fetch_keys "$from" "$raw"
  osm_allowed_signers "$from" "$raw" "$allowed"
  if ! ssh-keygen -Y verify -f "$allowed" -I "$from" -n "$OSM_SIG_NAMESPACE" \
    -s "$sigfile" <"$ciphertext" >/dev/null 2>&1; then
    osm_die "the signature does not match any key published by '${from}'. do not trust this message."
  fi
  osm_warn "signature verified against a key published by '${from}'."
}
