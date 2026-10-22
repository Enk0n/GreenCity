# Task Execution Report: Continuous Integration & Continuous Delivery (CI/CD)

| Parameter | Details | 
| :--- | :--- | 
| **Project** | GreenCity | 
| **Date** | October 22, 2026 | 
| **Task** | Implement a Continuous Integration/Continuous Delivery (Trello #10) | 
| **Stack** | GitHub Actions, GHCR, Docker Compose, Linux Self-hosted Runner | 
| **Status** | Completed & Validated | 

## 1. Executive Summary

This task successfully implemented a complete end-to-end CI/CD pipeline for the GreenCity project using GitHub Actions. The infrastructure now automatically compiles the source code, builds Docker images using a multi-stage approach, publishes them to the GitHub Container Registry (GHCR), and deploys the updated containers to an on-premise virtual machine via a securely connected self-hosted runner.

## 2. CI/CD Architecture

### 2.1. Continuous Integration (CI)
* **Trigger:** Initiated automatically on `push` or `pull_request` to the main branches, or manually via `workflow_dispatch`.
* **Matrix Build:** Utilizes a build matrix to run parallel jobs for `backcore`, `backuser`, and `frontend`, significantly reducing total build time.
* **Multi-stage Dockerfiles:** Source code is compiled (Maven/Node.js) directly inside the Docker build process, eliminating the need for standalone build jobs and artifact passing in GitHub Actions.
* **Registry:** Images are tagged with the commit SHA and `latest`, then pushed to GitHub Container Registry (`ghcr.io`).

### 2.2. Continuous Deployment (CD)
* **Runner:** A GitHub Self-hosted runner was installed and configured as a systemd service (`actions.runner.service`) on the target Oracle Linux VM (`greencity-app`).
* **Deployment Job:** Conditional job (`deploy`) that waits for the CI phase to complete. It executes directly on the VM, pulling the latest images from GHCR and executing `docker compose up -d --remove-orphans` for zero-downtime recreation.

## 3. Implementation Details

* **Workflow File:** Created `.github/workflows/ci.yml` defining the `build-and-push` and `deploy` stages.
* **Compose Update:** Refactored the production `docker-compose.yml` to replace local image builds with fully qualified GHCR image URIs (e.g., `ghcr.io/enk0n/greencity-backcore:latest`).
* **Permissions:** Granted `packages: write` permissions to the `GITHUB_TOKEN` for registry access and configured GHCR packages as Public to allow unauthenticated pulls on the target server.

## 4. Challenges & Root Cause Analysis (RCA)

| # | Problem Encountered | Root Cause | Implemented Solution | 
| :-: | :--- | :--- | :--- | 
| **1** | `Invalid workflow file: You have an error in your yaml syntax` | Bash command string (`cat << EOF`) was accidentally piped into the workflow file content. | Cleaned up the YAML file using `sed` to remove arbitrary shell commands from the document header. | 
| **2** | GitHub Actions panel redirected to templates instead of showing runs. | GitHub does not discover or execute workflows on `push` from secondary branches unless the workflow file exists in the default branch. | Temporarily set `ci-cd` as the Default branch in repository settings to force workflow discovery without merging. | 
| **3** | Runner registration failed: `The SSL connection could not be established` & `404 Not Found`. | VM clock drift (time synchronization failure after sleep mode) caused the GitHub SSL certificate validation to fail and the registration token to expire. | Restarted `chronyd`, forced time sync (`chronyc makestep`), regenerated the token, and re-registered the runner. | 
| **4** | Deployment job stuck in `Waiting for a runner...` | The self-hosted runner service lost session state due to the aforementioned time drift. | Stopped the daemon, cleared old credentials (`.runner`, `.credentials`), re-authenticated, and restarted the systemd service. | 

## 5. Deliverables

* **GitHub Actions Workflow:** `.github/workflows/ci.yml`
* **Docker Compose Topology:** `app/docker-compose.yml` (GHCR-ready)
* **Registered Runner:** Active `greencity-app` self-hosted runner.