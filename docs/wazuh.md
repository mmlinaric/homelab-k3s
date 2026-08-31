# sec1 Wazuh deployment and recovery

`sec1` is a native, single-node Wazuh 4.14.7 installation on Ubuntu Server
26.04. OpenTofu owns the Proxmox VM, Ansible owns the operating system and
Wazuh configuration, and Restic sends encrypted recovery points to OVH S3.

## Fixed design

| Setting | Value |
| --- | --- |
| Proxmox node | `pve1` |
| VM ID and hostname | `120`, `sec1` |
| Address | `192.168.60.20/24` on VLAN 60 |
| Resources | 4 vCPU, 8 GiB RAM |
| Live/staging disks | 64 GiB / 32 GiB on `local-lvm` |
| Dashboard | `https://wazuh.mmlinaric.com` |
| Indexed retention | 30 days |
| Backup retention | 14 daily, 8 weekly, 12 monthly |

The Wazuh installer checksum and all component versions are pinned in Git.
Wazuh packages remain held until an explicit, backup-gated upgrade changes the
pin. Ubuntu 26.04 is intentional even though Wazuh's summary recommended-OS
list has not yet been updated beyond Ubuntu 24.04.

## Required S3 setup

Create `mmlinaric-homelab-wazuh` in the same OVH region as the existing
homelab buckets. Enable versioning and SSE-OMK. Do not enable Object Lock,
because Restic must remove unreferenced packs. Configure lifecycle rules to
abort incomplete multipart uploads after seven days and expire non-current
versions after 30 days.

Use one workstation-only credential for OpenTofu state and a separate
credential for the `sec1` Restic repository. Restrict them to their prefixes
when the OVH project permission model permits it. The Restic credential and
password must also be present in the encrypted offline recovery kit.

## Bitwarden Secrets Manager values

Create a dedicated Wazuh project, or add these exact POSIX-compatible names to
the existing homelab project:

```text
WAZUH_INDEXER_ADMIN_PASSWORD
WAZUH_INDEXER_ANOMALYADMIN_PASSWORD
WAZUH_INDEXER_KIBANASERVER_PASSWORD
WAZUH_INDEXER_KIBANARO_PASSWORD
WAZUH_INDEXER_LOGSTASH_PASSWORD
WAZUH_INDEXER_READALL_PASSWORD
WAZUH_INDEXER_SNAPSHOTRESTORE_PASSWORD
WAZUH_API_ADMIN_PASSWORD
WAZUH_API_WUI_PASSWORD
WAZUH_ENROLLMENT_PASSWORD
WAZUH_CLOUDFLARE_API_TOKEN
WAZUH_ACME_EMAIL
WAZUH_RESTIC_PASSWORD
WAZUH_S3_ACCESS_KEY
WAZUH_S3_SECRET_KEY
WAZUH_S3_ENDPOINT
WAZUH_S3_REGION
WAZUH_TELEGRAM_BOT_TOKEN
WAZUH_TELEGRAM_CHAT_ID
```

The nine Wazuh component passwords must be 8-64 characters, include upper and
lowercase letters, a number, and one of `.*+?-`, and contain no other symbols.
Generate every password independently. Never rotate `WAZUH_RESTIC_PASSWORD`
for an existing repository.

The Cloudflare token needs only DNS record edit and zone read permissions for
the `mmlinaric.com` zone. The Telegram token belongs to the dedicated Wazuh
backup bot and `WAZUH_TELEGRAM_CHAT_ID` identifies its separate group.

## Deployment

Install the pinned collections, provision the VM, then apply the RouterOS
change before enrolling the Proxmox agents:

```bash
ansible-galaxy collection install -r ansible/collections/requirements.yml

cd infra/proxmox/sec1
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
export AWS_ACCESS_KEY_ID='<state-access-key>'
export AWS_SECRET_ACCESS_KEY='<state-secret-key>'
export TF_VAR_proxmox_api_token='<user@realm!token=secret>'
tofu init -backend-config=backend.hcl
tofu plan -out=sec1.tfplan
tofu apply sec1.tfplan
```

From an authenticated RouterOS Safe Mode session, upload and run
`_rb5009_enable_sec1_wazuh.rsc`, followed by its read-only audit. The rule is
deliberately placed before `MGMT: block initiating into private networks`.

Run Ansible with only the selected Bitwarden project injected:

```bash
export BWS_ACCESS_TOKEN='<machine-account-token>'
bws run --project-id '<wazuh-project-id>' -- \
  'ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/wazuh.yml'
```

The first run creates an installer archive with Bitwarden-managed passwords,
runs the canonical all-in-one assistant, obtains the DNS-01 certificate,
initializes Restic, and enrolls `k3s-01`, `pve1`, and `pve2`. Subsequent runs
must be idempotent. An existing unmanaged Wazuh installation is not adopted.

