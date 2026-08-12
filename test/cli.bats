load helpers/fixtures
load helpers/assertions

setup_file() {
  load helpers/fixtures
  WORK="$(fixture_workspace)"
  XDG_CONFIG_HOME="${WORK}/config"
  SERVED="${WORK}/served"
  mkdir -p "$SERVED" "${WORK}/home/.ssh" "${WORK}/bare/.ssh"
  fixture_generate_ed25519 "${WORK}/home/.ssh" "id_ed25519"
  fixture_publish_keys "$SERVED" "alice" "${WORK}/home/.ssh/id_ed25519.pub"
  keyserver_start "$SERVED"
  NOAGE="$(sandbox_path_excluding "${WORK}/bin-noage" age)"
  NOCLIP="$(sandbox_path_excluding "${WORK}/bin-noclip" none)"
  export WORK SERVED OSM_GITHUB_BASE KEYSERVER_PID XDG_CONFIG_HOME NOAGE NOCLIP
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
  assert_output_contains "osm send <user>"
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

@test "reads the message from the clipboard when nothing is piped" {
  local dir="${WORK}/clipread"
  sandbox_path_excluding "$dir" none >/dev/null
  "$OSM_BIN" send alice 'clipboard sourced secret' --no-clipboard >"${WORK}/clip.armored"
  printf '%s\n' '#!/usr/bin/env bash' "cat '${WORK}/clip.armored'" >"${dir}/pbpaste"
  chmod +x "${dir}/pbpaste"

  run env PATH="$dir" HOME="${WORK}/home" python3 -c 'import os,pty,sys; sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))' "$OSM_BIN" read

  assert_status 0
  assert_output_contains "clipboard sourced secret"
}

paste_shim() {
  local dir="$1" name="$2" payload="$3"
  sandbox_path_excluding "$dir" pbpaste >/dev/null
  printf '%s\n' '#!/usr/bin/env bash' "cat '${payload}'" >"${dir}/${name}"
  chmod +x "${dir}/${name}"
}

run_read_on_tty() {
  env PATH="$1" HOME="${WORK}/home" "$OSM_BIN" read --clipboard </dev/null
}

@test "reads the clipboard with wl-paste" {
  "$OSM_BIN" send alice 'wayland secret' --no-clipboard >"${WORK}/wl.armored"
  paste_shim "${WORK}/bin-wlpaste" wl-paste "${WORK}/wl.armored"

  run run_read_on_tty "${WORK}/bin-wlpaste"

  assert_status 0
  assert_output_contains "wayland secret"
}

@test "reads the clipboard with xclip" {
  "$OSM_BIN" send alice 'xclip secret' --no-clipboard >"${WORK}/xc.armored"
  paste_shim "${WORK}/bin-xclippaste" xclip "${WORK}/xc.armored"

  run run_read_on_tty "${WORK}/bin-xclippaste"

  assert_status 0
  assert_output_contains "xclip secret"
}

@test "reads the clipboard with xsel" {
  "$OSM_BIN" send alice 'xsel secret' --no-clipboard >"${WORK}/xs.armored"
  paste_shim "${WORK}/bin-xselpaste" xsel "${WORK}/xs.armored"

  run run_read_on_tty "${WORK}/bin-xselpaste"

  assert_status 0
  assert_output_contains "xsel secret"
}

@test "explains what to do when there is nothing to read at all" {
  local dir="${WORK}/bin-noclip-read"
  sandbox_path_excluding "$dir" pbpaste >/dev/null

  run run_read_on_tty "$dir"

  assert_status 1
  assert_output_contains "nothing to read"
}
