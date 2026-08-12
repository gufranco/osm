osm_cmd_send() {
  local user="" prefix="" message="" no_clipboard=0 target="" literal=0
  while [ $# -gt 0 ]; do
    if [ "$literal" -eq 0 ]; then
      case "$1" in
      --key)
        prefix=${2:-}
        shift 2
        continue
        ;;
      --no-clipboard)
        no_clipboard=1
        shift
        continue
        ;;
      --)
        literal=1
        shift
        continue
        ;;
      -*) osm_die "unknown option for send: $1" ;;
      *) ;;
      esac
    fi
    if [ -z "$target" ]; then target=$1; else message=$1; fi
    shift
  done
  if [ -z "$target" ]; then
    osm_die "usage: osm send <github-user>[:<fingerprint-prefix>] [message]"
  fi
  user=${target%%:*}
  case "$target" in
  *:*)
    prefix=${target#*:}
    ;;
  *) ;;
  esac
  osm_send_run "$user" "$prefix" "$message" "$no_clipboard"
}

osm_send_run() {
  local user="$1" prefix="$2" message="$3" no_clipboard="$4"
  local work raw supported selected selected_fps plaintext ciphertext armor alg copier
  osm_init_workspace
  work="$OSM_WORKSPACE"
  raw="${work}/raw.keys"
  supported="${work}/supported.keys"
  selected="${work}/selected.keys"
  selected_fps="${work}/selected.fps"
  plaintext="${work}/plain"
  ciphertext="${work}/cipher"
  armor="${work}/armor"
  osm_fetch_keys "$user" "$raw"
  osm_supported_keys "$raw" >"$supported"
  osm_require_keys "$user" "$raw" "$supported"
  osm_select_keys "$supported" "$prefix" "$selected" "$selected_fps"
  if [ -n "$prefix" ]; then
    osm_reject_bad_pin "$user" "$prefix" "$supported" "$selected_fps"
  fi
  osm_read_plaintext "$plaintext" "$message"
  if osm_have age; then
    alg="age"
    osm_encrypt_age "$selected" "$plaintext" "$ciphertext"
  else
    alg="rsa-oaep-sha1"
    osm_warn "age is not installed. falling back to RSA, which is size limited and provides no integrity check."
    osm_encrypt_openssl "$selected" "$plaintext" "$ciphertext" "$work"
  fi
  osm_emit_armor "$alg" "$user" "$selected_fps" "$ciphertext" >"$armor"
  cat "$armor"
  if [ "$no_clipboard" -eq 0 ]; then
    if copier=$(osm_clipboard_copy "$armor"); then
      osm_warn "copied to the clipboard with ${copier}."
    else
      osm_warn "no clipboard tool found. copy the block above manually."
    fi
  fi
}

osm_cmd_read() {
  local source="" identity_override="" literal=0
  while [ $# -gt 0 ]; do
    if [ "$literal" -eq 0 ]; then
      case "$1" in
      --identity)
        identity_override=${2:-}
        shift 2
        continue
        ;;
      --)
        literal=1
        shift
        continue
        ;;
      -*) osm_die "unknown option for read: $1" ;;
      *) ;;
      esac
    fi
    source=$1
    shift
  done
  osm_read_run "$source" "$identity_override"
}

osm_read_run() {
  local source="$1" identity_override="$2"
  local work input keys ciphertext alg identity
  osm_init_workspace
  work="$OSM_WORKSPACE"
  input="${work}/input"
  keys="${work}/addressed.fps"
  ciphertext="${work}/cipher"
  if [ -n "$source" ]; then
    if [ ! -f "$source" ]; then
      osm_die "file '${source}' does not exist."
    fi
    tr -d '\r' <"$source" >"$input"
  else
    tr -d '\r' >"$input"
  fi
  osm_require_armor "$input"
  osm_armor_field "$input" "key" >"$keys"
  if [ ! -s "$keys" ]; then
    osm_die "the osm message has no key header, so osm cannot tell which identity to use."
  fi
  alg=$(osm_armor_field "$input" "alg" | head -1)
  if ! osm_armor_body "$input" | tr -d '\n' | openssl base64 -d -A -out "$ciphertext" 2>/dev/null; then
    osm_die "the message body is not valid base64. the paste may be incomplete."
  fi
  identity=$(osm_resolve_identity "$keys" "$identity_override")
  case "$alg" in
  age)
    if ! osm_have age; then
      osm_die "this message needs age to open. install it with: brew install age, or apt install age"
    fi
    osm_decrypt_age "$identity" "$ciphertext"
    ;;
  rsa-oaep-sha1) osm_decrypt_openssl "$identity" "$ciphertext" ;;
  *) osm_die "unknown algorithm '${alg}'. this message may come from a newer osm." ;;
  esac
}

