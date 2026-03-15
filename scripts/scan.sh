#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0

header() {
    echo ""
    echo "========================================"
    echo "  $1"
    echo "========================================"
}

check_tool() {
    if ! command -v "$1" &>/dev/null; then
        echo "SKIP: $1 not installed"
        return 1
    fi
}

# --- SAST ---
header "SAST — Semgrep"
if check_tool semgrep; then
    semgrep scan --config auto "$ROOT/app/" --error --severity ERROR || FAILED=1
fi

# --- Dependency scan ---
header "SCA — Trivy (filesystem)"
if check_tool trivy; then
    trivy fs "$ROOT/app/" --severity CRITICAL,HIGH --exit-code 1 || FAILED=1
fi

# --- Dockerfile lint ---
header "Dockerfile lint — Hadolint"
if check_tool hadolint; then
    hadolint "$ROOT/docker/Dockerfile" || FAILED=1
fi

# --- Secret detection ---
header "Secret detection — Gitleaks"
if check_tool gitleaks; then
    gitleaks detect --source "$ROOT" --no-git --exit-code 1 || FAILED=1
fi

# --- IaC scan ---
header "IaC scan — Checkov"
if check_tool checkov; then
    CHECKOV_ARGS=(-d "$ROOT/terraform/" --quiet --compact)
    [ -f "$ROOT/.checkov.yml" ] && CHECKOV_ARGS+=(--config-file "$ROOT/.checkov.yml")
    checkov "${CHECKOV_ARGS[@]}" || FAILED=1
fi

# --- Policy check ---
header "Policy check — Conftest"
if check_tool conftest; then
    conftest test "$ROOT/docker/Dockerfile" -p "$ROOT/policies/conftest/" || FAILED=1
fi

# --- Container image scan ---
header "Container image scan — Trivy"
if check_tool trivy && check_tool docker; then
    IMAGE="secure-pipeline-template:scan"
    docker build -t "$IMAGE" -f "$ROOT/docker/Dockerfile" "$ROOT" --quiet
    trivy image "$IMAGE" --severity CRITICAL,HIGH --exit-code 1 || FAILED=1
fi

echo ""
if [ "$FAILED" -ne 0 ]; then
    echo "RESULT: Some scans failed. Review output above."
    exit 1
else
    echo "RESULT: All scans passed."
fi
