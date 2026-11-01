# Task Execution Report: Infrastructure Scaling, Observability, ECR Artifacts & MCP Server Integration

| Parameter | Details |
| :--- | :--- |
| **Project** | GreenCity |
| **Date** | October 31 - November 2, 2026 |
| **Git Branches** | `infra-ecr-mcp` |
| **Stack** | AWS EC2 (`t2.medium`), K3s, DataDog, AWS ECR, Kubernetes PSS, Python (FastMCP), Docker |
| **Status** | Completed, Validated & Scaled |

---

## 1. Executive Summary

This phase finalized the infrastructure production readiness, resolved critical resource bottlenecks, and enabled AI integration capabilities for the GreenCity microservices ecosystem:
1. **Vertical Infrastructure Scaling:** Successfully scaled the underlying AWS EC2 instance from `t2.small` (2GB RAM) to `t2.medium` (4GB RAM) to prevent recurrent `OOMKilled` events caused by the combined footprint of Java Spring Boot, PostgreSQL, and new telemetry agents.
2. **Cluster Security (PSS):** Enforced Kubernetes Pod Security Standards (PSS) at the `restricted` level, ensuring all deployments adhere to the principle of least privilege, non-root execution, and restricted Linux capabilities.
3. **Unified Observability (DataDog):** Deployed the DataDog Agent via Helm to collect infrastructure metrics, application states, and centralized logs across the K3s cluster, routed securely to the European region (`datadoghq.eu`).
4. **Artifact Management (AWS ECR):** Established a secure, centralized AWS Elastic Container Registry (ECR) for hosting GreenCity Docker images, decoupling artifact storage from the local K3s `containerd` engine and establishing robust `imagePullSecrets`.
5. **AI Context Bridging (MCP Server):** Developed and containerized a Model Context Protocol (MCP) server exposing read-only PostgreSQL schema data to AI clients over a long-lived Server-Sent Events (SSE) HTTP transport layer.

---

## 2. Infrastructure, Topology & Integrated Services

| Component | Target / Environment | Role / Functionality | Connectivity / Transport |
| :--- | :--- | :--- | :--- |
| **AWS EC2 Host** | `t2.medium` (eu-central-1) | Scaled compute node for K3s cluster | SSH, HTTP, HTTPS |
| **`datadog-agent`** | K3s (`datadog` ns) | Cluster monitoring, APM, and log aggregation | HTTPS to `datadoghq.eu` |
| **`aws-ecr`** | AWS (`eu-central-1`) | Private artifact registry for container images | AWS CLI / Docker Login / K8s Secret |
| **`greencity-backend`**| K3s (`greencity` ns) | Core application workload pulled from ECR | HTTP, ClusterIP |
| **`greencity-mcp`** | K3s (`greencity` ns) | AI integration gateway (FastMCP Server) | HTTP/SSE (`:8000`), Postgres (`:5432`) |

---

## 3. Implementation Details

### 3.1. Infrastructure Scaling & Stabilization
* **EC2 Instance Modification:** Stopped the instance via AWS CLI, modified the instance attribute to `t2.medium`, and restarted it.
* **Swap Management:** Verified the persistent 4GB SWAP file (`/swapfile`) remained active post-reboot, providing an effective 8GB of virtual memory to support concurrent JVMs and DataDog processes.

### 3.2. Pod Security Standards (PSS) Enforcement
* Applied strict namespace labeling to `greencity` and other critical namespaces.
* **Configurations enforced:** `runAsNonRoot: true`, explicit UID/GID (1000), `allowPrivilegeEscalation: false`, and `seccompProfile: RuntimeDefault`.
* Ensured zero `ALL` capabilities in the container context via `drop: ["ALL"]`.

### 3.3. DataDog Observability Pipeline
* **Helm Deployment:** Installed via the official DataDog Helm chart.
* **Regional Binding:** Configured `datadog.site=datadoghq.eu` to match the target account.
* **Log Collection:** Enabled cluster-wide log capturing by setting `logs.enabled=true` and `logs.containerCollectAll=true`. The agents automatically track stdout/stderr from all pods without requiring sidecar injection or complex Fluentd configurations.

