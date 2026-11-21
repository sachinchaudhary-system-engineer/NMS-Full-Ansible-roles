# infra-ansible

Server preparation for the NMS platform, done with Ansible, on a **private network with no internet**.

One control machine configures every server. Everything the servers need (packages, Python wheels, binaries) is built on an internet machine, carried on a drive, and installed from local files.

---

## 1. Scope

**This repo does:**

- Prepare every server: offline package repository, hostnames, time sync, base packages, kernel settings.
- Install and configure the server software: HAProxy and Keepalived, PostgreSQL with Patroni and etcd, pgBackRest, MinIO, GitLab.
- Prepare the Kubernetes nodes and stage the RKE2 files.
- Check after every run that the servers are ready.

**This repo does not (yet):**

- Install Kubernetes (RKE2). That is the next stage, after the servers are ready.
- Build images or run CI.
- Deploy the application. Argo CD does that later.
- Handle certificates, TLS, firewall rules or traffic rules. We add those as separate steps once the base is working.

---

## 2. How it works without internet

```text
INTERNET MACHINE                                 PRIVATE NETWORK
----------------                                 ---------------
scripts/02-build-offline-rpm-repo.sh        drive            scripts/verify-bundle.sh
scripts/03-download-ansible-wheels-and-collections.sh ========>        scripts/07-install-ansible-on-controller.sh
scripts/04-download-third-party-binaries.sh                     ansible-playbook playbooks/site.yml
scripts/06-pack-offline-bundle.sh                           (servers install from local files)
```

The bundle holds six things:

| Part | What it is | Used for |
|---|---|---|
| `offline-rpm-repo/` | RPM files with every dependency, plus repository metadata | `dnf install` on every server |
| `ansible-python-wheels/` | Python packages for ansible-core | Installing Ansible on the control machine |
| `ansible-collections/` | Extra Ansible modules | Control machine |
| `third-party-binaries/` | etcd, exporters, MinIO, RKE2 files | Database, backup and Kubernetes servers |
| `gitlab/` | GitLab package | The registry server |
| `git/` | This repo as a Git bundle | Getting the playbooks onto the control machine |

The bundle is **not** committed to GitHub. It is large, and it is rebuilt for each release.

---

## 3. Server groups

| Group | Servers | What Ansible sets up |
|---|---|---|
| `loadbalancer` | 2 | HAProxy and Keepalived, with one virtual IP |
| `k8s_masters` | 3 | Kubernetes control-plane prerequisites |
| `k8s_workers` | 3 | Kubernetes worker prerequisites |
| `database` | 3 | PostgreSQL, etcd, Patroni, pgBackRest |
| `backup` | 1 | The storage disk and MinIO |
| `registry` | 1 | GitLab (Git repositories and the image registry) |

`k8s` is a parent group that holds the masters and the workers. The control machine itself is the admin machine and is not in the inventory.

Still to decide with the team: where MongoDB, Neo4j, RabbitMQ and Redis run. Their groups are added when that is decided (see step 9).

---

## 4. Directory structure

```text
infra-ansible/
├── README.md
├── ansible.cfg
├── .gitignore
│
├── inventory/
│   ├── production.ini          # servers, grouped by role
│   ├── group_vars/             # settings per group
│   │   ├── all.yml
│   │   ├── loadbalancer.yml
│   │   ├── k8s.yml
│   │   ├── database.yml
│   │   ├── backup.yml
│   │   └── registry.yml
│   └── host_vars/              # settings for a single server
│
├── playbooks/
│   ├── site.yml                # runs everything in order
│   ├── 01-common.yml           # offline repo and baseline, all servers
│   ├── 02-loadbalancer.yml
│   ├── 03-k8s-prereq.yml
│   ├── 04-backup.yml
│   ├── 05-database.yml
│   ├── 06-registry.yml
│   └── 99-validate.yml
│
├── roles/                      # one role per job
│   ├── offline_repo/
│   ├── common/
│   ├── loadbalancer/
│   ├── k8s_prereq/
│   ├── minio/
│   ├── database/
│   ├── gitlab/
│   └── validate/
│       └── (each role has: tasks/  defaults/  handlers/  templates/  files/)
│
├── scripts/                    # run on the internet machine and the control machine
│   ├── rpm-package-list.txt            # list of OS packages for the offline repo
│   ├── pinned-versions.env            # every pinned version
│   ├── 02-build-offline-rpm-repo.sh
│   ├── 03-download-ansible-wheels-and-collections.sh
│   ├── 04-download-third-party-binaries.sh
│   ├── 06-pack-offline-bundle.sh
│   ├── verify-bundle.sh
│   └── 07-install-ansible-on-controller.sh
│
├── bundle/                     # offline files (not committed)
└── vault/                      # encrypted secrets (only encrypted files are committed)
```

How the folders work together:

- **inventory** says *which* servers exist and *what settings* they have.
- **roles** say *how* to configure one thing. Each role has one job.
- **playbooks** say *which roles run on which group*, in order.
- **scripts** build and check the offline bundle. They are not Ansible.

---

## 5. Step-by-step plan

Do the steps in order. Finish and check each one before the next.

### Step 0: Decisions

Fix the things everything else depends on.

- Client server OS and version. The scripts assume a RHEL-family system with `dnf`. Change them if it is different.
- IP plan, hostnames and which server goes in which group.
- The admin user that exists on every server.

**Result:** `inventory/production.ini` and `inventory/group_vars/all.yml` filled in.

### Step 1: Build the offline bundle (internet machine)

