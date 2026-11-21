#!/usr/bin/env bash
# Run on the INTERNET machine. Prints the latest versions in the format of pinned-versions.env.
#   bash scripts/01-find-latest-versions.sh            just print
#   bash scripts/01-find-latest-versions.sh --write    also overwrite scripts/pinned-versions.env
set -uo pipefail

fail() { echo "ERROR: $1" >&2; exit 1; }

# Latest release tag of a GitHub repository, read from the redirect of /releases/latest.
latest() {
  local url
  url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest") \
    || fail "cannot reach github.com for $1"
  echo "${url##*/tag/}"
}

ANSIBLE=2.21.6   # newest ansible-core that supports Python 3.12 (RHEL 10 default)

RKE2=$(latest rancher/rke2) || exit 1
RKE2=${RKE2//+/%2B}
ETCD=$(latest etcd-io/etcd) || exit 1
NODE=$(latest prometheus/node_exporter) || exit 1
PGEXP=$(latest prometheus-community/postgres_exporter) || exit 1
NODE=${NODE#v}
PGEXP=${PGEXP#v}

for v in "$ANSIBLE" "$RKE2" "$ETCD" "$NODE" "$PGEXP"; do
  [ -n "$v" ] && [ "$v" != "null" ] || fail "one version came back empty"
done

OUTPUT="ANSIBLE_CORE_VERSION=$ANSIBLE
RKE2_VERSION=$RKE2
ETCD_VERSION=$ETCD
NODE_EXPORTER_VERSION=$NODE
POSTGRES_EXPORTER_VERSION=$PGEXP"

echo "$OUTPUT"
if [ "${1:-}" = "--write" ]; then
  echo "$OUTPUT" > "$(dirname "$0")/pinned-versions.env"
  echo "Written to scripts/pinned-versions.env"
fi
