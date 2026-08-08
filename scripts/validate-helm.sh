#!/usr/bin/env bash
set -euo pipefail

helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo add external-secrets https://charts.external-secrets.io --force-update
helm repo add metallb https://metallb.github.io/metallb --force-update
helm repo add traefik https://traefik.github.io/charts --force-update
helm repo add longhorn https://charts.longhorn.io --force-update
helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
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
render_application cloudnative-pg cnpg/cloudnative-pg 0.29.0 cnpg-system clusters/homelab/applications/cloudnative-pg.yaml
render_application monitoring prometheus-community/kube-prometheus-stack 88.2.0 monitoring clusters/homelab/applications/kube-prometheus-stack.yaml
render_application blackbox prometheus-community/prometheus-blackbox-exporter 11.16.0 monitoring clusters/homelab/applications/blackbox-exporter.yaml

helm template argocd argo/argo-cd \
  --version 10.3.0 \
  --namespace argocd \
  --values ansible/files/argocd-values.yaml > /dev/null

helm template barman cnpg/plugin-barman-cloud \
  --version 0.7.1 \
  --namespace cnpg-system > /dev/null

helm template external-secrets external-secrets/external-secrets \
  --version 2.9.0 \
  --namespace external-secrets \
  --values ansible/files/external-secrets-values.yaml > /dev/null

printf 'All pinned Helm charts rendered successfully.\n'
