# Task Execution Report: Unified Observability Pipeline (OpenTelemetry, Prometheus, Grafana & Splunk)

| Parameter | Details |
| :--- | :--- |
| **Project** | GreenCity |
| **Date** | October 26, 2026 |
| **Git Branches** | `observability-otel-splunk` |
| **Stack** | OpenTelemetry Collector Contrib, Prometheus, Grafana, Splunk Enterprise, Docker Compose |
| **Status** | Completed & Validated |

---

## 1. Executive Summary

This phase established a scalable, vendor-agnostic observability architecture for the GreenCity microservices ecosystem adhering to CNCF standards:
1. **Telemetry Ingestion & Processing (OpenTelemetry):** Deployed OpenTelemetry Collector Contrib as the central telemetry gateway, ingesting OTLP events, host performance metrics, container health stats, and application stdout/stderr streams.
2. **Time-Series Metric Storage (Prometheus):** Configured automated scraping of the OpenMetrics exporter (`greencity` namespace) to collect infrastructure and container utilization data.
3. **Data Visualization (Grafana):** Implemented automated datasource provisioning for Prometheus, enabling real-time dashboard inspection of CPU load, memory utilization, and container resource limits.
4. **Centralized Log Analytics & Security Auditing (Splunk Enterprise):** Enabled Splunk HTTP Event Collector (HEC) over TLS and integrated Docker's native `fluentd` logging driver, routing live application logs with automatic key-value field extraction.

---

## 2. Infrastructure, Topology & Integrated Services

| Component | Target / Environment | Role / Functionality | Connectivity / Transport |
| :--- | :--- | :--- | :--- |
| **`otel-collector`** | Docker (`monitoring-net`) | Unified telemetry router, metric processor, and log forwarder | OTLP (`4317`/`4318`), Fluentd (`24224`), Prom (`8889`) |
| **`prometheus`** | Docker (`monitoring-net`) | Time-series database (TSDB) scraping OTel metrics | HTTP Pull (`:8889`, `:9090`) |
| **`grafana`** | Docker (`monitoring-net`) | Metric visualization and dashboard UI | HTTP (`:3000`) |
| **`splunk`** | Docker (`monitoring-net`) | Centralized log indexing, HEC receiver, and SPL analytics engine | HTTPS / TLS HEC (`:8088`), Web UI (`:8000`) |
| **`greencity-log-sim`** | Docker Host | Application log generator using native Docker logging driver | Fluent forward protocol (`localhost:24224`) |

---

## 3. Implementation Details

### 3.1. OpenTelemetry Collector Pipeline (`monitoring/otel-collector/otel-collector-config.yml`)
* **Dual-Pipeline Architecture:** Decoupled `metrics` and `logs` ingestion paths with shared batching and memory management.
* **Receivers:**
  * `otlp`: Ingests native gRPC (`:4317`) and HTTP (`:4318`) telemetry payloads.
  * `hostmetrics`: Samples host CPU, memory, disk I/O, network traffic, and system load at 10-second intervals.
  * `docker_stats`: Scrapes container-level CPU and memory consumption directly via the Docker daemon socket (`unix:///var/run/docker.sock`) targeting API version `1.40`.
  * `fluentforward`: Real-time ingestion endpoint on port `24224` (TCP/UDP) capturing stdout/stderr from Docker containers.
* **Processors:**
  * `memory_limiter`: Set to a 75% hard limit with a 20% spike threshold to prevent process eviction.
  * `batch`: Groups events into chunks of 128 items or flushes on a 3-second timeout.
* **Exporters:**
  * `prometheus`: Serves an OpenMetrics scrape endpoint on port `:8889` under the `greencity` namespace.
  * `splunk_hec`: Dispatches batched logs over TLS to `https://splunk:8088/services/collector` using bearer token authentication.

### 3.2. Prometheus & Grafana Provisioning
* **Prometheus Configuration (`monitoring/prometheus/prometheus.yml`):** Set a global 10-second scrape interval targeting `otel-collector:8889`.
* **Automated Datasource Setup (`monitoring/grafana/provisioning/datasources/datasource.yml`):** Automatically registers Prometheus as the default datasource on container bootstrap, eliminating manual UI setup.

