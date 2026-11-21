#!/usr/bin/env bash
# Run on the INTERNET machine, from the infra-ansible folder.
# Downloads Patroni (with etcd3 support) and its dependencies as wheel files.
# Source packages (.tar.gz) are converted to wheels, so the offline install needs no build tools.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=bundle/patroni-python-wheels
rm -rf "$OUT"; mkdir -p "$OUT"
python3 -m pip download --dest "$OUT" "patroni[etcd3]" psycopg2-binary
for src in "$OUT"/*.tar.gz; do
  [ -e "$src" ] || continue
  python3 -m pip wheel --no-deps --wheel-dir "$OUT" "$src"
  rm "$src"
done
echo "Patroni wheels: $(ls "$OUT" | wc -l)"
ls "$OUT"
