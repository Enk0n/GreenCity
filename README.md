# Step-by-Step Guide: Enterprise Observability Pipeline Setup

**Project:** GreenCity  
**Stack:** OpenTelemetry Collector Contrib, Prometheus, Grafana, Splunk Enterprise  
**Standard:** CNCF Unified Telemetry Hub (Metrics, Container Stats & Streaming Logs)  

---

## 1. Overview & Architecture

This guide details the reproducible setup of a decoupled, vendor-agnostic observability stack for GreenCity.

```
+-------------------------------------------------------------+
|                     GreenCity Ecosystem                     |
|  Microservices / Containers (stdout/stderr & Docker Engine) |
+-------------------------------------------------------------+
               |                               |
     Docker Fluentd Driver           Docker Daemon Socket
        (port 24224)              (/var/run/docker.sock)
               |                               |
               v                               v
         fluentforward                    docker_stats / hostmetrics
               \                               /
                v                             v
       +-----------------------------------------------+
       |        OpenTelemetry Collector Contrib        |
       |     Pipelines: Metrics & Centralized Logs     |
       +-----------------------------------------------+
               /                               \
     Prometheus Pull                         Splunk HEC Push
      (:8889 OpenMetrics)                     (:8088 HTTPS)
             |                                       |
             v                                       v
      +--------------+                       +---------------+
      |  Prometheus  |                       |     Splunk    |
      | TSDB (:9090) |                       |   Enterprise  |
      +--------------+                       | Index: "main" |
             |                               +---------------+
             v                                       |
      +--------------+                               v
      |   Grafana    |                       | Splunk Search |
      |  UI (:3000)  |                       |   UI (:8000)  |
      +--------------+                       +---------------+
```

---

## 2. Directory Structure Setup

From the repository root (`/mnt/c/GreenCity`), initialize the monitoring workspace:

```bash
mkdir -p monitoring/otel-collector
mkdir -p monitoring/prometheus
mkdir -p monitoring/grafana/provisioning/datasources
mkdir -p docs
```

Target structure:
```
monitoring/
├── docker-compose.monitoring.yml
├── otel-collector/
│   └── otel-collector-config.yml
├── prometheus/
│   └── prometheus.yml
└── grafana/
    └── provisioning/
        └── datasources/
            └── datasource.yml
```

---

## 3. Configuration Files

### 3.1. OpenTelemetry Collector (`monitoring/otel-collector/otel-collector-config.yml`)

The collector serves as the central hub:
* Ingests native OTLP (`4317`/`4318`), host resources, container metrics via Docker socket, and application logs via Fluentd forward protocol.
* Exports time-series metrics for Prometheus and secure HTTPS payloads to Splunk HEC.

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

  # Host hardware & OS resource metrics
  hostmetrics:
    collection_interval: 10s
    scrapers:
      cpu:
      memory:
      disk:
      load:
      network:

  # Container metrics directly from Docker daemon socket
  docker_stats:
    endpoint: "unix:///var/run/docker.sock"
    collection_interval: 10s
    timeout: 5s
    api_version: "1.40"

  # Container logs receiver via Docker fluentd logging driver
  fluentforward:
    endpoint: 0.0.0.0:24224

processors:
  batch:
    timeout: 3s
    send_batch_size: 128
  memory_limiter:
    check_interval: 1s
    limit_percentage: 75
    spike_limit_percentage: 20

exporters:
  # Expose scrape endpoint for Prometheus
  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: "greencity"

  # Forward logs to Splunk Enterprise via HEC over TLS
  splunk_hec:
    token: "00000000-0000-0000-0000-000000000000"
    endpoint: "https://splunk:8088/services/collector"
    source: "greencity:docker"
    sourcetype: "docker:container:log"
    index: "main"
    tls:
      insecure_skip_verify: true

  # Real-time stdout debugging in collector logs
  debug:
    verbosity: basic

service:
  pipelines:
    metrics:
      receivers: [otlp, hostmetrics, docker_stats]
      processors: [memory_limiter, batch]
      exporters: [prometheus, debug]
    logs:
      receivers: [otlp, fluentforward]
      processors: [memory_limiter, batch]
      exporters: [splunk_hec, debug]
```

---

### 3.2. Prometheus Configuration (`monitoring/prometheus/prometheus.yml`)

Instruct Prometheus to scrape the OpenTelemetry exporter endpoint:

```yaml
global:
  scrape_interval: 10s
  evaluation_interval: 10s

scrape_configs:
  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8889']

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
```

---

### 3.3. Grafana Datasource Auto-Provisioning (`monitoring/grafana/provisioning/datasources/datasource.yml`)

Eliminates manual Web UI setup by injecting the Prometheus datasource on launch:

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
```

---

### 3.4. Docker Compose Orchestration (`monitoring/docker-compose.monitoring.yml`)

Orchestrates all four components inside an isolated bridge network (`monitoring-net`):

