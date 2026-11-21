#!/usr/bin/env bash
# Run on the INTERNET machine, from the repository root, using the same OS release
# (and ideally the same kernel) as the client servers.
# Output: bundle/offline-rpm-repo  (RPM files plus repository metadata)
set -euo pipefail

OUT=${1:-bundle/offline-rpm-repo}
PKGS_FILE=${2:-scripts/rpm-package-list.txt}
MISSING="$OUT/MISSING.txt"

mkdir -p "$OUT"
rm -f "$MISSING"
sudo dnf install -y dnf-plugins-core createrepo_c

PKGS=$(grep -Ev '^(#|$)' "$PKGS_FILE")

# Kernel modules must match the kernel running on the servers.
# Override with KERNEL=<version> if the servers run a different kernel than this machine.
KERNEL=${KERNEL:-$(uname -r)}
PKGS="$PKGS kernel-modules-extra-$KERNEL"

# Try everything at once. If one name is wrong, find out which one.
if ! sudo dnf download --resolve --alldeps --destdir "$OUT" $PKGS; then
  echo "A package failed. Checking one by one..."
  for p in $PKGS; do
    sudo dnf download --resolve --alldeps --destdir "$OUT" "$p" || echo "$p" >> "$MISSING"
  done
fi

sudo chown -R "$USER": "$OUT"
createrepo_c "$OUT"

echo "RPM files: $(ls "$OUT"/*.rpm | wc -l)"
if [ -f "$MISSING" ]; then
  echo "NOT FOUND (fix the name or enable the repository that has it):"
  cat "$MISSING"
fi
