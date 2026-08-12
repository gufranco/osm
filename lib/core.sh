OSM_VERSION="1.1.0"
OSM_FORMAT_VERSION="1"
OSM_GITHUB_BASE="${OSM_GITHUB_BASE:-https://github.com}"
OSM_HTTP_TIMEOUT="${OSM_HTTP_TIMEOUT:-10}"
OSM_ARMOR_BEGIN="-----BEGIN OSM MESSAGE-----"
OSM_ARMOR_END="-----END OSM MESSAGE-----"
OSM_OAEP_OVERHEAD=42
OSM_WORKSPACE=""

osm_die() {
  printf 'osm: %s\n' "$1" >&2
  exit "${2:-1}"
}

osm_warn() {
  printf 'osm: %s\n' "$1" >&2
}

osm_cleanup() {
  if [ -n "$OSM_WORKSPACE" ]; then
    rm -rf "$OSM_WORKSPACE"
    OSM_WORKSPACE=""
  fi
}

osm_init_workspace() {
  if [ -z "$OSM_WORKSPACE" ]; then
    OSM_WORKSPACE=$(mktemp -d "${TMPDIR:-/tmp}/osm-XXXXXX")
    chmod 700 "$OSM_WORKSPACE"
  fi
}

osm_have() {
  command -v "$1" >/dev/null 2>&1
}

osm_openssl_flavor() {
  local version
  if ! osm_have openssl; then
    printf 'absent\n'
    return 0
  fi
  version=$(openssl version 2>/dev/null || printf 'unknown')
  case "$version" in
  LibreSSL*) printf 'libressl\n' ;;
  OpenSSL*) printf 'openssl\n' ;;
  *) printf 'unknown\n' ;;
  esac
}
