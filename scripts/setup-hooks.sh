#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Setting up pre-commit hooks..."

# Ensure we're in a git repo
if [ ! -d "$ROOT/.git" ]; then
    echo "Not a git repository. Run 'git init' first."
    exit 1
fi

HOOK="$ROOT/.git/hooks/pre-commit"

cat > "$HOOK" << 'HOOK_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

echo "Running pre-commit security checks..."

# Secret detection on staged files
if command -v gitleaks &>/dev/null; then
    gitleaks protect --staged --exit-code 1
    echo "✓ No secrets detected"
else
    echo "WARN: gitleaks not installed — skipping secret scan"
fi

# Lint Dockerfile if changed
if git diff --cached --name-only | grep -q "Dockerfile"; then
    if command -v hadolint &>/dev/null; then
        git diff --cached --name-only | grep "Dockerfile" | xargs hadolint
        echo "✓ Dockerfile lint passed"
    fi
fi

# Lint Python if changed
if git diff --cached --name-only | grep -q "\.py$"; then
    if command -v ruff &>/dev/null; then
        git diff --cached --name-only | grep "\.py$" | xargs ruff check
        echo "✓ Python lint passed"
    fi
fi

echo "Pre-commit checks passed."
HOOK_SCRIPT

chmod +x "$HOOK"
echo "Pre-commit hook installed at $HOOK"
