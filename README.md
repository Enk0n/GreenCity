# GreenCity Infrastructure Automation (Ansible)

Automated provisioning and multi-tier deployment of the **GreenCity** platform across Oracle Linux 9.8 virtual machines using modular Ansible roles.

---

## 1. Architecture Overview

The infrastructure decouples the persistence layer from the application container runtime:

* **Database Tier (`greencity-db`)**: Dedicated VM running standalone PostgreSQL 15, bound to local network interfaces with configured firewall and client authentication.
* **Application Tier (`greencity-app`)**: Dedicated VM running Docker Engine and Docker Compose, pulling the application repository, injecting `.env` configurations, and serving HTTP traffic.

### Target Node Topology

| Hostname | Role | OS | IP Address / Interface | Ports |
| :--- | :--- | :--- | :--- | :--- |
| `greencity-db` | Database Server | Oracle Linux 9.8 | Static (`192.168.0.134`) | `5432/tcp` |
| `greencity-app` | Application Server | Oracle Linux 9.8 | Dynamic / DHCP (`192.168.0.228`) | `80/tcp`, `8080/tcp` |

---

## 2. Directory Structure

The Ansible codebase follows the standard role-based layout:

```text
ansible/
├── ansible.cfg                # Engine configurations & connection parameters
├── inventory.ini              # Host grouping and per-node variables
├── site.yml                   # Master orchestration playbook
├── group_vars/
│   ├── all.yml                # Universal configurations (SELinux mode)
│   ├── db_servers.yml         # PostgreSQL ports, credentials, network bindings
│   └── app_servers.yml        # Git branch, repo URL, paths, exposed HTTP ports
└── roles/
    ├── common/                # OS-level baseline (SELinux, firewalld)
    │   └── tasks/main.yml
    ├── postgresql/            # DB installation, templates, handlers, user/db creation
    │   ├── tasks/main.yml
    │   ├── handlers/main.yml
    │   └── templates/
    │       └── pg_hba.conf.j2
    ├── docker/                # Official Docker CE repo setup & engine installation
    │   └── tasks/main.yml
    └── app/                   # Code checkout, .env templating, compose execution
        ├── tasks/main.yml
        └── templates/
            └── env.j2
```

---

## 3. Prerequisites

* **Control Node**:
  * Linux / WSL environment.
  * Ansible core installed (`ansible >= 2.14`).
  * Python 3 and `sshpass` (for password-based authentication).
* **Managed Nodes**:
  * 2x Oracle Linux 9.8 instances reachable via SSH.
  * Sudo/root access enabled for the management users.

---

## 4. Configuration Setup

### Step 1: Inventory Definition (`inventory.ini`)

Assign hostnames, target IP addresses, and SSH users to respective groups:

```ini
[db_servers]
greencity-db ansible_host=192.168.0.134 ansible_user=greencity-db

[app_servers]
greencity-app ansible_host=192.168.0.228 ansible_user=greencity-app

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_become=yes
```

### Step 2: Parameterization (`group_vars/`)

* **`group_vars/all.yml`**:
  ```yaml
  ---
  selinux_mode: permissive
  ```

* **`group_vars/db_servers.yml`**:
  ```yaml
  ---
  db_name: "greencity"
  db_user: "greencity"
  db_pass: "greencity_pass"
  db_port: 5432
  listen_addresses: "*"
  ```

* **`group_vars/app_servers.yml`**:
  ```yaml
  ---
  app_repo_url: "https://github.com/Enk0n/GreenCity.git"
  app_repo_branch: "docker-dockercompose"
  app_dest_dir: "/home/{{ ansible_user }}/GreenCity"

  app_http_ports:
    - "80/tcp"
    - "8080/tcp"

  datasource_url: "jdbc:postgresql://192.168.0.134:5432/greencity"
  datasource_user: "greencity"
  datasource_password: "greencity_pass"
  ```

---

## 5. Deployment Execution

### Step 1: Verify Host Reachability

Test connection and authentication to all nodes:

```bash
ansible all -i inventory.ini -m ping --ask-pass --ask-become-pass
```

### Step 2: Execute Syntax Validation

Ensure all YAML tasks, handlers, and templates parse correctly:

```bash
ansible-playbook -i inventory.ini site.yml --syntax-check
```

### Step 3: Run Orchestration Playbook

Deploy the complete infrastructure stack:

```bash
ansible-playbook -i inventory.ini site.yml --ask-pass --ask-become-pass
```

---

## 6. Role Breakdown

1. **`common`**:
   * Sets SELinux to `permissive` mode to avoid unconfined container and socket blocking.
   * Enables and activates `firewalld`.

2. **`postgresql`**:
   * Installs PostgreSQL 15 and `python3-psycopg2` module dependencies.
   * Initializes cluster data directory on initial run.
   * Sets `listen_addresses = '*'` in `postgresql.conf`.
   * Deploys `pg_hba.conf` template granting `md5` remote network access.
   * Opens firewall port `5432/tcp`.
   * Creates the `greencity` database and dedicated application credentials.

3. **`docker`**:
   * Registers upstream Docker CE repository on RHEL/CentOS family.
   * Installs Docker Engine, CLI, Containerd, and Compose plugins.
   * Ensures the system service is active and appends the operational user to the `docker` security group.

4. **`app`**:
   * Opens inbound firewall ports `80/tcp` and `8080/tcp`.
   * Enforces recursive file ownership on destination paths.
   * Pulls the repository from the target branch.
   * Dynamically renders the application `.env` file via Jinja2 (`env.j2`).
   * Executes `docker compose up -d --build` non-interactively.

---

## 7. Verification & Testing

Verify end-to-end functionality following deployment:

1. **Database Listener Check**:
   ```bash
   nc -zv 192.168.0.134 5432
   ```

2. **Container State**:
   ```bash
   ssh greencity-app@192.168.0.228 "docker compose -f /home/greencity-app/GreenCity/app/docker-compose.yml ps"
   ```

3. **HTTP Web Interface**:
   ```bash
   curl -I [http://192.168.0.228](http://192.168.0.228)
   ```
   *Expected Response:* `HTTP/1.1 200 OK` (or reverse proxy redirection).
