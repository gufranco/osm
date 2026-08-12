load helpers/fixtures
load helpers/assertions

setup_file() {
  load helpers/fixtures
  WORK="$(fixture_workspace)"
  XDG_CONFIG_HOME="${WORK}/config"
  SERVED="${WORK}/served"
  mkdir -p "$SERVED" "${WORK}/home/.ssh"
  fixture_generate_ed25519 "${WORK}/home/.ssh" "id_ed25519"
  fixture_generate_rsa "${WORK}/home/.ssh" "weak" 2048
  fixture_generate_rsa "${WORK}/home/.ssh" "strong" 4096
  fixture_publish_keys "$SERVED" "alice" "${WORK}/home/.ssh/id_ed25519.pub"
  fixture_publish_keys "$SERVED" "weakuser" "${WORK}/home/.ssh/weak.pub"
  fixture_publish_keys "$SERVED" "stronguser" "${WORK}/home/.ssh/strong.pub"
  keyserver_start "$SERVED"
  NOQR="$(sandbox_path_excluding "${WORK}/bin-noqr" qrencode)"
  export WORK SERVED OSM_GITHUB_BASE KEYSERVER_PID XDG_CONFIG_HOME NOQR
}

teardown_file() {
  load helpers/fixtures
  keyserver_stop
  rm -rf "$WORK"
}

setup() {
  export HOME="${WORK}/home"
}

@test "compresses a repetitive payload and marks the encoding" {
  head -c 4000 /dev/zero | tr '\0' 'a' >"${WORK}/repetitive"

  "$OSM_BIN" send alice --no-clipboard <"${WORK}/repetitive" >"${WORK}/rep.armored" 2>/dev/null

  run grep -c '^enc: gzip' "${WORK}/rep.armored"
  assert_status 0
}

@test "a compressed payload survives the round trip" {
  head -c 4000 /dev/zero | tr '\0' 'b' >"${WORK}/rep2"

  "$OSM_BIN" send alice --no-clipboard <"${WORK}/rep2" >"${WORK}/rep2.armored" 2>/dev/null
  "$OSM_BIN" read "${WORK}/rep2.armored" >"${WORK}/rep2.recovered"

  assert_files_identical "${WORK}/rep2" "${WORK}/rep2.recovered"
}

@test "compression shrinks the message it produces" {
  head -c 4000 /dev/zero | tr '\0' 'c' >"${WORK}/rep3"

  "$OSM_BIN" send alice --no-clipboard <"${WORK}/rep3" >"${WORK}/rep3.armored" 2>/dev/null

  [[ "$(wc -c <"${WORK}/rep3.armored")" -lt 2000 ]]
}

@test "an incompressible payload is left uncompressed" {
  head -c 3000 /dev/urandom >"${WORK}/random"

  "$OSM_BIN" send alice --no-clipboard <"${WORK}/random" >"${WORK}/random.armored" 2>/dev/null

  run grep -c '^enc:' "${WORK}/random.armored"
  assert_status 1
}

@test "an incompressible payload still round trips" {
  if [[ -n "${OSM_COVERAGE:-}" ]]; then
    skip "kcov ptrace instrumentation corrupts binary streams, the artifact itself does not"
  fi
  head -c 3000 /dev/urandom >"${WORK}/random2"

  "$OSM_BIN" send alice --no-clipboard <"${WORK}/random2" >"${WORK}/random2.armored" 2>/dev/null
  "$OSM_BIN" read "${WORK}/random2.armored" >"${WORK}/random2.recovered"

  assert_files_identical "${WORK}/random2" "${WORK}/random2.recovered"
}

@test "warns about an RSA key below the modern floor" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send weakuser --no-clipboard"

  assert_status 0
  assert_output_contains "2048-bit RSA key"
  assert_output_contains "rotate to ed25519"
}

@test "stays quiet about an RSA key at or above the floor" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send stronguser --no-clipboard"

  assert_status 0
  assert_output_lacks "below the"
}

