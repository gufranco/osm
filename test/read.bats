load helpers/fixtures
load helpers/assertions

setup_file() {
  load helpers/fixtures
  WORK="$(fixture_workspace)"
  XDG_CONFIG_HOME="${WORK}/config"
  SERVED="${WORK}/served"
  mkdir -p "$SERVED" "${WORK}/home/.ssh" "${WORK}/stranger/.ssh"
  fixture_generate_ed25519 "${WORK}/home/.ssh" "id_ed25519_personal"
  fixture_generate_ed25519 "${WORK}/stranger/.ssh" "id_ed25519"
  fixture_publish_keys "$SERVED" "alice" "${WORK}/home/.ssh/id_ed25519_personal.pub"
  keyserver_start "$SERVED"
  ADDRESSED="$(fixture_fingerprint "${WORK}/home/.ssh/id_ed25519_personal.pub")"
  HOME="${WORK}/home" "$OSM_BIN" send alice 'the recovered secret' --no-clipboard >"${WORK}/message"
  export WORK SERVED OSM_GITHUB_BASE KEYSERVER_PID XDG_CONFIG_HOME ADDRESSED
}

teardown_file() {
  load helpers/fixtures
  keyserver_stop
  rm -rf "$WORK"
}

setup() {
  export HOME="${WORK}/home"
}

@test "finds the matching identity under a non-default filename" {
  run "$OSM_BIN" read "${WORK}/message"

  assert_status 0
  assert_output_contains "the recovered secret"
}

@test "reads the message from stdin" {
  run bash -c "'$OSM_BIN' read < '${WORK}/message'"

  assert_status 0
  assert_output_contains "the recovered secret"
}

@test "names the addressed fingerprint when no local key matches" {
  HOME="${WORK}/stranger" run "$OSM_BIN" read "${WORK}/message"

  assert_status 1
  assert_output_contains "no local private key matches"
  assert_output_contains "$ADDRESSED"
}

@test "rejects a message whose body was altered" {
  fixture_tamper_body "${WORK}/message" "${WORK}/tampered"

  run "$OSM_BIN" read "${WORK}/tampered"

  assert_status 1
  assert_output_lacks "the recovered secret"
}

@test "reports a truncated message missing its closing line" {
  grep -v -- "-----END OSM MESSAGE-----" "${WORK}/message" >"${WORK}/truncated"

  run "$OSM_BIN" read "${WORK}/truncated"

  assert_status 1
  assert_output_contains "truncated"
}

@test "reports input that is not an osm message at all" {
  printf 'just some chat text\n' >"${WORK}/noise"

  run "$OSM_BIN" read "${WORK}/noise"

  assert_status 1
  assert_output_contains "does not contain an osm message"
}

@test "reports a body that is not valid base64" {
  fixture_corrupt_body "${WORK}/message" "${WORK}/corrupt"

  run "$OSM_BIN" read "${WORK}/corrupt"

  assert_status 1
  assert_output_lacks "the recovered secret"
}

@test "reports a message with no key header" {
  grep -v '^key: ' "${WORK}/message" >"${WORK}/nokey"

  run "$OSM_BIN" read "${WORK}/nokey"

  assert_status 1
  assert_output_contains "no key header"
}

@test "reports an algorithm it does not understand" {
  sed 's/^alg: age$/alg: future-cipher/' "${WORK}/message" >"${WORK}/future"

  run "$OSM_BIN" read "${WORK}/future"

  assert_status 1
  assert_output_contains "unknown algorithm"
}

@test "honours an explicit identity override" {
  run "$OSM_BIN" read --identity "${WORK}/home/.ssh/id_ed25519_personal" "${WORK}/message"

  assert_status 0
  assert_output_contains "the recovered secret"
}

@test "reports an identity override that does not exist" {
  run "$OSM_BIN" read --identity "${WORK}/nope" "${WORK}/message"

  assert_status 1
  assert_output_contains "does not exist"
}

@test "reports a missing input file" {
  run "$OSM_BIN" read "${WORK}/absent-file"

  assert_status 1
  assert_output_contains "does not exist"
}

@test "rejects an unknown option" {
  run "$OSM_BIN" read --bogus

  assert_status 1
  assert_output_contains "unknown option for read"
}
