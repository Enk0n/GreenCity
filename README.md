# Step-by-Step Guide: Vulnerability and Dependency Scanning with Trivy and Snyk in CI/CD

This technical guide outlines the implementation of container image scanning and Software Composition Analysis (SCA) within the GreenCity CI/CD pipeline using **Trivy** and **Snyk**, fulfilling the security requirements of Trello Card #29.

---

## Step 1: Branch Setup and Workspace Isolation

Create and switch to a dedicated feature branch from `ci-cd` to keep security pipeline experimentation isolated from other tracks:

```bash
cd /mnt/c/GreenCity
git checkout ci-cd
git checkout -b security-scan
```

---

## Step 2: Snyk Authentication & GitHub Secret Setup

Snyk requires an API token to communicate with its vulnerability intelligence database during CLI execution:

1. Log in to [snyk.io](https://snyk.io/) using your GitHub credentials.
2. Navigate to **Account settings** → **General**.
3. Under the **Auth Token** section, click **`click to show`** in the **KEY** field to reveal your API key.
4. Add the token to GitHub:
   * Open your GitHub repository → **Settings** → **Secrets and variables** → **Actions**.
   * Click **New repository secret**.
   * Set **Name** to `SNYK_TOKEN` and paste your key into **Secret**.
   * Click **Add secret**.

*(Trivy does not require external tokens as it fetches vulnerability databases automatically during execution).*

---

## Step 3: Implement the Security Workflow

Create the security workflow file `.github/workflows/security.yml` configured to run Snyk for dependency audits and Trivy for container image inspection:

```yaml
name: Security & Vulnerability Scanning (Trivy & Snyk)

on:
  push:
    branches:
      - security-scan
      - main
  pull_request:
    branches:
      - main
  workflow_dispatch:

jobs:
  # -------------------------------------------------------------
  # Job 1: Snyk SCA (Software Composition Analysis)
  # -------------------------------------------------------------
  snyk-sca:
    name: Snyk Dependency Scan
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'

      - name: Install Snyk CLI
        uses: snyk/actions/setup@master

      - name: Snyk test Backcore dependencies
        continue-on-error: true
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
        run: |
          cd app/greencity-backcore
          chmod +x mvnw || true
          snyk test --command=mvn --severity-threshold=high

      - name: Snyk test Frontend dependencies
        continue-on-error: true
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
        run: |
          cd app/greencity-frontend
          snyk test --strict-out-of-sync=false --severity-threshold=high

  # -------------------------------------------------------------
  # Job 2: Trivy Container Image Scan
  # -------------------------------------------------------------
  trivy-image-scan:
    name: Trivy Container Image Scan
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        image:
          - greencity-backcore
          - greencity-backuser
          - greencity-frontend

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Run Trivy vulnerability scanner on GHCR image
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'ghcr.io/enk0n/${{ matrix.image }}:latest'
          format: 'table'
          exit-code: '0'
          ignore-unfixed: true
          vuln-type: 'os,library'
          severity: 'CRITICAL,HIGH'
```

---

## Step 4: Resolving Common Configuration Challenges

During setup, three specific execution hurdles were identified and resolved:

1. **Permission Denied (`exit code: -13` / `EACCES`):**
   * *Problem:* Snyk defaulted to executing the local `./mvnw` script, which lacked executable permissions inside the runner workspace.
   * *Fix:* Added `chmod +x mvnw || true` and explicitly forced the system Maven binary using the flag `--command=mvn`.
2. **Lockfile Desynchronization (`Status 422 Unprocessable Entity`):**
   * *Problem:* `@types/google-one-tap` was present in `package.json` but missing from `package-lock.json`. Snyk halts execution by default on out-of-sync dependency manifests.
   * *Fix:* Passed `--strict-out-of-sync=false` to evaluate available dependencies without forcing a full `npm install`.
3. **Non-blocking Pipeline Integration:**
   * *Problem:* Snyk and Trivy return non-zero exit codes (e.g., `exit code 1` or `2`) when high/critical issues are detected, causing pipeline failure.
   * *Fix:* Added `continue-on-error: true` for Snyk and `exit-code: '0'` for Trivy to ensure security scanning acts as an informative audit stage rather than breaking active builds.

---

## Step 5: Commit and Register Workflow

1. Commit the configuration file:
   ```bash
   cd /mnt/c/GreenCity
   git add .github/workflows/security.yml
   git commit -m "ci(security): implement Trivy container scans and Snyk SCA audit"
   git push -u origin security-scan
   ```

2. Register the workflow in GitHub:
   * Navigate to **Settings** → **General**.
   * Under **Default branch**, temporarily switch to **`security-scan`** so GitHub registers the new workflow file in the **Actions** tab.
   * Go to the **Actions** tab and trigger **Security & Vulnerability Scanning (Trivy & Snyk)**.

---

## Step 6: Snyk Web Dashboard Integration

To establish continuous tracking and automated remediation capabilities:

1. Open [app.snyk.io](https://app.snyk.io/) and navigate to the project import page.
2. Choose **GitHub** as the source and select the **`GreenCity`** repository.
3. Click **Add selected repositories**.
4. Snyk automatically detects and parses all 15 project manifests across backend Maven POMs, frontend package manifests, and Kubernetes Helm charts.

---

## Step 7: Verifying Scan Results

1. **In GitHub Actions Console:**
   * Open the **Actions** run and expand **`Trivy Container Image Scan (greencity-backcore)`** → **`Run Trivy vulnerability scanner on GHCR image`**. View the tabular output listing CVEs, severity levels, installed package versions, and fixed versions.
   * Select **`Snyk Dependency Scan`** → **`Snyk test Backcore dependencies`** or **`Snyk test Frontend dependencies`** to view identified library vulnerabilities and target upgrade paths.
2. **In Snyk Web Dashboard:**
   * Open `https://app.snyk.io/org/enk0n` to review the project dashboard.
   * The breakdown highlights vulnerability severity levels across files, including `core/pom.xml` (26 Critical, 110 High) and `package.json` (5 Critical, 48 High).
