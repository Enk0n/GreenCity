# Task Execution Report (October 12, 2026)

**Project:** GreenCity  
**Executed Task:** Setup a Webapp (Oracle Linux VMs)

---

## Stage Goals

* Manual deployment and operational verification of the GreenCity application on two VMs running Oracle Linux 9.8.
* Separation of the database (PostgreSQL 15) from the application server (Docker / Docker Compose) within the local network.

---

## What Was Done

### 1. Infrastructure Preparation
* Created and booted two virtual machines: `greencity-db` (`192.168.0.134`) and `greencity-app`.
* Configured basic OS security parameters: set SELinux to `permissive` mode, started and configured `firewalld` (opened ports `80`, `8080`, `5432`).

### 2. Database Server Setup (`greencity-db`)
* Installed and initialized the PostgreSQL 15 package.
* Configured `postgresql.conf` (`listen_addresses = '*'`) and `pg_hba.conf` to accept external connections from the application server.
* Created the `greencity` database and a corresponding user with the necessary access privileges.

### 3. Application Server Setup (`greencity-app`)
* Installed Docker Engine and the Docker Compose plugin.
* Cloned the GreenCity project repository (`docker-dockercompose` branch).
* Created and configured the `.env` environment file, specifying the connection to the external database (`greencity-db`).
* Deployed and launched the application containers using `docker compose up -d --build`.
* Conducted end-to-end testing: the web interface is accessible via a browser, and user data is successfully stored in the external database.

---

## Challenges and Solutions

* **Issue:** The application on `greencity-app` could not connect to PostgreSQL on `greencity-db` (`Connection refused` / `Timeout`).
  * **Solution:** Verified and adjusted the `listen_addresses` parameter in `postgresql.conf`, added the allow rule `host all all 0.0.0.0/0 md5` in `pg_hba.conf`, and opened port `5432/tcp` in `firewalld` on the database server.

* **Issue:** Firewall blocking network traffic to the application's web interface.
  * **Solution:** Permanently opened ports `80/tcp` and `8080/tcp` on the `greencity-app` server using `firewall-cmd --permanent --add-port`, followed by reloading the firewall rules.

* **Issue:** Regular user lacked permissions to run Docker containers without using `sudo`.
  * **Solution:** Added the working user to the system `docker` group (`usermod -aG docker <username>`) to ensure proper and secure execution of Docker Compose commands.

---

## Next Steps

* **Deployment Automation:** Write and structure automation scripts (Ansible Roles) to recreate the entire infrastructure from scratch.
* **Load Balancing:** Configure Nginx/HAProxy to proxy incoming requests.
