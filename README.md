# GreenCity: Cloud Infrastructure & Kubernetes Deployment

This repository contains the Infrastructure as Code (IaC) and Kubernetes manifests required to deploy the GreenCity microservices application on AWS. 

The project utilizes **Terraform** for cloud resource provisioning and **k3s** (a lightweight Kubernetes distribution) for container orchestration.

## Architecture Overview

* **Cloud Provider:** AWS (eu-central-1)
* **Infrastructure:** EC2 (`t2.micro`), VPC, Public Subnet, Security Groups (Ports 22, 80, 443).
* **Orchestration:** k3s (Kubernetes) with Traefik Ingress Controller.
* **Storage:** AWS EBS with a Kubernetes PersistentVolumeClaim (PVC) for database durability.
* **Microservices:**
  * **PostgreSQL:** Relational database handling both Core and User schemas.
  * **Core Backend (`greencity-backend`):** Java Spring Boot API (Port 8080).
  * **User Backend (`greencity-user`):** Java Spring Boot Auth/User API (Port 8060).
  * **Frontend (`greencity-frontend`):** Angular application served via Nginx (Port 80).

---

## Step 1: Infrastructure Provisioning (Terraform)

The foundational cloud infrastructure is managed via Terraform to ensure reproducibility.

1. **Initialize and Apply Terraform:**

   ```bash
   cd terraform
   terraform init
   terraform apply -auto-approve
   ```

2. **Resource Constraints & SWAP File:**
   Since the deployment targets an AWS Free Tier `t2.micro` instance (1 GB RAM), running two heavy Java Spring Boot applications alongside PostgreSQL and k3s would immediately result in `OOMKilled` errors. To resolve this, a **4 GB SWAP file** is configured on the EC2 instance:

   ```bash
   sudo fallocate -l 4G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

## Step 2: Kubernetes Cluster Setup (k3s)

1. **Install k3s:**

   ```bash
   curl -sfL https://get.k3s.io | sh -
   ```

2. **Configure Namespace:**

   ```bash
   kubectl create namespace greencity
   ```

3. **Local Image Registry Bypass:**
   To avoid pushing heavy proprietary images to a public Docker Hub, images were exported as `.tar` archives and directly imported into the k3s `containerd` runtime:

   ```bash
   sudo k3s ctr images import greencity-frontend.tar
   sudo k3s ctr images import greencity-backcore.tar
   sudo k3s ctr images import greencity-backuser.tar
   ```

## Step 3: Application Deployment

All Kubernetes manifests are located in the `k8s/` directory. Deploy them sequentially:

1. **Database Layer:**

   ```bash
   kubectl apply -f k8s/postgres.yaml
   ```

   *Includes a PVC to ensure data survives pod restarts.*

2. **Backend Services:**

   ```bash
   kubectl apply -f k8s/backend.yaml
   kubectl apply -f k8s/user-backend.yaml
   ```

   *Note: Environment variables for Azure Blob Storage and SMTP were replaced with mock credentials (`dummykey`, `mock_password123`) to prevent secret exposure in version control while allowing Spring context to initialize successfully.*

3. **Frontend & Ingress Routing:**

   ```bash
   kubectl apply -f k8s/frontend.yaml
   kubectl apply -f k8s/ingress.yaml
   ```

   *Traefik is configured to route `/user`, `/ownSecurity`, and `/googleSecurity` to the User API (8060), various endpoints like `/tags` and `/econews` to the Core API (8080), and the root path `/` to the Nginx Frontend.*

---

## Step 4: Troubleshooting & Hotfixes

During the integration phase, several critical issues were identified and resolved on the fly:

### 1. Frontend API Call Redirection (The `localhost` Bug)

**Issue:** The compiled Angular static assets had hardcoded API URLs pointing to `http://localhost:8080` and `http://localhost:8060`, causing CORS and connection refused errors in the browser.

**Solution:** Executed an in-container text replacement (`sed`) to update the compiled JS bundles with the public EC2 IP address without rebuilding the Docker image.

   ```bash
   kubectl exec -it -n greencity deployment/greencity-frontend -- /bin/sh -c '
     sed -i "s|http://localhost:8060|http://<EC2_PUBLIC_IP>|g" /usr/share/nginx/html/main*.js
     sed -i "s|http://localhost:8080|http://<EC2_PUBLIC_IP>|g" /usr/share/nginx/html/main*.js
   '
   ```

### 2. Bypassing Email Verification (Auth Block)

**Issue:** Because mock SMTP credentials were provided, the backend could not send activation emails. New users were created in the database but were stuck in a `DEACTIVATED` state with pending tokens in the `verify_emails` table, resulting in `400 Bad Request` upon login.

**Solution:** Manually verified the latest registered user directly via the PostgreSQL pod:

   ```bash
   # Remove pending email verification lock
   kubectl exec -n greencity deployment/postgres -- psql -U greencity -d greencity -c "DELETE FROM verify_emails WHERE user_id = (SELECT max(id) FROM users);"

   # Activate user account
   kubectl exec -n greencity deployment/postgres -- psql -U greencity -d greencity -c "UPDATE users SET user_status = 1 WHERE id = (SELECT max(id) FROM users);"
   ```

### 3. Git Push Protection & Secret Management

**Issue:** GitHub blocked the push due to large file limits (`.tar` files) and detected secrets (Azure Storage Keys in `backend.yaml`).

**Solution:** 

* Added `*.tar` to `.gitignore` and removed them from the commit.
* Replaced actual Azure keys with `dummykey` placeholders.
* Rewrote the commit history using `git commit --amend` to ensure no secrets were leaked in the repository history.

---

## Cost Management (AWS Free Tier)

To avoid incurring charges when the environment is not actively being tested, stop the EC2 instance. EBS storage will persist the database and k3s state.

   ```bash
   aws ec2 stop-instances --instance-ids <YOUR_INSTANCE_ID> --region eu-central-1
   ```
