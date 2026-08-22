# Migration runbook

The migration keeps the old Docker services authoritative until the final export. GitLab and Keycloak remain on the exact application versions used by the old stack during the move.

## Rehearsal

1. Deploy the new cluster and wait for all controllers and storage to become healthy.
2. Use workstation hosts-file entries to test the new ingress without changing shared DNS.
3. Run `scripts/export-current.sh` on the old Docker host.
4. Copy the export directory to the administrative workstation over SSH.
5. Restore both applications into the new cluster using the procedures below.
6. Test Keycloak login, GitLab login, clone over HTTPS, push over HTTPS, project browsing, and registry pull and push.
7. Delete the rehearsal data or repeat the final restore during the cutover.

## Pre-flight checks

Perform these checks before announcing the maintenance window. Both GitLab
instances must run the same GitLab version. The manifest currently pins the
target to 19.2.1-ce.0, matching the old Compose service.

```bash
# On the old Docker host
docker exec gitlab gitlab-rake gitlab:env:info | grep -E 'GitLab version|GitLab Shell version'
docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'gitlab|keycloak'

# On the K3s server
sudo k3s kubectl -n gitlab exec gitlab-0 -- gitlab-rake gitlab:env:info | grep -E 'GitLab version|GitLab Shell version'
sudo k3s kubectl -n keycloak get keycloak,keycloak-db
sudo k3s kubectl -n velero get backupstoragelocation default
```

The old Docker runner is not migrated by this runbook. It uses Docker socket
access and has no equivalent workload in this repository. If any project needs
CI during or after cutover, deploy and register a Kubernetes-executor GitLab
Runner before retiring the old host.

## Final export

Announce the maintenance window. Stop writes before exporting:

```bash
docker stop gitlab-runner
docker stop keycloak
docker exec gitlab gitlab-rails runner 'ApplicationSetting.current.update!(maintenance_mode: true)'
./scripts/export-current.sh ./migration-final
cd migration-final && sha256sum -c SHA256SUMS
```

Copy the directory to the workstation. Keep the old data and containers intact until the acceptance checks and backup jobs succeed.

For example, from the administrative workstation:

```bash
scp -r <old-user>@<old-host>:<path-to-homelab>/migration-final ./
cd migration-final && sha256sum -c SHA256SUMS
```

Before restoring GitLab, open the `gitlab-secrets-json` item in Bitwarden
Secrets Manager and replace its value with the exact contents of
`migration-final/gitlab-secrets.json`. This is JSON text, not base64 text and
not a quoted JSON string. Then force the target ExternalSecret to refresh:

```bash
sudo k3s kubectl -n gitlab annotate externalsecret gitlab-secrets-json \
  force-sync="$(date +%s)" --overwrite
sudo k3s kubectl -n gitlab wait --for=condition=Ready \
  externalsecret/gitlab-secrets-json --timeout=2m
```

## Restore Keycloak

Pause the Keycloak operator and generated StatefulSet so the database stays quiet:

```bash
kubectl -n keycloak scale deployment keycloak-operator --replicas=0
kubectl -n keycloak scale statefulset keycloak --replicas=0
dbpod="$(kubectl -n keycloak get pod -l cnpg.io/cluster=keycloak-db,role=primary -o jsonpath='{.items[0].metadata.name}')"
dbpassword="$(kubectl -n keycloak get secret keycloak-database -o jsonpath='{.data.password}' | base64 -d)"
kubectl -n keycloak exec "$dbpod" -- env PGPASSWORD="$dbpassword" psql -h keycloak-db-rw -U keycloak -d keycloak -c 'select pg_terminate_backend(pid) from pg_stat_activity where datname = '\''keycloak'\'' and pid <> pg_backend_pid();'
kubectl -n keycloak exec -i "$dbpod" -- env PGPASSWORD="$dbpassword" psql -h keycloak-db-rw -U keycloak -d keycloak < migration-final/keycloak.sql
kubectl -n keycloak scale deployment keycloak-operator --replicas=1
```

