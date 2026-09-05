#!/usr/bin/env bash
set -euo pipefail

helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm repo add metallb https://metallb.github.io/metallb --force-update
helm repo add traefik https://traefik.github.io/charts --force-update
helm repo add longhorn https://charts.longhorn.io --force-update
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts --force-update
helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo add vm https://victoriametrics.github.io/helm-charts --force-update
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo add grafana-community https://grafana-community.github.io/helm-charts --force-update
helm repo add jenkins https://charts.jenkins.io --force-update
helm repo update

render_application() {
  local release="$1"
  local chart="$2"
  local version="$3"
  local namespace="$4"
  local application="$5"

  yq '.spec.source.helm.valuesObject' "${application}" \
    | helm template "${release}" "${chart}" \
        --version "${version}" \
        --namespace "${namespace}" \
        --api-versions monitoring.coreos.com/v1 \
        --api-versions monitoring.coreos.com/v1/ServiceMonitor \
        --values - > /dev/null
}

render_application cert-manager jetstack/cert-manager v1.21.1 cert-manager clusters/homelab/applications/cert-manager.yaml
render_application external-secrets external-secrets/external-secrets 2.9.0 external-secrets clusters/homelab/applications/external-secrets.yaml
render_application metallb metallb/metallb 0.16.1 metallb-system clusters/homelab/applications/metallb.yaml
render_application traefik traefik/traefik 41.2.0 traefik clusters/homelab/applications/traefik.yaml
render_application longhorn longhorn/longhorn 1.12.0 longhorn-system clusters/homelab/applications/longhorn.yaml
render_application velero vmware-tanzu/velero 12.1.0 velero clusters/homelab/applications/velero.yaml
render_application cloudnative-pg cnpg/cloudnative-pg 0.29.0 cnpg-system clusters/homelab/applications/cloudnative-pg.yaml
yq '.spec.source.helm.valuesObject' clusters/homelab/applications/prometheus-operator-crds.yaml \
  | helm template prometheus-operator-crds prometheus-community/prometheus-operator-crds \
      --version 31.0.1 \
      --namespace monitoring \
      --include-crds \
      --values - > /dev/null
render_application monitoring prometheus-community/kube-prometheus-stack 88.6.2 monitoring clusters/homelab/applications/kube-prometheus-stack.yaml
render_application victoria-metrics-pilot vm/victoria-metrics-k8s-stack 0.91.2 monitoring clusters/homelab/applications/victoria-metrics-pilot.yaml
render_application blackbox prometheus-community/prometheus-blackbox-exporter 11.17.2 monitoring clusters/homelab/applications/blackbox-exporter.yaml
render_application loki grafana-community/loki 18.7.6 monitoring clusters/homelab/applications/loki.yaml
render_application alloy grafana/alloy 1.11.1 monitoring clusters/homelab/applications/alloy.yaml
render_application jenkins jenkins/jenkins 5.9.54 jenkins clusters/homelab/applications/jenkins.yaml

helm template forgejo oci://code.forgejo.org/forgejo-helm/forgejo \
  --version 17.1.4 \
  --namespace forgejo \
  --api-versions monitoring.coreos.com/v1 \
  --api-versions monitoring.coreos.com/v1/ServiceMonitor \
  --values <(yq '.spec.source.helm.valuesObject' clusters/homelab/applications/forgejo.yaml) > /dev/null

helm template argocd argo/argo-cd \
  --version 10.3.0 \
  --namespace argocd \
  --values ansible/files/argocd-values.yaml > /dev/null

helm template external-secrets external-secrets/external-secrets \
  --version 2.9.0 \
  --namespace external-secrets \
  --values ansible/files/external-secrets-values.yaml > /dev/null

printf 'All pinned Helm charts rendered successfully.\n'
