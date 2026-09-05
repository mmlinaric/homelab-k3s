# VictoriaMetrics operations

VictoriaMetrics is the cluster's authoritative metrics store, scraper, and rule
evaluator. The application name retains the `victoria-metrics-pilot` suffix to
avoid recreating its PVC and operator-managed resources during the cutover.

The active pipeline consists of VictoriaMetrics Operator, `vmagent`, `vmalert`,
and a single-node `vmsingle`. Existing `ServiceMonitor`, `PodMonitor`, and
`PrometheusRule` objects are converted by the VictoriaMetrics Operator. The
kube-prometheus-stack application remains installed for Grafana, Alertmanager,
kube-state-metrics, node exporter, Prometheus CRDs, and their operator; its
Prometheus server is disabled.

Grafana provisions VMSingle as its default Prometheus-compatible datasource
using UID `prometheus`. Preserving that UID keeps existing dashboards working.
`vmalert` evaluates converted application and Kubernetes rules plus native
VictoriaMetrics health rules, then sends alerts to the existing Alertmanager and
Telegram routing.

## Verify the pipeline

```bash
kubectl -n argocd get applications \
  kube-prometheus-stack victoria-metrics-pilot
kubectl -n monitoring get vmsingle,vmagent,vmalert
kubectl -n monitoring get pods,pvc
kubectl -n monitoring get prometheus
```

The applications and VictoriaMetrics resources must be healthy. The final
command should report no Prometheus resources. The old Prometheus PVC is retained
temporarily for rollback but has no running pod attached to it.

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

All active targets and rules must be healthy. Native groups named `vm-health`,
`vmagent`, `vmalert`, `vmoperator`, and `vmsingle` monitor the replacement
pipeline itself.

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
`vm_slow_row_inserts_total`, rule evaluation failures, pod restarts, and VMSingle
PVC growth. The configured retention is seven days with a 10 GiB Longhorn PVC
and 1 GB free-space reserve.

## Rollback

The old Prometheus PVC is retained so the server can be restored without losing
its existing local history. To roll back, revert the cutover commits so that:

1. `vmalert` returns to `notifier.blackhole: "true"`.
2. kube-prometheus-stack sets `prometheus.enabled: true` and re-enables its
   Prometheus rule group.
3. Grafana's generated Prometheus datasource is restored as the default.

Wait for Prometheus to become ready and confirm its targets before restoring its
alert notifications. Do not run both rule evaluators against Alertmanager unless
duplicate notifications are acceptable.

After the rollback window expires, the unused PVC named
`prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0`
may be deleted manually. PVC deletion is intentionally not automated.
