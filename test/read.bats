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
  assert_output_contains "no osm message found"
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

@test "recognises a key held only by the ssh agent" {
  if ! command -v ssh-agent >/dev/null 2>&1 || ! command -v ssh-add >/dev/null 2>&1; then
    skip "this machine has no ssh-agent to hold a key in"
  fi
  local agentkey="${WORK}/agentonly"
  ssh-keygen -q -t ed25519 -N '' -f "$agentkey" </dev/null
  fixture_publish_keys "$SERVED" "agentuser" "${agentkey}.pub"
  "$OSM_BIN" send agentuser 'for the agent user' --no-clipboard >"${WORK}/agent.armored" 2>/dev/null
  local sock="/tmp/osm-test-agent-$$.sock"
  rm -f "$sock"
  eval "$(ssh-agent -a "$sock" -s)" >/dev/null
  ssh-add -q "$agentkey" 2>/dev/null

  HOME="${WORK}/stranger" run "$OSM_BIN" read "${WORK}/agent.armored"

  ssh-agent -k >/dev/null 2>&1
  rm -f "$sock"
  assert_status 1
  assert_output_contains "your ssh agent does hold one of these keys"
  assert_output_contains "--identity-command"
}

@test "stays quiet about agents when none holds the key" {
  run "$OSM_BIN" read "${WORK}/message" --identity "${WORK}/absent-key"

  assert_status 1
  assert_output_lacks "ssh agent does hold"
}

@test "reads the private key from a command" {
  run "$OSM_BIN" read "${WORK}/message" \
    --identity-command "cat ${WORK}/home/.ssh/id_ed25519_personal"

  assert_status 0
  assert_output_contains "the recovered secret"
}

@test "reports a failing identity command" {
  run "$OSM_BIN" read "${WORK}/message" --identity-command "false"

  assert_status 1
  assert_output_contains "identity command"
}

@test "reports an identity command that produces nothing" {
  run "$OSM_BIN" read "${WORK}/message" --identity-command "true"

  assert_status 1
  assert_output_contains "produced nothing"
}

@test "names the whole block when the paste is missing it" {
  printf 'brew install gufranco/osm/osm\n' >"${WORK}/wrongpaste"

  run "$OSM_BIN" read "${WORK}/wrongpaste"

  assert_status 1
  assert_output_contains "copy the whole block"
}