### 3.3. Splunk Enterprise Setup & Orchestration
* **Docker Compose Orchestration (`monitoring/docker-compose.monitoring.yml`):** Deployed official Splunk image in `monitoring-net` with persistent storage volumes.
* **HEC Token Integration:** Initialized HTTP Event Collector with pre-shared token `00000000-0000-0000-0000-000000000000` bound to `index="main"` and `sourcetype="docker:container:log"`.

### 3.4. Docker Container Log Forwarding
* Attached Docker's native `fluentd` log driver directly to running containers without requiring application-level code modifications.
* Configured asynchronous non-blocking log shipping (`fluentd-async=true`) targeting `localhost:24224`.

---

## 4. Verification & Observability Metrics

### 4.1. Prometheus Target & Infrastructure Metrics
* Target `http://otel-collector:8889/metrics` transitioned to **HEALTHY / UP = 1**.
* Validated real-time PromQL time-series metrics:
  * `greencity_system_cpu_time_seconds_total`
  * `greencity_system_cpu_load_average_1m`
  * `greencity_system_memory_usage_bytes`
  * `container_cpu_usage_total` and `container_memory_usage_total`

### 4.2. Splunk Real-Time Container Ingestion
* Deployed `greencity-log-sim` streaming simulated authentication JSON logs every 3 seconds.
* Validated live log arrival in Splunk Search & Reporting:
  ```spl
  index=* sourcetype="docker:container:log"
  ```
* Confirmed dynamic schema parsing across all payload fields:
  * `service` = `greencity-backend`
  * `level` = `INFO`
  * `latency_ms` = extracted integer metric
  * `msg` = `JWT validation passed for user_id=...`
  * `container_name` = `greencity-log-sim`
* Verified manual OTLP HTTP ingestion via `/v1/logs` endpoint (`HTTP 200 OK`).

---

## 5. Challenges & Root Cause Analysis (RCA)

| # | Encountered Issue | Root Cause | Implemented Resolution |
| :-: | :--- | :--- | :--- |
| **1** | Splunk container exit: `License not accepted, adjust SPLUNK_GENERAL_TERMS` | Newer Splunk base images mandate explicit agreement to General Terms. | Added `SPLUNK_GENERAL_TERMS=--accept-sgt-current-at-splunk-com` to Compose environment variables. |
| **2** | Splunk HEC rejected incoming OTel log batches | OTel exporter configured for cleartext `http://`, but Splunk HEC strictly enforces SSL/TLS by default. | Updated endpoint to `https://splunk:8088/services/collector` and enabled `tls.insecure_skip_verify: true`. |
| **3** | WSL2 bind-mount desynchronization (`failed to create shim task`) | Executing `sed -i` within WSL2 created a new file inode, breaking the active Windows Docker Desktop mount. | Recreated container instances using `docker compose up -d --force-recreate`. |
| **4** | Docker daemon socket permission denied (`connect: permission denied unix:///var/run/docker.sock`) | OTel Collector process ran under an unprivileged user (UID `10001`) without host socket rights. | Granted host socket permissions (`chmod 666 /var/run/docker.sock`) and set `user: "0:0"` in Docker Compose. |
| **5** | Docker API version error (`client version 1.25 is too old. Minimum supported API version is 1.40`) | OTel `docker_stats` receiver defaulted to legacy API `1.25`, which modern Docker engines reject. | Explicitly declared `api_version: "1.40"` under `receivers.docker_stats`. |
| **6** | Fluentd log driver syntax rejection (`unknown log opt fluentd-async-connect`) | Deprecated option naming in `docker run` parameters. | Corrected parameter syntax to `--log-opt fluentd-async=true`. |

---

## 6. Deliverables & State

* **Orchestration Manifest:** `monitoring/docker-compose.monitoring.yml`
* **OTel Hub Configuration:** `monitoring/otel-collector/otel-collector-config.yml`
* **Scrape Configuration:** `monitoring/prometheus/prometheus.yml`
* **Datasource Auto-Provisioning:** `monitoring/grafana/provisioning/datasources/datasource.yml`