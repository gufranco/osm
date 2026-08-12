load helpers/fixtures
load helpers/assertions

setup_file() {
  load helpers/fixtures
  WORK="$(fixture_workspace)"
  XDG_CONFIG_HOME="${WORK}/config"
  SERVED="${WORK}/served"
  mkdir -p "$SERVED" "${WORK}/home/.ssh" "${WORK}/nokeys/.ssh"
  fixture_generate_ed25519 "${WORK}/home/.ssh" "id_ed25519"
  fixture_publish_keys "$SERVED" "alice" "${WORK}/home/.ssh/id_ed25519.pub"
  keyserver_start "$SERVED"
  NO_OPENSSL="$(sandbox_path_excluding "${WORK}/bin-noopenssl" openssl)"
  NO_CURL="$(sandbox_path_excluding "${WORK}/bin-nocurl" curl)"
  NO_KEYGEN="$(sandbox_path_excluding "${WORK}/bin-nokeygen" ssh-keygen)"
  LIBRE="$(sandbox_path_excluding "${WORK}/bin-libre" openssl)"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "LibreSSL 3.3.6\n"' >"${LIBRE}/openssl"
  chmod +x "${LIBRE}/openssl"
  ODD="$(sandbox_path_excluding "${WORK}/bin-odd" openssl)"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "WeirdSSL 9.9\n"' >"${ODD}/openssl"
  chmod +x "${ODD}/openssl"
  export WORK SERVED OSM_GITHUB_BASE KEYSERVER_PID XDG_CONFIG_HOME NO_OPENSSL NO_CURL NO_KEYGEN LIBRE ODD
}

teardown_file() {
  load helpers/fixtures
  keyserver_stop
  rm -rf "$WORK"
}

setup() {
  export HOME="${WORK}/home"
}

@test "reports an unexpected HTTP status from the key host" {
  run bash -c "printf 'x\n' | '$OSM_BIN' send status503 --no-clipboard"

  assert_status 1
  assert_output_contains "unexpected HTTP 503"
}

@test "doctor flags a missing openssl" {
  run env PATH="$NO_OPENSSL" HOME="${WORK}/home" "$OSM_BIN" doctor

  assert_status 1
  assert_output_contains "install openssl"
}

@test "doctor flags a missing curl" {
  run env PATH="$NO_CURL" HOME="${WORK}/home" "$OSM_BIN" doctor

  assert_status 1
  assert_output_contains "curl is required"
}

@test "doctor flags a missing ssh-keygen" {
  run env PATH="$NO_KEYGEN" HOME="${WORK}/home" "$OSM_BIN" doctor

  assert_status 1
  assert_output_contains "install openssh"
}

@test "doctor names LibreSSL and explains the padding pin" {
  run env PATH="$LIBRE" HOME="${WORK}/home" "$OSM_BIN" doctor

  assert_status 0
  assert_output_contains "LibreSSL"
  assert_output_contains "SHA-1"
}

@test "version tolerates an unrecognised openssl build" {
  run env PATH="$ODD" HOME="${WORK}/home" "$OSM_BIN" version

  assert_status 0
  assert_output_contains "osm $(fixture_expected_version)"
}

@test "reports no identity when the ssh directory holds no public keys" {
  printf 'x\n' | "$OSM_BIN" send alice --no-clipboard >"${WORK}/message"

  HOME="${WORK}/nokeys" run "$OSM_BIN" read "${WORK}/message"

  assert_status 1
  assert_output_contains "no local private key matches"
}

@test "send accepts a double dash before the message" {
  run bash -c "'$OSM_BIN' send alice --no-clipboard -- 'dashed secret' | '$OSM_BIN' read"

  assert_status 0
  assert_output_contains "dashed secret"
}

@test "read accepts a double dash before the file" {
  "$OSM_BIN" send alice 'dashed read' --no-clipboard >"${WORK}/dashed"

  run "$OSM_BIN" read -- "${WORK}/dashed"

  assert_status 0
  assert_output_contains "dashed read"
}

@test "copies with wl-copy when it is the only copier" {
  local dir="${WORK}/bin-wl"
  sandbox_path_excluding "$dir" pbcopy >/dev/null
  printf '%s\n' '#!/usr/bin/env bash' "cat >'${WORK}/wl.out'" >"${dir}/wl-copy"
  chmod +x "${dir}/wl-copy"

  run env PATH="$dir" HOME="${WORK}/home" bash -c "printf 'x\n' | '$OSM_BIN' send alice"

  assert_status 0
  assert_output_contains "copied to the clipboard with wl-copy"
}

@test "copies with xclip when it is the only copier" {
  local dir="${WORK}/bin-xclip"
  sandbox_path_excluding "$dir" pbcopy >/dev/null
  printf '%s\n' '#!/usr/bin/env bash' "cat >'${WORK}/xclip.out'" >"${dir}/xclip"
  chmod +x "${dir}/xclip"

  run env PATH="$dir" HOME="${WORK}/home" bash -c "printf 'x\n' | '$OSM_BIN' send alice"

  assert_status 0
  assert_output_contains "copied to the clipboard with xclip"
}

@test "copies with xsel when it is the only copier" {
  local dir="${WORK}/bin-xsel"
  sandbox_path_excluding "$dir" pbcopy >/dev/null
  printf '%s\n' '#!/usr/bin/env bash' "cat >'${WORK}/xsel.out'" >"${dir}/xsel"
  chmod +x "${dir}/xsel"

  run env PATH="$dir" HOME="${WORK}/home" bash -c "printf 'x\n' | '$OSM_BIN' send alice"

  assert_status 0
  assert_output_contains "copied to the clipboard with xsel"
}
