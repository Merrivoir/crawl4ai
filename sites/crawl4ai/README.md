# Aryseller Crawl4AI interface

This directory owns the service interface at
https://aryseller.com/services/crawl4ai/. Its API prefix remains
`/services/crawl4ai/api`; token handling and the API contract are unchanged.
The company home page is in `Merrivoir/aryseller-website`, and public Caddy
configuration is in `Merrivoir/aryseller-infra`.

`dist/` contains authored static source. The CSS and favicon are a snapshot of
the existing branding; no other repository is needed to build this interface.

## Preview and browser checks

Run `node sites/crawl4ai/preview.cjs` from the repository root and open
http://127.0.0.1:5180/services/crawl4ai/. An optional local backend is forwarded
at 127.0.0.1:11235; without it the UI reports an unavailable service.

`node sites/crawl4ai/qa.cjs OUTPUT_DIRECTORY BASE_URL` checks the UI with mocked
API responses, missing/invalid credentials, escaped result text, downloads and
320/390/768px layouts. Set `PLAYWRIGHT_MODULE_PATH` if Playwright is installed
outside this repository. `live-qa.cjs` is an explicit production integration
test; it uses SSH to read the existing token into memory and performs a real
crawl. Local mocked checks do not prove a production deployment.

## Runtime

The deployment scaffold is `deploy/vps/compose.yaml`. On the existing VPS it is
installed as `/home/traen/crawl4ai/compose.yaml`, with this repository under
`/home/traen/crawl4ai/source`. Its separate `web` service builds this directory.
The `aryseller_crawl4ai_web` external network is created by infrastructure.

After clean startup following `aryseller-infra/SETUP.md`, interface-only updates:

```bash
cd /home/traen/crawl4ai
docker compose config --quiet
docker compose build web
docker compose up -d --no-deps --wait --wait-timeout 60 web
```

Backend updates remain separate: build and update only `crawl4ai`. Keep its
existing `.secrets.env` and `config.yml`; do not regenerate tokens on updates.
No application update modifies the mail or infrastructure checkout.
