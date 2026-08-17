# Hermes Agent Kubernetes access

Hermes can diagnose the cluster, but it must not receive the administrator
kubeconfig. Apply the RBAC manifest in this
repository first; Argo CD will then maintain the `argocd/hermes-agent` service
account and its deliberately narrow role.

The role can read workload status, events, selected controller and backup
custom resources, node and storage metadata, pod logs, and Argo CD
Application status. It cannot read Secrets or ConfigMaps, exec into, attach
to, or port-forward a pod, manage RBAC, alter workload specifications, sync
an Argo CD Application, or delete resources.

## Create the kubeconfig

Run the following once from a trusted administrator shell after the RBAC
manifest has synced. It creates a short-lived bearer-token kubeconfig outside
the repository. A Kubernetes service-account token is itself a credential: do
not commit it, paste it into Telegram, or mount the administrator kubeconfig
into Hermes.

```bash
set -euo pipefail
umask 077

hermes_kube_dir="$HOME/.hermes/kube"
hermes_kubeconfig="$hermes_kube_dir/hermes-agent.kubeconfig"
install -d -m 700 "$hermes_kube_dir"
install -m 600 /dev/null "$hermes_kubeconfig"

api_server="$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')"
ca_data="$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')"
token="$(kubectl -n argocd create token hermes-agent --duration=24h)"

kubectl --kubeconfig="$hermes_kubeconfig" config set-cluster homelab \
  --server="$api_server" \
  --certificate-authority-data="$ca_data"
kubectl --kubeconfig="$hermes_kubeconfig" config set-credentials hermes-agent \
  --token="$token"
kubectl --kubeconfig="$hermes_kubeconfig" config set-context hermes-agent \
  --cluster=homelab \
  --user=hermes-agent \
  --namespace=argocd
kubectl --kubeconfig="$hermes_kubeconfig" config use-context hermes-agent
unset token
```

The token expires after 24 hours. Re-run the snippet to rotate it; immediate
revocation is as simple as deleting the `ClusterRoleBinding` or service
account. If the API server enforces a shorter maximum token lifetime, use the
lifetime it permits.

Verify the boundary before giving the file to Hermes:

```bash
export KUBECONFIG="$HOME/.hermes/kube/hermes-agent.kubeconfig"
kubectl auth can-i get pods --all-namespaces
kubectl auth can-i get secrets --all-namespaces
kubectl auth can-i create pods/exec -n gitlab
kubectl auth can-i delete deployments -n gitlab
```

The first command should return `yes`; the final three must return `no`.

## Run Hermes with the constrained credential

Use Hermes's Docker terminal backend and mount only this kubeconfig read-only;
do not mount the host Docker socket, `/etc/rancher/k3s`, or an administrator
kubeconfig. Merge this into `~/.hermes/config.yaml`, adapting the host path if
needed:

```yaml
approvals:
  mode: manual
  cron_mode: deny
  single_query_mode: deny
terminal:
  backend: docker
  docker_mount_cwd_to_workspace: false
  docker_forward_env: []
  docker_volumes:
    - "/home/mario/.hermes/kube/hermes-agent.kubeconfig:/home/hermes/.kube/config:ro"
```

Set `TELEGRAM_ALLOWED_USERS` to only your numeric Telegram user ID. Hermes
documents this allowlist, manual command approvals, and Docker isolation in
its [security guide](https://hermes-agent.nousresearch.com/docs/user-guide/security/).

Pod logs can accidentally contain application credentials, so Kubernetes RBAC
cannot promise that an agent with log access will never encounter a secret.
Avoid logging credentials and, if that is not feasible, remove `pods/log` from
the role. For stronger containment, run the Hermes terminal container on a
separate host or VM and firewall its egress to the Kubernetes API only.

## What Hermes can fix

It can identify failing pods, image-pull and scheduling failures, unhealthy
storage, failed backups, certificate/controller status, and Argo CD drift. A
broken Renovate change is a Git problem: Hermes should prepare a revert pull
request or report the exact revision, while you retain the merge/deploy
decision. Kubernetes RBAC cannot grant the Argo CD API's sync action without
also introducing a separately authenticated Argo CD boundary. Granting it
permission to patch Argo Application sources or Kubernetes workloads would let
it bypass GitOps and escalate a prompt-injection mistake into arbitrary cluster
changes.
