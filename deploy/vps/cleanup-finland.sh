#!/usr/bin/env bash
# Retire the inspected RMCF installation while retaining aryseller mail.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run with sudo bash cleanup-finland.sh'; exit 1; }
[[ $(hostname) == vm1523243.vds.chsl.one ]] || { echo 'Unexpected host'; exit 1; }
runner=actions.runner.Merrivoir-rmcf-server.vpsfin.service
volumes=(
  428969500ce5622a3c828402c744791fc2a118d39afb08bd9093005f192f5e6a
  76377362479c61f8f2074b3e7e3830bc495c72216a3bf0b4d176ba3dd5cf9f4c
  rmcf-server_npm_data rmcf-server_npm_letsencrypt
)
paths=(/home/traen/actions-runner /var/lib/rmcf /var/www/rmcf /home/traen/rmcf-uploads-export-20261011)
for path in "${paths[@]}"; do
  if [[ -e $path ]]; then
    [[ ! -L $path && $(readlink -f -- "$path") == "$path" ]] || { echo "Unsafe path: $path"; exit 1; }
  fi
done
for name in aryseller-mailserver aryseller-roundcube aryseller-caddy; do
  [[ $(docker inspect -f '{{.State.Running}}' "$name") == true ]] || exit 1
done
for volume in "${volumes[@]}"; do
  [[ -z $(docker ps -aq --filter "volume=$volume") ]] || { echo "Volume in use: $volume"; exit 1; }
done
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup=/home/traen/crawl4ai-migration/backups/$stamp
install -d -m 700 -o traen -g traen "$backup"
sources=()
for path in "${paths[@]}" /etc/tinyproxy /etc/systemd/system/"$runner"; do
  [[ ! -e $path ]] || sources+=("${path#/}")
done
for volume in "${volumes[@]}"; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    mount=$(docker volume inspect -f '{{.Mountpoint}}' "$volume")
    [[ $mount == /var/lib/docker/volumes/"$volume"/_data ]] || exit 1
    sources+=("${mount#/}")
  fi
done
# Stop the runner first so no new deployment can race the backup/deletion.
systemctl disable --now "$runner"
systemctl disable --now tinyproxy.service
if docker inspect rmcf_compute >/dev/null 2>&1; then docker stop rmcf_compute; fi
trap 'echo "Cleanup interrupted; mail was preserved. Inspect the backup and retired services before retrying." >&2' ERR
tar -C / -I 'gzip -1' -cf "$backup/retired-services.tar.gz" "${sources[@]}"
tar -tzf "$backup/retired-services.tar.gz" >/dev/null
(cd "$backup" && sha256sum retired-services.tar.gz > retired-services.tar.gz.sha256)
chown traen:traen "$backup/retired-services.tar.gz" "$backup/retired-services.tar.gz.sha256"
chmod 600 "$backup/retired-services.tar.gz" "$backup/retired-services.tar.gz.sha256"
echo "Verified backup: $backup/retired-services.tar.gz"
for name in rmcf_compute rmcf-server-nginx-1; do
  if docker inspect "$name" >/dev/null 2>&1; then docker rm "$name"; fi
done
for volume in "${volumes[@]}"; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then docker volume rm "$volume"; fi
done
if docker network inspect rmcf-compute_default >/dev/null 2>&1; then
  docker network rm rmcf-compute_default
fi
for path in "${paths[@]}"; do
  if [[ -e $path ]]; then
    [[ ! -L $path && $(readlink -f -- "$path") == "$path" ]] || exit 1
    rm -rf -- "$path"
  fi
done
if [[ -f /etc/systemd/system/$runner && ! -L /etc/systemd/system/$runner ]]; then
  rm -- /etc/systemd/system/"$runner"
fi
systemctl daemon-reload
apt-get purge -y tinyproxy tinyproxy-bin
# Only the explicitly inspected obsolete images; never prune mail resources.
for image in 8189fec5b330 4a8a8a81cc16 532e0928289b eb3e82f41ae2 d7da856ff86d 2aa69b382a38 2fb88b98da9f 33198da2828a 8be9c9f10232 1d13701a5f9f af51b15dd3fc; do
  if docker image inspect "$image" >/dev/null 2>&1; then docker image rm "$image"; fi
done
for name in aryseller-mailserver aryseller-roundcube aryseller-caddy; do
  [[ $(docker inspect -f '{{.State.Running}}' "$name") == true ]] || exit 1
done
curl -fsS -o /dev/null https://mail.aryseller.com/
touch /home/traen/crawl4ai-migration/cleanup-complete
chown traen:traen /home/traen/crawl4ai-migration/cleanup-complete
echo 'CLEANUP_COMPLETE: aryseller mail preserved; ports 80/443 remain with its Caddy.'