### RouterOS event ingestion

The manager listens for BSD syslog on `192.168.60.20:514/udp`. Both Wazuh and
UFW accept that listener only from the RB5009 management address
`192.168.20.1`. Custom rules identify authentication failures, administrator
logins, configuration changes, critical/error/warning events, and explicitly
logged firewall events.

After the Ansible configuration is applied, import
`_rb5009_enable_sec1_syslog.rsc` in RouterOS Safe Mode and run
`_rb5009_enable_sec1_syslog_audit.rsc`. The RouterOS action binds its source to
`192.168.20.1`, retains the existing local logs, and forwards only curated
topics. Use `_rb5009_enable_sec1_syslog_rollback.rsc` to remove only these
selectors and the `wazuhsec1` remote action.

Do not enable blanket WAN-drop logging. RouterOS forwards `firewall` events
only for firewall rules that explicitly have logging enabled. Normal DNS
queries are not forwarded; DNS warnings and errors remain covered by the
severity selectors.

The expected handshake retry from the intermittently connected Pixel 9
WireGuard peer is classified at level 1. If it repeats 120 times within ten
minutes, Wazuh emits one level-7 availability alert and then suppresses repeat
alerts for one hour. Authentication failures and failures for other peers keep
their original severity.

### Alerting and operator workflow

Wazuh sends every level 10 or higher alert to the same dedicated Telegram
destination used for backup status. The manager invokes the managed
`custom-telegram` integration with the alert in JSON format. Its root-owned
credential file is group-readable only by Wazuh; tokens are supplied from
Bitwarden Secrets Manager and never stored in Git.

Four lower-severity events are also sent because they represent monitoring
failure rather than ordinary security severity: a sustained WireGuard outage,
a credential-bearing Kubernetes object change, a failed ClamAV scan, and a
failed YARA rules update. Telegram messages summarize what happened, why it
matters, and the next investigation step instead of forwarding an unformatted
JSON event. Agent restart/disconnect events remain in the monitoring-health
view and weekly digest so routine maintenance does not page the operator.
Both immediate alerts and the weekly digest honor Telegram's bounded
`retry_after` response once, preventing a transient rate limit from silently
discarding a notification.

Use `Homelab Security Cockpit` as the normal Wazuh entry point:

`https://wazuh.mmlinaric.com/app/dashboards#/view/homelab-security-cockpit`

It opens on the previous 24 hours and contains six counters plus five working
queues: `Needs Attention`, `Critical and High Vulnerabilities`, `Monitoring,
Patch and Scanner Health`, `Authentication Failures`, and `Important Change
Trail`. `Critical Security Alerts` is an event count for the selected time
range. It is deliberately separate from the current `Critical
Vulnerabilities` and `High Vulnerabilities` inventory counters, so a quiet
alert period cannot be mistaken for fully patched hosts. The intended workflow
is:

1. Treat Telegram as the inbox. Open Wazuh only for an immediate notification
   that needs context, or when the weekly digest shows a non-zero category.
2. Start with `Needs Attention`, then use the matching queue to identify the
   host, identity, source address, affected object, package, and original
   event. Review the vulnerability queue separately even when the alert count
   is zero.
3. Change the time picker or add a host/identity filter to establish whether
   the event is isolated or repeated. Use Wazuh's stock dashboards only for
   deeper host, compliance, or event-specific investigation.
4. Record or fix the cause. Tune a rule only after its exact provenance and
   outcome are proven routine; do not suppress an entire event family.

Every Sunday at 09:00, with up to 30 minutes of jitter, `sec1` sends a weekly
operator digest. It reports agent and core-service health, actionable and
critical events, authentication/configuration/FIM activity, malware and
monitoring failures, successful ClamAV evidence, current Critical/High
vulnerability records, vulnerability coverage, and package/reboot posture for
all five hosts. Counts under the alert heading cover the preceding seven days,
so historical events retain their old severity until they age out after a
tuning change. Vulnerability counts are current inventory records, not unique
CVEs: the same CVE can appear for multiple installed package versions, and old
installed kernel packages can dominate the total even when APT has no pending
updates. Use the vulnerability queue's host, package version, condition, and
reference fields to decide what is actually remediable.

Each host runs `/usr/local/sbin/sec1-package-status` every six hours through
its Wazuh log collector. The latest report records the number of actionable
APT updates, updates deferred by Ubuntu's phased rollout, security-labelled
updates, and whether the running kernel trails the newest installed kernel.
Deferred updates are informational; they remain visible without being treated
as a patch failure. Non-zero results appear in `Monitoring, Patch and Scanner
Health`; missing reports lower the weekly digest's reporting coverage. The
manager's own vulnerability scan is explicitly enabled so `sec1` is not a
coverage blind spot.

