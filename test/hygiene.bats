load helpers/fixtures
load helpers/assertions

setup_file() {
  load helpers/fixtures
  WORK="$(fixture_workspace)"
  XDG_CONFIG_HOME="${WORK}/config"
  SERVED="${WORK}/served"
  mkdir -p "$SERVED" "${WORK}/home/.ssh" "${WORK}/scratch"
  fixture_generate_ed25519 "${WORK}/home/.ssh" "id_ed25519"
  fixture_publish_keys "$SERVED" "alice" "${WORK}/home/.ssh/id_ed25519.pub"
  keyserver_start "$SERVED"
  FAKEBIN="$(sandbox_path_excluding "${WORK}/bin-fake" none)"
  printf '#!/usr/bin/env bash\ncat >"%s/clipboard"\n' "$WORK" >"${FAKEBIN}/pbcopy"
  chmod +x "${FAKEBIN}/pbcopy"
  export WORK SERVED OSM_GITHUB_BASE KEYSERVER_PID XDG_CONFIG_HOME FAKEBIN
}

teardown_file() {
  load helpers/fixtures
  keyserver_stop
  rm -rf "$WORK"
}

setup() {
  export HOME="${WORK}/home"
  rm -rf "${WORK}/scratch"
  mkdir -p "${WORK}/scratch"
}

@test "removes its workspace after a successful run" {
  TMPDIR="${WORK}/scratch" run bash -c "printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 0
  assert_equal "$(find "${WORK}/scratch" -maxdepth 1 -name 'osm-*' | wc -l | tr -d ' ')" "0"
}

@test "removes its workspace after a failed run" {
  TMPDIR="${WORK}/scratch" run bash -c "printf 'x\n' | '$OSM_BIN' send ghost --no-clipboard"

  assert_status 1
  assert_equal "$(find "${WORK}/scratch" -maxdepth 1 -name 'osm-*' | wc -l | tr -d ' ')" "0"
}

@test "removes its workspace after decrypting" {
  "$OSM_BIN" send alice 'cleanup check' --no-clipboard >"${WORK}/msg"

  TMPDIR="${WORK}/scratch" run "$OSM_BIN" read "${WORK}/msg"

  assert_status 0
  assert_equal "$(find "${WORK}/scratch" -maxdepth 1 -name 'osm-*' | wc -l | tr -d ' ')" "0"
}

@test "copies only ciphertext to the clipboard" {
  local payload="clipboard-canary-${RANDOM}"

  run env PATH="$FAKEBIN" HOME="${WORK}/home" bash -c \
    "printf '%s\n' '$payload' | '$OSM_BIN' send alice"

  assert_status 0
  assert_output_contains "copied to the clipboard with pbcopy"
  run cat "${WORK}/clipboard"
  assert_output_contains "-----BEGIN OSM MESSAGE-----"
  assert_output_lacks "$payload"
}

@test "documents that stdin avoids exposing the message in the process list" {
  run "$OSM_BIN" help

  assert_status 0
  assert_output_contains "process list"
}
