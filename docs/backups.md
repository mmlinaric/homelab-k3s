# Backup design and verification

The backup system has four independent layers. Each layer has one job and one tested restore path.

| Layer | Source | Off-site target | Retention |
| --- | --- | --- | --- |
| K3s control plane | Encrypted embedded-etcd snapshot | `mmlinaric-homelab-etcd`, prefix `homelab/etcd` | 28 snapshots, about 14 days |
| GitLab | Native application and configuration archives on `gitlab-backups` PVC | `mmlinaric-homelab-velero`, prefix `homelab` | 14 daily, 8 weekly, 12 monthly restore windows |
| Forgejo | Quiesced `forgejo-data` snapshot and validated PostgreSQL dump on `forgejo-backups` | `mmlinaric-homelab-velero`, prefix `homelab` | 14 daily, 8 weekly, 12 monthly restore windows |
| Keycloak logical | Validated `pg_dump` archive on `keycloak-backups` PVC | `mmlinaric-homelab-velero`, prefix `homelab` | 14 daily, 8 weekly, 12 monthly restore windows |
| Dependency-Track logical | Validated `pg_dump` archive on `dependency-track-backups` PVC | `mmlinaric-homelab-velero`, prefix `homelab` | 14 daily, 8 weekly, 12 monthly restore windows |
| Jenkins | Crash-consistent `JENKINS_HOME` snapshot plus idle thinBackup set | `mmlinaric-homelab-velero`, prefix `homelab` | 14 daily, 8 weekly, 12 monthly restore windows |
| Local volumes | Longhorn snapshots | Cluster-local Longhorn storage | 3 daily snapshots plus weekly cleanup |
| Wazuh `sec1` | OpenSearch snapshot plus manager/runtime state, encrypted by Restic | `mmlinaric-homelab-wazuh`, prefix `restic/sec1` | 14 daily, 8 weekly, 12 monthly recovery points |

The weekly and monthly Velero schedules use TTL values of 56 days and 366 days. Their run frequency produces approximately 8 weekly and 12 monthly recovery points per application. Velero stores Kubernetes metadata in S3 and uses Kopia to encrypt and deduplicate moved volume data. OVH managed encryption protects the etcd objects at rest.

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

Velero executes `/scripts/backup.sh` in the `keycloak-logical-backup` pod before snapshotting the 20 GiB `keycloak-backups` PVC. The script writes a PostgreSQL custom-format archive to a temporary filename, validates it with `pg_restore --list`, atomically renames it, writes a SHA-256 checksum, and removes staging files older than three days. A failed dump or validation fails the Velero backup before any snapshot is accepted.

The live CNPG PVC is not selected by these schedules. Only the backup helper and staging PVC carry `backup.homelab/strategy: velero`.

| Schedule | Cron | TTL |
| --- | --- | --- |
| `keycloak-daily` | 02:00 every day | 336h |
| `keycloak-weekly` | 04:00 Sunday | 1344h |
| `keycloak-monthly` | 06:00 on day 1 | 8784h |

Keycloak recovery is limited to the latest successfully completed logical backup. Point-in-time recovery is intentionally unavailable because Barman WAL and physical backups would not have a client-side encryption layer.

## Forgejo consistency boundary

Forgejo stores repositories and application-generated secrets on `forgejo-data` while relational metadata lives in `forgejo-db`. Forgejo does not provide a GitLab-equivalent online backup that guarantees these stores represent one point in time, and upstream warns against relying on the database copy embedded by `forgejo dump`.

Before Velero snapshots either PVC, the hook on `forgejo-backup` scales the Forgejo deployment to zero, waits for the pod to exit, creates a PostgreSQL custom-format dump through the CNPG primary, validates it with `pg_restore --list`, and writes a SHA-256 checksum. With application writes stopped, Velero captures the live `forgejo-data` volume and the matching database dump, then the post-hook immediately restores one Forgejo replica. The off-site Kopia transfer continues independently. A watchdog restores the replica if the hook path leaves Forgejo stopped for more than 30 minutes.

This deliberate interruption normally lasts only through shutdown, dump, and CSI snapshot creation. Blackbox alerting waits five minutes to avoid notifying on a normal short backup window.

| Schedule | Cron | TTL |
| --- | --- | --- |
| `forgejo-daily` | 04:00 every day | 336h |
| `forgejo-weekly` | 06:00 Sunday | 1344h |
| `forgejo-monthly` | 09:00 on day 1 | 8784h |

Always restore `forgejo-data` and the database dump from the same Velero backup. Do not combine a repository snapshot from one recovery point with a dump from another.

## Dependency-Track consistency boundary

Dependency-Track uses the same logical database backup pattern as Keycloak. Before Velero snapshots the `dependency-track-backups` staging PVC, it runs `pg_dump`, validates the custom-format archive with `pg_restore --list`, and writes a SHA-256 checksum. The live CNPG volume is not selected.

The same Velero recovery point also moves the `dependency-track-data` PVC through Kopia. Most of this volume is optional short-lived file storage, but `/data/.dependency-track/keys/secret-management-kek.json` is required to decrypt integration secrets stored in PostgreSQL. Kopia encrypts both PVCs before upload; the OVH S3 provider cannot read the dump, keyset, or transient files without the repository password held in Bitwarden and the offline recovery kit. After KEK rotation, trigger and verify a new backup immediately.

| Schedule | Cron | TTL |
| --- | --- | --- |
| `dependency-track-daily` | 01:00 every day | 336h |
| `dependency-track-weekly` | 03:00 Sunday | 1344h |
| `dependency-track-monthly` | 05:00 on day 1 | 8784h |