@test "explains how to install qrencode when --qr cannot run" {
  run env PATH="$NOQR" HOME="${WORK}/home" bash -c \
    "printf 'x\n' | '$OSM_BIN' send alice --qr --no-clipboard"

  assert_status 1
  assert_output_contains "needs qrencode"
}

@test "compression raises what fits through the RSA fallback" {
  local noage
  noage="$(sandbox_path_excluding "${WORK}/bin-noage-compress" age)"
  head -c 900 /dev/zero | tr '\0' 'd' >"${WORK}/bigrepeat"

  run env PATH="$noage" HOME="${WORK}/home" bash -c \
    "'$OSM_BIN' send stronguser --no-clipboard < '${WORK}/bigrepeat'"

  assert_status 0
  assert_output_contains "alg: rsa-oaep-sha1"
}

@test "an expiring message carries an exp header" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --expires 1h --no-clipboard"

  assert_status 0
  assert_output_contains "exp: "
}

@test "a message inside its window still opens" {
  "$OSM_BIN" send alice 'still fresh' --expires 1h --no-clipboard >"${WORK}/fresh" 2>/dev/null

  run "$OSM_BIN" read "${WORK}/fresh"

  assert_status 0
  assert_output_contains "still fresh"
}

@test "an expired message is refused with the deadline shown" {
  "$OSM_BIN" send alice 'gone stale' --expires 1s --no-clipboard >"${WORK}/stale" 2>/dev/null
  sleep 2

  run "$OSM_BIN" read "${WORK}/stale"

  assert_status 1
  assert_output_contains "expired"
  assert_output_contains "--ignore-expiry"
  assert_output_lacks "gone stale"
}

@test "an expired message opens under --ignore-expiry" {
  "$OSM_BIN" send alice 'stale but wanted' --expires 1s --no-clipboard >"${WORK}/stale2" 2>/dev/null
  sleep 2

  run "$OSM_BIN" read "${WORK}/stale2" --ignore-expiry

  assert_status 0
  assert_output_contains "stale but wanted"
}

@test "a malformed duration is rejected" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --expires soon --no-clipboard"

  assert_status 1
  assert_output_contains "duration"
}

@test "an unknown duration unit is rejected" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --expires 5y --no-clipboard"

  assert_status 1
  assert_output_contains "unknown duration unit"
}

@test "the expiry deadline is rendered as a readable date" {
  "$OSM_BIN" send alice 'x' --expires 1s --no-clipboard >"${WORK}/stale3" 2>/dev/null
  sleep 2

  run "$OSM_BIN" read "${WORK}/stale3"

  assert_status 1
  assert_output_contains "UTC"
}

@test "a custom clipboard command is used for copying" {
  run env HOME="${WORK}/home" OSM_CLIPBOARD_COPY="tee ${WORK}/custom-clip" bash -c \
    "printf 'x\n' | '$OSM_BIN' send alice"

  assert_status 0
  assert_output_contains "copied to the clipboard with tee"
}

@test "a custom clipboard command is used for reading" {
  "$OSM_BIN" send alice 'from a custom clipboard' --no-clipboard >"${WORK}/custom.armored" 2>/dev/null

  run env HOME="${WORK}/home" OSM_CLIPBOARD_PASTE="cat ${WORK}/custom.armored" \
    "$OSM_BIN" read --clipboard

  assert_status 0
  assert_output_contains "from a custom clipboard"
}

@test "the first contact warning lists the fingerprints to verify" {
  export XDG_CONFIG_HOME="${WORK}/fresh-pin-store"
  mkdir -p "$XDG_CONFIG_HOME"

  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 0
  assert_output_contains "verify these fingerprints out of band"
  assert_output_contains "SHA256:"
}

@test "accepts a duration in minutes" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --expires 30m --no-clipboard"

  assert_status 0
  assert_output_contains "exp: "
}

@test "accepts a duration in days" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --expires 7d --no-clipboard"

  assert_status 0
  assert_output_contains "exp: "
}

@test "accepts a bare duration in seconds" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --expires 3600 --no-clipboard"

  assert_status 0
  assert_output_contains "exp: "
}

