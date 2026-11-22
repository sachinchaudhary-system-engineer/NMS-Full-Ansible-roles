#!/usr/bin/env bash
# Run at the CLIENT site on the Ansible control machine (no internet).
# Creates the offline repository, installs ansible-core and the collections.
set -euo pipefail

BUNDLE=${BUNDLE:-/opt/bundle}
REPO_DIR=${REPO_DIR:-/opt/offline-repo}
VENV=${VENV:-/opt/ansible-venv}
COLLECTIONS=${COLLECTIONS:-/opt/ansible-collections}

# 1. Local package repository
sudo mkdir -p "$REPO_DIR"
sudo cp -r "$BUNDLE/offline-rpm-repo/." "$REPO_DIR/"
sudo tee /etc/yum.repos.d/offline.repo > /dev/null <<REPO
[offline]
name=offline
baseurl=file://$REPO_DIR
enabled=1
gpgcheck=0
REPO

sudo dnf --disablerepo='*' --enablerepo=offline install -y python3-pip python3-pip-wheel rsync

# 2. ansible-core from the wheels, with no internet
sudo mkdir -p "$VENV" "$COLLECTIONS"
sudo chown "$USER": "$VENV" "$COLLECTIONS"
python3 -m venv "$VENV"
"$VENV/bin/pip" install --no-index --find-links="$BUNDLE/ansible-python-wheels/ansible" ansible-core

# 3. Collections
"$VENV/bin/ansible-galaxy" collection install "$BUNDLE"/ansible-collections/*.tar.gz -p "$COLLECTIONS"

echo "export PATH=$VENV/bin:\$PATH" | sudo tee /etc/profile.d/ansible.sh > /dev/null
"$VENV/bin/ansible" --version