Restore the database and `dependency-track-data` PVC from the same recovery point into the same or a newer Dependency-Track version. Start one API server after import, wait for its readiness endpoint, and let schema migrations complete before restoring normal replica counts.

## Jenkins consistency boundary

Both the live `jenkins` PVC and the separate `jenkins-backups` PVC carry `backup.homelab/strategy: velero`. Every Jenkins Velero schedule snapshots both volumes and moves their data through Kopia to OVH S3. The live PVC is a crash-consistent copy of `JENKINS_HOME`; it includes controller configuration, jobs, build records, UI-managed credentials, and the controller encryption keys required to decrypt them.

The maintained thinBackup plugin provides a second, application-aware recovery path. It waits until Jenkins is idle, enters quiet mode if necessary, and writes a full backup to the separate 20 GiB `jenkins-backups` PVC at 23:00. It retains seven local full sets. Workspaces, archived artifacts, downloaded tools, plugin binaries, and controller keys are excluded; configuration, jobs, build records, and next build numbers are retained. A thinBackup-only restore therefore requires credentials to be recreated from Bitwarden and JCasC, while a successful restore of the live PVC preserves UI-managed credentials together with their encryption keys.

UI-managed credentials and plugin settings persist across ordinary controller restarts on the live `jenkins` PVC. The Helm chart must keep `controller.JCasC.overwriteConfiguration: false` so its init container does not delete controller and plugin-owned XML during pod recreation, and JCasC must not declare a partial credentials list because that replaces credentials outside the list. Important credentials should still remain declarative in Bitwarden and JCasC so recovery does not depend exclusively on a crash-consistent controller snapshot.

The `jenkins-ci-cache` and `buildkit-data-buildkit-0` PVCs are rebuildable caches and intentionally carry no Velero backup label.

Velero snapshots and moves both the live and backup PVCs after the thinBackup application window:

| Schedule | Cron | TTL |
| --- | --- | --- |
| `jenkins-daily` | 00:30 every day | 336h |
| `jenkins-weekly` | 02:30 Sunday | 1344h |
| `jenkins-monthly` | 08:30 on day 1 | 8784h |

Before accepting a Jenkins recovery point, confirm that thinBackup created a new complete set before the Velero backup began and that two DataUploads completed: one for `jenkins` and one for `jenkins-backups`. An older thinBackup set is retained deliberately if a long build prevents the newest scheduled backup from reaching an idle boundary. A completed DataUpload proves that volume data reached the Kopia repository, but only a restore drill proves that the crash-consistent Jenkins home can start cleanly.

## First backup activation

### Wazuh activation

The `sec1` backup is independent of Velero. Its systemd job briefly stops
manager ingestion, creates a completed OpenSearch snapshot, captures the
official Wazuh central-component state, restarts ingestion, and commits the
combined recovery point to an encrypted Restic repository. See `wazuh.md` for
bucket preparation, secret names, manual execution, and recovery.

Do not accept the first recovery point until the OpenSearch snapshot reports
`SUCCESS`, Restic lists the tagged snapshot, its checksum manifest validates,
and the dedicated Telegram group receives the success notification.

Generate the Kopia repository password before creating the first backup. Use at least 32 random bytes, store the value in Bitwarden, and place its secret UUID in `CHANGE_ME_BWS_VELERO_REPOSITORY_PASSWORD_ID`. This password must never be rotated after the first repository is created. A different password makes existing Kopia data unreadable.

After Argo CD is healthy:

```bash
kubectl -n velero get backupstoragelocation default
kubectl -n velero get externalsecret velero-credentials velero-repo-credentials
kubectl -n velero get daemonset node-agent
kubectl -n velero get backups.velero.io
kubectl -n velero get datauploads.velero.io
```

Do not proceed until the initial backups are `Completed`, their hooks show zero failures, their DataUploads are complete, and new objects are visible in `mmlinaric-homelab-velero`.

## Routine verification

Run these checks after upgrades and at least monthly:

```bash
velero schedule get
velero backup get
kubectl -n velero get backuprepository,dataupload
kubectl get etcdsnapshotfile
kubectl -n longhorn-system get recurringjobs.longhorn.io
```

Quarterly, perform every applicable restore drill described in `restore.md`. Record the backup ID, source timestamp, restore duration, application version, checks performed, and result.

## Failure boundaries

- Velero does not replace `gitlab-backup`. The native archive is the application-consistent artifact.
- Velero snapshots Forgejo repositories only while Forgejo is stopped and pairs that snapshot with a validated PostgreSQL dump.
- Velero does not snapshot the live Keycloak or Dependency-Track databases. It moves validated logical dumps and provides their off-site recovery paths.
- Velero does not back up embedded etcd. K3s owns control-plane snapshots.
- Velero moves both a crash-consistent live Jenkins home and the application-aware thinBackup sets. Prefer the live PVC for exact controller recovery and retain Bitwarden, Git, and thinBackup as independent recovery paths.
- Wazuh index history is backed up with the OpenSearch snapshot API. Never copy the live `/var/lib/wazuh-indexer` tree as a recovery method.
- Longhorn snapshots are fast local rollback points. They are not off-site backups.
- Prometheus history, Alertmanager state, and Grafana local state are disposable. Persist dashboard and alert changes in Git.
- Git does not contain secret values. Bitwarden availability and the offline recovery kit are part of disaster recovery.
