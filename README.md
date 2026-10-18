# Step-by-Step Guide: Nginx Load Balancer Configuration with Docker Compose

A comprehensive, chronological technical guide detailing the deployment of an Nginx Reverse Proxy / Load Balancer, horizontal scaling of backend services, and validation of multiple load balancing algorithms for the GreenCity project.

---

## Step 1: Git Branch Preparation

1. Check out the baseline branch containing the stable Docker Compose setup:
   ```bash
   cd /mnt/c/GreenCity
   git checkout docker-dockercompose
   ```

2. Create and switch to the dedicated feature branch for the load balancer task:
   ```bash
   git checkout -b docker-load-balancer
   ```

---

## Step 2: Nginx Load Balancer Configuration

1. Create a dedicated directory for Nginx configuration files:
   ```bash
   mkdir -p app/nginx
   ```

2. Create the configuration file `app/nginx/nginx.conf`:
   ```nginx
   events {
       worker_connections 1024;
   }

   http {
       # Upstream pool defining the backend service instances
       upstream greencity_backend {
           # Algorithm Option 1: Round Robin (Default)
           server backcore1:8080 max_fails=3 fail_timeout=10s;
           server backcore2:8080 max_fails=3 fail_timeout=10s;

           # Algorithm Option 2: Weighted Round Robin
           # server backcore1:8080 weight=3 max_fails=3 fail_timeout=10s;
           # server backcore2:8080 weight=1 max_fails=3 fail_timeout=10s;

           # Algorithm Option 3: IP Hash (Sticky Sessions)
           # ip_hash;
           # server backcore1:8080;
           # server backcore2:8080;
       }

       server {
           listen 8080;
           server_name localhost;

           location / {
               proxy_pass http://greencity_backend;
               proxy_set_header Host $host;
               proxy_set_header X-Real-IP $remote_addr;
               proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
               proxy_set_header X-Forwarded-Proto $scheme;

               # Custom header exposing which upstream instance processed the request
               add_header X-Handled-By $upstream_addr always;
           }
       }
   }
   ```

---

## Step 3: Docker Compose Stack Refactoring

Update `app/docker-compose.yml` to:
* Remove host port binding (`8080:8080`) directly from the backend containers to ensure traffic flows exclusively through the reverse proxy.
* Split the single `backcore` service into two independent instances: `backcore1` and `backcore2`.
* Add the `nginx` container bound to host port `8080`, mounting the custom `nginx.conf`.
* Drop the obsolete `version: '3.8'` attribute.

```yaml
services:
  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: greencity
    ports:
      - "5432:5432"

  backuser:
    image: greencity-backuser:local
    environment:
      - DATASOURCE_URL=jdbc:postgresql://db:5432/greencity
      - DATASOURCE_USER=${POSTGRES_USER}
      - DATASOURCE_PASSWORD=${POSTGRES_PASSWORD}
      - AZURE_CONNECTION_STRING=${AZURE_CONNECTION_STRING}
      - AZURE_CONTAINER_NAME=${AZURE_CONTAINER_NAME}
      - EMAIL_ADDRESS=${EMAIL_ADDRESS}
      - PASSWORD_FROM_GMAIL=${PASSWORD_FROM_GMAIL}
    ports:
      - "8060:8060"
    depends_on:
      - db

  backcore1:
    image: greencity-backcore:local
    environment:
      - DATASOURCE_URL=jdbc:postgresql://db:5432/greencity
      - DATASOURCE_USER=${POSTGRES_USER}
      - DATASOURCE_PASSWORD=${POSTGRES_PASSWORD}
      - AZURE_CONNECTION_STRING=${AZURE_CONNECTION_STRING}
      - AZURE_CONTAINER_NAME=${AZURE_CONTAINER_NAME}
    depends_on:
      - db

  backcore2:
    image: greencity-backcore:local
    environment:
      - DATASOURCE_URL=jdbc:postgresql://db:5432/greencity
      - DATASOURCE_USER=${POSTGRES_USER}
      - DATASOURCE_PASSWORD=${POSTGRES_PASSWORD}
      - AZURE_CONNECTION_STRING=${AZURE_CONNECTION_STRING}
      - AZURE_CONTAINER_NAME=${AZURE_CONTAINER_NAME}
    depends_on:
      - db

  nginx:
    image: nginx:alpine
    container_name: greencity-loadbalancer
    ports:
      - "8080:8080"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - backcore1
      - backcore2

  frontend:
    image: greencity-frontend:local
    ports:
      - "80:80"
    depends_on:
      - backcore1
      - backcore2
      - backuser
```

---

