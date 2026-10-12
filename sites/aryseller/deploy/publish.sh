#!/usr/bin/env bash
# Publish on the existing VPS and keep the aryseller mail stack intact.
set -euo pipefail
[[ $(hostname) == vm1523243.vds.chsl.one ]] || { echo 'Unexpected VPS'; exit 1; }
staging=/home/traen/aryseller-site
mail=/home/traen/aryseller-mail-server
site=$mail/docker-data/caddy/data/aryseller-site
stamp=$(date -u +%Y%m%dT%H%M%SZ)
release=$site/releases/$stamp
backup=$staging/backups/$stamp
for container in aryseller-mailserver aryseller-roundcube aryseller-caddy crawl4ai-crawl4ai-1; do
  [[ $(docker inspect -f '{{.State.Running}}' "$container") == true ]] || exit 1
done
docker network inspect crawl4ai_default >/dev/null
[[ -f $staging/site.tar.gz && -f $staging/Caddyfile && -f $staging/compose.web.yaml ]]
if [[ -e $site/current && ! -L $site/current ]]; then echo 'Current release is not a symlink'; exit 1; fi
previous=$(readlink "$site/current" 2>/dev/null || true)
install -d -m 755 "$release"
install -d -m 700 "$backup"
cp "$mail/Caddyfile" "$backup/Caddyfile"
cp "$mail/compose.yaml" "$backup/compose.yaml"
[[ ! -f $mail/compose.web.yaml ]] || cp "$mail/compose.web.yaml" "$backup/compose.web.yaml"
tar -xzf "$staging/site.tar.gz" -C "$release"
find "$release" -type d -exec chmod 755 {} +
find "$release" -type f -exec chmod 644 {} +
[[ -f $release/index.html && -f $release/services/crawl4ai/index.html ]]
# Validate before touching the running proxy configuration.
docker cp "$staging/Caddyfile" aryseller-caddy:/tmp/aryseller-candidate.Caddyfile
docker exec aryseller-caddy caddy validate --config /tmp/aryseller-candidate.Caddyfile --adapter caddyfile
cd "$mail"
docker compose -f compose.yaml -f "$staging/compose.web.yaml" config --quiet
ln -s "releases/$stamp" "$site/.current-$stamp"
mv -Tf "$site/.current-$stamp" "$site/current"
rollback() {
  echo 'Publication failed; restoring the previous Caddy configuration.' >&2
  cp "$backup/Caddyfile" "$mail/Caddyfile"
  cp "$backup/compose.yaml" "$mail/compose.yaml"
  if [[ -n $previous ]]; then
    ln -s "$previous" "$site/.rollback-$stamp"
    mv -Tf "$site/.rollback-$stamp" "$site/current"
  fi
  docker exec aryseller-caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile || true
}
trap rollback ERR
# cp overwrites the inode of the existing bind-mounted Caddyfile.
cp "$staging/Caddyfile" "$mail/Caddyfile"
cp "$staging/compose.web.yaml" "$mail/compose.web.yaml"
chmod 644 "$mail/Caddyfile" "$mail/compose.web.yaml"
python3 "$staging/integrate.py"
docker compose config --quiet
# Recreate only Caddy to declare both networks persistently.
docker compose -f compose.yaml -f compose.web.yaml up -d --no-deps caddy
for attempt in $(seq 1 30); do
  if curl -fsS https://aryseller.com/ -o /dev/null 2>/dev/null && curl -fsS https://aryseller.com/services/crawl4ai/api/health -o /dev/null 2>/dev/null; then break; fi
  sleep 2
done
curl -fsS https://aryseller.com/ -o /dev/null
curl -fsS https://aryseller.com/services/crawl4ai/ -o /dev/null
curl -fsS https://aryseller.com/services/crawl4ai/api/health
curl -fsS https://mail.aryseller.com/ -o /dev/null
trap - ERR
printf '\nSITE_PUBLISHED release=%s backup=%s\n' "$release" "$backup"
