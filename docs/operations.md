# Routine operations

## GitOps workflow

Create a branch, change manifests, run `pwsh ./scripts/validate.ps1`, open a pull request, and merge only after CI passes. Argo CD automatically syncs `main`, prunes removed resources, and self-heals manual changes. Stateful resources carry confirmation annotations to reduce accidental deletion risk.

Renovate opens scheduled pull requests. Review release notes, backup status, compatibility, and rollback steps before merging. Upgrade GitLab only along a supported upgrade path and never skip required stops.

## Daily checks

Use Grafana and Telegram alerts for normal monitoring. Investigate any failed or stale Velero backup, K3s snapshot warning, unhealthy Longhorn volume, certificate expiry, or unavailable public probe.

Useful commands:

```bash
kubectl -n argocd get applications
kubectl get externalsecrets -A
kubectl -n longhorn-system get volumes.longhorn.io
kubectl -n velero get backups.velero.io,backuprepositories.velero.io,datauploads.velero.io
kubectl -n keycloak get cluster
kubectl get etcdsnapshotfile
kubectl get certificate -A
```

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

The GitLab Velero template creates application and configuration archives before snapshotting its staging PVC. The Keycloak Velero template creates and validates a logical dump before snapshotting its staging PVC. Wait for every backup to complete and confirm the off-site objects exist before proceeding. Never treat a `Completed` Kubernetes Job or Backup resource as restore proof. Follow the verification checks in `backups.md`.
