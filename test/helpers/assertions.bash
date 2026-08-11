assert_status() {
  local expected=$1
  if [[ "$status" -ne "$expected" ]]; then
    printf 'expected exit status %s, got %s\noutput:\n%s\n' "$expected" "$status" "$output" >&2
    return 1
  fi
}

assert_output_contains() {
  local needle=$1
  case "$output" in
  *"$needle"*) ;;
  *)
    printf 'expected output to contain: %s\nactual output:\n%s\n' "$needle" "$output" >&2
    return 1
    ;;
  esac
}

assert_output_lacks() {
  local needle=$1
  case "$output" in
  *"$needle"*)
    printf 'expected output NOT to contain: %s\nactual output:\n%s\n' "$needle" "$output" >&2
    return 1
    ;;
  *) ;;
  esac
}

assert_equal() {
  local actual=$1 expected=$2
  if [[ "$actual" != "$expected" ]]; then
    printf 'expected: %s\nactual:   %s\n' "$expected" "$actual" >&2
    return 1
  fi
}

assert_files_identical() {
  local left=$1 right=$2
  if ! cmp -s "$left" "$right"; then
    printf 'files differ: %s vs %s\n' "$left" "$right" >&2
    printf 'left  sha: %s\n' "$(shasum -a 256 <"$left" | awk '{print $1}')" >&2
    printf 'right sha: %s\n' "$(shasum -a 256 <"$right" | awk '{print $1}')" >&2
    return 1
  fi
}
