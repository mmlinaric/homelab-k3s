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

The `gitlab-secrets.json` Bitwarden entry must contain the exported file before the first production restore. Sync the ExternalSecret, then recreate the GitLab pod if the old secret had already been copied into its config PVC.

Copy the backup into the dedicated backup staging PVC with a temporary pod:

```bash
kubectl -n gitlab scale statefulset gitlab --replicas=0
kubectl -n gitlab run backup-loader --image=busybox:1.37.0 --restart=Never --overrides='{"spec":{"containers":[{"name":"backup-loader","image":"busybox:1.37.0","command":["sleep","3600"],"volumeMounts":[{"name":"backups","mountPath":"/backups"}]}],"volumes":[{"name":"backups","persistentVolumeClaim":{"claimName":"gitlab-backups"}}]}}'
kubectl -n gitlab wait pod/backup-loader --for=condition=Ready --timeout=120s
backup_file="$(basename migration-final/*_gitlab_backup.tar)"
kubectl -n gitlab cp "migration-final/${backup_file}" "backup-loader:/backups/${backup_file}"
kubectl -n gitlab delete pod backup-loader
kubectl -n gitlab scale statefulset gitlab --replicas=1
kubectl -n gitlab rollout status statefulset/gitlab --timeout=30m
backup_id="${backup_file%_gitlab_backup.tar}"
kubectl -n gitlab exec gitlab-0 -- gitlab-backup restore BACKUP="$backup_id" force=yes
kubectl -n gitlab exec gitlab-0 -- gitlab-ctl reconfigure
kubectl -n gitlab exec gitlab-0 -- gitlab-ctl restart
```

Run GitLab's checks:

```bash
kubectl -n gitlab exec gitlab-0 -- gitlab-rake gitlab:check SANITIZE=true
kubectl -n gitlab exec gitlab-0 -- gitlab-rake gitlab:doctor:secrets
```

## Cutover and acceptance

1. Point LAN split DNS at `192.168.70.100` and confirm the Cloudflare Tunnel routes are healthy.
2. Remove any workstation hosts-file overrides.
3. Test Keycloak admin only from the LAN. Confirm public `/admin` and `/realms/master` routes return 404.
4. Test GitLab OIDC, HTTPS Git operations, and registry operations.
5. Create manual Velero backups from `gitlab-daily` and `keycloak-daily`, plus a manual CNPG backup. Confirm all three complete and objects appear in OVH Object Storage.
6. Confirm Telegram receives a test alert.
7. Keep the old host powered off but recoverable for at least one week. Decommission unused Compose applications only after that hold period.

Rollback consists of restoring the old DNS targets, starting the old containers, disabling GitLab maintenance mode, and treating any writes made on K3s as a separate reconciliation task.
