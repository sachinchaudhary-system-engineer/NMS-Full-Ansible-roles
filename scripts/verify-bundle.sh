#!/usr/bin/env bash
# Run at the CLIENT site after copying the bundle. Prints nothing wrong if all files are intact.
set -euo pipefail

BUNDLE=${1:-/opt/bundle}
cd "$BUNDLE"
if sha256sum -c SHA256SUMS --quiet; then
  echo "OK: every file matches its checksum"
else
  echo "FAIL: copy the damaged files again from the second drive" >&2
  exit 1
fi
