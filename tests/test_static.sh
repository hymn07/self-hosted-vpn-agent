#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

for script in scripts/*.sh tests/*.sh; do
  bash -n "$script"
done

python3 -m compileall -q scripts tests
python3 -m unittest discover -s tests -p 'test_*.py'
python3 scripts/deployment_config.py validate config/deployment.example.yaml
python3 scripts/deployment_config.py summary config/deployment.example.yaml >/dev/null

if rg -n --glob '!.git/**' -- \
  '-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----' .; then
  echo "发现私钥内容" >&2
  exit 1
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh tests/*.sh
fi

echo "静态检查通过"
