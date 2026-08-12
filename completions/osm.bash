_osm() {
  local cur prev commands send_opts read_opts
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  commands="send read keys doctor version help"
  send_opts="--to --keys-file --key --json --qr --sign --accept-new-key --no-clipboard"
  read_opts="--identity --clipboard --require-signature"

  case "$prev" in
    --keys-file | --identity)
      mapfile -t COMPREPLY < <(compgen -f -- "$cur")
      return
      ;;
    *) ;;
  esac

  if [[ "$COMP_CWORD" -eq 1 ]]; then
    mapfile -t COMPREPLY < <(compgen -W "$commands" -- "$cur")
    return
  fi

  case "${COMP_WORDS[1]}" in
    send) mapfile -t COMPREPLY < <(compgen -W "$send_opts" -- "$cur") ;;
    read) mapfile -t COMPREPLY < <(compgen -W "$read_opts" -- "$cur") ;;
    *) COMPREPLY=() ;;
  esac
}
complete -F _osm osm
