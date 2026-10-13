# Step-by-Step Guide: Refactoring Monolithic Playbook into Ansible Roles

A chronological, technical execution guide detailing how the GreenCity infrastructure was restructured into modular Ansible roles, debugged, validated, and pushed to version control.

---

## Step 1: Git Branch Initialization and Cleanup

1. Navigate to the project root and switch to a dedicated feature branch:
   ```bash
   cd /mnt/c/GreenCity
   git checkout -b ansible
   ```

2. Inspect existing branches and remove unintended artifacts:
   ```bash
   git branch
   git branch -d checkout
   ```

---

## Step 2: Role and Directory Hierarchy Creation

Create the standard Ansible roles directory structure:

```bash
cd /mnt/c/GreenCity/ansible
mkdir -p group_vars \
  roles/common/tasks \
  roles/postgresql/{tasks,handlers,templates} \
  roles/docker/tasks \
  roles/app/{tasks,templates}
```

---

## Step 3: Parameter Decoupling via `group_vars/`

### 3.1. Universal OS Configuration (`group_vars/all.yml`)
```yaml
---
selinux_mode: permissive
```

### 3.2. Database Node Variables (`group_vars/db_servers.yml`)
*Note: The asterisk must be wrapped in quotes to prevent YAML parsing errors.*
```yaml
---
db_name: "greencity"
db_user: "greencity"
db_pass: "greencity_pass"
db_port: 5432
listen_addresses: "*"
```

### 3.3. Application Server Variables (`group_vars/app_servers.yml`)
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

## Step 4: Role Implementation

### 4.1. Role: `common`
Define OS baseline tasks in `roles/common/tasks/main.yml`:
```yaml
---
- name: Set SELinux to permissive mode
  selinux:
    policy: targeted
    state: "{{ selinux_mode }}"

- name: Ensure firewalld is running and enabled
  service:
    name: firewalld
    state: started
    enabled: true
```

### 4.2. Role: `postgresql`

1. **Jinja2 Authentication Template (`roles/postgresql/templates/pg_hba.conf.j2`)**:
   ```text
   local   all             all                                     peer
   host    all             all             127.0.0.1/32            md5
   host    all             all             ::1/128                 md5
   host    all             all             0.0.0.0/0               md5
   ```

2. **Service Reload Handler (`roles/postgresql/handlers/main.yml`)**:
   ```yaml
   ---
   - name: restart postgresql
     service:
       name: postgresql
       state: restarted
   ```

3. **Tasks Definition (`roles/postgresql/tasks/main.yml`)**:
   ```yaml
   ---
   - name: Install PostgreSQL server and client libraries
     dnf:
       name:
         - postgresql-server
         - postgresql-contrib
         - python3-psycopg2
       state: present

   - name: Check if PostgreSQL database is already initialized
     stat:
       path: /var/lib/pgsql/data/PG_VERSION
     register: pg_data

   - name: Initialize PostgreSQL database
     command: postgresql-setup --initdb
     when: not pg_data.stat.exists

   - name: Enable and start PostgreSQL service
     service:
       name: postgresql
       state: started
       enabled: true

   - name: Configure postgresql.conf to listen on all interfaces
     lineinfile:
       path: /var/lib/pgsql/data/postgresql.conf
       regexp: '^#?listen_addresses\s*='
       line: "listen_addresses = '{{ listen_addresses }}'"
     notify: restart postgresql

   - name: Deploy pg_hba.conf configuration
     template:
       src: pg_hba.conf.j2
       dest: /var/lib/pgsql/data/pg_hba.conf
       owner: postgres
       group: postgres
       mode: '0600'
     notify: restart postgresql

   - name: Flush handlers to apply config changes
     meta: flush_handlers

   - name: Open PostgreSQL port in firewalld
     firewalld:
       port: "{{ db_port }}/tcp"
       permanent: true
       state: enabled
       immediate: true

   - name: Create GreenCity database
     postgresql_db:
       name: "{{ db_name }}"
       login_user: postgres
     become_user: postgres

   - name: Create GreenCity database user
     postgresql_user:
       name: "{{ db_user }}"
       password: "{{ db_pass }}"
       login_user: postgres
     become_user: postgres
   ```

