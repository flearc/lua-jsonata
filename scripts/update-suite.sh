#!/usr/bin/env bash
# Refetch the jsonata-js test-suite (groups + datasets) at a pinned tag.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${1:-v2.2.1}"
VER="${TAG#v}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Fetching jsonata-js ${TAG} ..."
curl -sL "https://codeload.github.com/jsonata-js/jsonata/tar.gz/refs/tags/${TAG}" | tar xz -C "$TMP"
SRC="$TMP/jsonata-${VER}/test/test-suite"
test -d "$SRC/groups" || { echo "groups not found in tarball" >&2; exit 1; }

rm -rf spec/jsonata-suite/groups spec/jsonata-suite/datasets
mkdir -p spec/jsonata-suite
cp -R "$SRC/groups" spec/jsonata-suite/groups
cp -R "$SRC/datasets" spec/jsonata-suite/datasets

SHA="$(curl -s "https://api.github.com/repos/jsonata-js/jsonata/git/ref/tags/${TAG}" \
  | grep '"sha"' | head -1 | sed 's/.*"sha": "//;s/".*//')"

cat > spec/jsonata-suite/UPSTREAM.md <<EOF
# Vendored jsonata-js test-suite

- Upstream: https://github.com/jsonata-js/jsonata
- Version: ${TAG}
- Tag ref SHA: ${SHA}
- Vendored paths: test/test-suite/groups, test/test-suite/datasets
- License: MIT (© the JSONata authors). The MIT license/notice is preserved here by reference.

This directory is a frozen snapshot used as a conformance compass. Refresh deliberately with:

    scripts/update-suite.sh ${TAG}
EOF

GROUPS="$(find spec/jsonata-suite/groups -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
CASES="$(find spec/jsonata-suite/groups -name '*.json' -type f | wc -l | tr -d ' ')"
echo "Vendored ${GROUPS} groups, ${CASES} case files to spec/jsonata-suite/."