### 3.4. AWS ECR Artifact Management Pipeline
* Created cloud repositories `greencity-backend` and `greencity-mcp` via `aws ecr create-repository`.
* **K3s to Docker Migration:** Exported local K3s images utilizing `k3s ctr images export`, loaded them into the host Docker daemon, and re-tagged them with the AWS Account URI.
* **Kubernetes Authentication:** Generated a `docker-registry` secret (`ecr-secret`) in K3s using a temporary AWS ECR login token to allow automated, continuous ImagePull operations.

### 3.5. Model Context Protocol (MCP) Server
* **Application Logic (`server.py`):** Developed a Python application using `FastMCP` exposing a `get_events` tool. The logic securely queries `information_schema.tables` from `postgres-service` to provide database context to AI agents.
* **Database Security:** Connected to PostgreSQL dynamically via environment variables with read-only query structures to prevent SQL injection or unintended data mutation.
* **Kubernetes Deployment:** Packaged into a minimal `python:3.11-slim` container, mapped to internal port `8000`, and exposed within the cluster via a `ClusterIP` service to prevent unauthorized external access.

---

## 4. Verification & Observability Metrics

### 4.1. DataDog & Infrastructure Metrics
* EC2 host memory utilization stabilized post-scaling (no further `OOMKilled` evictions).
* Agent nodes initialized `3/3 Running`.
* Live logs from `greencity-backend` and `postgres` successfully indexed and searchable in the DataDog Log Explorer.

### 4.2. MCP Server Readiness
* Pod stabilized with `Running (1/1)` status after architecture adjustments.
* Verified SSE connectivity from a cluster-internal context:
  ```http
  HTTP/1.1 200 OK
  content-type: text/event-stream; charset=utf-8
  event: endpoint
  data: /messages/?session_id=cdd74394d4744142a7818ce680944f8b
  ```
* Confirmed successful port-forwarding functionality (`kubectl port-forward svc/greencity-mcp-service 8000:8000`) for local AI client integrations.

---

## 5. Challenges & Root Cause Analysis (RCA)

| # | Encountered Issue | Root Cause | Implemented Resolution |
| :-: | :--- | :--- | :--- |
| **1** | Node Instability & Pod Evictions (`OOMKilled`) | Adding DataDog and MCP to the existing Spring Boot workloads exceeded the 2GB physical RAM limit of the `t2.small` instance. | Vertically scaled the AWS EC2 instance to `t2.medium` (4GB RAM) while maintaining SWAP. |
| **2** | Docker login failure: `command not found` & no local images visible | K3s uses isolated `containerd` natively, bypassing traditional Docker daemon tools. | Installed `docker.io`, exported images from K3s via `ctr`, and imported via `docker load`. |
| **3** | ECR Push Error: `repository does not exist` | AWS ECR does not auto-create repositories upon receiving a `docker push` command. | Manually provisioned `greencity-mcp` via `aws ecr create-repository`. |
| **4** | MCP Container `CrashLoopBackOff` immediately upon start | The default FastMCP `stdio` transport instantly receives `EOF` in a Kubernetes daemon context, causing a standard `sys.exit(0)`. | Transitioned the server to HTTP Server-Sent Events (SSE) via `mcp.run(transport="sse")` on `0.0.0.0:8000`. |
| **5** | Python `ModuleNotFoundError: mcp.server.fastmcp` | The `mcp` SDK published a breaking v2 release natively replacing `FastMCP` with `MCPServer`. | Pinned the dependency to legacy v1 via `pip install "mcp[cli]<2"` in the Dockerfile. |

---

## 6. Deliverables & State

* **Infrastructure State:** Stable on AWS `t2.medium`.
* **Artifact:** AWS ECR repositories (`greencity-backend`, `greencity-mcp`)
* **Source Code:** `mcp/server.py` (FastMCP HTTP Server)
* **Build Manifest:** `mcp/Dockerfile` (Python 3.11 with MCP v1 lock)
* **Orchestration Manifest:** `k8s/mcp-deployment.yaml` (Deployment + ClusterIP + PSS contexts)