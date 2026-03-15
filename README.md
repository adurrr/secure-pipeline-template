# Secure Pipeline Template

Production-ready CI/CD pipeline template with integrated security scanning, infrastructure as code, and policy enforcement.

Works on **AWS**, **on-premise**, or **local** environments out of the box.

## What's included

| Layer | Tools | Purpose |
|-------|-------|---------|
| **SAST** | Semgrep | Static analysis on every push |
| **SCA** | Trivy | Dependency vulnerability scanning |
| **Container** | Trivy, Hadolint | Image scanning + Dockerfile linting |
| **Secrets** | Gitleaks | Pre-commit and CI secret detection |
| **IaC** | Checkov, tfsec | Terraform misconfiguration scanning |
| **Policy** | OPA / Conftest | Custom policy enforcement |
| **Infrastructure** | Terraform | AWS ECS Fargate (optional) |
| **Local / On-prem** | Docker Compose + Nginx | TLS, rate limiting, hardened containers |
| **Monitoring** | CloudWatch or stdout logs | Security alerts and audit logging |

## Quick start — local / on-premise

```bash
# 1. Generate self-signed TLS certs (or bring your own)
./scripts/generate-certs.sh

# 2. Start the stack
docker compose up -d

# 3. Verify
curl -k https://localhost/healthz
```

That's it. Nginx handles TLS termination, HTTP-to-HTTPS redirect, rate limiting, and security headers. The app container runs as non-root with a read-only filesystem.

## Quick start — AWS

```bash
# 1. Configure Terraform
cp terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars
# Edit with your AWS account details

# 2. Deploy
cd terraform/environments/dev
terraform init && terraform plan && terraform apply
```

## Running security scans locally

```bash
# Install pre-commit hooks (secret detection, linting)
./scripts/setup-hooks.sh

# Run all scans (SAST, SCA, container, IaC, policy)
./scripts/scan.sh
```

The scan script auto-skips tools that aren't installed and reports which checks ran.

## Pipeline stages

```
push → lint → SAST → SCA → build → image-scan → policy-check → deploy-staging → integration-tests → deploy-prod
```

Every stage acts as a gate — a failure in any security stage blocks the deployment.

## Repository structure

```
├── .github/workflows/     CI/CD pipeline definitions
├── app/                   Sample application (Python/Flask)
├── docker/
│   ├── Dockerfile         Multi-stage, non-root, read-only
│   └── nginx.conf         TLS, rate limiting, security headers
├── docker-compose.yml     Local / on-premise deployment
├── terraform/
│   ├── modules/           Reusable infra modules (VPC, ECS, ALB)
│   └── environments/      Per-environment configs
├── policies/
│   ├── opa/               Rego policies for infrastructure
│   └── conftest/          Dockerfile and container policies
└── scripts/
    ├── scan.sh            Run all security scans locally
    ├── setup-hooks.sh     Install git pre-commit hooks
    ├── generate-certs.sh  Generate self-signed TLS certs
    └── deploy.sh          Deploy to local, staging, or production
```

## Customizing for your project

1. Replace the sample app in `app/` with your service
2. Update `docker/Dockerfile` for your runtime
3. Adjust Nginx config in `docker/nginx.conf` for your domain
4. Add project-specific policies in `policies/`
5. Tune Semgrep rules in `.semgrep.yml` for your stack
6. (Optional) Configure `terraform/environments/` for AWS

## Security scanning thresholds

Configured in `.github/workflows/ci.yml`:

- **CRITICAL/HIGH vulnerabilities**: pipeline fails
- **MEDIUM**: warning, logged to report
- **LOW/INFO**: logged only

## License

AGPL-3.0 — see [LICENSE](LICENSE)