The operator returns Keycloak to one replica. Wait for readiness and test the existing realm before proceeding.

## Restore GitLab

GitLab restores require the matching `gitlab-secrets.json` from the old
instance. Copy both it and the backup archive while GitLab is stopped. This
avoids accidentally retaining the fresh cluster's generated secrets.

```bash
sudo k3s kubectl -n gitlab scale statefulset gitlab --replicas=0
sudo k3s kubectl -n gitlab wait --for=delete pod/gitlab-0 --timeout=10m

sudo k3s kubectl -n gitlab run migration-loader --image=busybox:1.37.0 \
  --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"migration-loader","image":"busybox:1.37.0","command":["sleep","3600"],"volumeMounts":[{"name":"config","mountPath":"/config"},{"name":"backups","mountPath":"/backups"}]}],"volumes":[{"name":"config","persistentVolumeClaim":{"claimName":"config-gitlab-0"}},{"name":"backups","persistentVolumeClaim":{"claimName":"gitlab-backups"}}]}}'
sudo k3s kubectl -n gitlab wait pod/migration-loader --for=condition=Ready --timeout=2m

backup_file="$(basename migration-final/*_gitlab_backup.tar)"
sudo k3s kubectl -n gitlab cp "migration-final/gitlab-secrets.json" \
  migration-loader:/config/gitlab-secrets.json
sudo k3s kubectl -n gitlab cp "migration-final/${backup_file}" \
  "migration-loader:/backups/${backup_file}"
sudo k3s kubectl -n gitlab exec migration-loader -- sh -ec \
  'chmod 0600 /config/gitlab-secrets.json; sha256sum /config/gitlab-secrets.json /backups/*_gitlab_backup.tar'
sudo k3s kubectl -n gitlab delete pod migration-loader --wait=true

sudo k3s kubectl -n gitlab scale statefulset gitlab --replicas=1
sudo k3s kubectl -n gitlab rollout status statefulset/gitlab --timeout=30m
backup_id="${backup_file%_gitlab_backup.tar}"
sudo k3s kubectl -n gitlab exec gitlab-0 -- gitlab-ctl stop puma
sudo k3s kubectl -n gitlab exec gitlab-0 -- gitlab-ctl stop sidekiq
sudo k3s kubectl -n gitlab exec gitlab-0 -- gitlab-backup restore BACKUP="$backup_id" force=yes
sudo k3s kubectl -n gitlab exec gitlab-0 -- gitlab-ctl reconfigure
sudo k3s kubectl -n gitlab exec gitlab-0 -- gitlab-ctl restart
sudo k3s kubectl -n gitlab rollout status statefulset/gitlab --timeout=30m
```

Run GitLab's checks:

```bash
sudo k3s kubectl -n gitlab exec gitlab-0 -- gitlab-rake gitlab:check SANITIZE=true
sudo k3s kubectl -n gitlab exec gitlab-0 -- gitlab-rake gitlab:doctor:secrets
```

## Cutover and acceptance

1. Point LAN split DNS at `192.168.60.100` and confirm the Cloudflare Tunnel routes are healthy.
2. Remove any workstation hosts-file overrides.
3. Test Keycloak admin only from the LAN. Confirm public `/admin` and `/realms/master` routes return 404.
4. Test GitLab OIDC, HTTPS Git operations, and registry operations.
5. Create manual Velero backups from `gitlab-daily` and `keycloak-daily`. Confirm both complete and objects appear in OVH Object Storage.
6. Confirm Telegram receives a test alert.
7. Keep the old host powered off but recoverable for at least one week. Decommission unused Compose applications only after that hold period.

Rollback consists of restoring the old DNS targets, starting the old containers, disabling GitLab maintenance mode, and treating any writes made on K3s as a separate reconciliation task.
