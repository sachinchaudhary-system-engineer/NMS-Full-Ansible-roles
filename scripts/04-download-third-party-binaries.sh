#!/usr/bin/env bash
# Run on the INTERNET machine. Downloads pinned binaries into bundle/third-party-binaries.
set -euo pipefail

source "$(dirname "$0")/pinned-versions.env"
: "${RKE2_VERSION:?Set RKE2_VERSION in scripts/pinned-versions.env}"
: "${ETCD_VERSION:?Set ETCD_VERSION in scripts/pinned-versions.env}"
: "${NODE_EXPORTER_VERSION:?Set NODE_EXPORTER_VERSION in scripts/pinned-versions.env}"
: "${POSTGRES_EXPORTER_VERSION:?Set POSTGRES_EXPORTER_VERSION in scripts/pinned-versions.env}"

mkdir -p bundle/third-party-binaries
cd bundle/third-party-binaries

# RKE2 files (staged on the nodes now, installed in the Kubernetes step)
BASE=https://github.com/rancher/rke2/releases/download/$RKE2_VERSION
curl -fLO "$BASE/rke2.linux-amd64.tar.gz"
curl -fLO "$BASE/rke2-images.linux-amd64.tar.zst"
curl -fLO "$BASE/sha256sum-amd64.txt"
curl -fL https://get.rke2.io -o rke2-install.sh

# Database servers
curl -fLO "https://github.com/etcd-io/etcd/releases/download/$ETCD_VERSION/etcd-$ETCD_VERSION-linux-amd64.tar.gz"
curl -fLO "https://github.com/prometheus-community/postgres_exporter/releases/download/v$POSTGRES_EXPORTER_VERSION/postgres_exporter-$POSTGRES_EXPORTER_VERSION.linux-amd64.tar.gz"

# Every server
curl -fLO "https://github.com/prometheus/node_exporter/releases/download/v$NODE_EXPORTER_VERSION/node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz"

# MinIO server and client. Confirm these are still available and check the licence.
# curl -fLO https://dl.min.io/server/minio/release/linux-amd64/minio
# curl -fLO https://dl.min.io/client/mc/release/linux-amd64/mc

echo "Binaries downloaded: $(ls | wc -l)"
