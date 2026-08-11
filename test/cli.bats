load helpers/fixtures
load helpers/assertions

setup_file() {
  load helpers/fixtures
  WORK="$(fixture_workspace)"
  SERVED="${WORK}/served"
  mkdir -p "$SERVED" "${WORK}/home/.ssh" "${WORK}/bare/.ssh"
  fixture_generate_ed25519 "${WORK}/home/.ssh" "id_ed25519"
  fixture_publish_keys "$SERVED" "alice" "${WORK}/home/.ssh/id_ed25519.pub"
  keyserver_start "$SERVED"
  NOAGE="$(sandbox_path_excluding "${WORK}/bin-noage" age)"
  NOCLIP="$(sandbox_path_excluding "${WORK}/bin-noclip" none)"
  export WORK SERVED OSM_GITHUB_BASE KEYSERVER_PID NOAGE NOCLIP
}

teardown_file() {
  load helpers/fixtures
  keyserver_stop
  rm -rf "$WORK"
}

setup() {
  export HOME="${WORK}/home"
}

@test "version reports the version and the active engine" {
  run "$OSM_BIN" version

  assert_status 0
  assert_output_contains "osm 1.0.0"
  assert_output_contains "engine: age"
}

@test "version reports the fallback engine when age is absent" {
  run env PATH="$NOAGE" "$OSM_BIN" version

  assert_status 0
  assert_output_contains "rsa-oaep-sha1"
}

@test "help prints the usage block" {
  run "$OSM_BIN" help

  assert_status 0
  assert_output_contains "osm send <github-user>"
  assert_output_contains "osm read [file]"
}

@test "no arguments prints usage and fails" {
  run "$OSM_BIN"

  assert_status 1
  assert_output_contains "usage:"
}

@test "an unknown command is reported" {
  run "$OSM_BIN" frobnicate

  assert_status 1
  assert_output_contains "unknown command 'frobnicate'"
}

@test "send without a recipient reports usage" {
  run "$OSM_BIN" send

  assert_status 1
  assert_output_contains "usage: osm send"
}

@test "send rejects an unknown option" {
  run "$OSM_BIN" send alice --bogus

  assert_status 1
  assert_output_contains "unknown option for send"
}

@test "keys without a recipient reports usage" {
  run "$OSM_BIN" keys

  assert_status 1
  assert_output_contains "usage: osm keys"
}

@test "doctor passes when every dependency is present" {
  run "$OSM_BIN" doctor

  assert_status 0
  assert_output_contains "age"
  assert_output_contains "ok"
}

@test "doctor fails and gives a remedy when age is missing" {
  run env PATH="$NOAGE" HOME="${WORK}/home" "$OSM_BIN" doctor

  assert_status 1
  assert_output_contains "missing"
  assert_output_contains "brew install age"
}

@test "doctor warns when no usable key pair exists" {
  run env HOME="${WORK}/bare" "$OSM_BIN" doctor

  assert_status 0
  assert_output_contains "no key pair found"
}

@test "doctor counts usable identities" {
  run "$OSM_BIN" doctor

  assert_status 0
  assert_output_contains "usable key pair"
}

@test "send still succeeds when no clipboard tool exists" {
  run env PATH="$NOCLIP" HOME="${WORK}/home" bash -c \
    "printf 'x\n' | '$OSM_BIN' send alice"

  assert_status 0
  assert_output_contains "no clipboard tool found"
  assert_output_contains "-----BEGIN OSM MESSAGE-----"
}
