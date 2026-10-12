#!/usr/bin/env bash
set -euo pipefail
cd /home/traen/crawl4ai
[[ -f source/pyproject.toml && -f compose.yaml ]]
umask 077
if [[ ! -f .secrets.env ]]; then
  python3 - <<'PY'
import secrets
from pathlib import Path
keys = ('CRAWL4AI_API_TOKEN', 'SECRET_KEY', 'REDIS_PASSWORD')
with Path('.secrets.env').open('x') as f:
    for key in keys:
        f.write(f'{key}={secrets.token_hex(32)}\n')
PY
fi
chmod 600 .secrets.env
if [[ ! -f config.yml ]]; then
  python3 - <<'PY'
from pathlib import Path
p = Path('source/deploy/docker/config.yml')
s = p.read_text()
changes = {
    'maxsize: 1000': 'maxsize: 100',
    'workers: 4': 'workers: 1',
    'per_principal: 0': 'per_principal: 2',
    'memory_threshold_percent: 95.0': 'memory_threshold_percent: 85.0',
    'max_pages: 40': 'max_pages: 2',
    'idle_ttl_sec: 300': 'idle_ttl_sec: 120',
    'default_limit: "1000/minute"': 'default_limit: "60/minute"',
}
for old, new in changes.items():
    assert old in s, old
    s = s.replace(old, new)
Path('config.yml').write_text(s)
PY
fi
chmod 644 config.yml
docker compose config --quiet
echo 'DEPLOYMENT_CONFIG_OK: secrets generated on server; API binds host loopback.'
