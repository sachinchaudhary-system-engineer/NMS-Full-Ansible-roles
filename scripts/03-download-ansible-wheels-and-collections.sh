#!/usr/bin/env bash
# Run on the INTERNET machine, using the same OS release (same Python) as the client servers.
# Output: bundle/ansible-python-wheels/ansible and bundle/ansible-collections
set -euo pipefail

source "$(dirname "$0")/pinned-versions.env"
: "${ANSIBLE_CORE_VERSION:?Set ANSIBLE_CORE_VERSION in scripts/pinned-versions.env}"

mkdir -p bundle/ansible-python-wheels/ansible bundle/ansible-collections

python3 -m pip download --only-binary=:all: "ansible-core==$ANSIBLE_CORE_VERSION" -d bundle/ansible-python-wheels/ansible

# A temporary Ansible, only to download the collections
python3 -m venv /tmp/ansible-build
/tmp/ansible-build/bin/pip install "ansible-core==$ANSIBLE_CORE_VERSION"
/tmp/ansible-build/bin/ansible-galaxy collection download ansible.posix community.general -p bundle/ansible-collections

echo "Wheels: $(ls bundle/ansible-python-wheels/ansible | wc -l)   Collections: $(ls bundle/ansible-collections/*.tar.gz | wc -l)"