Preview the digest without sending or trigger it immediately with:

```bash
sudo /usr/local/sbin/wazuh-weekly-digest
sudo systemctl start wazuh-weekly-digest.service
systemctl list-timers wazuh-weekly-digest.timer
```

The summary is deterministic and processes alert metadata only on `sec1`.
External AI summarization is deliberately disabled until a provider, data
boundary, cost limit, and failure behavior are explicitly approved. The
operator workflow does not depend on AI to classify or deliver alerts.

To reconcile only this integration after a normal full deployment, keep the
existing credential file or inject the two Telegram values and run:

```bash
bws run --project-id '<wazuh-project-id>' -- \
  'ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/wazuh.yml \
  --limit sec1 --tags telegram_alerts'
```

### RouterOS investigation

The Wazuh dashboard contains the saved search `RouterOS Security Events` and
dashboard `RouterOS Security Monitoring`. Both use the filter
`decoder.name: routeros`; the saved search exposes timestamp, severity, rule,
source, and original event fields for investigation.

Open the dashboard directly at
`https://wazuh.mmlinaric.com/app/dashboards#/view/routeros-security-monitoring`.
The saved-object IDs are fixed in the role, so a complete deployment recreates
or reconciles both objects instead of relying on manual dashboard state.

### Kubernetes API audit monitoring

K3s writes a bounded JSON-lines audit log to
`/var/lib/rancher/k3s/server/logs/audit.log`. The policy stores metadata only:
it never records Secret values or API request and response bodies. Routine
health checks, reads, watches, events, leases, endpoint updates, and controller
status updates are suppressed. Secret metadata access, interactive pod access,
service-account token issuance, and remaining API mutations are retained.

The `k3s-01` Wazuh agent forwards the audit log through its existing encrypted
agent connection. Custom rules raise denied interactive requests, pod
`exec`/`attach`/`portforward`, service-account token requests, RBAC changes,
interactive Secret access, and deletion of namespaces or CRDs. Rules at level
10 and higher also use the managed Telegram integration.

Known controller provenance is handled below the indexed alert threshold for
successful TokenReviews, control-plane Secret watches, K3s node status,
Prometheus service reconciliation, External Secrets status, and the Velero
namespace's backup workload lifecycle. A CloudNativePG RoleBinding create that
returns `409 AlreadyExists`, and `keycloak-db` patching its own CloudNativePG
status, are also routine. Approved Forgejo and Velero backup hooks remain
searchable at level 3. Equivalent events from any other identity, namespace,
resource, or response outcome retain the original severity.

K3s bridge-CNI attach and teardown records for ephemeral `veth*` interfaces are
retained at level 3, rather than notifying. This narrowly handles the expected
`prom=256 old_prom=0` and `prom=0 old_prom=256` transitions emitted by K3s's
hashed CNI binary running as `bridge`; alerts for non-veth devices, unexpected
transitions, and other executables remain unchanged.

Reconcile the K3s side without bootstrap secrets, then apply the Wazuh role in
the normal BWS-backed deployment:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/k3s-audit.yml

bws run --project-id '<wazuh-project-id>' -- \
  'ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/wazuh.yml \
  --limit sec1 --tags kubernetes_audit'
```

K3s retains at most ten rotated 50 MiB files for 14 days. Wazuh keeps matching
alerts under its normal 30-day indexed retention. Open the investigation view
at `https://wazuh.mmlinaric.com/app/dashboards#/view/k3s-security-monitoring`.

### Endpoint malware detection

`sec1`, `k3s-01`, `ops1`, `pve1`, and `pve2` use two complementary local scanners.
Wazuh FIM triggers YARA whenever a monitored system or `/root` file is
created or modified. A daily low-priority ClamAV scan covers `/etc`,
`/usr/local/bin`, `/usr/local/sbin`, `/root`, `/home`, `/tmp`, and `/var/tmp`.
The scanner considers regular files only, stays on the originating filesystem,
and skips user cache trees. It therefore does not recurse into Proxmox VM
storage, K3s container layers, Wazuh index data, or backup mounts.
Temporary files which disappear while `/tmp` or `/var/tmp` is being scanned do
not fail the service; inaccessible files that still exist remain scan errors.

ClamAV's `freshclam` service maintains the official signed malware database.
The scan uses the non-resident `clamscan` executable, avoiding roughly 1 GiB of
continuous RAM per host that the `clamd` daemon would otherwise consume. The
daily timer starts at 03:30 with up to four hours of jitter and uses low CPU and
I/O weights.

