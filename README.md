# infra-ansible

Server preparation for the NMS platform, done with Ansible, on a **private network with no internet**.

One control machine configures every server. Everything the servers need (packages, Python wheels, binaries, Docker and Harbor files) is built on an internet machine, carried on a drive, and installed from local files.

---

## 1. Scope

**This repo does:**

- Prepare every server: offline package repository, hostnames, time sync, base packages, kernel settings.
- Install and configure server software: HAProxy and Keepalived, PostgreSQL with Patroni and etcd, MinIO, the Harbor registry.
- Prepare the Kubernetes nodes and install RKE2 from staged files.
- Check after every run that the servers are ready.

**This repo does not (yet):**

- Build images or run CI.
- Deploy the application. Argo CD does that later.
- Handle certificates, firewall rules or traffic rules beyond the optional TLS variables.

Tested so far on RHEL 10.2, Python 3.12, x86_64: bundle checks, offline Ansible install, the offline repo served over HTTP, client installs from it, and the `offline_repo` role. The other roles are not yet tested.

---

## 2. How it works without internet

```text
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

The control machine is also the **repo server**: it serves the RPM repository over HTTP, and every other server installs from it.

The bundle (a tar file with a `.sha256` file next to it) holds:

| Part | What it is | Used for |
|---|---|---|
| `offline-rpm-repo/` | RPM files with every dependency (including Docker), plus repository metadata | `dnf install` on every server |
| `ansible-python-wheels/` | Python packages for ansible-core | Installing Ansible on the control machine |
| `ansible-collections/` | Extra Ansible modules | Control machine |
| `patroni-python-wheels/` | Python packages for Patroni | Database servers |
| `third-party-binaries/` | etcd, exporters, RKE2 files, Harbor installer | Database, registry and Kubernetes servers |
| `ansible-repo-git-bundle/` | This repo as a Git bundle and as a project archive | Getting the playbooks onto the control machine |

`bundle/SHA256SUMS` lists the checksum of every file. `bundle/README.txt` and `bundle/BUILD-INFO.txt` describe the build. The bundle is **not** committed to GitHub. It is large, and it is rebuilt for each release.

---

## 3. Server groups

| Group | Servers | What Ansible sets up |
|---|---|---|
| `loadbalancer` | 2 | HAProxy and Keepalived, with one virtual IP |
| `k8s` | 3 | Kubernetes node prerequisites and RKE2 |
| `database` | 3 | PostgreSQL, etcd, Patroni |
| `backup` | 1 | The storage disk and MinIO |
| `harbor_registry` | 1 | The container image registry (Harbor) |

The control machine is the admin machine and is not in the inventory. A `gitlab` role exists, but no playbook uses it.

Still to decide with the team: where MongoDB, Neo4j, RabbitMQ and Redis run.

---

## 4. Directory structure

```text
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
│   ├── 01-common.yml           # baseline, all servers
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

- **inventory** says *which* servers exist and *what settings* they have.
- **roles** say *how* to configure one thing. Each role has one job.
- **playbooks** say *which roles run on which group*, in order.
- **scripts** build and check the offline bundle. They are not Ansible.

---

## 5. Step-by-step plan

Do the steps in order. Finish and check each one before the next.

### Step 0: Decisions

- Client server OS and version. The scripts assume a RHEL-family system with `dnf`.
- IP plan, hostnames and which server goes in which group.
- The admin user that exists on every server. Set it as `ansible_user` in `inventory/group_vars/all.yml` (or per host in the inventory).

**Result:** `inventory/production.ini` and `inventory/group_vars/all.yml` filled in.

### Step 1: Build the offline bundle (internet machine)

Run on a machine with the **same OS release and kernel** as the client servers. Packages such as `kernel-modules-extra` must match the running kernel.

```bash
bash scripts/01-find-latest-versions.sh                  # fills in scripts/pinned-versions.env
# review scripts/rpm-package-list.txt and scripts/docker-package-list.txt
bash scripts/02-build-offline-rpm-repo.sh
bash scripts/03-download-ansible-wheels-and-collections.sh
bash scripts/04-download-third-party-binaries.sh
bash scripts/05-download-patroni-wheels.sh
bash scripts/08-download-harbor-and-docker.sh
bash scripts/06-pack-offline-bundle.sh <release>         # always last
```

**Done when:** `nms-offline-bundle-<release>.tar` and its `.sha256` file exist.

### Step 2: Copy and unpack at the client site (control machine)

```bash
sha256sum -c nms-offline-bundle-<release>.tar.sha256
tar -xf nms-offline-bundle-<release>.tar
tar -xzf bundle/ansible-repo-git-bundle/ansible-project-<release>.tar.gz
mv bundle NMS-Full-Ansible-roles/bundle
cd NMS-Full-Ansible-roles
(cd bundle && sha256sum -c SHA256SUMS --quiet; echo "check exit: $?")
```

**Done when:** the tar check says `OK` and the file check ends with `check exit: 0`.

### Step 3: Install Ansible on the control machine

```bash
BUNDLE=$HOME/NMS-Full-Ansible-roles/bundle bash scripts/07-install-ansible-on-controller.sh
source /etc/profile.d/ansible.sh
ansible --version
```

