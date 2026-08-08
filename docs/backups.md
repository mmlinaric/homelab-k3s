# Backup design and verification

The backup system has five independent layers. Each layer has one job and one tested restore path.

| Layer | Source | Off-site target | Retention |
| --- | --- | --- | --- |
| K3s control plane | Encrypted embedded-etcd snapshot | `mmlinaric-homelab-etcd`, prefix `homelab/etcd` | 28 snapshots, about 14 days |
| GitLab | Native application and configuration archives on `gitlab-backups` PVC | `mmlinaric-homelab-velero`, prefix `homelab` | 14 daily, 8 weekly, 12 monthly restore windows |
| Keycloak logical | Validated `pg_dump` archive on `keycloak-backups` PVC | `mmlinaric-homelab-velero`, prefix `homelab` | 14 daily, 8 weekly, 12 monthly restore windows |
| Keycloak physical | CNPG Barman base backups and WAL | `mmlinaric-homelab-keycloak`, prefix `keycloak` | 30-day PITR window |
| Local volumes | Longhorn snapshots | Cluster-local Longhorn storage | 3 daily snapshots plus weekly cleanup |

The weekly and monthly Velero schedules use TTL values of 56 days and 366 days. Their run frequency produces approximately 8 weekly and 12 monthly recovery points per application. Velero stores Kubernetes metadata in S3 and uses Kopia to encrypt and deduplicate moved volume data. OVH managed encryption protects all objects at rest, including metadata and CNPG or etcd objects that do not pass through Kopia.

## GitLab consistency boundary

The live `config`, `logs`, and `data` PVCs carry both `backup.homelab/strategy: native` and `velero.io/exclude-from-backup: "true"`. Velero therefore does not move crash-consistent copies of the live Omnibus filesystems.

Before every scheduled backup, Velero runs this hook in the GitLab container:

```bash
gitlab-backup create CRON=1
gitlab-ctl backup-etc --backup-path /var/opt/gitlab/backups/config
```

GitLab writes the native archive and its separate Omnibus configuration archive to `/var/opt/gitlab/backups`, which is the standalone 50 GiB `gitlab-backups` PVC. The configuration archive preserves `gitlab-secrets.json` and files under `/etc/gitlab` that the normal application archive excludes. That PVC carries `backup.homelab/strategy: velero`, so Longhorn CSI snapshot data movement sends it through Kopia to OVH S3. Kubernetes Secrets are excluded from Velero. The existing `gitlab-secrets.json` must also remain in Bitwarden and in the offline recovery kit.

Schedules use `Europe/Warsaw` through the Velero controller timezone:

| Schedule | Cron | TTL |
| --- | --- | --- |
| `gitlab-daily` | 03:00 every day | 336h |
| `gitlab-weekly` | 05:00 Sunday | 1344h |
| `gitlab-monthly` | 07:00 on day 1 | 8784h |

The schedules use a four-hour item-operation timeout and a two-hour GitLab hook timeout. Data movement concurrency starts at one per node. Kopia cache is limited to 2 GiB.

## Keycloak consistency boundaries

Keycloak has two independent PostgreSQL recovery formats. CNPG and Barman continuously archive WAL and create a physical base backup at 01:00. This provides the 30-day point-in-time recovery path.

Velero separately executes `/scripts/backup.sh` in the `keycloak-logical-backup` pod before snapshotting the 20 GiB `keycloak-backups` PVC. The script writes a PostgreSQL custom-format archive to a temporary filename, validates it with `pg_restore --list`, atomically renames it, writes a SHA-256 checksum, and removes staging files older than three days. A failed dump or validation fails the Velero backup before any snapshot is accepted.

The live CNPG PVC is not selected by these schedules. Only the backup helper and staging PVC carry `backup.homelab/strategy: velero`.

| Schedule | Cron | TTL |
| --- | --- | --- |
| `keycloak-daily` | 02:00 every day | 336h |
| `keycloak-weekly` | 04:00 Sunday | 1344h |
| `keycloak-monthly` | 06:00 on day 1 | 8784h |

Barman objects do not pass through Kopia. They use TLS in transit and OVH managed encryption at rest. The logical archive is the client-encrypted, portable recovery layer; Barman remains the PITR layer.

## First backup activation

Generate the Kopia repository password before creating the first backup. Use at least 32 random bytes, store the value in Bitwarden, and place its secret UUID in `CHANGE_ME_BWS_VELERO_REPOSITORY_PASSWORD_ID`. This password must never be rotated after the first repository is created. A different password makes existing Kopia data unreadable.

After Argo CD is healthy:

```bash
kubectl -n velero get backupstoragelocation default
kubectl -n velero get externalsecret velero-credentials velero-repo-credentials
kubectl -n velero get daemonset node-agent
velero backup create gitlab-initial --from-schedule gitlab-daily --wait
velero backup describe gitlab-initial --details
kubectl -n velero get dataupload -l velero.io/backup-name=gitlab-initial
velero backup create keycloak-initial --from-schedule keycloak-daily --wait
velero backup describe keycloak-initial --details
kubectl -n velero get dataupload -l velero.io/backup-name=keycloak-initial
```

Do not proceed until both backups are `Completed`, their hooks show zero failures, their DataUploads are complete, and new objects are visible in `mmlinaric-homelab-velero`.

## Routine verification

Run these checks after upgrades and at least monthly:

```bash
velero schedule get
velero backup get
kubectl -n velero get backuprepository,dataupload
kubectl -n keycloak get backup,scheduledbackup,objectstore
kubectl get etcdsnapshotfile
kubectl -n longhorn-system get recurringjobs.longhorn.io
```

Quarterly, perform all four off-site restore drills described in `restore.md`. Record the backup ID, source timestamp, restore duration, application version, checks performed, and result.

## Failure boundaries

- Velero does not replace `gitlab-backup`. The native archive is the application-consistent artifact.
- Velero does not snapshot the live Keycloak database. It moves a validated logical dump, while CNPG and Barman own physical backup and PITR.
- Velero does not back up embedded etcd. K3s owns control-plane snapshots.
- Longhorn snapshots are fast local rollback points. They are not off-site backups.
- Prometheus history, Alertmanager state, and Grafana local state are disposable. Persist dashboard and alert changes in Git.
- Git does not contain secret values. Bitwarden availability and the offline recovery kit are part of disaster recovery.
