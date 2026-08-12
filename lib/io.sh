osm_clipboard_copy() {
  local file="$1"
  if [ -n "$OSM_CLIPBOARD_COPY" ]; then
    $OSM_CLIPBOARD_COPY <"$file" >/dev/null 2>&1 && printf '%s\n' "$OSM_CLIPBOARD_COPY" && return 0
  fi
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
  if [ -n "$OSM_CLIPBOARD_PASTE" ]; then
    $OSM_CLIPBOARD_PASTE && return 0
    return 1
  fi
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

osm_clipboard_clear_later() {
  local copier="$1" armor="$2" seconds="$3"
  if [ "$seconds" -le 0 ]; then
    return 0
  fi
  (
    sleep "$seconds"
    if osm_clipboard_paste 2>/dev/null | cmp -s - "$armor"; then
      printf '' | "$copier" >/dev/null 2>&1 || true
    fi
  ) >/dev/null 2>&1 &
}

osm_compress() {
  local plain="$1" dest="$2"
  if ! osm_have gzip; then
    return 1
  fi
  if ! gzip -c "$plain" >"$dest" 2>/dev/null; then
    return 1
  fi
  if [ "$(wc -c <"$dest" | tr -d " ")" -ge "$(wc -c <"$plain" | tr -d " ")" ]; then
    return 1
  fi
  return 0
}

osm_decompress() {
  local src="$1"
  if ! osm_have gunzip; then
    osm_die "this message is compressed and gunzip is not installed."
  fi
  gunzip -c "$src"
}

osm_emit_qr() {
  local armor="$1"
  if ! osm_have qrencode; then
    osm_die "--qr needs qrencode. install it with: brew install qrencode, or apt install qrencode"
  fi
  if [ "$(wc -c <"$armor" | tr -d " ")" -gt 2900 ]; then
    osm_die "the message is too large for a QR code. send it as text instead."
  fi
  qrencode -t ANSIUTF8 <"$armor"
}