YARA uses the public Signature-Base rules. The bootstrap Git revision and
archive SHA-256 are pinned in Ansible. Every Sunday, each endpoint checks for a
new revision, downloads it into a private staging directory, excludes rules
which require scanner-specific external variables, compiles the remaining
bundle, scans `/bin/true` as a parser smoke check, and atomically switches the
`current` symlink. A failed update leaves the last-known-good bundle active;
three compiled releases are retained. The active revision, source URL, and
license are recorded under `/var/lib/sec1-malware/yara/current`. The `sec1`
copy is included in the encrypted S3 recovery point.

YARA and ClamAV detections are Wazuh level 12 and therefore notify Telegram.
Scanner and updater failures are level 7. No file is deleted or quarantined
automatically; investigate the host and isolate it before taking destructive
action.

Rootcheck's legacy string heuristic is reduced to level 1 for the exact
`cat`, `chgrp`, `chmod`, `chown`, `date`, `echo`, `env`, `ls`, `md5sum`, and
`uname` paths supplied by Ubuntu's verified `rust-coreutils` package. Other
rootcheck detections remain level 7. Proxmox FIM likewise ignores only the HA
manager's generated `lrm_status` and `lrm_status.tmp.<pid>` files; the rest of
`/etc/pve` remains monitored in real time.

Useful commands:

```bash
systemctl list-timers sec1-yara-update.timer sec1-clamav-scan.timer
systemctl start sec1-yara-update.service
systemctl start sec1-clamav-scan.service
journalctl -u sec1-yara-update.service -u sec1-clamav-scan.service
cat /var/lib/sec1-malware/yara/current/REVISION
freshclam --version
```

Reconcile only this feature without exposing the unrelated Wazuh secrets:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/wazuh.yml \
  --tags malware_detection
```

## Backup operation

`sec1-wazuh-backup.timer` runs at 02:15 Europe/Zagreb with up to 15 minutes of
jitter. Its service:

1. Stops new manager ingestion and drains Filebeat.
2. Creates a completed OpenSearch filesystem snapshot.
3. Exports indexer security configuration.
4. Copies manager state, agent keys, queues, configuration, certificates,
   dashboard state, alert logs, and exact package versions.
5. Restarts ingestion even if a later step fails.
6. Commits both state sets as one encrypted Restic snapshot.
7. Applies retention and integrity checks, then reports to Telegram.

Useful commands:

```bash
systemctl list-timers sec1-wazuh-backup.timer
systemctl start sec1-wazuh-backup.service
journalctl -u sec1-wazuh-backup.service
set -a; source /etc/sec1-backup/restic.env; set +a
restic snapshots --host sec1 --tag wazuh
```

Never copy `/var/lib/wazuh-indexer` as a live filesystem backup. Indexed data
is recoverable only through the OpenSearch snapshot stored inside the Restic
recovery point.

## Full recovery

1. Power off or isolate the failed original `sec1`; never run two production
   copies at `192.168.60.20`.
2. Recreate VM 120 with OpenTofu and install the exact Wazuh version recorded
   by the selected backup.
3. Stop `wazuh-manager`, `filebeat`, and `wazuh-dashboard` on the replacement.
4. Restore the selected Restic paths to a temporary directory and validate
   `manager-current/SHA256SUMS` before copying anything into place.
5. Restore `manager-current/files` with numeric ownership, ACLs, and extended
   attributes preserved.
6. Restore `manager-current/indexer-security` using
   `indexer-security-init.sh`, then register the restored filesystem snapshot
   repository read-only.
7. Restore the snapshot named in `recovery-manifest.txt`, including dashboard
   indices and global state. Do not restore raw indexer data files.
8. Start the indexer, manager, Filebeat, and dashboard in that order. Confirm
   the preserved agent identities before opening 1514/1515.

The staging portion is deliberately non-destructive and can be used to inspect
a recovery point before approving the service restore:

```bash
install -d -m 0700 /srv/wazuh-restore
set -a; source /etc/sec1-backup/restic.env; set +a
restic snapshots --host sec1 --tag wazuh
restic restore '<snapshot-id>' --target /srv/wazuh-restore
cd /srv/wazuh-restore/srv/wazuh-backup/manager-current
sha256sum --check SHA256SUMS
sed -n '1,120p' recovery-manifest.txt
```

Do not proceed unless every checksum succeeds and the manifest reports the
Wazuh package version installed on the replacement. Copy the saved `files/`
tree with `rsync -aR --acls --xattrs --numeric-ids` while the manager,
Filebeat, and dashboard are stopped. Keep the indexer running while its API is
used to register and restore the filesystem snapshot; restart it before
bringing the other three services back in order.

For a drill, use VM ID 320 and `192.168.60.220`, keep production DNS unchanged,
and prevent restored automation from contacting production integrations.
