osm_find_identity() {
  local wanted="$1"
  local pub priv fingerprint
  for pub in "$HOME"/.ssh/*.pub; do
    if [ ! -f "$pub" ]; then
      continue
    fi
    fingerprint=$(ssh-keygen -lf "$pub" 2>/dev/null | awk '{print $2}')
    priv="${pub%.pub}"
    if [ "$fingerprint" = "$wanted" ] && [ -f "$priv" ]; then
      printf '%s\n' "$priv"
      return 0
    fi
  done
  return 1
}

osm_resolve_identity() {
  local keyfile="$1" override="$2"
  local fingerprint identity
  if [ -n "$override" ]; then
    if [ ! -f "$override" ]; then
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
  osm_explain_agent "$keyfile"
  exit 1
}

osm_identity_is_encrypted() {
  ! ssh-keygen -y -f "$1" -P "" >/dev/null 2>&1
}

osm_require_passphrase_channel() {
  local identity="$1"
  if ! osm_identity_is_encrypted "$identity"; then
    return 0
  fi
  if (true </dev/tty) 2>/dev/null; then
    return 0
  fi
  osm_die "'${identity}' is passphrase protected and there is no terminal to prompt on. run osm from an interactive shell, or pass an unencrypted key with --identity."
}

osm_agent_fingerprints() {
  local dest="$1"
  : >"$dest"
  if [ -z "${SSH_AUTH_SOCK:-}" ]; then
    return 1
  fi
  ssh-add -l 2>/dev/null | awk '{print $2}' >"$dest" || true
  [ -s "$dest" ]
}

osm_explain_agent() {
  local keyfile="$1"
  local agentfile="${OSM_WORKSPACE}/agent.fps"
  if ! osm_agent_fingerprints "$agentfile"; then
    return 0
  fi
  if ! grep -q -F -f "$keyfile" "$agentfile" 2>/dev/null; then
    return 0
  fi
  printf '\n' >&2
  printf 'your ssh agent does hold one of these keys, so this message is addressed to you.\n' >&2
  printf 'age can only decrypt with a key file, and an agent such as 1Password never hands\n' >&2
  printf 'over the private half, so osm cannot use it directly. two ways through:\n' >&2
  printf '\n' >&2
  printf '  osm read --identity-command "op read op://Private/ssh-key/private-key"\n' >&2
  printf '  osm read --identity ~/.ssh/id_ed25519\n' >&2
  printf '\n' >&2
  printf 'the first keeps the key out of your disk. osm writes it to a private temporary\n' >&2
  printf 'file and deletes it when it exits.\n' >&2
}
