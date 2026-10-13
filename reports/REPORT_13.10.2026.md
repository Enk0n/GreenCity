# Task Execution Report: Ansible Automation Refactoring

| Parameter | Details |
| :--- | :--- |
| **Project** | GreenCity |
| **Date** | October 13, 2026 |
| **Executed Task** | Infrastructure Automation with Ansible Roles |
| **Environment** | Oracle Linux 9.8 (VirtualBox VMs) |
| **Status** | Completed |

---

## 1. Stage Goals

* Transition from a monolithic playbook (`playbook.yml`) to a modular, role-based architecture (`roles/`).
* Decouple hardcoded variables into dedicated environment files (`group_vars/`).
* Introduce dynamic Jinja2 templating for configuration files (`pg_hba.conf.j2`, `.env.j2`).
* Implement handler mechanisms for atomic service reloads (e.g., PostgreSQL).
* Execute and validate idempotent orchestration across isolated database and application tiers.

---

## 2. Infrastructure & Inventory Topology

Target instances managed via `inventory.ini`:

| Hostname | Group | IP Address | Managed User | Assigned Roles |
| :--- | :--- | :--- | :--- | :--- |
| `greencity-db` | `db_servers` | `192.168.0.134` | `greencity-db` | `common`, `postgresql` |
| `greencity-app` | `app_servers` | `192.168.0.228` | `greencity-app` | `common`, `docker`, `app` |

---

## 3. What Was Done

### 3.1. Architecture & Directory Structuring
* Initialized standard Ansible directory structure:
  * `group_vars/` for environment scoping (`all.yml`, `db_servers.yml`, `app_servers.yml`).
  * `roles/` containing decoupled operational logic (`common`, `postgresql`, `docker`, `app`).
  * `site.yml` as the master entry-point orchestration playbook.
* Managed changes under a dedicated Git feature branch: `ansible`.

### 3.2. Role Implementation Details

* **`common` Role**:
  * Enforced SELinux `permissive` mode across all hosts.
  * Verified and started `firewalld` system service.

* **`postgresql` Role**:
  * Installed `postgresql-server`, `postgresql-contrib`, and `python3-psycopg2`.
  * Implemented idempotency check via `stat` to prevent re-initialization of `/var/lib/pgsql/data`.
  * Configured `postgresql.conf` (`listen_addresses = '*'`) and generated `pg_hba.conf` from Jinja2 template.
  * Configured Ansible handler to trigger service reloads only on configuration changes.
  * Configured `firewalld` port `5432/tcp`.
  * Created target database `greencity` and user credentials via PostgreSQL modules.

* **`docker` Role**:
  * Added the official Docker CE repository to Oracle Linux YUM configuration.
  * Installed Docker Engine, CLI, Containerd, and Docker Compose plugin.
  * Enabled and started `docker` systemd service.
  * Appended the host operator (`{{ ansible_user }}`) to the `docker` security group.

* **`app` Role**:
  * Opened HTTP ingress firewall rules (`80/tcp`, `8080/tcp`).
  * Resolved directory ownership conflicts recursively for the application workspace.
  * Cloned GreenCity source code repository (`docker-dockercompose` branch).
  * Rendered runtime environment parameters into `app/.env` using Jinja2 (`env.j2`).
  * Triggered automated container build and start via `docker compose up -d --build`.

---

## 4. Challenges & Root Cause Analysis (RCA)

| # | Symptom | Root Cause | Resolution |
| :-: | :--- | :--- | :--- |
| **1** | `YAML parsing failed: While scanning an alias did not find expected alphabetic or numeric character` | Unquoted asterisk `*` in variable definition (`listen_addresses: *`), which YAML treats as an alias reference. | Quoted the value explicitly as a string: `listen_addresses: "*"`. |
| **2** | `git fetch failed: error: cannot open '.git/FETCH_HEAD': Permission denied` | Artifacts from prior manual root deployment had `root:root` ownership, blocking non-root user execution. | Added recursive `ansible.builtin.file` task setting `owner` and `group` to `{{ ansible_user }}` prior to Git checkout. |
| **3** | `fatal: empty ident name (for <user@host>) not allowed` during Git commit | WSL environment lacked configured Git committer metadata. | Executed `git config --global user.name` and `git config --global user.email`. |

---

## 5. Verification & Playbook Execution Summary

Final execution output of `ansible-playbook -i inventory.ini site.yml`:

```text
PLAY RECAP *******************************************************************************************
greencity-app              : ok=13    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
greencity-db               : ok=12    changed=0    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0
```

* **Connectivity Check**: Verified HTTP 200 response on `http://192.168.0.228`.
* **State Persistence**: Verified application container connectivity to remote PostgreSQL database (`192.168.0.134:5432`).

---

## 6. Next Steps

- [ ] Create dedicated Load Balancer instance (`greencity-lb`) using Nginx.
- [ ] Add `nginx` role to manage upstream routing and proxy headers.
- [ ] Implement health checks and load balancing across application backends.