@test "refuses to decrypt with a passphrase key when no terminal exists" {
  ssh-keygen -q -t ed25519 -N 'a-real-passphrase' -f "${WORK}/locked" </dev/null
  fixture_publish_keys "$SERVED" "lockeduser" "${WORK}/locked.pub"
  "$OSM_BIN" send lockeduser 'needs a prompt' --no-clipboard >"${WORK}/locked.armored" 2>/dev/null

  run "$OSM_BIN" read "${WORK}/locked.armored" --identity "${WORK}/locked" </dev/null

  assert_status 1
  assert_output_contains "passphrase protected"
}

@test "explains that gunzip is needed to open a compressed message" {
  local nogzip
  nogzip="$(sandbox_path_excluding "${WORK}/bin-nogunzip" gunzip)"
  head -c 4000 /dev/zero | tr '\0' 'e' >"${WORK}/gz"
  "$OSM_BIN" send alice --no-clipboard <"${WORK}/gz" >"${WORK}/gz.armored" 2>/dev/null

  run env PATH="$nogzip" HOME="${WORK}/home" "$OSM_BIN" read "${WORK}/gz.armored"

  assert_status 1
  assert_output_contains "gunzip is not installed"
}

@test "refuses a QR code for a message too large to encode" {
  if ! command -v qrencode >/dev/null 2>&1; then
    skip "qrencode is not installed on this machine"
  fi
  head -c 9000 /dev/urandom >"${WORK}/huge"

  run bash -c "'$OSM_BIN' send alice --qr --no-clipboard < '${WORK}/huge'"

  assert_status 1
  assert_output_contains "too large for a QR code"
}

@test "names the problem on a shell without local" {
  if ! command -v ksh >/dev/null 2>&1; then
    skip "ksh is not installed on this machine"
  fi

  run ksh "${OSM_REPO_ROOT}/dist/osm" version

  assert_status 1
  assert_output_contains 'does not support "local"'
}

@test "the banner tells a newcomer what the block is and how to open it" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 0
  assert_output_contains "This is an encrypted message"
  assert_output_contains "brew tap gufranco/osm"
  assert_output_contains "osm read"
}

@test "the banner sits above the block so it cannot corrupt parsing" {
  "$OSM_BIN" send alice 'banner safe' --no-clipboard >"${WORK}/bannered" 2>/dev/null

  run "$OSM_BIN" read "${WORK}/bannered"

  assert_status 0
  assert_output_contains "banner safe"
}

@test "the banner never appears inside the armored block" {
  "$OSM_BIN" send alice 'x' --no-clipboard >"${WORK}/inside" 2>/dev/null

  run awk '/^-----BEGIN OSM MESSAGE-----$/,/^-----END OSM MESSAGE-----$/' "${WORK}/inside"

  assert_status 0
  assert_output_lacks "This is an encrypted message"
  assert_output_lacks "brew tap"
}

@test "--no-banner omits it" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --no-banner --no-clipboard"

  assert_status 0
  assert_output_lacks "This is an encrypted message"
  assert_output_contains "-----BEGIN OSM MESSAGE-----"
}

@test "OSM_BANNER=0 omits it" {
  run env HOME="${WORK}/home" OSM_BANNER=0 bash -c "printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 0
  assert_output_lacks "This is an encrypted message"
  assert_output_contains "-----BEGIN OSM MESSAGE-----"
}

@test "json output carries no banner" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --json --no-clipboard"

  assert_status 0
  assert_output_lacks "This is an encrypted message"
  assert_output_contains '"alg":"age"'
}

@test "the clipboard receives the banner along with the block" {
  run env HOME="${WORK}/home" OSM_CLIPBOARD_COPY="tee ${WORK}/banner-clip" bash -c \
    "printf 'x\n' | '$OSM_BIN' send alice"

  assert_status 0
  run cat "${WORK}/banner-clip"
  assert_output_contains "This is an encrypted message"
  assert_output_contains "-----END OSM MESSAGE-----"
}
