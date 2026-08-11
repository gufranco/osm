#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
minimum=${1:-95}
coverage_dir="${root}/coverage"
runs_dir="${coverage_dir}/runs"
merged_dir="${coverage_dir}/merged"
artifact="${root}/dist/osm"

kcov_bin=$(command -v kcov)
bash_bin=$(command -v bash)
hashbang=$(printf '\043\041')

rm -rf "$coverage_dir"
mkdir -p "$runs_dir"

wrapper="${coverage_dir}/osm-instrumented"
{
  printf '%s%s\n' "$hashbang" "$bash_bin"
  # shellcheck disable=SC2016
  printf 'exec %q --include-path=%q "%s/run-$$-${RANDOM}" %q "$@"\n' \
    "$kcov_bin" "$artifact" "$runs_dir" "$artifact"
} >"$wrapper"
chmod 0755 "$wrapper"

OSM_BIN="$wrapper" bats "${root}/test"

"$kcov_bin" --merge "$merged_dir" "${runs_dir}"/run-* >/dev/null 2>&1

summary=$(find "$merged_dir" -name 'coverage.json' -print -quit)
if [[ -z "$summary" ]]; then
  printf 'no coverage.json produced under %s\n' "$merged_dir" >&2
  exit 1
fi

python3 - "$summary" "$minimum" <<'PY'
import json
import sys

report = json.load(open(sys.argv[1]))
actual = float(report["percent_covered"])
minimum = float(sys.argv[2])
print("covered %s of %s lines (%.2f%%), gate %.2f%%" % (
    report["covered_lines"], report["total_lines"], actual, minimum))
if actual + 1e-9 < minimum:
    sys.stderr.write("coverage %.2f%% is below the %.2f%% gate\n" % (actual, minimum))
    sys.exit(1)
PY