osm_cmd_keys() {
  local user="${1:-}"
  local work raw supported
  if [ -z "$user" ]; then
    osm_die "usage: osm keys <github-user>"
  fi
  osm_init_workspace
  work="$OSM_WORKSPACE"
  raw="${work}/raw.keys"
  supported="${work}/supported.keys"
  osm_fetch_keys "$user" "$raw"
  osm_supported_keys "$raw" >"$supported"
  osm_require_keys "$user" "$raw" "$supported"
  ssh-keygen -lf "$supported" | awk '{type=$NF; gsub(/[()]/, "", type); printf "%-10s %s %s bits\n", type, $2, $1}'
}

osm_doctor_line() {
  local label="$1" state="$2" remedy="$3"
  printf '%-14s %-8s %s\n' "$label" "$state" "$remedy"
}

osm_cmd_doctor() {
  local failures=0 flavor
  if osm_have age; then
    osm_doctor_line "age" "ok" "$(age --version 2>/dev/null)"
  else
    osm_doctor_line "age" "missing" "install with: brew install age, or apt install age"
    failures=$((failures + 1))
  fi
  if osm_have curl; then
    osm_doctor_line "curl" "ok" ""
  else
    osm_doctor_line "curl" "missing" "curl is required to fetch keys from GitHub"
    failures=$((failures + 1))
  fi
  if osm_have ssh-keygen; then
    osm_doctor_line "ssh-keygen" "ok" ""
  else
    osm_doctor_line "ssh-keygen" "missing" "install openssh"
    failures=$((failures + 1))
  fi
  flavor=$(osm_openssl_flavor)
  case "$flavor" in
  openssl) osm_doctor_line "openssl" "ok" "OpenSSL" ;;
  libressl) osm_doctor_line "openssl" "ok" "LibreSSL. the RSA fallback pins OAEP to SHA-1 so it interoperates with OpenSSL" ;;
  *)
    osm_doctor_line "openssl" "missing" "install openssl"
    failures=$((failures + 1))
    ;;
  esac
  osm_doctor_identities
  if [ "$failures" -gt 0 ]; then
    exit 1
  fi
}

osm_doctor_identities() {
  local pub count=0
  for pub in "$HOME"/.ssh/*.pub; do
    if [ -f "$pub" ] && [ -f "${pub%.pub}" ]; then
      count=$((count + 1))
    fi
  done
  if [ "$count" -gt 0 ]; then
    osm_doctor_line "identities" "ok" "${count} usable key pair(s) under ~/.ssh"
  else
    osm_doctor_line "identities" "warn" "no key pair found under ~/.ssh. you can receive nothing until you add one"
  fi
}

osm_cmd_version() {
  local engine
  engine="rsa-oaep-sha1 via $(osm_openssl_flavor)"
  if osm_have age; then
    engine="age"
  fi
  printf 'osm %s\nengine: %s\n' "$OSM_VERSION" "$engine"
}

osm_usage() {
  cat <<'USAGE'
osm - send encrypted messages through any chat, using GitHub SSH keys

usage:
  osm send <github-user>[:<fingerprint-prefix>] [message]
  osm read [file]
  osm keys <github-user>
  osm doctor
  osm version

options:
  --key <prefix>     encrypt to one key only, chosen by fingerprint prefix
  --identity <path>  decrypt with a specific private key
  --no-clipboard     do not copy the result to the clipboard

notes:
  Passing the message as an argument makes it visible to other users of this
  machine through the process list. Piping it on stdin avoids that.

examples:
  osm send alice 'database password: correct-horse'
  printf 'secret' | osm send alice
  pbpaste | osm read
  osm read message.txt
USAGE
}
