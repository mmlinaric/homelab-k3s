# Restore and disaster recovery

Test restores quarterly and after any backup tooling change. Never test a destructive restore against the production namespace.

## GitLab file-level restore drill

Create an isolated namespace and PVC, run a Restic pod with the `gitlab-restic` credentials copied into that namespace, and restore the latest snapshot. Confirm that a GitLab backup tar exists and passes `tar -tf`. Confirm `gitlab-secrets.json` is present in Bitwarden and can be materialized. A full application drill should deploy the same GitLab version and follow the GitLab restore section in `migration.md`.

## Keycloak database restore drill

Create a separate CNPG Cluster and a new ObjectStore that points at the existing backup prefix. Bootstrap the test Cluster with `recovery.objectStore` and a new target time or backup ID. Connect with `psql`, count realm and user records, then start a temporary Keycloak instance against the restored database. Delete only the test namespace after recording the result.

## Longhorn restore drill

Use the Longhorn UI to restore one backup as a new volume, create a temporary PVC from it, and mount it read-only in a test pod. Check expected files and record the backup timestamp. Do not attach a restored volume to an active production StatefulSet.

## K3s control-plane restore

Provision an Ubuntu host with the same K3s version. Supply the S3 settings directly during disaster recovery because Kubernetes Secrets are not available before etcd is restored. Download or identify the desired snapshot, then run:

```bash
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path='<snapshot-name>' \
  --etcd-s3 \
  --etcd-s3-endpoint='<endpoint>' \
  --etcd-s3-bucket='<bucket>' \
  --etcd-s3-access-key='<access-key>' \
  --etcd-s3-secret-key='<secret-key>'
sudo systemctl start k3s
```

Reapply the kube-vip manifest if needed, verify the API through `192.168.70.5`, and let Argo CD reconcile. Rotate any credential exposed during the recovery session.

## Evidence to record

For every drill, record the snapshot or backup ID, start and finish time, result, application version, data checks, and any manual intervention. Alerting proves a job ran; this evidence proves recovery works.
