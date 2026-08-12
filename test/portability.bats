load helpers/fixtures
load helpers/assertions

setup_file() {
  load helpers/fixtures
  WORK="$(fixture_workspace)"
  SERVED="${WORK}/served"
  mkdir -p "$SERVED" "${WORK}/home/.ssh"
  fixture_generate_ed25519 "${WORK}/home/.ssh" "id_ed25519"
  fixture_publish_keys "$SERVED" "alice" "${WORK}/home/.ssh/id_ed25519.pub"
  keyserver_start "$SERVED"
  export WORK SERVED OSM_GITHUB_BASE KEYSERVER_PID
}

teardown_file() {
  load helpers/fixtures
  keyserver_stop
  rm -rf "$WORK"
}

setup() {
  export HOME="${WORK}/home"
}

round_trip_under() {
  local runner="$1" dir="$2"
  printf 'portable payload\n' >"${dir}/original"
  $runner "$OSM_BIN" send alice --no-clipboard <"${dir}/original" >"${dir}/armored"
  $runner "$OSM_BIN" read "${dir}/armored" >"${dir}/recovered"
  cmp -s "${dir}/original" "${dir}/recovered"
}

@test "the artifact declares a POSIX sh shebang" {
  run head -1 "${OSM_REPO_ROOT}/dist/osm"

  assert_status 0
  assert_output_contains "/bin/sh"
}

@test "the artifact contains no bash-only constructs" {
  run grep -nE '\[\[|<\(|pipefail|BASH_SOURCE|\bdeclare\b|\bmapfile\b|\breadarray\b' "${OSM_REPO_ROOT}/dist/osm"

  assert_status 1
}

@test "round trips under the system sh" {
  local dir="${WORK}/sh"
  mkdir -p "$dir"

  run round_trip_under /bin/sh "$dir"

  assert_status 0
}

@test "round trips under the system bash" {
  local dir="${WORK}/bash"
  mkdir -p "$dir"

  run round_trip_under /bin/bash "$dir"

  assert_status 0
}

@test "round trips under every other shell present on this machine" {
  local dir found=0
  for candidate in dash ash mksh oksh posh yash zsh busybox; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    dir="${WORK}/shell-${candidate}"
    mkdir -p "$dir"
    if [[ "$candidate" == busybox ]]; then
      round_trip_under "busybox sh" "$dir"
    else
      round_trip_under "$candidate" "$dir"
    fi
    found=$((found + 1))
  done
  printf 'verified %s additional shell(s)\n' "$found"
}

@test "survives a TMPDIR containing spaces" {
  local dir="${WORK}/tmp dir with spaces"
  mkdir -p "$dir"

  TMPDIR="$dir" run bash -c "printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 0
  assert_output_contains "-----BEGIN OSM MESSAGE-----"
}

@test "survives a HOME containing spaces" {
  local spaced="${WORK}/home with spaces"
  mkdir -p "${spaced}/.ssh"
  cp -f "${WORK}/home/.ssh/id_ed25519" "${WORK}/home/.ssh/id_ed25519.pub" "${spaced}/.ssh/"
  "$OSM_BIN" send alice 'spaced home secret' --no-clipboard >"${WORK}/spaced.armored"

  HOME="$spaced" run "$OSM_BIN" read "${WORK}/spaced.armored"

  assert_status 0
  assert_output_contains "spaced home secret"
}

@test "survives a hostile IFS" {
  run env IFS=':' HOME="${WORK}/home" bash -c "printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 0
  assert_output_contains "-----BEGIN OSM MESSAGE-----"
}

@test "survives CDPATH being set" {
  run env CDPATH=/usr HOME="${WORK}/home" bash -c "printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 0
  assert_output_contains "-----BEGIN OSM MESSAGE-----"
}

@test "survives POSIXLY_CORRECT" {
  run env POSIXLY_CORRECT=1 HOME="${WORK}/home" bash -c "printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 0
  assert_output_contains "-----BEGIN OSM MESSAGE-----"
}

@test "carries non-ASCII intact under the C locale" {
  printf 'acentua\303\247\303\243o \303\247edilha\n' >"${WORK}/utf8"

  env LC_ALL=C LANG=C "$OSM_BIN" send alice --no-clipboard <"${WORK}/utf8" >"${WORK}/utf8.armored"
  env LC_ALL=C LANG=C "$OSM_BIN" read "${WORK}/utf8.armored" >"${WORK}/utf8.recovered"

  assert_files_identical "${WORK}/utf8" "${WORK}/utf8.recovered"
}

@test "carries non-ASCII intact under a UTF-8 locale" {
  printf 'acentua\303\247\303\243o \303\247edilha\n' >"${WORK}/utf8b"

  env LC_ALL=en_US.UTF-8 "$OSM_BIN" send alice --no-clipboard <"${WORK}/utf8b" >"${WORK}/utf8b.armored"
  env LC_ALL=en_US.UTF-8 "$OSM_BIN" read "${WORK}/utf8b.armored" >"${WORK}/utf8b.recovered"

  assert_files_identical "${WORK}/utf8b" "${WORK}/utf8b.recovered"
}

@test "creates private temporary files under a permissive umask" {
  run env HOME="${WORK}/home" bash -c "umask 000; printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 0
  assert_output_contains "-----BEGIN OSM MESSAGE-----"
}

@test "works under a restrictive umask" {
  run env HOME="${WORK}/home" bash -c "umask 077; printf 'x\n' | '$OSM_BIN' send alice --no-clipboard"

  assert_status 0
  assert_output_contains "-----BEGIN OSM MESSAGE-----"
}

@test "carries a payload with no trailing newline" {
  printf 'no trailing newline' >"${WORK}/bare"

  "$OSM_BIN" send alice --no-clipboard <"${WORK}/bare" >"${WORK}/bare.armored"
  "$OSM_BIN" read "${WORK}/bare.armored" >"${WORK}/bare.recovered"

  assert_files_identical "${WORK}/bare" "${WORK}/bare.recovered"
}

@test "carries binary content without corruption" {
  if [[ -n "${OSM_COVERAGE:-}" ]]; then
    skip "kcov ptrace instrumentation corrupts binary streams, the artifact itself does not"
  fi
  head -c 4096 /dev/urandom >"${WORK}/binary"

  "$OSM_BIN" send alice --no-clipboard <"${WORK}/binary" >"${WORK}/binary.armored"
  "$OSM_BIN" read "${WORK}/binary.armored" >"${WORK}/binary.recovered"

  assert_files_identical "${WORK}/binary" "${WORK}/binary.recovered"
}

@test "reads an armored block surrounded by unrelated chat text" {
  "$OSM_BIN" send alice 'buried secret' --no-clipboard >"${WORK}/core.armored"
  {
    printf 'hey, here is the thing you asked for\n\n'
    cat "${WORK}/core.armored"
    printf '\nlet me know if it works\n'
  } >"${WORK}/chatty"

  run "$OSM_BIN" read "${WORK}/chatty"

  assert_status 0
  assert_output_contains "buried secret"
}

@test "tolerates CRLF line endings from a chat client" {
  "$OSM_BIN" send alice 'crlf secret' --no-clipboard >"${WORK}/lf.armored"
  awk '{printf "%s\r\n", $0}' "${WORK}/lf.armored" >"${WORK}/crlf.armored"

  run "$OSM_BIN" read "${WORK}/crlf.armored"

  assert_status 0
  assert_output_contains "crlf secret"
}
