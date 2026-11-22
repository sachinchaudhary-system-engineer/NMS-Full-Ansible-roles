#!/usr/bin/env bash
# Adds Docker and the Harbor offline installer to the bundle.
# Run on a machine WITH internet, after scripts 02 and 04 (bundle/ must exist).
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/pinned-versions.env
BUNDLE=${BUNDLE:-$PWD/bundle}
REPO="$BUNDLE/offline-rpm-repo"
BIN="$BUNDLE/third-party-binaries"
LIST=scripts/docker-package-list.txt

[ -d "$REPO/repodata" ] || { echo "ERROR: $REPO has no repodata. Run script 02 first."; exit 1; }
command -v createrepo_c >/dev/null || { echo "ERROR: createrepo_c is missing. Run: sudo dnf install -y createrepo_c"; exit 1; }
[ -n "${HARBOR_VERSION:-}" ] || { echo "ERROR: HARBOR_VERSION is not set in scripts/pinned-versions.env"; exit 1; }

echo "== 1/4 Add Docker's repository (this build machine only)"
sudo curl -fsSL https://download.docker.com/linux/rhel/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo

echo "== 2/4 Download the Docker packages with ALL their dependencies"
PKGS=$(grep -vE '^\s*#|^\s*$' "$LIST" | tr '\n' ' ')
sudo dnf download -y --resolve --alldeps --destdir "$REPO" $PKGS
sudo chown -R "$(id -un):" "$REPO"

echo "== 3/4 Download the Harbor offline installer ($HARBOR_VERSION)"
mkdir -p "$BIN"
F="harbor-offline-installer-${HARBOR_VERSION}.tgz"
URL="https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/${F}"
curl -fL --retry 3 -o "$BIN/$F" "$URL"
curl -fL --retry 3 -o "$BIN/$F.asc" "$URL.asc" || { rm -f "$BIN/$F.asc"; echo "note: no .asc signature file for this release"; }
gzip -t "$BIN/$F" && echo "Harbor installer archive is intact"

echo "== 4/4 Rebuild the repository index"
createrepo_c --update "$REPO"

echo "Done. Now commit and pack the bundle."
