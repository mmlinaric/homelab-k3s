# Bootstrap runbook

## Server preparation

The target is Ubuntu Server on Proxmox with 10 vCPU, 20 GB static RAM, and a 400 GB disk. Reserve `192.168.70.10` in DHCP or configure it statically. Ensure the host name in `ansible/inventory/hosts.yml` resolves and that key-based SSH with sudo works.

Before running Ansible:

- Point `gitops_repo_url` at the private GitHub repository.
- Push this repository to its `main` branch.
- Complete every placeholder described in `secrets.md`.
- Ensure `192.168.70.5` and `192.168.70.100` are unused.
- Allow TCP 22, 80, 443, and 6443 from the LAN. Allow outbound HTTPS, DNS, NTP, and Cloudflare Tunnel traffic.

## Controller setup

From a Linux or WSL controller with Python and Ansible installed:

```bash
cd ansible
ansible-galaxy collection install -r collections/requirements.yml
ansible-playbook playbooks/bootstrap.yml
```

The playbook installs host dependencies, disables swap, installs the pinned K3s release, creates the API VIP, installs Helm, bootstraps cert-manager, External Secrets Operator, and Argo CD, then applies the root Application. It writes a local `kubeconfig` that targets `192.168.70.5`.

## Initial checks

```bash
export KUBECONFIG="$PWD/kubeconfig"
kubectl get nodes -o wide
kubectl -n argocd get applications
kubectl get pods -A
kubectl -n external-secrets get clustersecretstore bitwarden
kubectl -n velero get backupstoragelocation,schedule
kubectl -n velero get daemonset node-agent
kubectl -n longhorn-system get recurringjobs.longhorn.io
kubectl -n keycloak get cluster,backup,objectstore
kubectl -n keycloak get deployment keycloak-logical-backup
kubectl -n keycloak get pvc keycloak-backups
```

All Argo CD Applications should become Healthy and Synced. Some workloads will remain Pending until their ExternalSecrets are Ready. The Velero backup storage location must report `Available` before creating the first backup.

## Network setup

Create split DNS records on the LAN for `auth`, `gitlab`, `registry`, `grafana`, `argocd`, and `longhorn` under `mmlinaric.com`, all pointing to `192.168.70.100`. Keep the public records attached to the Cloudflare Tunnel only for `auth`, `gitlab`, and `registry`.

Test before changing shared DNS by adding the names to a workstation hosts file with `192.168.70.100`.

## Longhorn disk reserve

After the Longhorn node object exists, reserve 80 GiB on its default disk in the Longhorn UI. Go to Node, edit the node and disk, and set Storage Reserved to `85899345920` bytes. Keep over-provisioning at 100 percent on this single disk.