## Step 4: Environment & Daemon Permissions Fix

If non-root execution encounters socket permission restrictions (`unix:///var/run/docker.sock: permission denied`):

1. Append the operational user to the `docker` security group:
   ```bash
   sudo usermod -aG docker $USER
   ```

2. Reload current group membership without re-logging:
   ```bash
   newgrp docker
   ```

3. Verify socket communication:
   ```bash
   docker ps
   ```

---

## Step 5: Service Deployment & Cleanup

1. Launch the updated application topology and purge deprecated orphan containers from previous builds:
   ```bash
   cd /mnt/c/GreenCity/app
   docker compose up -d --remove-orphans
   ```

2. Confirm container runtime status:
   ```bash
   docker ps
   ```

---

## Step 6: Empirical Algorithm Validation & Testing

### 6.1. Round Robin Algorithm (Default)
Verify uniform distribution ($1 \to 2 \to 1 \to 2$):

```bash
for i in {1..6}; do curl -sI http://localhost:8080 | grep -i "X-Handled-By"; done
```

*Observed Terminal Output:*
```text
X-Handled-By: 172.20.0.3:8080
X-Handled-By: 172.20.0.5:8080
X-Handled-By: 172.20.0.3:8080
X-Handled-By: 172.20.0.5:8080
X-Handled-By: 172.20.0.3:8080
X-Handled-By: 172.20.0.5:8080
```

---

### 6.2. Weighted Round Robin Algorithm (3:1 Ratio)
1. Modify `upstream greencity_backend` in `app/nginx/nginx.conf`:
   ```nginx
   upstream greencity_backend {
       server backcore1:8080 weight=3 max_fails=3 fail_timeout=10s;
       server backcore2:8080 weight=1 max_fails=3 fail_timeout=10s;
   }
   ```

2. Reload Nginx without container restart:
   ```bash
   docker compose exec nginx nginx -s reload
   ```

3. Send an 8-request batch:
   ```bash
   for i in {1..8}; do curl -sI http://localhost:8080 | grep -i "X-Handled-By"; done
   ```

*Observed Terminal Output (75% to `backcore1`, 25% to `backcore2`):*
```text
X-Handled-By: 172.20.0.3:8080
X-Handled-By: 172.20.0.3:8080
X-Handled-By: 172.20.0.5:8080
X-Handled-By: 172.20.0.3:8080
X-Handled-By: 172.20.0.3:8080
X-Handled-By: 172.20.0.3:8080
X-Handled-By: 172.20.0.5:8080
X-Handled-By: 172.20.0.3:8080
```

---

### 6.3. IP Hash Algorithm (Sticky Sessions)
1. Update `upstream greencity_backend` in `app/nginx/nginx.conf`:
   ```nginx
   upstream greencity_backend {
       ip_hash;
       server backcore1:8080;
       server backcore2:8080;
   }
   ```

2. Reload configuration:
   ```bash
   docker compose exec nginx nginx -s reload
   ```

3. Send consecutive requests:
   ```bash
   for i in {1..6}; do curl -sI http://localhost:8080 | grep -i "X-Handled-By"; done
   ```

*Observed Terminal Output (100% persistent affinity to single backend):*
```text
X-Handled-By: 172.20.0.5:8080
X-Handled-By: 172.20.0.5:8080
X-Handled-By: 172.20.0.5:8080
X-Handled-By: 172.20.0.5:8080
X-Handled-By: 172.20.0.5:8080
X-Handled-By: 172.20.0.5:8080
```

---

### 6.4. Dynamic Failover & Fault Tolerance
1. Simulate abrupt crash/downtime of `backcore1`:
   ```bash
   docker compose stop backcore1
   ```

2. Verify client request behavior:
   ```bash
   curl -sI http://localhost:8080 | grep -E "(HTTP/|X-Handled-By)"
   ```

*Observed Terminal Output (Traffic immediately redirected to surviving instance):*
```text
HTTP/1.1 404
X-Handled-By: 172.20.0.5:8080
```

3. Recover the stopped service:
   ```bash
   docker compose start backcore1
   ```

---

## Step 7: Final Cleanup & Version Control Push

1. Remove obsolete Compose version warnings using `sed`:
   ```bash
   sed -i '/^version:/d' /mnt/c/GreenCity/app/docker-compose.yml
   ```

2. Stage, commit, and push modifications to GitHub:
   ```bash
   cd /mnt/c/GreenCity
   git add app/docker-compose.yml app/nginx/nginx.conf
   git commit -m "feat(load-balancer): configure nginx reverse proxy with multi-algorithm load balancing and failover"
   git push -u origin docker-load-balancer
   ```
