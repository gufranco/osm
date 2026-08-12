OSM_SED_KEYBITS='s/.*Public-Key: (\([0-9][0-9]*\) bit).*/\1/p'

osm_rsa_capacity() {
  local pem="$1"
  local bits
  bits=$(openssl pkey -pubin -in "$pem" -text -noout 2>/dev/null | sed -n "$OSM_SED_KEYBITS" | head -1)
  if [ -z "$bits" ]; then
    bits=$(openssl rsa -pubin -in "$pem" -text -noout 2>/dev/null | sed -n "$OSM_SED_KEYBITS" | head -1)
  fi
  if [ -z "$bits" ]; then
    osm_die "could not determine the recipient RSA key size."
  fi
  printf '%s\n' "$((bits / 8 - OSM_OAEP_OVERHEAD))"
}

osm_encrypt_age() {
  local selected="$1" plaintext="$2" ciphertext="$3"
  if ! age -R "$selected" -o "$ciphertext" <"$plaintext" 2>/dev/null; then
    osm_die "age failed to encrypt the message."
  fi
}

osm_encrypt_openssl() {
  local selected="$1" plaintext="$2" ciphertext="$3" work="$4"
  local pem="${work}/recipient.pem" capacity size
  if [ "$(osm_key_type "$selected")" != "ssh-rsa" ]; then
    osm_die "age is not installed and the recipient key is not RSA. install age (brew install age, apt install age) to send to this recipient."
  fi
  if ! ssh-keygen -e -m PKCS8 -f "$selected" >"$pem" 2>/dev/null; then
    osm_die "could not convert the recipient SSH key to PKCS8."
  fi
  capacity=$(osm_rsa_capacity "$pem") || exit 1
  size=$(wc -c <"$plaintext" | tr -d ' ')
  if [ "$size" -gt "$capacity" ]; then
    osm_die "message is ${size} bytes but this RSA key can carry only ${capacity}. install age to remove the limit."
  fi
  if ! openssl pkeyutl -encrypt -pubin -inkey "$pem" \
    -pkeyopt rsa_padding_mode:oaep -in "$plaintext" -out "$ciphertext" 2>/dev/null; then
    osm_die "openssl failed to encrypt the message."
  fi
}
osm_decrypt_age() {
  local identity="$1" ciphertext="$2"
  if ! age -d -i "$identity" "$ciphertext"; then
    osm_die "decryption failed. the message may be corrupt, altered, or addressed to a different key."
  fi
}

osm_decrypt_openssl() {
  local identity="$1" ciphertext="$2"
  if ! openssl pkeyutl -decrypt -inkey "$identity" \
    -pkeyopt rsa_padding_mode:oaep -in "$ciphertext" 2>/dev/null; then
    osm_die "decryption failed. if your private key begins with 'BEGIN OPENSSH PRIVATE KEY', convert it with: ssh-keygen -p -m PEM -f ${identity}"
  fi
}
