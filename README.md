# infra-ansible

Server preparation for the NMS platform, done with Ansible, on a private network with **no internet**.

One control machine configures every server. Everything the servers need (packages, Python wheels, binaries, Docker and Harbor files) is built on an internet machine, carried on a drive, and installed from local files.

> **The offline repo must be built for the exact RHEL minor release and kernel the client servers run** (for example 10.2 or 10.3). A repo built from newer packages than the servers have will not install. See [Release matching](#4-release-matching).

---

## 1. Scope

This repo does:

- Prepare every server: offline package repository, hostnames, time sync, base packages, kernel settings.
- Install and configure server software: HAProxy and Keepalived, PostgreSQL with Patroni and etcd, MinIO, the Harbor registry.
- Prepare the Kubernetes nodes and install RKE2 from staged files.
- Check after every run that the servers are ready.

This repo does not (yet):

- Build images or run CI.
- Deploy the application. Argo CD does that later.
- Handle certificates, firewall rules or traffic rules beyond the optional TLS variables.

---

## 2. Architecture

### Two networks, one drive

```
INTERNET MACHINE                                   PRIVATE NETWORK
----------------                                   ---------------
scripts/01-find-latest-versions.sh
scripts/02-build-offline-rpm-repo.sh
scripts/03-download-ansible-wheels-and-collections.sh
scripts/04-download-third-party-binaries.sh      drive   scripts/verify-bundle.sh
scripts/05-download-patroni-wheels.sh   ==========>      scripts/07-install-ansible-on-controller.sh
scripts/08-download-harbor-and-docker.sh                 ansible-playbook playbooks/site.yml
scripts/06-pack-offline-bundle.sh
```

### Inside the private network

```
                      +-------------------------------+
                      |  CONTROL MACHINE (admin)      |
                      |  - Ansible (venv in /opt)     |
                      |  - offline RPM repo (HTTP)    |
                      |  - this repo + bundle/        |
                      +---------------+---------------+
                                      | SSH (Ansible)  +  HTTP :8080 (dnf)
        +------------+----------+-----+------+-------------+------------+
        |            |          |            |             |            |
  +-----+-----+ +----+-----+ +---+----+ +-----+-----+ +-----+----+ +-----+------+
  |loadbalancer| |   k8s    | |database| |  backup   | | harbor   | |  (later)   |
  |  2 servers | |3 servers | |3 servers| | 1 server  | | registry | | MongoDB,   |
  |HAProxy +   | |RKE2      | |Patroni +| | MinIO     | | Harbor   | | Neo4j,     |
  |Keepalived  | |          | |etcd +   | |           | |          | | RabbitMQ,  |
  |one VIP     | |          | |PostgreSQL| |          | |          | | Redis (TBD)|
  +-----+------+ +----+-----+ +---------+ +-----------+ +----------+ +------------+
        |             ^
        +-- traffic --+   HAProxy forwards client traffic to the k8s group
```

- The **control machine is also the repo server**: it serves the RPM repository over HTTP, and every other server installs from it.
- The control machine is the admin machine and is **not** in the inventory.
- Every server installs only from local files. No task downloads anything from the internet.

### The bundle

A tar file with a `.sha256` file next to it:

| Part | What it is | Used for |
|---|---|---|
| `offline-rpm-repo/` | RPM files with every dependency (including Docker), plus repository metadata | `dnf install` on every server |
| `ansible-python-wheels/` | Python packages for ansible-core | Installing Ansible on the control machine |
| `ansible-collections/` | Extra Ansible modules | Control machine |
| `patroni-python-wheels/` | Python packages for Patroni | Database servers |
| `third-party-binaries/` | etcd, exporters, RKE2 files, Harbor installer | Database, registry and Kubernetes servers |
| `ansible-repo-git-bundle/` | This repo as a Git bundle and as a project archive | Getting the playbooks onto the control machine |

`bundle/SHA256SUMS` lists the checksum of every file. `bundle/README.txt` and `bundle/BUILD-INFO.txt` describe the build. The bundle is **not** committed to GitHub: it is large and is rebuilt for each release.

### How Ansible is layered

- **inventory** says which servers exist and what settings they have.
- **roles** say how to configure one thing. Each role has one job.
- **playbooks** say which roles run on which group, in order.
- **scripts** build and check the offline bundle. They are not Ansible.

Site differences go in `inventory/` (`group_vars`, `host_vars`). Values in `inventory/group_vars/all.yml` override the role defaults, so the roles stay untouched.

---

## 3. What is in this repo

```
infra-ansible/
├── README.md
├── ansible.cfg
├── .gitattributes              # keeps bundle/ out of the project archive
├── inventory/
│   ├── production.ini          # servers, grouped by role (placeholders until filled in)
│   ├── group_vars/             # all, loadbalancer, k8s, database, backup, harbor_registry
│   └── host_vars/              # settings for a single server
├── playbooks/
│   ├── site.yml                # runs everything in order
│   ├── 00-offline-repo.yml     # points every server at the offline repo
│   ├── 01-common.yml           # baseline, all servers (also runs offline_repo)
│   ├── 02-loadbalancer.yml
│   ├── 03-k8s-prereq.yml
│   ├── 04-backup.yml
│   ├── 05-database.yml
│   ├── 06-harbor-registry.yml
│   ├── 07-rke2.yml
│   └── 99-validate.yml
├── roles/                      # one role per job
│   └── offline_repo  common  loadbalancer  k8s_prereq  minio  database  harbor_registry  rke2  gitlab  validate
├── scripts/                    # run on the internet machine and the control machine
│   ├── pinned-versions.env
│   ├── rpm-package-list.txt
│   ├── docker-package-list.txt
│   ├── 01-find-latest-versions.sh
│   ├── 02-build-offline-rpm-repo.sh
│   ├── 03-download-ansible-wheels-and-collections.sh
│   ├── 04-download-third-party-binaries.sh
│   ├── 05-download-patroni-wheels.sh
│   ├── 06-pack-offline-bundle.sh
│   ├── 07-install-ansible-on-controller.sh
│   ├── 08-download-harbor-and-docker.sh
│   └── verify-bundle.sh
├── tests/
│   └── test-offline-repo.sh    # test script for the offline repo
├── bundle/                     # offline files (not committed)
└── vault/                      # encrypted secrets (only encrypted files are committed)
```

### Server groups

| Group | Servers | What Ansible sets up |
|---|---|---|
| `loadbalancer` | 2 | HAProxy and Keepalived, with one virtual IP |
| `k8s` | 3 | Kubernetes node prerequisites and RKE2 |
| `database` | 3 | PostgreSQL, etcd, Patroni |
| `backup` | 1 | The storage disk and MinIO |
| `harbor_registry` | 1 | The container image registry (Harbor) |

### Playbooks, roles and groups

| Playbook | Role | Runs on | What it does |
|---|---|---|---|
| `00-offline-repo.yml` | `offline_repo` | all servers | Disables other repo files, writes `offline.repo`, checks it is enabled |
| `01-common.yml` | `offline_repo`, `common` | all servers | Base packages, hostname, `/etc/hosts`, time zone, chrony |
| `02-loadbalancer.yml` | `loadbalancer` | `loadbalancer` | HAProxy and Keepalived with one virtual IP |
| `03-k8s-prereq.yml` | `k8s_prereq` | `k8s` | Kernel settings and node prerequisites, stages the RKE2 files |
| `04-backup.yml` | `minio` | `backup` | Storage disk, MinIO and its buckets |
| `05-database.yml` | `database` | `database` | PostgreSQL, etcd and Patroni cluster |
| `06-harbor-registry.yml` | `harbor_registry` | `harbor_registry` | Docker and the Harbor registry |
| `07-rke2.yml` | `rke2` | `k8s` | Installs RKE2 from the staged files |
| `99-validate.yml` | `validate` | all servers | Readiness checks |
| `site.yml` | all of the above | all groups | Runs everything in order |

The `gitlab` role exists, but no playbook uses it yet.

### Scripts

| Script | Where it runs | What it does |
|---|---|---|
| `pinned-versions.env` | internet machine | Every version used in the bundle (no `latest`) |
| `rpm-package-list.txt`, `docker-package-list.txt` | internet machine | Packages that go into the offline repo |
| `01-find-latest-versions.sh` | internet machine | Fills in `pinned-versions.env` |
| `02-build-offline-rpm-repo.sh` | internet machine | Builds the offline RPM repo with all dependencies |
| `03-download-ansible-wheels-and-collections.sh` | internet machine | Python wheels for Ansible and the Ansible collections |
| `04-download-third-party-binaries.sh` | internet machine | etcd, exporters, RKE2 files |
| `05-download-patroni-wheels.sh` | internet machine | Python wheels for Patroni |
| `08-download-harbor-and-docker.sh` | internet machine | Harbor installer and Docker files |
| `06-pack-offline-bundle.sh` | internet machine | Packs the bundle tar and its `.sha256`. Always last |
| `verify-bundle.sh` | private network | Checks the bundle files against `SHA256SUMS` |
| `07-install-ansible-on-controller.sh` | control machine | Installs Ansible from the bundle into `/opt/ansible-venv` |

---

## 4. Release matching

Packages in the offline repo must match the client servers. RHEL minor releases (for example 10.2 and 10.3) ship different package versions, and kernel packages such as `kernel-modules-extra` must match the **running kernel**.

If the repo is newer than the servers, dnf refuses installs where installed packages need the exact old versions.

- Ask the client for the exact release and kernel: `cat /etc/redhat-release` and `uname -r`.
- Build on a machine that runs the **same minor release**, and whose software source serves that release's packages. Some cloud images serve the newest 10.x content even on an older minor release.
- Check the finished repo before shipping:

```bash
ls bundle/offline-rpm-repo | grep '^redhat-release'   # must match the clients' release
ls bundle/offline-rpm-repo | grep '^kernel-core'      # must include the clients' running kernel
```

---

## 5. Rules we follow

- **Safe to run twice.** Every task can be repeated without breaking anything. The second run shows `changed=0`.
- **One role, one job.** A role never reaches into another role's work.
- **Pinned versions.** Every version is written in `scripts/pinned-versions.env`. No `latest`.
- **One release, one bundle.** The bundle is built for the clients' exact OS release and kernel.
- **Secrets in the vault.** Passwords and keys go only into `vault/` encrypted with `ansible-vault`.
- **No downloads on servers.** If a task needs a file from the internet, the file moves into the bundle instead.
- **Site differences live in `inventory/`.** Roles stay untouched.
- **Check before moving on.** Each step has a "done when" test.

---

## 6. Deployment plan

Do the steps in order. Finish and check each one before the next. Run commands from the repo root; add `-i inventory/production.ini` if `ansible.cfg` does not set the inventory. Paste each command as one line.

| Step | Where | What | Done when |
|---|---|---|---|
| 0. Decisions | team | Exact OS release and kernel, IP plan, hostnames, groups, admin user (`ansible_user`), NTP, DNS domain. Fill in `inventory/production.ini` and `inventory/group_vars/all.yml` | No placeholder (`192.0.2.x`) is left in the inventory |
| 1. Build the bundle | internet machine | Run scripts `01` to `05` and `08`, then `06-pack-offline-bundle.sh <release>` last, on a machine with the clients' OS release | `nms-offline-bundle-<release>.tar` and its `.sha256` exist, and the release check in section 4 passes |
| 2. Unpack | control machine | Verify the tar, extract it, extract the project archive, move `bundle/` into the project | `sha256sum -c SHA256SUMS` ends with exit 0 |
| 3. Install Ansible | control machine | `BUNDLE=$HOME/NMS-Full-Ansible-roles/bundle bash scripts/07-install-ansible-on-controller.sh`, without sudo | `ansible --version` works |
| 4. Serve the repo, connect | control machine | Serve `/opt/offline-repo` on HTTP port 8080, set up SSH keys to every server | `ansible all -m ping` answers `pong` everywhere |
| 5. Offline repo | all servers | `playbooks/00-offline-repo.yml` (set `offline_repo_url` in `all.yml`) | `dnf repolist` shows only `offline` |
| 6. Baseline | all servers | `playbooks/01-common.yml` | `chronyc tracking` shows a synced clock |
| 7. Load balancers | `loadbalancer` | Fill in `lb_vip`, `lb_interface`, `lb_auth_pass`, `lb_router_id`, `lb_vip_prefix`, `lb_services`, then `playbooks/02-loadbalancer.yml` | The virtual IP moves to lb2 when HAProxy stops on lb1 |
| 8. Kubernetes prerequisites | `k8s` | `playbooks/03-k8s-prereq.yml` | Nodes pass `validate`, RKE2 files are on each node |
| 9. Backup server | `backup` | `playbooks/04-backup.yml` | MinIO runs and its buckets exist |
| 10. Databases | `database` | `playbooks/05-database.yml` | `patronictl list` shows one Leader and two Replicas |
| 11. Registry | `harbor_registry` | `playbooks/06-harbor-registry.yml` | Harbor opens and a test image can be pushed |
| 12. RKE2 | `k8s` | `playbooks/07-rke2.yml` | RKE2 is running |
| 13. Rehearsal | all | `playbooks/site.yml`, then `99-validate.yml`, on clean servers with the network unplugged | Succeeds from empty servers, and a second run reports no changes |

Notes that apply across steps:

- Serving the repo: `sudo systemd-run --unit=offline-repo-http /usr/bin/python3 -m http.server 8080 --directory /opt/offline-repo` (one line). This does not survive a reboot; production needs a permanent systemd unit. Open TCP 8080 from the clients to the control machine.
- Booleans passed with `-e` must be JSON: `-e '{"common_set_hostname": false}'`. In YAML files, plain `false` works.
- Always run a practice pass first: `--check --diff`.
- `01-common.yml` sets each hostname to `<inventory name>.<dns_domain>` and writes every inventory server into `/etc/hosts`. Set `common_set_hostname: false` to keep existing names, and re-run it once the real IPs are in the inventory.
- When the team decides where MongoDB, Neo4j, RabbitMQ and Redis run, add one role and one playbook for each, following the same pattern.

---

## 7. Common commands

```bash
ansible all -m ping                                           # can we reach every server
ansible all --list-hosts                                      # which servers does Ansible see
ansible-playbook playbooks/site.yml                           # everything
ansible-playbook playbooks/03-k8s-prereq.yml --limit k8s1     # one server only
ansible-playbook playbooks/site.yml --check --diff            # show changes without making them
ansible-vault create vault/secrets.yml                        # create encrypted secrets
```

---

## 8. Open decisions

- Client server OS, exact minor release and kernel, and the admin user name (`ansible_user`).
- Whether `02-build-offline-rpm-repo.sh` can pin the release it downloads.
- Where MongoDB, Neo4j, RabbitMQ and Redis run.
- Whether the GPU server for the chatbot is part of the first release.
- Where the database schema comes from, since the application repositories contain no migration scripts.
- Internal time source, DNS and SMTP relay at the client site.
- A permanent systemd unit for serving the offline repo.
