load helpers/fixtures
load helpers/assertions

setup_file() {
  load helpers/fixtures
  WORK="$(fixture_workspace)"
  SERVED="${WORK}/served"
  mkdir -p "$SERVED" "${WORK}/keys"
  fixture_generate_ed25519 "${WORK}/keys" "one"
  fixture_generate_ed25519 "${WORK}/keys" "two"
  fixture_generate_rsa "${WORK}/keys" "rsa" 2048
  fixture_generate_ecdsa "${WORK}/keys" "curve"
  fixture_publish_keys "$SERVED" "solo" "${WORK}/keys/one.pub"
  fixture_publish_keys "$SERVED" "multi" "${WORK}/keys/one.pub" "${WORK}/keys/two.pub"
  fixture_publish_keys "$SERVED" "mixed" "${WORK}/keys/one.pub" "${WORK}/keys/curve.pub"
  fixture_publish_keys "$SERVED" "curveonly" "${WORK}/keys/curve.pub"
  fixture_publish_empty_account "$SERVED" "barren"
  keyserver_start "$SERVED"
  FP_ONE="$(fixture_fingerprint "${WORK}/keys/one.pub")"
  FP_TWO="$(fixture_fingerprint "${WORK}/keys/two.pub")"
  export WORK SERVED OSM_GITHUB_BASE KEYSERVER_PID FP_ONE FP_TWO
}

teardown_file() {
  load helpers/fixtures
  keyserver_stop
  rm -rf "$WORK"
}

@test "reports a GitHub account that does not exist" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send ghost --no-clipboard"

  assert_status 1
  assert_output_contains "no account 'ghost' at github"
}

@test "reports an account that publishes no keys" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send barren --no-clipboard"

  assert_status 1
  assert_output_contains "has no SSH keys published"
}

@test "reports an account whose keys are all unsupported types" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send curveonly --no-clipboard"

  assert_status 1
  assert_output_contains "publishes no key osm can encrypt to"
  assert_output_contains "ecdsa-sha2-nistp256"
}

@test "ignores unsupported key types when a supported one is present" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send mixed --no-clipboard"

  assert_status 0
  assert_output_contains "key: ${FP_ONE}"
  assert_output_lacks "ecdsa"
}

@test "addresses every supported key by default" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send multi --no-clipboard"

  assert_status 0
  assert_output_contains "key: ${FP_ONE}"
  assert_output_contains "key: ${FP_TWO}"
}

@test "pins a single key when a fingerprint prefix is supplied" {
  local prefix=${FP_TWO#SHA256:}

  run bash -c "printf 'x\n' | '$OSM_BIN' send 'multi:${prefix}' --no-clipboard"

  assert_status 0
  assert_output_contains "key: ${FP_TWO}"
  assert_output_lacks "key: ${FP_ONE}"
}

@test "pins a single key through the --key flag" {
  local prefix=${FP_ONE#SHA256:}

  run bash -c "printf 'x\n' | '$OSM_BIN' send multi --key '${prefix}' --no-clipboard"

  assert_status 0
  assert_output_contains "key: ${FP_ONE}"
  assert_output_lacks "key: ${FP_TWO}"
}

@test "rejects a fingerprint prefix that matches nothing and lists the choices" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send multi --key zzzznomatch --no-clipboard"

  assert_status 1
  assert_output_contains "matches fingerprint prefix zzzznomatch"
  assert_output_contains "$FP_ONE"
  assert_output_contains "$FP_TWO"
}

@test "rejects an ambiguous fingerprint prefix and lists the matches" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send multi --key 'SHA256:' --no-clipboard"

  assert_status 1
  assert_output_contains "is ambiguous"
  assert_output_contains "$FP_ONE"
  assert_output_contains "$FP_TWO"
}

@test "lists an account's usable keys with fingerprints" {
  run "$OSM_BIN" keys multi

  assert_status 0
  assert_output_contains "$FP_ONE"
  assert_output_contains "$FP_TWO"
  assert_output_contains "ED25519"
}

@test "reports an unreachable key server" {
  OSM_GITHUB_BASE="http://127.0.0.1:1" run bash -c "printf 'x\n' | '$OSM_BIN' send solo --no-clipboard"

  assert_status 1
  assert_output_contains "could not reach"
}

@test "addresses several recipients in one message" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send --to solo --to multi --no-clipboard"

  assert_status 0
  assert_output_contains "to: solo"
  assert_output_contains "to: multi"
}

@test "accepts a local public key file as a recipient" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send --keys-file '${WORK}/keys/one.pub' --no-clipboard"

  assert_status 0
  assert_output_contains "key: ${FP_ONE}"
  assert_output_contains "to: one.pub"
}

@test "rejects a key file that does not exist" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send --keys-file '${WORK}/absent.pub' --no-clipboard"

  assert_status 1
  assert_output_contains "does not exist"
}

@test "emits machine readable output with --json" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send solo --json --no-clipboard"

  assert_status 0
  assert_output_contains '"alg":"age"'
  assert_output_contains '"to":["solo"]'
  assert_output_contains "BEGIN OSM MESSAGE"
}

@test "resolves the key host from the recipient suffix" {
  run "$OSM_BIN" keys-url alice@gitlab

  assert_status 0
  assert_output_contains "https://gitlab.com/alice.keys"
}

@test "refuses Bitbucket with a concrete remedy" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send alice@bitbucket --no-clipboard"

  assert_status 1
  assert_output_contains "no public SSH key endpoint"
  assert_output_contains "--keys-file"
}

@test "treats an unknown host as a self-hosted forge" {
  run "$OSM_BIN" keys-url alice@git.example.com

  assert_status 0
  assert_output_contains "https://git.example.com/alice.keys"
}

@test "resolves the codeberg host" {
  run "$OSM_BIN" keys-url alice@codeberg

  assert_status 0
  assert_output_contains "https://codeberg.org/alice.keys"
}

@test "resolves the sourcehut host with its tilde convention" {
  run "$OSM_BIN" keys-url alice@sourcehut

  assert_status 0
  assert_output_contains "https://meta.sr.ht/~alice.keys"
}

@test "accepts the srht alias for sourcehut" {
  run "$OSM_BIN" keys-url alice@srht

  assert_status 0
  assert_output_contains "https://meta.sr.ht/~alice.keys"
}

@test "rejects a key file holding no usable key" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send --keys-file '${WORK}/keys/curve.pub' --no-clipboard"

  assert_status 1
  assert_output_contains "no usable recipient key"
}