- Do **not** run it with `sudo`. The script uses sudo where it needs it, and running it as root makes the Ansible environment root-owned.
- `BUNDLE` is needed unless the bundle is at `/opt/bundle`.
- The script copies the RPM repo to `/opt/offline-repo`, installs Ansible from the wheels into `/opt/ansible-venv`, and the collections into `/opt/ansible-collections`.

**Done when:** `ansible --version` works.

### Step 4: Serve the repo and connect to the servers

Serve the repo over HTTP on port 8080 (open the port from the clients to this machine):

```bash
sudo systemd-run --unit=offline-repo-http /usr/bin/python3 -m http.server 8080 --directory /opt/offline-repo
curl -sI http://<REPO_IP>:8080/repodata/repomd.xml | head -1      # expect HTTP/1.0 200 OK
```

This does not survive a reboot. For production, use a proper systemd unit.

Set up SSH from the control machine to every server (add the public key from `~/.ssh/id_ed25519.pub` to the admin user's `authorized_keys` on each server), then:

```bash
ansible all -m ping
```

**Done when:** every server answers `pong`.

### Step 5: Point every server at the offline repo (`offline_repo` role)

The repo URL is not stored in the project. Pass it, or set `offline_repo_url` in `inventory/group_vars/all.yml`:

```bash
ansible-playbook playbooks/00-offline-repo.yml -e offline_repo_url=http://<REPO_IP>:8080 --check --diff
ansible-playbook playbooks/00-offline-repo.yml -e offline_repo_url=http://<REPO_IP>:8080
```

The role disables every other repo file, writes `offline.repo`, refreshes the metadata and checks that `offline` is enabled.

**Done when:** the run ends with `failed=0`, and `sudo dnf repolist` on a server shows only `offline`.

### Step 6: Baseline for every server (`common` role)

```bash
ansible-playbook playbooks/01-common.yml
```

**Done when:** `chronyc tracking` shows a synced clock on every server.

### Step 7: Load balancers (`loadbalancer` role)

Fill in `lb_vip`, `lb_interface`, `lb_auth_pass`, `lb_router_id`, `lb_vip_prefix` and `lb_services` in `inventory/group_vars/loadbalancer.yml`. The role stops while any of the first three is still `CHANGE_ME`, and every service needs a backend group that exists in the inventory.

```bash
ansible-playbook playbooks/02-loadbalancer.yml
```

**Done when:** the virtual IP is on lb1 and moves to lb2 when HAProxy stops on lb1.

### Step 8: Kubernetes node prerequisites (`k8s_prereq` role)

```bash
ansible-playbook playbooks/03-k8s-prereq.yml
```

**Done when:** all nodes pass the checks in `validate`, and the RKE2 files are on each node.

### Step 9: Backup server (`minio` role)

```bash
ansible-playbook playbooks/04-backup.yml
```

**Done when:** MinIO is running and its buckets exist.

### Step 10: Database servers (`database` role)

```bash
ansible-playbook playbooks/05-database.yml
```

**Done when:** `patronictl list` shows one Leader and two Replicas.

### Step 11: Registry server (`harbor_registry` role)

```bash
ansible-playbook playbooks/06-harbor-registry.yml
```

**Done when:** Harbor opens and you can push a test image.

### Step 12: RKE2 and other data stores

```bash
ansible-playbook playbooks/07-rke2.yml
```

When the team decides where MongoDB, Neo4j, RabbitMQ and Redis run, add one role and one playbook for each, following the same pattern.

### Step 13: Validation and a full rehearsal

```bash
ansible-playbook playbooks/site.yml
ansible-playbook playbooks/99-validate.yml
```

Run on clean test servers with the network unplugged.

**Done when:** the whole run succeeds from empty servers, and a second run reports **no changes**.

---

## 6. Rules we follow

- **Safe to run twice.** Every task can be repeated without breaking anything. The second run shows `changed=0`.
- **One role, one job.** A role never reaches into another role's work.
- **Pinned versions.** Every version is written in `scripts/pinned-versions.env`. No `latest`.
- **Secrets in the vault.** Passwords and keys go only into `vault/` encrypted with `ansible-vault`.
- **No downloads on servers.** If a task needs a file from the internet, the file moves into the bundle instead.
- **Check before moving on.** Each step has a "done when" test.

---

## 7. Common commands

```bash
ansible all -m ping                                           # can we reach every server
ansible-playbook playbooks/00-offline-repo.yml -e offline_repo_url=http://<REPO_IP>:8080
ansible-playbook playbooks/site.yml                           # everything
ansible-playbook playbooks/03-k8s-prereq.yml --limit k8s1     # one server only
ansible-playbook playbooks/site.yml --check --diff            # show changes without making them
ansible-vault create vault/secrets.yml                        # create encrypted secrets
```

---

## 8. Open decisions

- Client server OS and version, and the admin user name (`ansible_user`).
- Where MongoDB, Neo4j, RabbitMQ and Redis run.
- Whether the GPU server for the chatbot is part of the first release.
- Where the database schema comes from, since the application repositories contain no migration scripts.
- Internal time source, DNS and SMTP relay at the client site.
- A permanent systemd unit for serving the offline repo.
