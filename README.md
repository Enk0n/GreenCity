# 🌿 GreenCity Multi-Node Docker Deployment Guide

Step-by-step guide for deploying the **GreenCity** web application in a distributed infrastructure across two virtual machines running **Oracle Linux 9.8**.

---

## 📐 System Architecture

The system is deployed on two separate virtual machines configured in **Bridged Adapter** network mode:

| Server | Operating System | IP Address (Example) | Services & Components | Open Ports |
| :--- | :--- | :--- | :--- | :--- |
| **`greencity-db`** | Oracle Linux 9.8 | `192.168.0.134` | PostgreSQL 15 | `5432/tcp`, `22/tcp` |
| **`greencity-app`** | Oracle Linux 9.8 | `192.168.0.XXX` | Docker, Docker Compose (Frontend, Backcore, Backuser) | `80/tcp`, `8080/tcp`, `22/tcp` |

---

## ⚙️ Step 1. Prerequisites and Base OS Configuration

Perform these steps **on both virtual machines** (`greencity-db` and `greencity-app`).

### 1.1 Set SELinux to Permissive Mode
```bash
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

### 1.2 Verify Network Connectivity
Ensure both virtual machines can reach each other across the network:
```bash
ping -c 3 <OTHER_VM_IP>
```

### Step 2. Database Server Setup (greencity-db)
2.1 Install and Enable PostgreSQL 15
```bash
sudo dnf install -y postgresql-server postgresql-contrib
sudo postgresql-setup --initdb
sudo systemctl enable --now postgresql
```

### 2.2 Configure Network Access for PostgreSQL
Allow PostgreSQL to listen on all network interfaces in postgresql.conf:
```bash
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /var/lib/pgsql/data/postgresql.conf
```
Allow connections from any IP address in pg_hba.conf:
```bash
echo "host all all 0.0.0.0/0 md5" | sudo tee -a /var/lib/pgsql/data/pg_hba.conf
sudo systemctl restart postgresql
```

### 2.3 Create Database and User
```bash
sudo -u postgres psql -c "CREATE DATABASE greencity;"
sudo -u postgres psql -c "CREATE USER greencity WITH PASSWORD 'greencity_pass';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE greencity TO greencity;"
```

### 2.4 Configure Firewall on DB Server
```bash
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --reload
```

### Step 3. Application Server Setup (greencity-app)
3.1 Install Docker and Docker Compose
```bash
sudo dnf config-manager --add-repo [https://download.docker.com/linux/centos/docker-ce.repo](https://download.docker.com/linux/centos/docker-ce.repo)
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

### 3.2 Configure Firewall on App Server
```bash
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

### Step 4. Repository Cloning and Environment Configuration
4.1 Clone Repository
```bash
git clone -b docker-dockercompose [https://github.com/Enk0n/GreenCity.git](https://github.com/Enk0n/GreenCity.git)
cd GreenCity/app
```
4.2 Create Environment Configuration File (.env)
In the GreenCity/app directory, create the .env file specifying the IP address of your database server:
```bash
cat <<EOF> .env
DATASOURCE_URL=jdbc:postgresql://192.168.0.xxx:5432/greencity
DATASOURCE_USER=greencity
DATASOURCE_PASSWORD=greencity_pass

POSTGRES_USER=greencity
POSTGRES_PASSWORD=greencity_pass

AZURE_CONNECTION_STRING=dummy
AZURE_CONTAINER_NAME=dummy
EMAIL_ADDRESS=dummy@example.com
PASSWORD_FROM_GMAIL=dummy
EOF
```
Note: Replace 192.168.0.xxx with the actual IP address of your greencity-db server.

### Step 5. Build and Launch Containers
Navigating inside the GreenCity/app directory, build and launch all services:
```bash
docker compose up -d --build
```
5.1 Verify Container Status
```bash
docker compose ps
```
All services (app-db-1, app-backuser-1, app-backcore-1, app-frontend-1) should show a status of Up.

### Step 6. Monitoring and Verification
Check Database Connection Logs
```bash
docker compose logs backcore --tail 50
```
The log output must show successful Liquibase migrations and Spring Boot initialization:
```bash
INFO Started GreenCityApplication in 42.405 seconds
```
Access Web Interface
Open a browser on your host machine and navigate to the App server IP:
```bash
http://<IP_GREENCITY_APP>
```
