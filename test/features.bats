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
  NOQR="$(sandbox_path_excluding "${WORK}/bin-noqr" none)"
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
