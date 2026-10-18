# Task Execution Report: Nginx Load Balancer Implementation

| Parameter | Details |
| :--- | :--- |
| **Project** | GreenCity |
| **Date** | October 18, 2026 |
| **Task** | Setup Load Balancing for Webapp |
| **Git Branch** | `docker-load-balancer` |
| **Stack** | Docker Compose, Nginx (Alpine), Java Spring Boot, PostgreSQL |
| **Status** | Completed & Validated |

---

## 1. Executive Summary

This task established a robust Layer 7 Reverse Proxy and Load Balancer using **Nginx** to front horizontally scaled backend instances of the GreenCity application core (`backcore`). The architecture prevents direct exposure of backend services to external clients, introduces fine-grained traffic distribution mechanisms, and ensures continuous service availability through automated failover handling.

---

## 2. Infrastructure & Topology Overview

The stack is containerized and orchestrated via Docker Compose within an isolated bridge network (`172.20.0.0/16`):

| Container Name | Service | Internal Port | Host Port | Role |
| :--- | :--- | :--- | :--- | :--- |
| `greencity-loadbalancer` | `nginx` | `8080/tcp` | `8080` | L7 Reverse Proxy & Load Balancer |
| `app-backcore1-1` | `backcore1` | `8080/tcp` | None (internal) | Primary Application Backend Instance |
| `app-backcore2-1` | `backcore2` | `8080/tcp` | None (internal) | Secondary Application Backend Instance |
| `app-backuser-1` | `backuser` | `8060/tcp` | `8060` | User Management Microservice |
| `app-frontend-1` | `frontend` | `80/tcp` | `80` | Web Client (Angular) |
| `app-db-1` | `db` | `5432/tcp` | `5432` | PostgreSQL 15 Database |

---

## 3. Implementation Details

### 3.1. Upstream & Proxy Configuration (`nginx.conf`)
* Configured an `upstream greencity_backend` block targeting the Docker service discovery DNS names (`backcore1:8080`, `backcore2:8080`).
* Configured proxy headers (`Host`, `X-Real-IP`, `X-Forwarded-For`, `X-Forwarded-Proto`) to preserve client metadata across hops.
* Injected an inspection header (`add_header X-Handled-By $upstream_addr always;`) to enable real-time verification of backend routing.

### 3.2. Topology Isolation (`docker-compose.yml`)
* Removed direct host port exposure from backend services (`8080:8080`) to ensure all incoming traffic passes through the load balancer.
* Duplicated the backend core into two parallel running containers (`backcore1` and `backcore2`), sharing the common database instance.
* Integrated the Nginx container with volume-mounted configuration, configured to depend on backend availability.

---

## 4. Load-Balancing Algorithms Evaluation

All four core requirements were tested empirically using automated request sequences via `curl`.

### 4.1. Round Robin (Default Algorithm)
* **Configuration:**
  ```nginx
  upstream greencity_backend {
      server backcore1:8080 max_fails=3 fail_timeout=10s;
      server backcore2:8080 max_fails=3 fail_timeout=10s;
  }
  ```
* **Test Command:**
  ```bash
  for i in {1..6}; do curl -sI http://localhost:8080 | grep -i "X-Handled-By"; done
  ```
* **Empirical Log Verification:**
  ```text
  X-Handled-By: 172.20.0.3:8080
  X-Handled-By: 172.20.0.5:8080
  X-Handled-By: 172.20.0.3:8080
  X-Handled-By: 172.20.0.5:8080
  X-Handled-By: 172.20.0.3:8080
  X-Handled-By: 172.20.0.5:8080
  ```
* **Outcome:** Equal distribution (1:1 ratio) alternating cyclically across instances.

---

### 4.2. Weighted Round Robin
* **Configuration:**
  ```nginx
  upstream greencity_backend {
      server backcore1:8080 weight=3 max_fails=3 fail_timeout=10s;
      server backcore2:8080 weight=1 max_fails=3 fail_timeout=10s;
  }
  ```
* **Test Command:**
  ```bash
  for i in {1..8}; do curl -sI http://localhost:8080 | grep -i "X-Handled-By"; done
  ```
* **Empirical Log Verification:**
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
* **Outcome:** Exact 3:1 traffic distribution (6 requests directed to `backcore1`, 2 requests to `backcore2`), conforming to the 75% vs 25% weight allocation.

---

### 4.3. IP Hash (Sticky Sessions)
* **Configuration:**
  ```nginx
  upstream greencity_backend {
      ip_hash;
      server backcore1:8080;
      server backcore2:8080;
  }
  ```
* **Test Command:**
  ```bash
  for i in {1..6}; do curl -sI http://localhost:8080 | grep -i "X-Handled-By"; done
  ```
* **Empirical Log Verification:**
  ```text
  X-Handled-By: 172.20.0.5:8080
  X-Handled-By: 172.20.0.5:8080
  X-Handled-By: 172.20.0.5:8080
  X-Handled-By: 172.20.0.5:8080
  X-Handled-By: 172.20.0.5:8080
  X-Handled-By: 172.20.0.5:8080
  ```
* **Outcome:** 100% request persistence routed to the same upstream worker based on the hash of the client's IPv4 address.

---

### 4.4. High Availability & Failover Validation
* **Action:** Simulated hardware or process crash on the primary node:
  ```bash
  docker compose stop backcore1
  ```
* **Verification Request:**
  ```bash
  curl -sI http://localhost:8080 | grep -E "(HTTP/|X-Handled-By)"
  ```
* **Empirical Log Verification:**
  ```text
  HTTP/1.1 404
  X-Handled-By: 172.20.0.5:8080
  ```
* **Outcome:** Nginx detected the unresponsiveness of `172.20.0.3` and instantaneously failed over to `172.20.0.5` without returning connection drops or `502 Bad Gateway` errors to the client.

---

## 5. Challenges & Root Cause Analysis (RCA)

| # | Problem Encountered | Root Cause | Implemented Solution |
| :-: | :--- | :--- | :--- |
| **1** | `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock` | Current WSL user was not part of the local `docker` Unix group. | Added user via `sudo usermod -aG docker $USER` and refreshed group context using `newgrp docker`. |
| **2** | Stale container `app-backcore-1` remained in `Exited` state. | Service rename (`backcore` -> `backcore1`/`backcore2`) caused Docker to retain the previous container as an orphan. | Deployed stack with the `--remove-orphans` flag. |
| **3** | `the attribute 'version' is obsolete` warning. | Docker Compose Specification v2 deprecates the top-level `version` string. | Removed `version: '3.8'` from `docker-compose.yml`. |

---

## 6. Deliverables & State

* **Configuration**: `app/nginx/nginx.conf`
* **Compose Topology**: `app/docker-compose.yml`
* **Branch**: `docker-load-balancer` pushed to remote repository.