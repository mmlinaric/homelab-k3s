# Secrets and configuration

No secret value belongs in Git. Bitwarden Secrets Manager is the source of truth, and External Secrets Operator materializes Kubernetes Secrets.

## Bootstrap values

Edit `ansible/group_vars/all.yml` and set the Bitwarden organization and project IDs. Confirm `ansible/inventory/hosts.yml` contains the correct SSH user and node address. The expected primary interface is `ens18`.

Export these variables on the Ansible controller before bootstrap:

```bash
export K3S_SERVER_TOKEN='a-long-random-cluster-token'
export BWS_ACCESS_TOKEN='your-machine-account-access-token'
export GITHUB_REPO_USERNAME='your-github-user'
export GITHUB_REPO_TOKEN='a-fine-grained-read-only-token'
```

The GitHub token only needs read access to the private repository. The Bitwarden machine account should only see the homelab project.

## Bitwarden entries

Create one Bitwarden secret per value below. Replace each `CHANGE_ME_BWS_*_ID` in the repository with the UUID of that secret, not its value.

| Area | Required values |
| --- | --- |
| Cloudflare | API token with DNS edit rights for the zone, tunnel credentials JSON |
| Keycloak | database username and password, PostgreSQL superuser username and password, bootstrap admin username and password, S3 access key and secret key |
| GitLab | existing `gitlab-secrets.json`, OIDC client secret, Restic repository, Restic password, S3 access key and secret key |
| Grafana | admin username and password, Keycloak OIDC client secret |
| Alertmanager | Telegram bot token and numeric chat ID |
| Longhorn | S3 access key and secret key |
| K3s etcd | S3 access key, secret key, and bucket |
| Shared S3 | endpoint and region |
| Argo CD | Keycloak OIDC client secret |

Also replace these non-secret placeholders:

```text
CHANGE_ME_BITWARDEN_ORGANIZATION_ID
CHANGE_ME_BITWARDEN_PROJECT_ID
CHANGE_ME_LONGHORN_BUCKET
CHANGE_ME_KEYCLOAK_BACKUP_BUCKET
CHANGE_ME_CONTABO_S3_ENDPOINT
CHANGE_ME_CONTABO_REGION
```

Find every unresolved value with:

```bash
rg -n CHANGE_ME .
```

## Keycloak clients

Create confidential clients in the `homelab` realm:

| Client | Redirect URI |
| --- | --- |
| `gitlab` | `https://gitlab.mmlinaric.com/users/auth/openid_connect/callback` |
| `grafana` | `https://grafana.mmlinaric.com/login/generic_oauth` |
| `argocd` | `https://argocd.mmlinaric.com/auth/callback` |

For Grafana, add a client role named `admin` and assign it only to administrators. The default mapped role is Viewer.

## Rotation

External Secrets refreshes values hourly. Most applications need a rollout after credential rotation because environment variables are read at process start. Restart only the affected workload, then verify login and backup access.
