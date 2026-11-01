# Step-by-Step Guide: Scaling Infrastructure, Deploying DataDog, AWS ECR, and MCP Server

A chronological, highly detailed technical execution guide documenting the transition of the GreenCity cluster from a lightweight environment to a production-ready state. This includes vertical EC2 scaling, applying DataDog telemetry, migrating to AWS ECR, and deploying a secure Model Context Protocol (MCP) server over SSE.

---

## Step 1: Git Branch Initialization and Cleanup

1. **Initialize Feature Branch**: Navigate to the project root and isolate the new feature work.
   ```bash
   cd /mnt/c/GreenCity
   git checkout -b infra-ecr-mcp
   ```

2. **Prevent Artifact Bloat**: Ensure heavy local image archives (`.tar`) from previous local-registry configurations are strictly ignored.
   ```bash
   grep -qxF '*.tar' .gitignore || echo "*.tar" >> .gitignore
   git add .gitignore
   ```

---

## Step 2: Infrastructure Compute Scaling (Vertical Scaling)

*Context: Running K3s, PostgreSQL, two Java Spring Boot applications, plus adding the DataDog Agent and MCP Server exceeds the memory constraints of a `t2.small` or `t2.micro` instance.*

1. **Stop the EC2 Instance**: Safely halt the current cluster node via AWS CLI.
   ```bash
   aws ec2 stop-instances --instance-ids <YOUR_INSTANCE_ID>
   aws ec2 wait instance-stopped --instance-ids <YOUR_INSTANCE_ID>
   ```

2. **Modify Instance Type**: Switch the compute capacity from `t2.small` (2 vCPU, 2GB RAM) to `t2.medium` (2 vCPU, 4GB RAM) to accommodate the increased JVM and telemetry footprint.
   ```bash
   aws ec2 modify-instance-attribute \
     --instance-id <YOUR_INSTANCE_ID> \
     --instance-type "{\"Value\": \"t2.medium\"}"
   ```

3. **Restart the Instance & Verify**:
   ```bash
   aws ec2 start-instances --instance-ids <YOUR_INSTANCE_ID>
   aws ec2 wait instance-running --instance-ids <YOUR_INSTANCE_ID>
   ```
   *(Note: Ensure the 4GB SWAP file created in previous deployments is still mounted and active via `free -h` after reboot).*

---

## Step 3: Directory Hierarchy Creation

Create the standard directory structure to house the new microservice code and Kubernetes manifests separately from existing components:

```bash
mkdir -p mcp k8s
```

---

## Step 4: Centralized Observability (DataDog)

Deploy the DataDog agent daemon across the K3s cluster. This configuration ensures host-level metrics and container stdout/stderr logs are routed automatically to the EU region without requiring sidecar containers.

1. **Install via Helm**:
   ```bash
   helm repo add datadog https://helm.datadoghq.com
   helm repo update

   helm upgrade --install datadog datadog/datadog \
     --namespace datadog --create-namespace \
     --set datadog.site='datadoghq.eu' \
     --set datadog.apiKey='<YOUR_DATADOG_API_KEY>' \
     --set datadog.logs.enabled=true \
     --set datadog.logs.containerCollectAll=true
   ```

2. **Validate Deployment**: Check that the DaemonSet has successfully scheduled pods on all nodes.
   ```bash
   kubectl get daemonset -n datadog
   kubectl logs -l app=datadog -n datadog --tail=50
   ```

---

## Step 5: Artifact Management (AWS ECR)

Shift away from loading local `.tar` files into K3s `containerd` by adopting a proper cloud container registry.

### 5.1. Create Private Cloud Repositories
Provision standard ECR repositories:
```bash
aws ecr create-repository --repository-name greencity-backend --region eu-central-1
aws ecr create-repository --repository-name greencity-mcp --region eu-central-1
```

### 5.2. Authenticate Kubernetes with ECR
Extract a temporary 12-hour authentication token from AWS and store it natively in Kubernetes as a Docker registry secret:
```bash
# Obtain token and create secret in one step
kubectl create secret docker-registry ecr-secret \
  --docker-server=054394900199.dkr.ecr.eu-central-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region eu-central-1) \
  --namespace=greencity
```

---

## Step 6: MCP Server Implementation

### 6.1. Core Application Logic (`mcp/server.py`)
Develop a FastMCP server to safely expose read-only database schema context to external AI models over HTTP SSE (Server-Sent Events).

```python
import os
import psycopg2
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("GreenCity MCP")
mcp.settings.host = "0.0.0.0"
mcp.settings.port = 8000

def get_db_connection():
    return psycopg2.connect(
        dbname=os.environ.get("DB_NAME", "greencity"),
        user=os.environ.get("DB_USER", "postgres"),
        password=os.environ.get("DB_PASSWORD", "postgres"),
        host=os.environ.get("DB_HOST", "postgres-service")
    )

@mcp.tool()
def get_events(limit: int = 10) -> str:
    """Returns database schema metadata for AI context injection"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        # Read-only query against information_schema to prevent SQL injection or data mutation
        cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public' LIMIT %s;", (limit,))
        tables = cur.fetchall()
        cur.close()
        conn.close()
        
        if not tables:
            return "No tables found in public schema."
            
        result = "Available GreenCity Database Tables:\n"
        for tbl in tables:
            result += f"- {tbl[0]}\n"
        return result
    except Exception as e:
        return f"Database integration error: {str(e)}"

if __name__ == "__main__":
    # Force SSE transport to keep the process alive in a K8s container
    mcp.run(transport="sse")
```

