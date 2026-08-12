osm_main() {
  local command=${1:-}
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$command" in
  send) osm_cmd_send "$@" ;;
  read) osm_cmd_read "$@" ;;
  keys) osm_cmd_keys "$@" ;;
  doctor) osm_cmd_doctor ;;
  version | --version | -v) osm_cmd_version ;;
  help | --help | -h) osm_usage ;;
  "") osm_usage && exit 1 ;;
  *) osm_die "unknown command '${command}'. run 'osm help' for usage." ;;
  esac
}

osm_main "$@"
