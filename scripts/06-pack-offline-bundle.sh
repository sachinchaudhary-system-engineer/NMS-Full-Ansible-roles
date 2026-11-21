#!/usr/bin/env bash
# Run on the INTERNET machine after all the build scripts.
# Writes checksums, packs everything into one tar file and checksums that too.
set -euo pipefail

RELEASE=${1:?usage: scripts/06-pack-offline-bundle.sh RELEASE   (for example 2026.11.1)}

# Put this repository into the bundle as a Git bundle
mkdir -p bundle/ansible-repo-git-bundle
git bundle create "bundle/ansible-repo-git-bundle/infra-ansible-$RELEASE.bundle" --all

( cd bundle && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS )

tar -cf "nms-offline-bundle-$RELEASE.tar" bundle
echo "tar exit code: $?"
sha256sum "nms-offline-bundle-$RELEASE.tar" > "nms-offline-bundle-$RELEASE.tar.sha256"
ls -lh "nms-offline-bundle-$RELEASE.tar"
