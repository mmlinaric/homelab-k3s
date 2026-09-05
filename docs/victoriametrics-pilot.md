# VictoriaMetrics operations

The `victoria-metrics-pilot` application is the cluster's complete metrics
stack. The name is retained to avoid recreating its PVC and operator-managed
resources after the migration.

It deploys VictoriaMetrics Operator, `vmagent`, `vmalert`, VMSingle, Grafana,
VMAlertmanager, kube-state-metrics, node-exporter, Kubernetes scrape objects,
rules, and dashboards. There is no Prometheus server and no Prometheus
Operator process.

The separate `prometheus-operator-crds` application installs CRDs only. This
lets third-party charts continue to create `ServiceMonitor`, `PodMonitor`,
`Probe`, and `PrometheusRule` objects. VictoriaMetrics Operator converts those
objects into VM-native equivalents; the CRD chart runs no pods.

Grafana uses VMSingle's Prometheus-compatible API through datasource UID
`prometheus`. `vmalert` evaluates both converted application rules and native
VictoriaMetrics/Kubernetes rules, then sends alerts to VMAlertmanager and its
Telegram receivers.

## Verify the pipeline

```bash
kubectl -n argocd get applications \
  victoria-metrics-pilot prometheus-operator-crds
kubectl -n monitoring get \
  vmsingle,vmagent,vmalert,vmalertmanager
kubectl -n monitoring get pods,pvc
kubectl -n monitoring get prometheus,alertmanager
```

Both applications and all VictoriaMetrics resources must be healthy. The last
command should report no resources because Prometheus and Prometheus-Operator
Alertmanager CRs are not used.

Inspect scrape targets and evaluated rules:

```bash
kubectl -n monitoring port-forward \
  service/vmagent-victoria-metrics-pilot-victoria-metrics-k8s-stack 18429:8429
kubectl -n monitoring port-forward \
  service/vmalert-victoria-metrics-pilot-victoria-metrics-k8s-stack 18080:8080

curl -fsS http://127.0.0.1:18429/api/v1/targets | jq \
  '{total: (.data.activeTargets | length), down: [.data.activeTargets[] | select(.health != "up")]}'
curl -fsS http://127.0.0.1:18080/api/v1/rules | jq \
  '{groups: (.data.groups | length), unhealthy: [.data.groups[].rules[] | select(.health != "ok")]}'
```

All active targets and rules must be healthy. Expected infrastructure jobs
include `apiserver`, `core-dns`, `kube-proxy`, `kubelet`, `kube-state-metrics`,
and `node-exporter`. Native rule groups monitor VMSingle, vmagent, vmalert,
VMAlertmanager, and VictoriaMetrics Operator.

Representative smoke-test queries:

```promql
sum(up) by (namespace, job)
probe_success
kube_node_info
kube_pod_status_ready
longhorn_volume_robustness
velero_backup_last_status
k3s_etcd_snapshot_ready
kubelet_volume_stats_used_bytes
```

## Resource and storage checks

```bash
kubectl top node
kubectl top pods -n monitoring --containers
kubectl -n monitoring get pvc
kubectl -n monitoring get pods \
  -o custom-columns='POD:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount'
```

Watch `vmagent_remotewrite_packets_dropped_total`,
`vmagent_remotewrite_pending_data_bytes`, `vm_rows_inserted_total`,
`vm_slow_row_inserts_total`, rule evaluation failures, notification failures,
pod restarts, and VMSingle PVC growth. Metrics retention is seven days on a
10 GiB Longhorn PVC with a 1 GB free-space reserve.

## Rollback

Revert the consolidation commits or restore the previous
`kube-prometheus-stack` Application from Git history. Disable the VM-native
exporters, Kubernetes scrapes, rules, Grafana, and VMAlertmanager before
re-enabling their kube-prometheus-stack counterparts to avoid port conflicts,
duplicate samples, and duplicate notifications.

The former Prometheus and Alertmanager StatefulSet PVCs may remain available
for a limited rollback window. Confirm their names with `kubectl get pvc -n
monitoring`; PVC deletion is intentionally manual.
