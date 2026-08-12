#!/bin/sh
set -eu

root=${1:-}
if [ -n "$root" ] && [ -d "$root" ]; then
  cd "$root"
fi

if [ ! -f build.sh ]; then
  printf 'build.sh is not in %s, the workspace was not synced as expected\n' "$(pwd)" >&2
  exit 1
fi

sh build.sh
sh dist/osm version

work=$(mktemp -d /tmp/osm-bsd-XXXXXX)
mkdir -p "${work}/home/.ssh" "${work}/served"
ssh-keygen -q -t ed25519 -N '' -f "${work}/home/.ssh/id_ed25519" </dev/null
awk '{print $1" "$2}' "${work}/home/.ssh/id_ed25519.pub" >"${work}/served/alice.keys"

python3 test/helpers/keyserver.py "${work}/served" >"${work}/port" 2>/dev/null &
attempts=0
while [ ! -s "${work}/port" ] && [ "$attempts" -lt 80 ]; do
  sleep 0.2
  attempts=$((attempts + 1))
done
if [ ! -s "${work}/port" ]; then
  printf 'the fixture key server never came up\n' >&2
  exit 1
fi

printf 'bsd round trip with acentuacao\n' >"${work}/original"
OSM_GITHUB_BASE="http://127.0.0.1:$(cat "${work}/port")" HOME="${work}/home" \
  sh dist/osm send alice --no-clipboard <"${work}/original" >"${work}/armored"
HOME="${work}/home" sh dist/osm read "${work}/armored" >"${work}/recovered"
cmp "${work}/original" "${work}/recovered"

printf 'round trip is byte identical on %s\n' "$(uname -s)"
