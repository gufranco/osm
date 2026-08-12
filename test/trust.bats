load helpers/fixtures
load helpers/assertions

setup_file() {
  load helpers/fixtures
  WORK="$(fixture_workspace)"
  XDG_CONFIG_HOME="${WORK}/config"
  SERVED="${WORK}/served"
  mkdir -p "$SERVED" "${WORK}/home/.ssh" "${WORK}/outsider/.ssh"
  fixture_generate_ed25519 "${WORK}/home/.ssh" "recipient"
  fixture_generate_ed25519 "${WORK}/home/.ssh" "sender"
  fixture_generate_ed25519 "${WORK}/home/.ssh" "rotated"
  fixture_generate_ed25519 "${WORK}/outsider/.ssh" "impostor"
  fixture_publish_keys "$SERVED" "alice" "${WORK}/home/.ssh/recipient.pub"
  fixture_publish_keys "$SERVED" "carol" "${WORK}/home/.ssh/sender.pub"
  fixture_publish_keys "$SERVED" "mallory" "${WORK}/outsider/.ssh/impostor.pub"
  keyserver_start "$SERVED"
  export WORK SERVED OSM_GITHUB_BASE KEYSERVER_PID XDG_CONFIG_HOME
}

teardown_file() {
  load helpers/fixtures
  keyserver_stop
  rm -rf "$WORK"
}

setup() {
  export HOME="${WORK}/home"
  export XDG_CONFIG_HOME="${WORK}/config-${BATS_TEST_NUMBER}"
  mkdir -p "$XDG_CONFIG_HOME"
}

@test "a signed message carries the sender and the signature" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --sign carol --no-clipboard"

  assert_status 0
  assert_output_contains "from: carol"
  assert_output_contains "sig: "
}

@test "the recipient verifies a good signature" {
  "$OSM_BIN" send alice 'authentic secret' --sign carol --no-clipboard >"${WORK}/signed"

  run "$OSM_BIN" read "${WORK}/signed"

  assert_status 0
  assert_output_contains "signature verified against a key published by 'carol'"
  assert_output_contains "authentic secret"
}

@test "a tampered body fails verification and prints no plaintext" {
  "$OSM_BIN" send alice 'authentic secret' --sign carol --no-clipboard >"${WORK}/tamper"
  fixture_tamper_body "${WORK}/tamper" "${WORK}/tampered"

  run "$OSM_BIN" read "${WORK}/tampered"

  assert_status 1
  assert_output_lacks "authentic secret"
}

@test "a signature from someone else's key is rejected" {
  "$OSM_BIN" send alice 'forged' --sign carol --no-clipboard >"${WORK}/forge"
  sed 's/^from: carol$/from: mallory/' "${WORK}/forge" >"${WORK}/forged"

  run "$OSM_BIN" read "${WORK}/forged"

  assert_status 1
  assert_output_contains "does not match any key published by 'mallory'"
  assert_output_lacks "forged"
}

@test "signing refuses when no local key matches the claimed sender" {
  run bash -c "HOME='${WORK}/outsider' printf 'x\n' | HOME='${WORK}/outsider' '$OSM_BIN' send alice --sign carol --no-clipboard"

  assert_status 1
  assert_output_contains "no local private key matches a key published by 'carol'"
}

@test "an unsigned message is refused under --require-signature" {
  "$OSM_BIN" send alice 'unsigned' --no-clipboard >"${WORK}/plain"

  run "$OSM_BIN" read "${WORK}/plain" --require-signature

  assert_status 1
  assert_output_contains "carries no signature"
}

@test "an unsigned message still opens without --require-signature" {
  "$OSM_BIN" send alice 'unsigned but fine' --no-clipboard >"${WORK}/plain2"

  run "$OSM_BIN" read "${WORK}/plain2"

  assert_status 0
  assert_output_contains "unsigned but fine"
}

@test "the first message to someone pins their fingerprints" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 0
  assert_output_contains "first message to 'alice'"
  assert_status 0
}

@test "a second message to the same keys is silent" {
  printf 'x\n' | "$OSM_BIN" send alice --no-clipboard >/dev/null 2>&1

  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 0
  assert_output_lacks "first message"
}

@test "a changed key is refused with the fingerprints shown" {
  printf 'x\n' | "$OSM_BIN" send alice --no-clipboard >/dev/null 2>&1
  fixture_publish_keys "$SERVED" "alice" "${WORK}/home/.ssh/rotated.pub"

  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 1
  assert_output_contains "changed since you last messaged them"
  assert_output_contains "--accept-new-key"

  fixture_publish_keys "$SERVED" "alice" "${WORK}/home/.ssh/recipient.pub"
}

@test "a changed key is accepted with --accept-new-key" {
  printf 'x\n' | "$OSM_BIN" send alice --no-clipboard >/dev/null 2>&1
  fixture_publish_keys "$SERVED" "alice" "${WORK}/home/.ssh/rotated.pub"

  run bash -c "printf 'x\n' | '$OSM_BIN' send alice --accept-new-key --no-clipboard"

  assert_status 0
  assert_output_contains "accepted new keys for 'alice'"

  fixture_publish_keys "$SERVED" "alice" "${WORK}/home/.ssh/recipient.pub"
}

@test "the pin store is private to the user" {
  printf 'x\n' | "$OSM_BIN" send alice --no-clipboard >/dev/null 2>&1

  run ls -l "${XDG_CONFIG_HOME}/osm/known_recipients"

  assert_status 0
  assert_output_contains "-rw-------"
}
