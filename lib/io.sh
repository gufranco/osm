osm_clipboard_copy() {
  local file="$1"
  if osm_have pbcopy; then
    pbcopy <"$file" && printf 'pbcopy\n' && return 0
  fi
  if osm_have wl-copy; then
    wl-copy <"$file" && printf 'wl-copy\n' && return 0
  fi
  if osm_have xclip; then
    xclip -selection clipboard <"$file" && printf 'xclip\n' && return 0
  fi
  if osm_have xsel; then
    xsel --clipboard --input <"$file" && printf 'xsel\n' && return 0
  fi
  return 1
}

osm_read_plaintext() {
  local dest="$1" message="$2"
  if [ -n "$message" ]; then
    printf '%s\n' "$message" >"$dest"
  else
    cat >"$dest"
  fi
  if [ ! -s "$dest" ]; then
    osm_die "refusing to send an empty message."
  fi
}

osm_clipboard_paste() {
  if osm_have pbpaste; then
    pbpaste && return 0
  fi
  if osm_have wl-paste; then
    wl-paste && return 0
  fi
  if osm_have xclip; then
    xclip -selection clipboard -o && return 0
  fi
  if osm_have xsel; then
    xsel --clipboard --output && return 0
  fi
  return 1
}
