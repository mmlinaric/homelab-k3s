# Routine operations

## GitOps workflow

Create a branch, change manifests, run `pwsh ./scripts/validate.ps1`, open a pull request, and merge only after CI passes. Argo CD automatically syncs `main`, prunes removed resources, and self-heals manual changes. Stateful resources carry confirmation annotations to reduce accidental deletion risk.

Renovate opens scheduled pull requests. Review release notes, backup status, compatibility, and rollback steps before merging. Upgrade GitLab only along a supported upgrade path and never skip required stops.

## Daily checks

Use Grafana and Telegram alerts for normal monitoring. Investigate any failed or stale Velero backup, K3s snapshot warning, unhealthy Longhorn volume, certificate expiry, or unavailable endpoint probe. The blackbox exporter checks the LAN-only Jenkins login endpoint from inside the cluster.

Useful commands:

```bash
kubectl -n argocd get applications
kubectl get externalsecrets -A
kubectl -n longhorn-system get volumes.longhorn.io
kubectl -n velero get backups.velero.io,backuprepositories.velero.io,datauploads.velero.io
kubectl -n keycloak get cluster
kubectl -n jenkins get statefulset,pvc
kubectl get etcdsnapshotfile
kubectl get certificate -A
```

## Centralized logs

Grafana Explore has a provisioned `Loki` data source. Alloy runs once per node and collects the containers on that node through the Kubernetes pod log API. Loki retains logs for seven days on a 10 Gi Longhorn volume.

Useful LogQL queries:

```logql
{cluster="homelab"}
{cluster="homelab", namespace="gitlab"}
{cluster="homelab", namespace="keycloak"} |= "error"
{cluster="homelab", namespace="jenkins"} |= "SEVERE"
```

Check the pipeline without exposing Loki outside the cluster:

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/instance=loki
kubectl -n monitoring get pvc storage-loki-0
kubectl -n monitoring get daemonset alloy
kubectl -n monitoring logs daemonset/alloy --tail=100
kubectl -n monitoring port-forward service/loki 3100:3100
curl -fsS http://127.0.0.1:3100/ready
```

Retention is enforced by Loki's compactor. Increase both `loki.limits_config.retention_period` and the `singleBinary.persistence.size` value together if seven days consistently approaches the volume capacity.

Logging alerts use two paths. Prometheus evaluates Loki, Alloy, canary, and storage health rules. Loki's ruler evaluates LogQL rules for GitLab and Keycloak error bursts and fatal signatures. Both paths send firing alerts to the existing Alertmanager and Telegram receiver. Keep generic error thresholds conservative; add application-specific signatures only after confirming the exact production log format in Logs Drilldown.

Longhorn access requires both a client address in the administrator LAN `192.168.88.0/24` and the Keycloak client role `longhorn:admin`. Verify the controls after authentication or network changes:

```bash
curl -Ik --resolve longhorn.mmlinaric.com:443:192.168.70.100 https://longhorn.mmlinaric.com/
kubectl -n longhorn-system logs deployment/longhorn-oauth2-proxy
```

An unauthenticated LAN request must redirect to Keycloak. A user without `longhorn:admin` must receive an authorization failure, while a user with the role must reach the Longhorn UI. A request originating outside `192.168.88.0/24` must receive HTTP 403 before authentication.

## Manual backup before risky work

```bash
for schedule in gitlab-daily keycloak-daily; do
  name="${schedule}-manual-$(date +%Y%m%d-%H%M)"
  kubectl -n velero get schedule "$schedule" -o json |
    jq --arg name "$name" '{
      apiVersion: "velero.io/v1",
      kind: "Backup",
      metadata: {name: $name, namespace: "velero", labels: {"velero.io/schedule-name": .metadata.name}},
      spec: .spec.template
    }' |
    kubectl apply -f -
done
sudo k3s etcd-snapshot save --name "manual-$(date +%Y%m%d-%H%M)" --s3
```

The GitLab Velero template creates application and configuration archives before snapshotting its staging PVC. The Keycloak Velero template creates and validates a logical dump before snapshotting its staging PVC. For Jenkins, first use Manage Jenkins, ThinBackup, Backup Now and confirm a new complete set exists on `jenkins-backups`; then create a manual backup from `jenkins-daily` using the same command pattern. Wait for every backup to complete and confirm the off-site objects exist before proceeding. Never treat a `Completed` Kubernetes Job or Backup resource as restore proof. Follow the verification checks in `backups.md`.
