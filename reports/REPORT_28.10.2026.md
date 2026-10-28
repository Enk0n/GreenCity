# Task Execution Report: GreenCity Cloud Deployment & Kubernetes Orchestration

| Parameter | Details |
| :--- | :--- |
| **Project** | GreenCity |
| **Date** | October 28, 2026 |
| **Git Branches** | `cloud-terraform` |
| **Stack** | AWS EC2, Terraform, Kubernetes (k3s), Traefik Ingress, PostgreSQL, Docker |
| **Status** | Completed & Validated |

---

## 1. Executive Summary

This phase successfully migrated the GreenCity microservices architecture from local development to a cloud-native environment on AWS:
1. **Infrastructure Provisioning (Terraform):** Automated the deployment of an AWS EC2 instance (`t2.micro`), configuring necessary Security Groups, VPCs, and a 4GB SWAP file to support resource-intensive Java Spring Boot applications within Free Tier limits.
2. **Container Orchestration (Kubernetes/k3s):** Installed and configured a lightweight k3s cluster, establishing an isolated `greencity` namespace and leveraging Traefik for Ingress routing.
3. **Microservices Deployment:** Deployed PostgreSQL with a PersistentVolumeClaim (PVC), alongside the `greencity-backend` (Core API), `greencity-user` (Auth API), and `greencity-frontend` (Angular/Nginx) services.
4. **Configuration & Secret Management:** Secured Azure Blob Storage credentials by substituting placeholders in Git-tracked manifests and integrated mock SMTP configurations to enable successful application context initialization.

---

## 2. Infrastructure, Topology & Integrated Services

| Component | Target / Environment | Role / Functionality | Connectivity / Transport |
| :--- | :--- | :--- | :--- |
| **AWS EC2** | `t2.micro` (eu-central-1) | Host infrastructure for the Kubernetes cluster | SSH (22), HTTP (80), HTTPS (443) |
| **k3s Cluster** | EC2 Host | Lightweight container orchestration | Internal Kubernetes Networking |
| **Traefik Ingress** | k3s (`kube-system`) | Edge router balancing traffic across microservices | HTTP (80) -> ClusterIPs |
| **PostgreSQL** | k3s (`greencity`) | Relational database with persistent EBS storage | TCP (5432) |
| **Core / User Backend**| k3s (`greencity`) | Java Spring Boot APIs | HTTP (8080 / 8060) |
| **Frontend** | k3s (`greencity`) | Nginx serving compiled Angular static assets | HTTP (80) |

---

## 3. Implementation Details

### 3.1. Infrastructure as Code (Terraform)
* **Resource Definition:** Managed AWS compute, networking, and security configurations via `.tf` scripts to ensure repeatable deployments.
* **Resource Optimization:** Applied a 4 GB SWAP file (`/swapfile`) to the EC2 instance, preventing `OOMKilled` events caused by the memory footprint of two JVMs running on a 1 GB instance.

### 3.2. Kubernetes Workloads (`k8s/` manifests)
* **Namespace Isolation:** All resources logically grouped under the `greencity` namespace.
* **Stateful Workloads:** Deployed PostgreSQL using a `PersistentVolumeClaim` (PVC) backed by AWS EBS, ensuring database durability across pod rescheduling.
* **Local Registry Import:** Bypassed external registries (like Docker Hub) by exporting images as `.tar` archives and importing them directly into the k3s `containerd` runtime (`k3s ctr images import`).

### 3.3. Ingress Routing & Traffic Management
* **Traefik Configuration (`k8s/ingress.yaml`):** Implemented path-based routing rules on port 80:
  * Authentication paths (`/user`, `/ownSecurity`) routed to `greencity-user-service` (Port 8060).
  * API endpoints (`/swagger-ui`, `/tags`, `/econews`) routed to `greencity-backend-service` (Port 8080).
  * Root traffic (`/`) routed to the Angular application on `greencity-frontend-service` (Port 80).

---

## 4. Verification & Observability Metrics

### 4.1. Application Health & Connectivity
* Validated successful startup of Core and User Spring Boot contexts without premature termination.
* Confirmed database migrations via Liquibase executed successfully during backend initialization.

### 4.2. Ingress & Routing Validation
* Verified external accessibility via the public EC2 IP address.
* Successfully interacted with the Swagger UI documentation and frontend interface, confirming Traefik effectively routes external HTTP requests to the appropriate internal services.

---

## 5. Challenges & Root Cause Analysis (RCA)

| # | Encountered Issue | Root Cause | Implemented Resolution |
| :-: | :--- | :--- | :--- |
| **1** | Frontend CORS & Connection Refused (`http://localhost`) | Compiled Angular assets contained hardcoded `localhost` references for API endpoints instead of relative paths or public IPs. | Executed in-container `sed` replacements across compiled JS bundles to inject the EC2 public IP without triggering an image rebuild. |
| **2** | Login returns `400 Bad Request` for new users | Mock SMTP configurations prevented activation emails from being sent, leaving user accounts locked in a `DEACTIVATED` state with pending tokens. | Executed direct SQL queries (`psql`) within the PostgreSQL pod to remove pending email verifications and force-activate user records. |
| **3** | GitHub blocks push due to Large Files | Docker image archives (`.tar`) exceeding 100MB were accidentally staged for commit. | Removed `.tar` files from index, appended `*.tar` to `.gitignore`, and rewrote commit history via `git commit --amend`. |
| **4** | GitHub Push Protection (Secret Scanning) | Active Azure Storage Account access keys were detected in `k8s/backend.yaml`. | Replaced the actual connection string with a `dummykey` placeholder and amended the commit to purge the secret from repository history. |

---

## 6. Deliverables & State

* **Infrastructure Configuration:** `terraform/` (VPC, SG, EC2 setup)
* **Kubernetes Manifests:** `k8s/` (`postgres.yaml`, `backend.yaml`, `user-backend.yaml`, `frontend.yaml`, `ingress.yaml`)
* **Cluster Status:** Operational on AWS EC2 (Instance can be stopped to manage Free Tier costs).