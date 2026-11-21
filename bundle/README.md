# bundle/

This folder holds the offline files. Its contents are **not** committed to Git (see `.gitignore`).
Build it on the internet machine with the scripts in `scripts/`, then carry it on a drive.

```text
bundle/
├── os-repo/        RPM files and repodata (build-os-repo.sh)
├── wheels/         Python wheels for ansible-core (build-ansible-bundle.sh)
├── collections/    Ansible collections (build-ansible-bundle.sh)
├── binaries/       etcd, exporters, MinIO, RKE2 files (download-binaries.sh)
├── gitlab/         GitLab package and its dependencies
├── git/            Git bundle of this repository
└── SHA256SUMS      checksums of every file (make-bundle.sh)
```
