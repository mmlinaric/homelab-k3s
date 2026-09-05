# VictoriaMetrics pilot

The cluster runs VictoriaMetrics beside Prometheus for a short comparison before
any monitoring cutover. Prometheus remains authoritative for dashboards, rules,
Alertmanager, and Telegram notifications during the pilot.

The pilot consists only of VictoriaMetrics Operator, `vmagent`, `vmalert`, and a
single-node `vmsingle`. Existing `ServiceMonitor`, `PodMonitor`, and
`PrometheusRule` objects are converted by the VictoriaMetrics Operator. Bundled
exporters, Kubernetes scrapes, dashboards, rules, Grafana, and Alertmanager are
disabled to avoid duplicate infrastructure.

## Expected footprint

| Pipeline | Declared primary-container memory requests |
| --- | ---: |
| Prometheus server and Prometheus Operator | 1664 MiB |
| VictoriaMetrics pilot components | 996 MiB |
| Projected schedulable-memory reduction | 668 MiB |

Operator-generated config-reloader sidecars add a small amount to both sides and
must be included when inspecting the live pod specs. The comparison must use
observed working-set memory as well as requests. A lower request does not prove
that a workload has enough headroom at peak load.

## Verify deployment

After Argo CD syncs the application, run:

```bash
kubectl -n argocd get application victoria-metrics-pilot
kubectl -n monitoring get vmsingle,vmagent,vmalert
kubectl -n monitoring get pods,pvc | grep -E 'victoria-metrics|NAME'
kubectl get vmservicescrape,vmpodscrape,vmrule -A
```

The converted resource counts should correspond to the source resources:

```bash
kubectl get servicemonitor -A --no-headers | wc -l
kubectl get vmservicescrape -A --no-headers | wc -l
kubectl get podmonitor -A --no-headers | wc -l
kubectl get vmpodscrape -A --no-headers | wc -l
kubectl get prometheusrule -A --no-headers | wc -l
kubectl get vmrule -A --no-headers | wc -l
```

VictoriaMetrics also owns one native `VMServiceScrape` for its operator, so an
exact total match is not expected. Inspect any larger discrepancy by comparing
resource names and namespaces.

Confirm that rule evaluation is active and notifications are blackholed:

```bash
kubectl -n monitoring port-forward \
  service/vmalert-victoria-metrics-pilot-victoria-metrics-k8s-stack 18080:8080
curl -fsS http://127.0.0.1:18080/api/v1/rules | jq '.data.groups | length'
kubectl -n monitoring get vmalert \
  victoria-metrics-pilot-victoria-metrics-k8s-stack \
  -o jsonpath='{.spec.extraArgs.notifier\.blackhole}{"\n"}'
```

The final command must print `true`. Do not configure a notifier during the
pilot.

## Compare targets and queries

Grafana provisions a non-default datasource named `VictoriaMetrics Pilot`.
Use Explore with the normal Prometheus datasource in one pane and the pilot in
another. Compare at least these queries over the same time range:

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

Then compare the source target pages:

```bash
kubectl -n monitoring port-forward \
  service/kube-prometheus-stack-prometheus 19090:9090
kubectl -n monitoring port-forward \
  service/vmagent-victoria-metrics-pilot-victoria-metrics-k8s-stack 18429:8429
curl -fsS http://127.0.0.1:19090/api/v1/targets > /tmp/prometheus-targets.json
curl -fsS http://127.0.0.1:18429/api/v1/targets > /tmp/vmagent-targets.json
```

Resolve missing or unhealthy targets before evaluating resource savings. A
target with different `job` or `instance` labels can also invalidate dashboards
and alerts even when both systems scrape the same endpoint.

## Measure for 72 hours

Use Prometheus as the common source for Kubernetes container measurements. These
queries calculate aggregate P95 usage for each metrics pipeline over the pilot
window:

```promql
quantile_over_time(
  0.95,
  (sum(container_memory_working_set_bytes{
    namespace="monitoring",
    pod=~"prometheus-kube-prometheus-stack-prometheus-.*",
    container!=""
  }))[72h:1m]
)
```

```promql
quantile_over_time(
  0.95,
  (sum(container_memory_working_set_bytes{
    namespace="monitoring",
    pod=~"(vmsingle|vmagent|vmalert)-victoria-metrics-pilot-.*|victoria-metrics-pilot-victoria-metrics-operator-.*",
    container!=""
  }))[72h:1m]
)
```

Repeat with CPU using:

```promql
quantile_over_time(
  0.95,
  (sum(rate(container_cpu_usage_seconds_total{
    namespace="monitoring",
    pod=~"PIPELINE_POD_REGEX",
    container!=""
  }[5m])))[72h:5m]
)
```

Record these additional values at the beginning and end of the window:

```bash
kubectl top node
kubectl top pods -n monitoring --containers
kubectl -n monitoring get pvc
kubectl -n monitoring get pods \
  -o custom-columns='POD:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount'
```

In the VictoriaMetrics datasource, review the rate of
`vm_slow_row_inserts_total`, `vm_slow_metric_name_loads_total`, and
`vm_rows_inserted_total`; in Prometheus, review `prometheus_tsdb_head_series`,
`prometheus_tsdb_head_samples_appended_total`, and rule evaluation failures.
Include a daily backup run and representative dashboard use in the window.

## Decision gate

Cut over only when all of the following are true:

- All production targets, dashboard queries, and custom rules have parity.
- `vmalert` has no rule evaluation errors or unexpectedly empty critical rules.
- Aggregate VictoriaMetrics P95 memory is at least 30 percent and 500 MiB lower.
- Aggregate VictoriaMetrics P95 CPU is no more than 10 percent higher.
- Daily VictoriaMetrics PVC growth and node disk-write pressure do not exceed
  Prometheus.
- No VictoriaMetrics component is OOM-killed, repeatedly restarted, or reporting
  sustained slow inserts.

If the gate passes, make a separate cutover change that connects `vmalert` to
the existing Alertmanager, makes the VictoriaMetrics datasource authoritative,
and disables the Prometheus server. Retain the old Prometheus PVC for seven days
before deleting it.

If the gate fails, remove `applications/victoria-metrics-pilot.yaml` from the
cluster kustomization and right-size Prometheus from its measured P99 usage.
