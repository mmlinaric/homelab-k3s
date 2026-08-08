#!/usr/bin/env bash
set -euo pipefail

output_dir="${1:-./migration-export}"
mkdir -p "${output_dir}"

docker exec keycloak-db pg_dump \
  --username keycloak \
  --dbname keycloak \
  --clean \
  --if-exists \
  --no-owner \
  --no-acl > "${output_dir}/keycloak.sql"

docker exec gitlab gitlab-backup create CRON=1
gitlab_backup="$(docker exec gitlab sh -c 'ls -1t /var/opt/gitlab/backups/*_gitlab_backup.tar | head -n 1')"
docker cp "gitlab:${gitlab_backup}" "${output_dir}/"
docker exec gitlab cat /etc/gitlab/gitlab-secrets.json > "${output_dir}/gitlab-secrets.json"

(
  cd "${output_dir}"
  sha256sum keycloak.sql ./*_gitlab_backup.tar gitlab-secrets.json > SHA256SUMS
)

printf 'Migration export written to %s\n' "${output_dir}"
