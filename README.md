# Homelab K3s

This repository is the declarative replacement for the Docker Compose homelab. It deploys GitLab and Keycloak on a single K3s server today, while keeping a direct path to a three-node cluster later.

## Architecture

```text
Internet -> Cloudflare Tunnel -> Traefik tunnel entrypoint -> public routes
LAN DNS  -> 192.168.70.100 -> Traefik websecure entrypoint -> all LAN routes
                                      |
                           GitLab and Keycloak
                                      |
                  Longhorn PVCs, CNPG, and Loki
                                      |
                        OVH Object Storage

Alloy DaemonSet -> Kubernetes pod log API -> Loki -> Grafana Explore

Operator -> 192.168.70.5 -> kube-vip -> K3s API
Git push -> GitHub main -> Argo CD auto-sync
Bitwarden Secrets Manager -> External Secrets Operator -> Kubernetes Secrets
```

The first node is `192.168.70.10`. MetalLB assigns `192.168.70.100` to Traefik, and kube-vip owns `192.168.70.5` for the Kubernetes API. GitLab SSH and GitLab Runner are intentionally absent.

## Repository layout

| Path | Purpose |
| --- | --- |
| `ansible/` | Agentless Ubuntu and K3s bootstrap |
| `bootstrap/` | Root Argo CD Application |
| `clusters/homelab/` | App of apps definitions and pinned Helm releases |
| `platform/` | Shared networking, certificates, secrets, storage, and monitoring config |
| `apps/` | GitLab, Keycloak, and Cloudflare Tunnel workloads |
| `recovery/` | Isolated, manually applied disaster recovery overlays |
| `scripts/` | Local validation and migration export helpers |
| `docs/` | Bootstrap, secrets, migration, restore, and scaling runbooks |

## Start here

1. Read [docs/secrets.md](docs/secrets.md) and replace every deployment `CHANGE_ME` value.
2. Follow [docs/bootstrap.md](docs/bootstrap.md) to prepare and bootstrap the new server.
3. Confirm the new services using temporary local DNS overrides.
4. Follow [docs/migration.md](docs/migration.md) for the cutover.
5. Run a restore drill using [docs/restore.md](docs/restore.md).

Run `pwsh ./scripts/validate.ps1` before pushing. Argo CD tracks `main`, prunes removed resources, and self-heals drift. Renovate opens dependency pull requests, but does not merge them.

## Backup model

The design targets a 24-hour RPO and uses several independent layers:

| Data | Mechanism | Schedule |
| --- | --- | --- |
| K3s control plane | Encrypted etcd snapshots to OVH Object Storage | Every 12 hours |
| GitLab application data | Native GitLab backup staged on a dedicated PVC, then Velero CSI data movement with Kopia to S3 | Daily, weekly, monthly |
| Keycloak database | Validated logical dump moved through Velero and Kopia | Daily, weekly, and monthly logical backups |
| Dependency-Track database | Validated logical dump moved through Velero and Kopia | Daily, weekly, and monthly logical backups |
| Local recovery points | Longhorn snapshots with integrity checks | Daily snapshots, weekly cleanup and integrity check |

Velero is intentionally not used for the live GitLab or Keycloak database volumes. Application-native backups provide the consistency boundary, and Velero moves the GitLab and Keycloak staging PVCs off site. See [docs/backups.md](docs/backups.md) for retention, verification, and recovery details.