```bash
# 1. Fill in scripts/pinned-versions.env and review scripts/rpm-package-list.txt
bash scripts/02-build-offline-rpm-repo.sh
bash scripts/03-download-ansible-wheels-and-collections.sh
bash scripts/04-download-third-party-binaries.sh
bash scripts/06-pack-offline-bundle.sh 2026.11.1
```

Run these on a machine with the **same OS release and kernel** as the client servers. Packages such as `kernel-modules-extra` must match the running kernel.

**Done when:** `nms-offline-bundle-<release>.tar` and its `.sha256` file exist, and a fresh offline server can install from the repo.

### Step 2: Control machine at the client site

```bash
bash scripts/verify-bundle.sh /opt/bundle
bash scripts/07-install-ansible-on-controller.sh
ssh-keygen -t ed25519
ssh-copy-id ansible@<each server>
ansible all -m ping
```

**Done when:** `ansible --version` works and `ansible all -m ping` answers `pong` from every server.

### Step 3: Baseline for every server (`offline_repo` and `common` roles)

- Copy the offline repository to every server and make dnf use only that.
- Set hostname and the name list in `/etc/hosts`.
- Set the timezone to UTC and set up chrony with your internal time source.
- Install the base packages.
- Lock the kernel version so it stays equal to the one in the bundle.
- Create the admin user and SSH key access.

```bash
ansible-playbook playbooks/01-common.yml
```

**Done when:** every server can `dnf install` from the offline repo, and `chronyc tracking` shows a synced clock.

### Step 4: Load balancers (`loadbalancer` role)

- Install HAProxy and Keepalived from the offline repo.
- Template the HAProxy and Keepalived configuration.
- Start both services and bring up the virtual IP.

```bash
ansible-playbook playbooks/02-loadbalancer.yml
```

**Done when:** the virtual IP is on lb1 and moves to lb2 when HAProxy stops on lb1.

### Step 5: Kubernetes node prerequisites (`k8s_prereq` role)

- Turn off swap and remove it from `/etc/fstab`.
- Load the `overlay` and `br_netfilter` kernel modules.
- Set the sysctl values Kubernetes needs.
- Install `container-selinux` and `kernel-modules-extra` from the offline repo.
- Prepare disks and directories for etcd and local storage.
- Copy the RKE2 files to `/opt/rke2-artifacts` on every node. **Do not install RKE2 yet.**

```bash
ansible-playbook playbooks/03-k8s-prereq.yml
```

**Done when:** all six nodes pass the checks in `validate`, and the RKE2 files are on each node.

### Step 6: Backup server (`minio` role)

- Mount the storage disk (XFS) and add it to `/etc/fstab`.
- Create the MinIO user and the systemd service.
- Start MinIO and create the buckets `velero`, `postgres` and `etcd`.

```bash
ansible-playbook playbooks/04-backup.yml
```

**Done when:** MinIO is running and the three buckets exist.

### Step 7: Database servers (`database` role)

- Install PostgreSQL and pgBackRest from the offline repo.
- Remove the default PostgreSQL cluster, because Patroni manages it.
- Install etcd from the bundle and start a 3-node etcd cluster.
- Install Patroni from the wheels into a virtual environment.
- Template the Patroni and pgBackRest configuration, with backups sent to MinIO.

```bash
ansible-playbook playbooks/05-database.yml
```

**Done when:** `patronictl list` shows one Leader and two Replicas, and a first pgBackRest backup completes.

### Step 8: Registry server (`gitlab` role)

- Install the GitLab package from the bundle.
- Configure it for your internal hostname, with the registry enabled.
- Create the first group and projects.

```bash
ansible-playbook playbooks/06-registry.yml
```

**Done when:** GitLab opens, and you can push a test image to its registry.

### Step 9: Other data stores (decision first)

When the team decides where MongoDB, Neo4j, RabbitMQ and Redis run, add one role and one playbook for each, following the same pattern as steps 4 to 8.

### Step 10: Validation and a full rehearsal

- Fill in the `validate` role. It checks repo access, time sync, kernel modules, service states and ports.
- Run everything on a clean set of test servers with the network cable unplugged:

```bash
ansible-playbook playbooks/site.yml
ansible-playbook playbooks/99-validate.yml
```

**Done when:** the whole run succeeds from empty servers, and a second run reports **no changes**.

---

## 6. Rules we follow

- **Safe to run twice.** Every task can be repeated without breaking anything. The second run shows `changed=0`.
- **One role, one job.** A role never reaches into another role's work.
- **Pinned versions.** Every version is written in `scripts/pinned-versions.env`. No `latest`.
- **Secrets in the vault.** Passwords and keys go only into `vault/` encrypted with `ansible-vault`. Never commit a plain password.
- **No downloads on servers.** If a task needs a file from the internet, the file moves into the bundle instead.
- **Check before moving on.** Each step has a "done when" test.

---

## 7. Common commands

```bash
ansible all -m ping                                   # can we reach every server
ansible-playbook playbooks/01-common.yml              # one step
ansible-playbook playbooks/site.yml                   # everything
ansible-playbook playbooks/03-k8s-prereq.yml --limit worker1   # one server only
ansible-playbook playbooks/site.yml --check --diff    # show changes without making them
ansible-vault create vault/secrets.yml                # create encrypted secrets
```

---

## 8. Open decisions

- Client server OS and version.
- Where MongoDB, Neo4j, RabbitMQ and Redis run.
- Whether the GPU server for the chatbot is part of the first release.
- Where the database schema comes from, since the application repositories contain no migration scripts.
- Internal time source, DNS and SMTP relay at the client site.
