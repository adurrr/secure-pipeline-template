# Security Pipeline Components

This document provides official definitions, integration guides, and best practices for each security component used in the pipeline.

---

## Table of Contents

- [Overview](#overview)
- [Semgrep (SAST)](#semgrep-sast)
- [Trivy (SCA / Container / IaC)](#trivy-sca--container--iac)
- [Hadolint (Dockerfile Linter)](#hadolint-dockerfile-linter)
- [Gitleaks (Secret Detection)](#gitleaks-secret-detection)
- [Checkov (IaC Security Scanner)](#checkov-iac-security-scanner)
- [Conftest (Policy Testing)](#conftest-policy-testing)
- [OPA / Rego (Policy Engine)](#opa--rego-policy-engine)
- [GitHub Actions (CI/CD)](#github-actions-cicd)
- [Pipeline Integration Map](#pipeline-integration-map)

---

## Overview

The secure pipeline uses six independent security gates, each serving a distinct purpose:

```
push → lint → SAST → SCA → build → image-scan → policy-check → deploy
         │       │      │       │         │              │
      Hadolint  Semgrep Trivy  Trivy    Trivy       Conftest/OPA
                Gitleaks       (fs)    (image)
                Checkov
```

Every gate must pass before deployment proceeds. A failure in any gate blocks the pipeline.

---

## Semgrep (SAST)

### Official Definition

Semgrep is a fast, open-source static analysis tool that searches code for bugs, enforces coding standards, and detects security vulnerabilities across 30+ languages. It uses pattern-matching rules rather than abstract interpretation, making it fast and easy to write custom rules.

- **Website:** https://semgrep.dev
- **Repository:** https://github.com/semgrep/semgrep
- **License:** LGPL 2.1 (core), proprietary (Pro rules)

### How It Connects to the Pipeline

**CI Integration** (`.github/workflows/ci.yml`):
```yaml
- name: Run Semgrep SAST
  uses: semgrep/semgrep-action@v1
  with:
    config: >-
      p/python
      p/flask
      p/owasp-top-ten
      p/secrets
```

**Local Integration** (`scripts/scan.sh`):
```bash
semgrep scan --config "$ROOT/.semgrep.yml" --config auto "$ROOT/app/" --error --severity ERROR
```

**Custom Rules** (`.semgrep.yml`):
The project defines custom rules for:
- Hardcoded secrets detection
- Debug mode prevention
- Shell injection prevention (`subprocess` with `shell=True`)

### Best Practices

1. **Pin action version**: Use `semgrep/semgrep-action@v1` (not `@master`) for stability
2. **Use custom rules alongside registry rules**: The project's `.semgrep.yml` extends community rules with project-specific checks
3. **Scope rules with `paths.include`**: Limit rules to relevant directories (e.g., `app/`) to reduce false positives
4. **Set `--severity ERROR` in CI**: Only block on errors; let warnings pass through
5. **SARIF upload**: Always upload SARIF results with `if: always()` so findings appear in GitHub Security tab
6. **Dependabot exclusion**: Add `if: (github.actor != 'dependabot[bot]')` to avoid permission issues on automated PRs

### Common Pitfalls

- **Missing `security-events: write` permission**: Blocks SARIF upload to GitHub
- **No `SEMGREP_APP_TOKEN`**: Without it, only community rules run (no Pro rules)
- **Inconsistent config between local and CI**: Always use the same rule set locally and in CI

---

## Trivy (SCA / Container / IaC)

### Official Definition

Trivy is a comprehensive security scanner by Aqua Security that detects vulnerabilities, misconfigurations, secrets, and license issues in container images, filesystems, Git repositories, and IaC files (Terraform, Kubernetes, Dockerfile, etc.).

- **Website:** https://trivy.dev
- **Repository:** https://github.com/aquasecurity/trivy
- **License:** Apache 2.0

### How It Connects to the Pipeline

Trivy is used in three scanning modes:

**1. Filesystem scan (SCA)** — in `security-scan` job:
```yaml
- name: Install Trivy
  run: |
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
      | sudo sh -s -- -b /usr/local/bin

- name: Scan dependencies with Trivy
  continue-on-error: true
  run: |
    trivy fs --format sarif --output trivy-sca.sarif \
      --severity CRITICAL,HIGH --exit-code 1 app/
```

**2. Container image scan** — in `build` job:
```yaml
- name: Scan container image
  continue-on-error: true
  run: |
    trivy image --format sarif --output trivy-image.sarif \
      --severity CRITICAL,HIGH --exit-code 1 \
      ${{ env.IMAGE_NAME }}:${{ github.sha }}
```

**3. IaC misconfiguration scan** — in `iac-scan` job:
```yaml
- name: Scan Terraform misconfigurations with Trivy
  continue-on-error: true
  run: |
    trivy fs --format sarif --output trivy-iac.sarif \
      --scanners misconfig --severity CRITICAL,HIGH --exit-code 1 terraform/
```

**Local Integration** (`scripts/scan.sh`):
```bash
trivy fs "$ROOT/app/" --severity CRITICAL,HIGH --exit-code 1
trivy image "$IMAGE" --severity CRITICAL,HIGH --exit-code 1
```

### Best Practices

1. **Use the official install script**: Do NOT use `aquasecurity/trivy-action` — it fails on GitHub API rate limits in CI. Use the install script instead:
   ```bash
   curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
     | sudo sh -s -- -b /usr/local/bin
   ```
2. **`continue-on-error: true`**: Always set this on Trivy scan steps so the pipeline doesn't hard-fail before SARIF upload
3. **Guard SARIF uploads**: Use `if: always() && hashFiles('trivy-*.sarif') != ''` to only upload when results exist
4. **Severity filtering**: Use `--severity CRITICAL,HIGH` to focus on actionable findings
5. **Use `--scanners misconfig`** for IaC: This scans Terraform files for misconfigurations without running vulnerability checks
6. **Cache the vulnerability DB**: Consider using `actions/cache` for the Trivy DB to speed up runs

### Common Pitfalls

- **GitHub API rate limits**: The `trivy-action` can fail on rate limits — use the install script instead
- **Exit code confusion**: `--exit-code 1` fails the step on findings; `--exit-code 0` passes regardless
- **Missing SARIF files**: If Trivy finds no vulnerabilities, it may not create a SARIF file — guard uploads with `hashFiles()`

---

## Hadolint (Dockerfile Linter)

### Official Definition

Hadolint is a Dockerfile linter that parses Dockerfiles into an AST and performs rules on them. It leverages ShellCheck for linting Bash code within `RUN` instructions. It enforces Docker best practices like pinned versions, non-root users, and proper instruction usage.

- **Repository:** https://github.com/hadolint/hadolint
- **License:** GPL 3.0

### How It Connects to the Pipeline

**CI Integration** (`.github/workflows/ci.yml`):
```yaml
- name: Lint Dockerfile
  uses: hadolint/hadolint-action@v3.1.0
  with:
    dockerfile: docker/Dockerfile
```

**Local Integration** (`scripts/scan.sh`):
```bash
hadolint "$ROOT/docker/Dockerfile"
```

**Conftest Policy** (`policies/conftest/dockerfile.rego`):
The project also validates Dockerfiles against custom OPA policies:
- No `:latest` tags
- Must include `USER` instruction
- No piping `curl` to `sh`
- No privileged ports (< 1024, except 80 and 443)
- No passwords or secrets in `ENV`

### Best Practices

1. **Pin action version**: Use `hadolint/hadolint-action@v3.1.0` (not `@master`)
2. **Use `.hadolint.yaml` for configuration**: Centralize ignore rules rather than inline pragmas
3. **Inline ignores for exceptions**: Use `# hadolint ignore=RULE` for one-off suppressions with comments explaining why
4. **Set `failure-threshold: warning`**: Catch info-level issues in CI without failing on style issues
5. **Common rules to consider ignoring**: `DL3008` (pin apt versions) is often too noisy

### Key Rules Reference

| Rule | Severity | Description |
|------|----------|-------------|
| DL3000 | error | Use absolute WORKDIR paths |
| DL3002 | warning | Last USER should not be root |
| DL3006 | warning | Always tag FROM images explicitly |
| DL3007 | warning | Do not use `:latest` tag |
| DL3008 | warning | Pin apt-get package versions |
| DL3020 | error | Use COPY instead of ADD for files |
| DL3025 | warning | Use JSON notation for CMD/ENTRYPOINT |
| DL4006 | warning | Set pipefail before RUN with pipes |

---

## Gitleaks (Secret Detection)

### Official Definition

Gitleaks is a secret detection tool that scans git repositories (commit history, working tree, or remote URLs) for passwords, API keys, tokens, and other sensitive information using pattern matching and entropy analysis.

- **Repository:** https://github.com/gitleaks/gitleaks
- **License:** MIT

### How It Connects to the Pipeline

**CI Integration** (`.github/workflows/ci.yml`):
```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0  # CRITICAL: gitleaks needs full git history

- name: Run Gitleaks
  uses: gitleaks/gitleaks-action@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Pre-commit Hook** (`scripts/setup-hooks.sh`):
```bash
gitleaks protect --staged --exit-code 1
```

**Local Integration** (`scripts/scan.sh`):
```bash
gitleaks detect --source "$ROOT" --exit-code 1
```

### Best Practices

1. **`fetch-depth: 0` is mandatory**: Without full git history, gitleaks fails with "ambiguous argument / unknown revision"
2. **Use pre-commit hooks**: Install via `scripts/setup-hooks.sh` to catch secrets before they're committed
3. **Extend default config**: Use `[extend] useDefault = true` in `.gitleaks.toml` rather than writing rules from scratch
4. **Combine entropy + keywords**: Use `entropy` threshold with `keywords` for fewer false positives
5. **Organization license**: GitHub organizations need `GITLEAKS_LICENSE` secret (free for personal accounts)
6. **Allowlist strategically**: Use rule-specific allowlists (`[[rules.allowlist]]`) over global ones

### Common Pitfalls

- **Missing `fetch-depth: 0`**: The #1 cause of gitleaks failures in CI
- **`generic-api-key` noise**: The default rule produces many false positives — consider disabling it
- **Go regex limitations**: Gitleaks uses Go's regex engine which does NOT support lookaheads
- **`.gitignore` doesn't affect gitleaks**: Gitleaks scans git history, not just the working tree

---

## Checkov (IaC Security Scanner)

### Official Definition

Checkov by Bridgecrew (Prisma Cloud) is a static code analysis tool for infrastructure as code. It detects security and compliance misconfigurations in Terraform, CloudFormation, Kubernetes, Dockerfile, Helm, Ansible, GitHub Actions workflows, and more.

- **Repository:** https://github.com/bridgecrewio/checkov
- **License:** Apache 2.0

### How It Connects to the Pipeline

**CI Integration** (`.github/workflows/ci.yml`):
```yaml
- name: Run Checkov on Terraform
  uses: bridgecrewio/checkov-action@v12
  with:
    directory: terraform/
    framework: terraform
    soft_fail: false
    output_format: sarif
    output_file_path: checkov.sarif
```

**Configuration** (`.checkov.yml`):
```yaml
soft-fail: false
compact: true
quiet: true
skip-check:
  - CKV_AWS_158  # KMS encryption — enabled via kms_key_arn variable
  - CKV_AWS_144  # S3 cross-region replication — environment-specific
  - CKV2_AWS_76  # WAF Log4j AMR rule — depends on waf_acl_arn variable
  - CKV_AWS_18   # S3 access logging — ALB logs bucket would create infinite loop
```

**Local Integration** (`scripts/scan.sh`):
```bash
checkov -d "$ROOT/terraform/" --quiet --compact
```

### Best Practices

1. **Pin action to SHA**: The checkov-action has known bugs — pin to a specific commit for stability
2. **Document skip-check reasons**: Every `skip-check` entry should have a comment explaining WHY
3. **Use `soft_fail: false`** in CI: Ensure the job actually fails on findings
4. **Framework selection**: Only scan frameworks you use — `framework: terraform` not `all`
5. **SARIF + CLI output**: Use `output_format: sarif` for GitHub integration
6. **Evaluate variables**: Set `evaluate-variables: true` to resolve Terraform variable references

### Common Pitfalls

- **Variable evaluation**: Without `evaluate-variables: true`, Terraform variable references won't resolve, causing false positives
- **Skip-check documentation**: Always add comments to `skip-check` entries explaining the reason
- **Framework overlap**: Don't scan `secrets` framework if you already use gitleaks — it's redundant

---

## Conftest (Policy Testing)

### Official Definition

Conftest is a CLI tool from the OPA project that tests structured configuration data (Kubernetes manifests, Terraform plans, Docker Compose, etc.) against Rego policies. It provides a simple way to enforce policies as code in CI/CD pipelines.

- **Repository:** https://github.com/open-policy-agent/conftest
- **License:** Apache 2.0

### How It Connects to the Pipeline

**CI Integration** (`.github/workflows/ci.yml`):
```yaml
- name: Install Conftest
  run: |
    VERSION=0.68.2
    curl -fsSL -o conftest.tar.gz \
      "https://github.com/open-policy-agent/conftest/releases/download/v${VERSION}/conftest_${VERSION}_Linux_x86_64.tar.gz"
    tar xzf conftest.tar.gz
    sudo mv conftest /usr/local/bin/

- name: Check Dockerfile policies
  run: conftest test docker/Dockerfile -p policies/conftest/

- name: Check Terraform policies
  run: conftest test tfplan.json -p policies/opa/ --all-namespaces
```

**Policy Files**:
- `policies/conftest/dockerfile.rego` — Dockerfile policies (no :latest, must have USER, no curl|sh, etc.)
- `policies/opa/deployment.rego` — Infrastructure policies (read-only filesystem, encryption, TLS 1.2+, no public S3, no SSH from 0.0.0.0/0)

### Best Practices

1. **Use `-o github` in CI**: Generates `::error` annotations that appear inline in PR diffs
2. **`--fail-on-warn`**: Treat warnings as failures in CI for stricter enforcement
3. **`--all-namespaces`**: Evaluate rules across all Rego packages, not just `main`
4. **Test Terraform plans, not raw .tf files**: Conftest expects JSON/YAML input — generate a plan JSON first:
   ```bash
   terraform init -backend=false
   terraform plan -no-color -out=tfplan
   terraform show -json tfplan > tfplan.json
   conftest test tfplan.json -p policies/opa/ --all-namespaces
   ```
5. **Unit test policies**: Use `conftest verify` with `*_test.rego` files to validate policy logic
6. **Use OPA v1 syntax**: Always use `import rego.v1` and `deny contains msg if { ... }` pattern

### Common Pitfalls

- **Raw .tf files**: Conftest cannot parse HCL directly — always convert to JSON via `terraform show -json`
- **Namespace scoping**: Rules must be in the correct package namespace — use `--all-namespaces`
- **Exit codes**: `0` = clean, `1` = failures, `2` = test errors — understand the difference
- **No dedicated GitHub Action**: Use the binary directly or via Docker container

---

## OPA / Rego (Policy Engine)

### Official Definition

OPA (Open Policy Agent) is an open-source, general-purpose policy engine that enables unified, context-aware policy enforcement across the stack. Rego is OPA's high-level declarative language for expressing policies as code.

- **Website:** https://www.openpolicyagent.org
- **Repository:** https://github.com/open-policy-agent/opa
- **License:** Apache 2.0

### How It Connects to the Pipeline

OPA/Rego policies are evaluated by Conftest in the `policy-check` job. The project defines two policy sets:

**Dockerfile Policies** (`policies/conftest/dockerfile.rego`):
- `deny`: No `:latest` tags
- `deny`: Must include `USER` instruction
- `deny`: No piping `curl` to `sh`
- `deny`: No privileged ports (< 1024, except 80/443)
- `deny`: No passwords/secrets in `ENV`
- `warn`: Should include `HEALTHCHECK`

**Infrastructure Policies** (`policies/opa/deployment.rego`):
- `deny`: Containers must use `readonlyRootFilesystem`
- `deny`: S3 buckets must have encryption
- `deny`: VPCs must have flow logs
- `deny`: ALB must use TLS 1.2+
- `deny`: S3 must block public ACLs
- `deny`: No SSH (port 22) from 0.0.0.0/0

### OPA v1 Syntax (Required)

All Rego policies in this project use OPA v1 syntax:

```rego
package deployment
import rego.v1

# Deny rule (collection pattern)
deny contains msg if {
    input.resource_type == "aws_ecs_task_definition"
    container := input.resource.container_definitions[_]
    not container.readonlyRootFilesystem
    msg := sprintf("Container '%s' must use readonlyRootFilesystem", [container.name])
}

# Helper rule (bare if body, no contains)
has_user if {
    some i
    input[i].Cmd == "user"
}
```

### Best Practices

1. **Always use `import rego.v1`**: Required for OPA 1.0+ compatibility
2. **`deny contains msg if { ... }`**: Use the collection pattern for accumulating multiple violations
3. **`some x in collection`**: Use `some ... in` for iterator variables — NOT `some container` before `:=`
4. **No `some` before `:=`**: `some container` before a `:=` assignment causes a duplicate declaration error
5. **Helper rules use bare `if`**: Helpers like `has_user` use `if { ... }` body without `contains`
6. **`default allow := false`**: Explicit default deny is a security best practice
7. **Use `sprintf` for messages**: Format violation messages with context

### Common Pitfalls

- **Missing `import rego.v1`**: Without it, `contains` and `if` keywords may not work
- **Duplicate declaration error**: `some container` before `:=` is invalid — use `some container in input.containers` instead
- **Rule naming**: Rules named `deny`, `violation`, or `warn` are automatically evaluated by Conftest
- **Performance**: Avoid iterating over large collections multiple times — use helper rules to cache results

---

## GitHub Actions (CI/CD)

### Official Definition

GitHub Actions is a CI/CD platform built into GitHub that enables automated workflows directly from repositories. Workflows are defined in YAML and triggered by repository events (push, PR, schedule, etc.).

- **Website:** https://docs.github.com/en/actions
- **License:** Proprietary (free for public repositories)

### How It Connects to the Pipeline

The entire security pipeline is defined in `.github/workflows/ci.yml`:

```
push → lint → security-scan → iac-scan → build → policy-check → deploy-staging → deploy-prod
```

**Key permissions:**
```yaml
permissions:
  contents: read
  security-events: write  # Required for SARIF upload
  id-token: write          # Required for AWS OIDC auth
```

**Key patterns:**
- Deploy jobs guard on `vars.AWS_REGION != ''` to skip when AWS is not configured
- No `environment:` key on deploy jobs (prevents failed deployment records)
- `continue-on-error: true` on Trivy steps to allow SARIF upload before failure
- `fetch-depth: 0` for gitleaks to access full git history

### Best Practices

1. **Pin action versions**: Use `@v4` or SHA pins, never `@master`
2. **Minimal permissions**: Use `permissions:` block with least privilege
3. **Guard deploy jobs**: Use `if: vars.AWS_REGION != ''` to skip when AWS is not configured
4. **No `environment:` on deploy jobs**: GitHub creates failed deployment records even when skipped
5. **SARIF upload guards**: Use `if: always() && hashFiles('file.sarif') != ''` to prevent upload failures
6. **OIDC authentication**: Use `aws-actions/configure-aws-credentials@v4` with role assumption instead of long-lived keys

### Common Pitfalls

- **Missing `security-events: write`**: Blocks SARIF upload to GitHub Security tab
- **Missing `id-token: write`**: Blocks AWS OIDC authentication
- **`environment:` on skipped jobs**: Creates failed deployment records in GitHub
- **Mutable action tags**: `@master` can be compromised — always pin to a version or SHA

---

## Pipeline Integration Map

| Stage | Tool | Purpose | Config File | CI Step |
|-------|------|---------|-------------|---------|
| Lint | Hadolint | Dockerfile linting | `.hadolint.yaml` | `hadolint-action@v3.1.0` |
| Lint | Ruff | Python linting | N/A | `ruff-action@v3` |
| SAST | Semgrep | Static analysis | `.semgrep.yml` | `semgrep-action@v1` |
| Secrets | Gitleaks | Secret detection | `.gitleaks.toml` | `gitleaks-action@v2` |
| SCA | Trivy | Dependency scanning | `trivy.yaml` | Install script + CLI |
| IaC | Checkov | Terraform scanning | `.checkov.yml` | `checkov-action@v12` |
| IaC | Trivy | IaC misconfigurations | N/A | Install script + CLI |
| Build | Docker | Image build | `docker/Dockerfile` | `build-push-action@v6` |
| Container | Trivy | Image scanning | N/A | Install script + CLI |
| Policy | Conftest | Dockerfile policies | `policies/conftest/` | Binary install |
| Policy | Conftest | Infrastructure policies | `policies/opa/` | Binary install |
| Deploy | AWS CLI | ECS deployment | N/A | `deploy.sh staging/production` |

### Local Scanning

All security tools can be run locally via `scripts/scan.sh`:

```bash
# Install pre-commit hooks (secret detection, linting)
./scripts/setup-hooks.sh

# Run all scans (SAST, SCA, container, IaC, policy)
./scripts/scan.sh
```

The scan script gracefully skips tools that aren't installed and reports which checks ran.