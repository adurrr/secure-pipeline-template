# Secure Pipeline Template

## Project overview
Reusable CI/CD pipeline template with integrated security scanning. Designed to work on AWS, on-premise, or local environments. Licensed under AGPL-3.0.

## Architecture
- **App**: Python/Flask sample service in `app/` (replace with your own)
- **Local/on-prem**: Docker Compose + Nginx (TLS, rate limiting, security headers)
- **AWS (optional)**: Terraform modules for VPC, ALB, ECS Fargate in `terraform/`
- **Security pipeline**: GitHub Actions with 6 gates (Semgrep, Trivy, Hadolint, Gitleaks, Checkov, Conftest)
- **Policies as code**: OPA/Rego in `policies/`

## Git workflow
- **Gitflow**: `main` (stable releases), `develop` (active development)
- Feature branches: `feature/<name>` off `develop`
- Commits: human style, no AI attribution, no co-authored-by tags
- Author: Adur <26388026+adurrr@users.noreply.github.com>

## Key commands
```bash
# Local test (Python only)
cd app && python main.py          # runs on :8080

# Local test (Docker)
./scripts/generate-certs.sh       # one-time TLS cert setup
docker-compose up -d --build      # or: docker compose up -d --build

# Security scans
./scripts/scan.sh                 # runs all installed scanners

# Terraform
cd terraform/environments/dev
terraform init && terraform plan
```

## Security scan tools
- **SAST**: Semgrep (config: `.semgrep.yml`)
- **IaC**: Checkov (config: `.checkov.yml` — 4 documented env-dependent skips)
- **Secrets**: Gitleaks (pre-commit hook via `scripts/setup-hooks.sh`)
- **Container**: Trivy + Hadolint
- **Policy**: Conftest with Rego policies in `policies/`

## Endpoints
- `GET /healthz` — liveness check
- `GET /readyz` — readiness check
- `GET /api/v1/info` — service metadata

## Notes
- `scripts/scan.sh` gracefully skips tools that aren't installed
- `scripts/deploy.sh` supports `local`, `staging`, and `production` targets
- Docker Compose works with both v1 (`docker-compose`) and v2 (`docker compose`)
- Terraform `kms_key_arn` and `waf_acl_arn` are optional — pass them in tfvars for production hardening

## CI/CD known issues and fixes

### Trivy installation
- **Do not** use `aquasecurity/trivy-action` — it fails on GitHub API rate limits in CI
- Use the official install script instead:
  ```bash
  curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
    | sudo sh -s -- -b /usr/local/bin
  ```
- Always set `continue-on-error: true` on Trivy scan steps so the pipeline doesn't hard-fail before SARIF upload
- Guard SARIF uploads with `if: always() && hashFiles('trivy-sca.sarif') != ''`

### Gitleaks (secrets scan)
- Requires full git history — checkout with `fetch-depth: 0` in the `security-scan` job
- Without this, gitleaks fails with "ambiguous argument / unknown revision"

### OPA/Rego policies (conftest + deployment.rego)
- Must use OPA v1 syntax: `import rego.v1`, `deny contains msg if { ... }`, `warn contains msg if { ... }`
- Use `some i` for iterator variables in `input[i]` expressions
- Do NOT use `some container` or `some rule` before a `:=` assignment — that's a duplicate declaration error
- Helper rules (e.g. `has_user`) use bare `if { ... }` body, no `contains`

### Deploy jobs (staging / production)
- Deploy jobs must guard on `vars.AWS_REGION != ''` so they are skipped when AWS is not configured
- **Do not** add `environment: staging` / `environment: production` to jobs — GitHub creates failed deployment records even when the job is skipped

### Docker Compose — read-only containers
- App runs with `read_only: true`; gunicorn needs `/tmp` for worker temp files
- Required: `tmpfs: - /tmp` under the app service, or gunicorn will crash on startup
