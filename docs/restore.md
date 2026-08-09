# Restore and disaster recovery

Test restores quarterly and after any backup tooling change. Never test a destructive restore against a production namespace.

The GitLab and Keycloak drills use the optional Velero CLI on the operator workstation. It is not installed on the K3s server by the bootstrap playbook.

## GitLab staging restore drill

Choose a completed backup, then restore only PVC resources into an isolated namespace. The live GitLab PVCs were excluded from the backup, so this restores the `gitlab-backups` staging PVC and its moved data.

```bash
backup_name="$(velero backup get -o json | jq -r '[.items[] | select(.status.phase == "Completed") | select(.metadata.labels["velero.io/schedule-name"] == "gitlab-daily")] | sort_by(.status.completionTimestamp) | last | .metadata.name')"
kubectl create namespace gitlab-restore
velero restore create "gitlab-drill-$(date +%s)" \
  --from-backup "$backup_name" \
  --include-namespaces gitlab \
  --namespace-mappings gitlab:gitlab-restore \
  --include-resources persistentvolumeclaims \
  --wait
kubectl -n gitlab-restore get pvc
kubectl -n velero get datadownload
```

Mount the restored PVC without starting GitLab:

```bash
kubectl -n gitlab-restore run backup-inspector \
  --image=alpine:3.23.3 \
  --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"backup-inspector","image":"alpine:3.23.3","command":["sleep","3600"],"volumeMounts":[{"name":"backups","mountPath":"/backups","readOnly":true}]}],"volumes":[{"name":"backups","persistentVolumeClaim":{"claimName":"gitlab-backups"}}]}}'
kubectl -n gitlab-restore wait pod/backup-inspector --for=condition=Ready --timeout=5m
kubectl -n gitlab-restore exec backup-inspector -- sh -c 'ls -lh /backups && tar -tf "$(ls -1t /backups/*_gitlab_backup.tar | head -1)" >/dev/null && tar -tf "$(ls -1t /backups/config/*.tar | head -1)" >/dev/null'
```

Confirm both archives are readable. Confirm the configuration archive contains `gitlab-secrets.json`, and confirm that file can also be recovered from the offline recovery kit. GitLab SSH is not exposed in this deployment, so host SSH keys are outside the recovery scope. Delete the isolated namespace only after recording the result.

For a full application drill, deploy the same GitLab version in an isolated namespace, mount the restored staging PVC at `/var/opt/gitlab/backups`, restore the configuration archive into `/etc/gitlab`, and run:

```bash
gitlab-backup restore BACKUP='<timestamp-and-version>' force=yes
gitlab-ctl reconfigure
gitlab-rake gitlab:check SANITIZE=true
gitlab-rake gitlab:doctor:secrets
```

Test sign-in, repository browsing, HTTPS clone and push, and registry pull and push.

## Keycloak logical restore drill

Choose a completed logical backup and restore its staging PVC into an isolated namespace:

```bash
backup_name="$(velero backup get -o json | jq -r '[.items[] | select(.status.phase == "Completed") | select(.metadata.labels["velero.io/schedule-name"] == "keycloak-daily")] | sort_by(.status.completionTimestamp) | last | .metadata.name')"
kubectl create namespace keycloak-logical-restore
velero restore create "keycloak-logical-drill-$(date +%s)" \
  --from-backup "$backup_name" \
  --include-namespaces keycloak \
  --namespace-mappings keycloak:keycloak-logical-restore \
  --include-resources persistentvolumeclaims \
  --wait
kubectl -n keycloak-logical-restore get pvc
kubectl -n velero get datadownload
```

Mount the restored PVC with the pinned PostgreSQL image and validate the newest archive:

```bash
kubectl -n keycloak-logical-restore run backup-inspector \
  --image=ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie \
  --restart=Never \
  --overrides='{"spec":{"securityContext":{"fsGroup":26},"containers":[{"name":"backup-inspector","image":"ghcr.io/cloudnative-pg/postgresql:18.1-standard-trixie","command":["sleep","3600"],"volumeMounts":[{"name":"backups","mountPath":"/backups","readOnly":true}]}],"volumes":[{"name":"backups","persistentVolumeClaim":{"claimName":"keycloak-backups"}}]}}'
kubectl -n keycloak-logical-restore wait pod/backup-inspector --for=condition=Ready --timeout=5m
kubectl -n keycloak-logical-restore exec backup-inspector -- sh -ec 'cd /backups; checksum="$(ls -1t keycloak-*.dump.sha256 | head -1)"; sha256sum -c "$checksum"; pg_restore --list "${checksum%.sha256}" >/dev/null'
```

For a full logical drill, create an empty isolated PostgreSQL 18 cluster with database and owner `keycloak`, then import with `pg_restore --exit-on-error --no-owner --no-acl`. Start a temporary Keycloak instance against it and verify realms, clients, users, and sign-in.

## Dependency-Track logical restore drill

Restore the staging PVC from the latest completed `dependency-track-daily` backup into an isolated namespace, following the Keycloak procedure with these substitutions:

| Keycloak value | Dependency-Track value |
| --- | --- |
| `keycloak-daily` | `dependency-track-daily` |
| `keycloak` | `dependency-track` |
| `keycloak-logical-restore` | `dependency-track-logical-restore` |
| `keycloak-backups` | `dependency-track-backups` |
| `keycloak-*.dump.sha256` | `dependency-track-*.dump.sha256` |

Restore both `dependency-track-backups` and `dependency-track-data` from the same recovery point. Before starting Dependency-Track, confirm `dependency-track-data` contains `.dependency-track/keys/secret-management-kek.json` and keep its contents out of logs and restore evidence.

Validate the dump checksum and archive with `sha256sum -c` and `pg_restore --list`. For a full drill, create an isolated PostgreSQL 18 cluster with database and owner `dependency-track`, import using `pg_restore --exit-on-error --no-owner --no-acl`, mount the restored data PVC, and start the same or a newer Dependency-Track API server. Confirm `/health/ready` returns `UP`, sign-in works, projects are present, stored integration secrets remain usable, and a test SBOM analysis completes.

## K3s control-plane restore

Provision an Ubuntu host with the pinned K3s version and retrieve the K3s token and S3 credentials from the offline recovery kit. Kubernetes Secrets are unavailable until etcd has been restored.

Stop K3s, restore the chosen S3 snapshot, then start it normally:

```bash
sudo systemctl stop k3s
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path='<snapshot-name>' \
  --token='<original-k3s-token>' \
  --etcd-s3 \
  --etcd-s3-endpoint='<endpoint-hostname>' \
  --etcd-s3-region='<region>' \
  --etcd-s3-bucket='mmlinaric-homelab-etcd' \
  --etcd-s3-folder='homelab/etcd' \
  --etcd-s3-access-key='<access-key>' \
  --etcd-s3-secret-key='<secret-key>'
sudo systemctl start k3s
```

Reapply the kube-vip manifest if needed, verify the API through `192.168.70.5`, and let Argo CD reconcile. Rotate any credential exposed during the recovery session.

## Longhorn local recovery

Longhorn snapshots are only local recovery points. Use them for a recent rollback while the Longhorn storage system is healthy. Restore a snapshot to a new volume, mount it read-only in a test pod, and validate files before considering any production replacement. They do not replace the off-site GitLab, Keycloak, or etcd restore paths.

## Evidence to record

For every drill, record the snapshot or backup ID, source timestamp, start and finish time, result, application version, data checks, and any manual intervention. Alerting proves a controller reported success. This evidence proves recovery works.
