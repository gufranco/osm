load helpers/fixtures
load helpers/assertions

setup_file() {
  load helpers/fixtures
  WORK="$(fixture_workspace)"
  SERVED="${WORK}/served"
  mkdir -p "$SERVED" "${WORK}/home/.ssh"
  fixture_generate_rsa_pem "${WORK}/home/.ssh" "id_rsa" 2048
  fixture_generate_rsa "${WORK}/home/.ssh" "id_rsa_openssh" 2048
  fixture_generate_ed25519 "${WORK}/home/.ssh" "id_ed25519"
  fixture_publish_keys "$SERVED" "rsauser" "${WORK}/home/.ssh/id_rsa.pub"
  fixture_publish_keys "$SERVED" "opensshuser" "${WORK}/home/.ssh/id_rsa_openssh.pub"
  fixture_publish_keys "$SERVED" "curveuser" "${WORK}/home/.ssh/id_ed25519.pub"
  keyserver_start "$SERVED"
  NOAGE="$(sandbox_path_excluding "${WORK}/bin-noage" age)"
  export WORK SERVED OSM_GITHUB_BASE KEYSERVER_PID NOAGE
}

teardown_file() {
  load helpers/fixtures
  keyserver_stop
  rm -rf "$WORK"
}

setup() {
  export HOME="${WORK}/home"
}

@test "the sandbox path really has no age on it" {
  run env PATH="$NOAGE" bash -c 'command -v age'

  assert_status 1
}

@test "falls back to RSA and says so when age is absent" {
  run env PATH="$NOAGE" HOME="${WORK}/home" bash -c \
    "printf 'small secret\n' | '$OSM_BIN' send rsauser --no-clipboard"

  assert_status 0
  assert_output_contains "alg: rsa-oaep-sha1"
  assert_output_contains "falling back to RSA"
}

@test "round trips through the RSA fallback on both sides" {
  printf 'fallback payload with acentuação\n' >"${WORK}/original"
  env PATH="$NOAGE" HOME="${WORK}/home" "$OSM_BIN" send rsauser --no-clipboard \
    <"${WORK}/original" >"${WORK}/armored" 2>/dev/null
  env PATH="$NOAGE" HOME="${WORK}/home" "$OSM_BIN" read "${WORK}/armored" >"${WORK}/recovered"

  assert_files_identical "${WORK}/original" "${WORK}/recovered"
}

@test "refuses an Ed25519 recipient when age is absent" {
  run env PATH="$NOAGE" HOME="${WORK}/home" bash -c \
    "printf 'x\n' | '$OSM_BIN' send curveuser --no-clipboard"

  assert_status 1
  assert_output_contains "recipient key is not RSA"
  assert_output_contains "install age"
}

@test "refuses a message larger than the RSA key can carry" {
  head -c 400 /dev/zero | tr '\0' 'a' >"${WORK}/toobig"

  run env PATH="$NOAGE" HOME="${WORK}/home" bash -c \
    "'$OSM_BIN' send rsauser --no-clipboard < '${WORK}/toobig'"

  assert_status 1
  assert_output_contains "can carry only"
  assert_output_contains "install age"
}

@test "accepts a message exactly at the RSA capacity" {
  head -c 214 /dev/zero | tr '\0' 'a' >"${WORK}/atlimit"

  run env PATH="$NOAGE" HOME="${WORK}/home" bash -c \
    "'$OSM_BIN' send rsauser --no-clipboard < '${WORK}/atlimit'"

  assert_status 0
  assert_output_contains "alg: rsa-oaep-sha1"
}

@test "guides the user when the private key is in OpenSSH format" {
  env PATH="$NOAGE" HOME="${WORK}/home" "$OSM_BIN" send opensshuser --no-clipboard \
    <<<"secret" >"${WORK}/openssh.armored" 2>/dev/null

  run env PATH="$NOAGE" HOME="${WORK}/home" "$OSM_BIN" read "${WORK}/openssh.armored"

  assert_status 1
  assert_output_contains "ssh-keygen -p -m PEM"
}

@test "tells the recipient to install age when the message needs it" {
  "$OSM_BIN" send curveuser 'age only secret' --no-clipboard >"${WORK}/age.armored"

  run env PATH="$NOAGE" HOME="${WORK}/home" "$OSM_BIN" read "${WORK}/age.armored"

  assert_status 1
  assert_output_contains "needs age to open"
}