### 6.2. Containerization (`mcp/Dockerfile`)
Package the application securely. Pin the dependency to `mcp[cli]<2` to avoid breaking changes introduced in recent SDK releases.

```dockerfile
FROM python:3.11-slim
WORKDIR /app

# Install minimal dependencies without caching to reduce image bloat
RUN pip install --no-cache-dir "mcp[cli]<2" psycopg2-binary

COPY server.py /app/server.py

# Execute directly as the main process
ENTRYPOINT ["python", "server.py"]
```

### 6.3. Build and Cloud Registry Push
Authenticate your local Docker daemon with AWS, build the image, and push it upstream.
```bash
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin 054394900199.dkr.ecr.eu-central-1.amazonaws.com

docker build -t 054394900199.dkr.ecr.eu-central-1.amazonaws.com/greencity-mcp:latest mcp/
docker push 054394900199.dkr.ecr.eu-central-1.amazonaws.com/greencity-mcp:latest
```

---

## Step 7: Kubernetes Orchestration (`k8s/mcp-deployment.yaml`)

Define the deployment following Kubernetes Pod Security Standards (PSS) at the `restricted` tier.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: greencity-mcp
  namespace: greencity
spec:
  replicas: 1
  selector:
    matchLabels:
      app: greencity-mcp
  template:
    metadata:
      labels:
        app: greencity-mcp
    spec:
      imagePullSecrets:
        - name: ecr-secret # Injects the AWS authentication token
      securityContext:
        # PSS Restricted enforces non-root execution
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: mcp
          image: 054394900199.dkr.ecr.eu-central-1.amazonaws.com/greencity-mcp:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 8000
          env:
            - name: PYTHONDONTWRITEBYTECODE
              value: "1"
            - name: DB_HOST
              value: "postgres-service"
            - name: DB_NAME
              value: "greencity"
            - name: DB_USER
              value: "postgres"
            - name: DB_PASSWORD
              value: "postgres"
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"] # Drop all root Linux capabilities
          resources:
            requests:
              cpu: "50m"
              memory: "128Mi"
            limits:
              cpu: "200m"
              memory: "256Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: greencity-mcp-service
  namespace: greencity
spec:
  type: ClusterIP
  selector:
    app: greencity-mcp
  ports:
    - port: 8000
      targetPort: 8000
```

---

## Step 8: Troubleshooting & Root Cause Analysis

1. **Resource Exhaustion & Pod Eviction (`OOMKilled`)**:
   * *Problem:* Initial attempts to run K3s, Spring Boot, DataDog, and MCP concurrently on a `t2.small` (2GB RAM) caused kernel `OOMKiller` to terminate the PostgreSQL and Java pods. Node status flapped to `NotReady`.
   * *Fix:* Executed Step 2 to vertically scale the EC2 instance to `t2.medium` (4GB RAM) while maintaining the 4GB SWAP file.

2. **ECR Push Rejection (`repository does not exist`)**:
   * *Problem:* `docker push` failed because AWS ECR does not support auto-creation of repositories on push like some public registries.
   * *Fix:* Manually provisioned the `greencity-mcp` namespace via `aws ecr create-repository` prior to pushing.

3. **MCP Container `CrashLoopBackOff` on Startup**:
   * *Problem:* The default FastMCP `stdio` transport reads from standard input. In a detached Kubernetes container context, `stdin` immediately receives `EOF`, causing the Python process to exit cleanly (0).
   * *Fix:* Transitioned the server architecture to HTTP Server-Sent Events via `mcp.run(transport="sse")`, which spins up an internal Uvicorn web server bound to `0.0.0.0:8000`.

4. **Python `ModuleNotFoundError: mcp.server.fastmcp`**:
   * *Problem:* Automated builds broke because the official `mcp` SDK published a breaking v2 release that entirely restructured imports (replacing `FastMCP` with `MCPServer`).
   * *Fix:* Pinned the dependency to the stable v1 branch via `pip install "mcp[cli]<2"` in the `Dockerfile`.

---

## Step 9: Validation

1. **Apply Manifests to Cluster**:
   ```bash
   kubectl apply -f k8s/mcp-deployment.yaml
   ```

2. **Verify SSE Transport Connectivity**:
   Establish a temporary tunnel to the cluster-internal service and probe the SSE endpoint.
   ```bash
   kubectl port-forward -n greencity svc/greencity-mcp-service 8000:8000 &
   sleep 2
   curl -m 3 -i -N http://127.0.0.1:8000/sse
   ```
   *Expected Output (Confirms successful handshake and session creation):*
   ```http
   HTTP/1.1 200 OK
   server: uvicorn
   content-type: text/event-stream; charset=utf-8
   Transfer-Encoding: chunked

   event: endpoint
   data: /messages/?session_id=cdd74394d4744142a7818ce680944f8b
   ```
