# Infrastructure Components

This document covers the infrastructure components used in the secure pipeline template, including their official definitions, configuration, and best practices.

---

## Table of Contents

- [Docker & Docker Compose](#docker--docker-compose)
- [Nginx (Reverse Proxy)](#nginx-reverse-proxy)
- [Flask & Gunicorn (Application)](#flask--gunicorn-application)
- [Terraform (Infrastructure as Code)](#terraform-infrastructure-as-code)
- [AWS ECS Fargate](#aws-ecs-fargate)
- [AWS Application Load Balancer](#aws-application-load-balancer)
- [AWS VPC](#aws-vpc)
- [AWS S3 & CloudWatch](#aws-s3--cloudwatch)
- [AWS IAM](#aws-iam)

---

## Docker & Docker Compose

### Official Definition

Docker is a platform for developing, shipping, and running applications in containers. Docker Compose is a tool for defining and running multi-container Docker applications using a single YAML configuration file.

- **Docker Website:** https://www.docker.com
- **Docker Compose Docs:** https://docs.docker.com/compose/
- **License:** Apache 2.0 (Docker Engine), Apache 2.0 (Compose)

### How It Connects to the Pipeline

**Dockerfile** (`docker/Dockerfile`):
- Multi-stage build (build stage + production stage)
- Non-root user (`appuser`)
- Read-only filesystem support
- Health check built into the image
- Gunicorn as the WSGI server

**Docker Compose** (`docker-compose.yml`):
- Two services: `app` and `nginx`
- App runs with `read_only: true` and `tmpfs: /tmp`
- Nginx handles TLS termination and proxies to the app
- Resource limits on both services
- Health checks for both services
- `no-new-privileges` security option on both services

### Best Practices

1. **Multi-stage builds**: Use a build stage for dependencies and a minimal production stage
2. **Non-root user**: Always create and switch to a non-root user (`USER appuser`)
3. **Read-only filesystem**: Run containers with `read_only: true` and `tmpfs` for writable paths
4. **`no-new-privileges`**: Prevent privilege escalation via setuid binaries
5. **Resource limits**: Set CPU and memory limits to prevent resource exhaustion
6. **Health checks**: Define `HEALTHCHECK` in the Dockerfile and `healthcheck` in Compose
7. **Pin base images**: Use specific version tags (e.g., `python:3.12-slim`) not `:latest`
8. **`.dockerignore`**: Exclude unnecessary files from the build context

### Common Pitfalls

- **Gunicorn needs `/tmp`**: With `read_only: true`, gunicorn needs `tmpfs: /tmp` for worker temp files
- **Docker Compose v1 vs v2**: The deploy script handles both `docker compose` (v2) and `docker-compose` (v1)
- **Self-signed certs**: Use `scripts/generate-certs.sh` for local development; use real certs in production

---

## Nginx (Reverse Proxy)

### Official Definition

Nginx is a high-performance HTTP server and reverse proxy. In this project, it handles TLS termination, HTTP-to-HTTPS redirection, rate limiting, and security headers.

- **Website:** https://nginx.org
- **License:** BSD 2-Clause

### How It Connects to the Pipeline

**Configuration** (`docker/nginx.conf`):
- TLS termination with TLSv1.2 and TLSv1.3 only
- HTTP-to-HTTPS redirect on port 80
- Rate limiting: 30 requests/second with burst of 20
- Security headers: HSTS, X-Frame-Options, X-Content-Type-Options, CSP, Referrer-Policy
- Proxy pass to the Flask app on port 8080
- Health check endpoint bypasses rate limiting

### Best Practices

1. **TLS 1.2+ only**: Disable older protocols (`ssl_protocols TLSv1.2 TLSv1.3`)
2. **Strong cipher suite**: Use `HIGH:!aNULL:!MD5` to prefer strong ciphers
3. **HSTS**: Set `Strict-Transport-Security` with `includeSubDomains` and long max-age
4. **Rate limiting**: Use `limit_req_zone` with burst to prevent abuse
5. **`server_tokens off`**: Hide Nginx version from response headers
6. **Access log off for health checks**: Reduce log noise from health check endpoints
7. **Security headers**: Apply with `always` flag to ensure they're sent on all response codes

### Common Pitfalls

- **`X-XSS-Protection` is deprecated**: Modern browsers ignore it; rely on CSP instead
- **`ssl_prefer_server_ciphers` is deprecated**: In OpenSSL 1.1.1+ and nginx 1.27+, the server respects client cipher preferences with TLS 1.3
- **Missing `X-Forwarded-Proto`**: Required for Flask to know the original scheme (HTTP vs HTTPS)
- **Rate limit zone size**: `10m` handles ~160,000 unique IPs; adjust for higher traffic

---

## Flask & Gunicorn (Application)

### Official Definition

Flask is a lightweight WSGI web application framework for Python. Gunicorn is a Python WSGI HTTP server for UNIX that serves as the production server in front of Flask.

- **Flask Website:** https://flask.palletsprojects.com
- **Gunicorn Website:** https://gunicorn.org
- **License:** BSD 3-Clause (Flask), MIT (Gunicorn)

### How It Connects to the Pipeline

**Application** (`app/main.py`):
- Health check endpoint: `GET /healthz`
- Readiness endpoint: `GET /readyz`
- Info endpoint: `GET /api/v1/info`
- Request logging via `@app.before_request`
- `MAX_CONTENT_LENGTH` set to 1MB to prevent large payload attacks
- `ProxyFix` middleware for proper header forwarding behind Nginx

**Gunicorn Configuration** (`docker/Dockerfile`):
```dockerfile
ENTRYPOINT ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "main:app"]
```

### Best Practices

1. **Never run with `debug=True`** in production — the Semgrep rule catches this
2. **Set `MAX_CONTENT_LENGTH`**: Prevent denial-of-service via large request bodies
3. **Use `ProxyFix`**: Required when behind a reverse proxy to get correct `X-Forwarded-*` headers
4. **Gunicorn workers**: Use `2 * cores + 1` formula for worker count; 2 workers is minimum for the default container
5. **Access log to stdout**: `--access-logfile -` sends access logs to stdout for container log collection
6. **Pin dependencies**: Use exact versions in `requirements.txt` (e.g., `flask==3.1.3`)

### Common Pitfalls

- **Flask dev server in production**: Never use `app.run()` in production — always use Gunicorn
- **Missing `ProxyFix`**: Without it, `request.remote_addr` and `request.scheme` will be incorrect behind Nginx
- **Gunicorn temp files**: With `read_only: true`, gunicorn needs `/tmp` as tmpfs

---

## Terraform (Infrastructure as Code)

### Official Definition

Terraform by HashiCorp is an infrastructure as code tool that enables declarative cloud resource management across multiple providers. It uses HCL (HashiCorp Configuration Language) for configuration.

- **Website:** https://www.terraform.io
- **License:** BSL 1.1 (Terraform 1.6+), MPL 2.0 (OpenTofu fork)

### How It Connects to the Pipeline

**Module Structure:**
```
terraform/
├── modules/
│   ├── vpc/          # VPC, subnets, NAT gateways, flow logs
│   ├── alb/          # Application Load Balancer, security groups, S3 logs
│   └── ecs/          # ECS cluster, task definition, service, IAM roles
└── environments/
    ├── dev/           # Development environment
    └── prod/          # Production environment
```

**Key Features:**
- VPC with public/private subnets, NAT gateways, and flow logs
- ALB with TLS 1.2+, WAF association, and access logging
- ECS Fargate with read-only filesystem, health checks, and circuit breaker
- IAM roles with least privilege
- Optional KMS encryption and WAF via variables

### Best Practices

1. **Module composition**: Use environment-specific wrappers around reusable modules
2. **Variable defaults**: Use empty string defaults (`""`) for optional resources like KMS and WAF
3. **`lifecycle { create_before_destroy = true }`**: Use on security groups to avoid dependency cycles
4. **Encryption at rest**: Pass `kms_key_arn` for CloudWatch log encryption
5. **Deletion protection**: Enable on ALB (`enable_deletion_protection = true`)
6. **Remote state**: Use S3 backend with DynamoDB locking for production (commented out in templates)
7. **Provider version pinning**: Use `~> 5.0` for AWS provider to allow minor updates

### Common Pitfalls

- **Variable pass-through**: Always pass `kms_key_arn` and `waf_acl_arn` from environments to modules
- **ALB egress**: Restrict to VPC CIDR instead of `0.0.0.0/0`
- **ECS DNS**: Fargate tasks need DNS egress (port 53 UDP/TCP) in their security group
- **S3 self-logging**: Never enable S3 access logging on a bucket to itself — it creates an infinite loop

---

## AWS ECS Fargate

### Official Definition

Amazon ECS (Elastic Container Service) with Fargate is a serverless compute engine for containers that eliminates the need to manage servers. Fargate provisions and scales compute resources automatically.

- **Website:** https://aws.amazon.com/ecs/
- **Pricing:** Per-vCPU-hour and per-GB-hour

### How It Connects to the Pipeline

**ECS Module** (`terraform/modules/ecs/main.tf`):
- Fargate launch type with `awsvpc` network mode
- Read-only root filesystem with tmpfs mount for `/tmp`
- Health check using the `/healthz` endpoint
- Circuit breaker with automatic rollback
- CloudWatch log group with optional KMS encryption
- IAM roles: execution role (pull images, write logs) and task role (application permissions)

### Best Practices

1. **`awsvpc` network mode**: Required for Fargate — each task gets its own ENI
2. **Read-only filesystem**: Use `readonlyRootFilesystem = true` with a tmpfs volume for `/tmp`
3. **Circuit breaker**: Enable `deployment_circuit_breaker` with `rollback = true` for automatic rollback
4. **Least privilege IAM**: Separate execution role (pull images) from task role (app permissions)
5. **Health checks**: Define both Docker `HEALTHCHECK` and ECS `healthCheck` for defense in depth
6. **Private subnets**: Run tasks in private subnets with NAT gateway for outbound access
7. **Container insights**: Enable on the cluster for monitoring (`containerInsights = enabled`)

### Common Pitfalls

- **Missing DNS egress**: Fargate tasks need UDP/TCP port 53 for DNS resolution
- **Missing `/tmp` volume**: Gunicorn and other runtimes need a writable `/tmp` — use an empty volume mount
- **IAM policy ARN**: Use `arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy` for the managed policy
- **Task role vs execution role**: Don't confuse them — execution role is for the ECS agent, task role is for the application

---

## AWS Application Load Balancer

### Official Definition

The AWS Application Load Balancer (ALB) operates at Layer 7 and routes traffic to targets (ECS tasks, Lambda functions, etc.) based on HTTP/HTTPS request content.

- **Website:** https://aws.amazon.com/elasticloadbalancing/application-load-balancer/

### How It Connects to the Pipeline

**ALB Module** (`terraform/modules/alb/main.tf`):
- HTTPS listener on port 443 with TLS 1.2+ policy
- HTTP-to-HTTPS redirect on port 80
- Health check on `/healthz` endpoint
- Access logging to S3 with lifecycle rules
- Optional WAF association
- Security group restricting ingress to HTTPS only

### Best Practices

1. **TLS 1.2+ only**: Use `ELBSecurityPolicy-TLS13-1-2-2021-06` policy
2. **Deletion protection**: Enable in production (`enable_deletion_protection = true`)
3. **Drop invalid headers**: Enable `drop_invalid_header_fields = true`
4. **Access logging**: Enable and configure lifecycle rules to expire logs after 90 days
5. **WAF association**: Pass `waf_acl_arn` for production deployments
6. **Restrict egress**: Use VPC CIDR instead of `0.0.0.0/0` for ALB egress to ECS
7. **S3 bucket policy**: Configure ELB account ID for cross-account log writing

### Common Pitfalls

- **S3 self-logging**: Never enable S3 access logging on the ALB logs bucket to itself
- **ELB account ID**: Required for the S3 bucket policy — varies by region
- **Certificate ARN**: Must be in the same region as the ALB
- **Security group egress**: Restrict to VPC CIDR, not `0.0.0.0/0`

---

## AWS VPC

### Official Definition

Amazon VPC (Virtual Private Cloud) enables you to launch AWS resources in a logically isolated virtual network that you define. It provides network isolation, subnets, route tables, and gateways.

- **Website:** https://aws.amazon.com/vpc/

### How It Connects to the Pipeline

**VPC Module** (`terraform/modules/vpc/main.tf`):
- Public and private subnets across multiple AZs
- NAT gateways for private subnet outbound access
- VPC flow logs to CloudWatch with optional KMS encryption
- Restricted default security group (no rules)
- DNS support enabled (`enable_dns_hostnames` and `enable_dns_support`)

### Best Practices

1. **Multi-AZ**: Deploy across at least 2 availability zones for high availability
2. **Private subnets for workloads**: Run ECS tasks in private subnets with NAT gateway
3. **Flow logs**: Enable VPC flow logs for audit trail and security analysis
4. **KMS encryption**: Pass `kms_key_arn` for CloudWatch log encryption
5. **Default security group**: Remove all rules from the default SG (`aws_default_security_group`)
6. **DNS support**: Enable both `enable_dns_hostnames` and `enable_dns_support` for ECS service discovery

### Common Pitfalls

- **NAT gateway cost**: NAT gateways incur hourly charges — use one per AZ for production, one for dev
- **EIP limits**: NAT gateways require Elastic IPs — default limit is 5 per region
- **Flow log IAM**: The flow log role needs specific permissions to write to CloudWatch

---

## AWS S3 & CloudWatch

### Official Definition

Amazon S3 (Simple Storage Service) provides object storage with high durability and availability. Amazon CloudWatch provides monitoring, logging, and alerting for AWS resources and applications.

- **S3 Website:** https://aws.amazon.com/s3/
- **CloudWatch Website:** https://aws.amazon.com/cloudwatch/

### How It Connects to the Pipeline

**S3 (ALB Logs Bucket)**:
- Versioning enabled
- Server-side encryption with KMS
- Lifecycle rules: expire logs after 90 days, abort incomplete uploads after 7 days
- Public access block enabled
- Bucket policy for ELB account access

**CloudWatch (ECS & VPC Logs)**:
- Log groups for ECS container logs and VPC flow logs
- 365-day retention
- Optional KMS encryption via `kms_key_arn`

### Best Practices

1. **Never enable S3 self-logging**: Logging a bucket to itself creates an infinite loop
2. **Public access block**: Always enable all four public access block settings
3. **KMS encryption**: Use customer-managed KMS keys for production
4. **Lifecycle rules**: Set expiration to avoid unbounded storage growth
5. **Log retention**: Set appropriate retention (365 days for production, shorter for dev)

---

## AWS IAM

### Official Definition

AWS IAM (Identity and Access Management) enables you to manage access to AWS services and resources securely. It provides fine-grained access control through users, groups, roles, and policies.

- **Website:** https://aws.amazon.com/iam/

### How It Connects to the Pipeline

**Execution Role** (`terraform/modules/ecs/main.tf`):
- Used by the ECS agent to pull container images and write logs
- Managed policy: `AmazonECSTaskExecutionRolePolicy`
- Trust policy: `ecs-tasks.amazonaws.com`

**Task Role** (`terraform/modules/ecs/main.tf`):
- Used by the running container for application-level AWS permissions
- Currently minimal — add permissions as needed

**Flow Logs Role** (`terraform/modules/vpc/main.tf`):
- Used by VPC flow logs to write to CloudWatch
- Trust policy: `vpc-flow-logs.amazonaws.com`
- Permissions: `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`

### Best Practices

1. **Separate execution and task roles**: Don't use the same role for ECS agent and application
2. **Least privilege**: Grant only the permissions needed for each role
3. **Trust policy scoping**: Scope trust policies to specific services (e.g., `ecs-tasks.amazonaws.com`)
4. **No long-lived keys**: Use IAM roles with OIDC federation for CI/CD, not access keys
5. **Tag everything**: Use default tags to track resource ownership and environment