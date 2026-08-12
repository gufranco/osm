OSM_TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OSM_REPO_ROOT="$(cd "${OSM_TEST_ROOT}/.." && pwd)"
OSM_BIN="${OSM_BIN:-${OSM_REPO_ROOT}/dist/osm}"

fixture_workspace() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/osm-test-XXXXXX")"
  mkdir -p "${dir}/config"
  printf '%s\n' "$dir"
}

fixture_generate_ed25519() {
  local dir=$1 name=$2
  ssh-keygen -q -t ed25519 -N '' -C "$name" -f "${dir}/${name}" </dev/null
}

fixture_generate_rsa() {
  local dir=$1 name=$2 bits=${3:-4096}
  ssh-keygen -q -t rsa -b "$bits" -N '' -C "$name" -f "${dir}/${name}" </dev/null
}

fixture_generate_rsa_pem() {
  local dir=$1 name=$2 bits=${3:-2048}
  ssh-keygen -q -t rsa -b "$bits" -m PEM -N '' -C "$name" -f "${dir}/${name}" </dev/null
}

fixture_generate_ecdsa() {
  local dir=$1 name=$2
  ssh-keygen -q -t ecdsa -b 256 -N '' -C "$name" -f "${dir}/${name}" </dev/null
}

fixture_fingerprint() {
  ssh-keygen -lf "$1" | awk '{print $2}'
}

fixture_publish_keys() {
  local served=$1 user=$2
  shift 2
  : >"${served}/${user}.keys"
  local pub
  for pub in "$@"; do
    awk '{print $1" "$2}' "$pub" >>"${served}/${user}.keys"
  done
}

fixture_publish_empty_account() {
  local served=$1 user=$2
  : >"${served}/${user}.keys"
}

keyserver_start() {
  local served=$1
  python3 "${OSM_TEST_ROOT}/helpers/keyserver.py" "$served" >"${served}/.port" 2>"${served}/.port.err" &
  KEYSERVER_PID=$!
  local waited=0
  while [[ ! -s "${served}/.port" ]]; do
    sleep 0.05
    waited=$((waited + 1))
    if [[ "$waited" -gt 100 ]]; then
      printf 'keyserver failed to start: %s\n' "$(cat "${served}/.port.err")" >&2
      return 1
    fi
  done
  KEYSERVER_PORT="$(cat "${served}/.port")"
  OSM_GITHUB_BASE="http://127.0.0.1:${KEYSERVER_PORT}"
  export OSM_GITHUB_BASE
}

keyserver_stop() {
  if [[ -n "${KEYSERVER_PID:-}" ]]; then
    kill "$KEYSERVER_PID" 2>/dev/null || true
    wait "$KEYSERVER_PID" 2>/dev/null || true
    KEYSERVER_PID=""
  fi
}

osm() {
  "$OSM_BIN" "$@"
}

sandbox_path_excluding() {
  local dir=$1 excluded=$2
  local tool resolved
  mkdir -p "$dir"
  for tool in bash env curl ssh-keygen openssl awk sed grep wc tr sort cat mktemp \
    chmod rm head fold cut dirname basename uname cmp mkdir touch age python3 kcov; do
    if [[ "$tool" == "$excluded" ]]; then
      continue
    fi
    resolved=$(command -v "$tool" 2>/dev/null) || continue
    ln -sf "$resolved" "${dir}/${tool}"
  done
  printf '%s\n' "$dir"
}

fixture_expected_version() {
  sed -n 's/^OSM_VERSION="\(.*\)"$/\1/p' "${OSM_REPO_ROOT}/lib/core.sh"
}