### 4.3. Role: `docker`
Define engine installation in `roles/docker/tasks/main.yml`:
```yaml
---
- name: Add official Docker repository
  get_url:
    url: [https://download.docker.com/linux/centos/docker-ce.repo](https://download.docker.com/linux/centos/docker-ce.repo)
    dest: /etc/yum.repos.d/docker-ce.repo
    mode: '0644'

- name: Install Docker and Docker Compose plugin
  dnf:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-compose-plugin
    state: present

- name: Enable and start Docker service
  service:
    name: docker
    state: started
    enabled: true

- name: Add current user to docker group
  user:
    name: "{{ ansible_user }}"
    groups: docker
    append: true
```

### 4.4. Role: `app`

1. **Environment Template (`roles/app/templates/env.j2`)**:
   ```text
   DATASOURCE_URL={{ datasource_url }}
   DATASOURCE_USER={{ datasource_user }}
   DATASOURCE_PASSWORD={{ datasource_password }}
   POSTGRES_USER={{ datasource_user }}
   POSTGRES_PASSWORD={{ datasource_password }}
   AZURE_CONNECTION_STRING=dummy
   AZURE_CONTAINER_NAME=dummy
   EMAIL_ADDRESS=dummy@example.com
   PASSWORD_FROM_GMAIL=dummy
   ```

2. **Tasks Definition (`roles/app/tasks/main.yml`)**:
   ```yaml
   ---
   - name: Open HTTP ports in firewalld
     firewalld:
       port: "{{ item }}"
       permanent: true
       state: enabled
       immediate: true
     loop: "{{ app_http_ports }}"

   - name: Ensure application directory has correct ownership
     file:
       path: "{{ app_dest_dir }}"
       owner: "{{ ansible_user }}"
       group: "{{ ansible_user }}"
       state: directory
       recurse: true

   - name: Clone GreenCity repository
     git:
       repo: "{{ app_repo_url }}"
       dest: "{{ app_dest_dir }}"
       version: "{{ app_repo_branch }}"
       force: true
     become_user: "{{ ansible_user }}"

   - name: Generate .env file from template
     template:
       src: env.j2
       dest: "{{ app_dest_dir }}/app/.env"
       owner: "{{ ansible_user }}"
       group: "{{ ansible_user }}"
       mode: '0644'

   - name: Build and run Docker Compose application
     command: docker compose up -d --build
     args:
       chdir: "{{ app_dest_dir }}/app"
     become_user: "{{ ansible_user }}"
   ```

---

## Step 5: Master Playbook & Inventory Configuration

1. **Inventory Specification (`inventory.ini`)**:
   ```ini
   [db_servers]
   greencity-db ansible_host=192.168.0.134 ansible_user=greencity-db

   [app_servers]
   greencity-app ansible_host=192.168.0.228 ansible_user=greencity-app

   [all:vars]
   ansible_python_interpreter=/usr/bin/python3
   ansible_become=yes
   ```

2. **Master Orchestrator (`site.yml`)**:
   ```yaml
   ---
   - name: Base OS Configuration (All nodes)
     hosts: all
     become: true
     roles:
       - common

   - name: Setup Database Server (greencity-db)
     hosts: db_servers
     become: true
     roles:
       - postgresql

   - name: Setup Application Server (greencity-app)
     hosts: app_servers
     become: true
     roles:
       - docker
       - app
   ```

---

## Step 6: Troubleshooting & Resolution Applied

1. **YAML Alias Parse Error**:
   * *Problem:* Unquoted `listen_addresses: *` in `group_vars/db_servers.yml` triggered YAML parser failure.
   * *Fix:* Wrapped the value in quotation marks: `listen_addresses: "*"`.

2. **Git Fetch Permission Conflict**:
   * *Problem:* The repository folder on `greencity-app` had remnants of root ownership (`root:root`), preventing `greencity-app` user from writing to `.git/FETCH_HEAD`.
   * *Fix:* Injected `file` task with `recurse: true` in `roles/app/tasks/main.yml` prior to the git clone task to enforce correct user/group permissions.

---

## Step 7: Playbook Validation & Deployment Execution

1. **Run Syntax Check**:
   ```bash
   ansible-playbook -i inventory.ini site.yml --syntax-check
   ```

2. **Execute Full Orchestration**:
   ```bash
   ansible-playbook -i inventory.ini site.yml --ask-pass --ask-become-pass
   ```

3. **Verify Deployment Health**:
   ```bash
   curl -I [http://192.168.0.228](http://192.168.0.228)
   ```
