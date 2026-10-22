# Step-by-Step Guide: Implementing CI/CD with GitHub Actions and Self-Hosted Runners

This guide details the steps taken to configure automated builds, GHCR publishing, and deployment to an Oracle Linux virtual machine for the GreenCity project.

---

## Step 1: Prepare the Target Environment

1. **Synchronize VM Time:**
   Ensure the target VM has the correct time to avoid SSL certificate errors during runner registration:
   ```bash
   sudo systemctl restart chronyd
   sudo chronyc makestep
   date
   ```

2. **Docker Permissions:**
   Ensure the user running the GitHub Action has passwordless Docker access:
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker
   ```

---

## Step 2: Install and Configure GitHub Self-Hosted Runner

1. In the GitHub repository, navigate to **Settings** -> **Actions** -> **Runners** -> **New self-hosted runner**.
2. Download and extract the runner software on the VM:
   ```bash
   mkdir actions-runner && cd actions-runner
   curl -o actions-runner-linux-x64-2.329.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.329.0/actions-runner-linux-x64-2.329.0.tar.gz
   tar xzf ./actions-runner-linux-x64-2.329.0.tar.gz
   ```
3. Authenticate using the token provided by GitHub:
   ```bash
   ./config.sh --url https://github.com/YOUR_ORG/GreenCity --token YOUR_TOKEN
   ```
4. Install and start the runner as a background systemd service:
   ```bash
   sudo ./svc.sh install
   sudo ./svc.sh start
   ```

---

## Step 3: Configure GitHub Actions Workflow

Create `.github/workflows/ci.yml` in your repository. This file uses a build matrix to parallelize image builds and a dependent job for deployment.

```yaml
name: GreenCity CI/CD Pipeline

on:
  push:
    branches: [ "main", "ci-cd" ]
  workflow_dispatch:

env:
  REGISTRY: ghcr.io

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    strategy:
      matrix:
        include:
          - service: backcore
            context: ./app/greencity-backcore
            image_name: greencity-backcore
          - service: backuser
            context: ./app/greencity-backuser
            image_name: greencity-backuser
          - service: frontend
            context: ./app/greencity-frontend
            image_name: greencity-frontend
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ github.repository_owner }}/${{ matrix.image_name }}
          tags: type=raw,value=latest
      - uses: docker/build-push-action@v5
        with:
          context: ${{ matrix.context }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    needs: build-and-push
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - run: |
          cd app
          docker compose pull
          docker compose up -d --remove-orphans
          docker image prune -f
```

---

## Step 4: Update Docker Compose Topology

Modify `app/docker-compose.yml` to point to the newly published GHCR images instead of building locally:

```yaml
services:
  backuser:
    image: ghcr.io/YOUR_GITHUB_USER/greencity-backuser:latest
    ...
  backcore1:
    image: ghcr.io/YOUR_GITHUB_USER/greencity-backcore:latest
    ...
  frontend:
    image: ghcr.io/YOUR_GITHUB_USER/greencity-frontend:latest
    ...
```

---

## Step 5: Registry Visibility & Validation

1. Navigate to **Packages** on your GitHub profile.
2. For each published package (`greencity-backcore`, `greencity-backuser`, `greencity-frontend`), go to **Package Settings**.
3. Under **Danger Zone**, change visibility to **Public** to allow the target VM to pull images without requiring a Personal Access Token (PAT).
4. Monitor the **Actions** tab on GitHub to verify successful end-to-end execution of both CI and CD jobs.
