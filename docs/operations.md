# Routine operations

## GitOps workflow

Create a branch, change manifests, run `pwsh ./scripts/validate.ps1`, open a pull request, and merge only after CI passes. Argo CD automatically syncs `main`, prunes removed resources, and self-heals manual changes. Stateful resources carry confirmation annotations to reduce accidental deletion risk.

Renovate opens scheduled pull requests. Review release notes, backup status, compatibility, and rollback steps before merging. Upgrade GitLab only along a supported upgrade path and never skip required stops.

## Daily checks

Use Grafana and Telegram alerts for normal monitoring. Investigate any failed CronJob, stale backup, unhealthy Longhorn volume, CNPG warning, certificate expiry, or unavailable public probe.

Useful commands:

```bash
kubectl -n argocd get applications
kubectl get externalsecrets -A
kubectl -n longhorn-system get volumes.longhorn.io
kubectl -n keycloak get cluster,backup
kubectl -n gitlab get cronjob,job
kubectl get certificate -A
```

## Manual backup before risky work

```bash
kubectl -n gitlab create job --from=cronjob/gitlab-backup "gitlab-backup-$(date +%s)"
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

Wait for each backup to complete and confirm the off-site object exists before proceeding.
