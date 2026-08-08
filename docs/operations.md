# Routine operations

## GitOps workflow

Create a branch, change manifests, run `pwsh ./scripts/validate.ps1`, open a pull request, and merge only after CI passes. Argo CD automatically syncs `main`, prunes removed resources, and self-heals manual changes. Stateful resources carry confirmation annotations to reduce accidental deletion risk.

Renovate opens scheduled pull requests. Review release notes, backup status, compatibility, and rollback steps before merging. Upgrade GitLab only along a supported upgrade path and never skip required stops.

## Daily checks

Use Grafana and Telegram alerts for normal monitoring. Investigate any failed or stale Velero backup, CNPG backup or WAL warning, K3s snapshot warning, unhealthy Longhorn volume, certificate expiry, or unavailable public probe.

Useful commands:

```bash
kubectl -n argocd get applications
kubectl get externalsecrets -A
kubectl -n longhorn-system get volumes.longhorn.io
kubectl -n velero get backup,backuprepository,dataupload
kubectl -n keycloak get cluster,backup,scheduledbackup,objectstore
kubectl get etcdsnapshotfile
kubectl get certificate -A
```

## Manual backup before risky work

```bash
velero backup create "gitlab-manual-$(date +%Y%m%d-%H%M)" \
  --from-schedule gitlab-daily \
  --wait
velero backup create "keycloak-logical-manual-$(date +%Y%m%d-%H%M)" \
  --from-schedule keycloak-daily \
  --wait
kubectl -n keycloak create -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  generateName: keycloak-manual-
  namespace: keycloak
spec:
  cluster:
    name: keycloak-db
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
sudo k3s etcd-snapshot save --name "manual-$(date +%Y%m%d-%H%M)" --s3
```

The GitLab Velero template creates application and configuration archives before snapshotting its staging PVC. The Keycloak Velero template creates and validates a logical dump before snapshotting its staging PVC. Wait for every backup to complete and confirm the off-site objects exist before proceeding. Never treat a `Completed` Kubernetes Job or Backup resource as restore proof. Follow the verification checks in `backups.md`.