```yaml
version: '3.8'

services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.96.0
    container_name: greencity-otel-collector
    restart: unless-stopped
    user: "0:0"
    command: ["--config=/etc/otelcol-contrib/config.yaml"]
    volumes:
      - ./otel-collector/otel-collector-config.yml:/etc/otelcol-contrib/config.yaml:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - "4317:4317"     # OTLP gRPC
      - "4318:4318"     # OTLP HTTP
      - "8889:8889"     # Prometheus metrics
      - "24224:24224"   # Fluentforward TCP (Docker logs)
      - "24224:24224/udp"
    networks:
      - monitoring-net

  prometheus:
    image: prom/prometheus:v2.50.0
    container_name: greencity-prometheus
    restart: unless-stopped
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"
    networks:
      - monitoring-net

  grafana:
    image: grafana/grafana:10.3.3
    container_name: greencity-grafana
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - grafana_data:/var/lib/grafana
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
    networks:
      - monitoring-net

  splunk:
    image: splunk/splunk:latest
    container_name: greencity-splunk
    restart: unless-stopped
    environment:
      - SPLUNK_GENERAL_TERMS=--accept-sgt-current-at-splunk-com
      - SPLUNK_START_ARGS=--accept-license
      - SPLUNK_PASSWORD=DevOpsPass123!
      - SPLUNK_HEC_TOKEN=00000000-0000-0000-0000-000000000000
    ports:
      - "8000:8000"   # Splunk Web UI
      - "8088:8088"   # Splunk HEC (HTTP Event Collector)
    volumes:
      - splunk_data:/opt/splunk/var
    networks:
      - monitoring-net

networks:
  monitoring-net:
    driver: bridge

volumes:
  prometheus_data:
  grafana_data:
  splunk_data:
```

---

## 4. Host Permissions & Deployment

### 4.1. Grant Docker Socket Access
In WSL2/Linux environments, ensure read/write access to the host daemon socket:
```bash
sudo chmod 666 /var/run/docker.sock
```

### 4.2. Start the Stack
```bash
cd /mnt/c/GreenCity/monitoring
docker compose -f docker-compose.monitoring.yml up -d
```

### 4.3. Validate Running Containers
```bash
docker compose -f docker-compose.monitoring.yml ps
```
All four containers (`greencity-otel-collector`, `greencity-prometheus`, `greencity-grafana`, `greencity-splunk`) must transition to state **`Up`** (Splunk will indicate `Up (healthy)` once initialized).

---

## 5. Connecting Real Application Logs

To stream container stdout/stderr into Splunk without code modification, attach the native `fluentd` log driver.

### 5.1. Launching Live Container Log Simulator
```bash
docker rm -f greencity-log-sim 2>/dev/null

docker run -d --name greencity-log-sim \
  --log-driver=fluentd \
  --log-opt fluentd-address=localhost:24224 \
  --log-opt fluentd-async=true \
  --log-opt tag="greencity.backend.auth" \
  busybox sh -c 'while true; do echo "{\"timestamp\":\"$(date -u +%FT%TZ)\",\"level\":\"INFO\",\"service\":\"greencity-backend\",\"msg\":\"JWT validation passed for user_id=$((RANDOM % 100))\",\"latency_ms\":$((RANDOM % 50 + 5))}"; sleep 3; done'
```

### 5.2. Applying to Production Compose Services
To stream logs from live GreenCity microservices (e.g., `greencity-backcore`), append the `logging` directive:
```yaml
services:
  backcore:
    image: greencity-backcore:latest
    logging:
      driver: "fluentd"
      options:
        fluentd-address: "localhost:24224"
        fluentd-async: "true"
        tag: "greencity.microservice.backcore"
```

---

## 6. End-to-End Verification & Querying

### 6.1. Prometheus Target Status
* Open `http://localhost:9090/targets` in a browser.
* The `otel-collector` endpoint (`http://otel-collector:8889`) must display state **UP**.

### 6.2. Grafana Dashboards
* Open `http://localhost:3000` (User: `admin` | Password: `admin`).
* Navigate to **Explore** (Compass icon), verify datasource is set to **Prometheus**.
* Switch to **Code** mode and test metrics:
  * **System Load:** `greencity_system_cpu_load_average_1m`
  * **CPU Utilization:** `sum by (state) (rate(greencity_system_cpu_time_seconds_total[1m]))`
  * **Memory Usage:** `greencity_system_memory_usage_bytes`
  * **Container Memory:** `container_memory_usage_total`

### 6.3. Splunk Enterprise Search
* Open `http://localhost:8000` (User: `admin` | Password: `DevOpsPass123!`).
* Go to **Search & Reporting**.
* Query incoming container logs:
  ```spl
  index=* sourcetype="docker:container:log"
  ```
* Perform analytical aggregations over parsed JSON fields:
  ```spl
  index=* sourcetype="docker:container:log" | stats avg(latency_ms) by service, level
  ```

---

## 7. Troubleshooting Runbook

| Failure Pattern | Root Cause | Fix / Resolution |
| :--- | :--- | :--- |
| **Splunk container restarts continuously** | Unaccepted license terms in newer official images. | Set `SPLUNK_GENERAL_TERMS=--accept-sgt-current-at-splunk-com` in Compose env. |
| **Splunk HEC drops OTel connections** | HEC port `8088` requires SSL by default; OTel pointed to `http://`. | Set exporter endpoint to `https://splunk:8088/services/collector` with `tls.insecure_skip_verify: true`. |
| **WSL2 Docker bind-mount failure on reload** | Modifying config via `sed -i` altered the file inode. | Run `docker compose up -d --force-recreate otel-collector`. |
| **OTel Collector: Docker socket permission denied** | Non-root container UID lacks access to `/var/run/docker.sock`. | Run `sudo chmod 666 /var/run/docker.sock` and declare `user: "0:0"` on `otel-collector`. |
| **OTel Collector: Docker API client version too old (1.25)** | Default client API version rejected by newer host Docker engines. | Add `api_version: "1.40"` under `receivers.docker_stats`. |
| **`docker run: unknown log opt fluentd-async-connect`** | Deprecated option naming. | Use `--log-opt fluentd-async=true`. |
