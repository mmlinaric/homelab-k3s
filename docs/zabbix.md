# ops1 Zabbix deployment and recovery

`ops1` is a native Zabbix 7.0 LTS installation on Ubuntu Server 26.04.
OpenTofu owns VM 220 on `pve2`; Ansible owns PostgreSQL, Zabbix, Nginx, TLS,
Agent 2, host enrollment, and encrypted backups.

| Setting | Value |
| --- | --- |
| Address | `192.168.60.21/24` on VLAN 60 |
| Resources | 2 vCPU, 4 GiB RAM |
| System/backup disks | 32 GiB / 16 GiB on `local-lvm` |
| Dashboard | `https://zabbix.mmlinaric.com` |
| Zabbix release | 7.0 LTS, package version pinned in Ansible |
| Backup retention | 14 daily, 8 weekly, 12 monthly |

## Required preparation

Create `mmlinaric-homelab-zabbix` in OVH Object Storage with versioning and
server-side encryption. Do not enable Object Lock because Restic pruning needs
to delete unreferenced packs. Keep OpenTofu state and the `ops1` Restic data in
separate prefixes; this deployment uses the Zabbix-scoped credential for both,
and the credentials can be split later without changing the layout.

Create the following Bitwarden Secrets Manager values:

```text
ZABBIX_DB_PASSWORD
ZABBIX_ADMIN_PASSWORD
ZABBIX_AGENT_PSK
ZABBIX_CLOUDFLARE_API_TOKEN
ZABBIX_ACME_EMAIL
ZABBIX_RESTIC_PASSWORD
ZABBIX_S3_ACCESS_KEY
ZABBIX_S3_SECRET_KEY
ZABBIX_S3_ENDPOINT
ZABBIX_S3_REGION
ZABBIX_TELEGRAM_BOT_TOKEN
ZABBIX_TELEGRAM_CHAT_ID
```

`ZABBIX_AGENT_PSK` must be 64 hexadecimal characters. Generate it with
`openssl rand -hex 32`. Keep the Restic password in the encrypted offline
recovery kit and never rotate it for an existing repository.

Create an internal/private-IP DNS record for `zabbix.mmlinaric.com` pointing to
`192.168.60.21`. The dashboard and SSH are allowed only from the two WireGuard
administrator addresses; it must not be proxied or published through
Cloudflare Tunnel.

## Deploy

Connect through the administrative WireGuard path. Provision the VM:

```bash
cd infra/proxmox/ops1
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
export AWS_ACCESS_KEY_ID='<state-access-key>'
export AWS_SECRET_ACCESS_KEY='<state-secret-key>'
export TF_VAR_proxmox_api_token='<pve2-user@realm!token=secret>'
tofu init -backend-config=backend.hcl
tofu plan -out=ops1.tfplan
tofu apply ops1.tfplan
```

In RouterOS Safe Mode, upload and run
`network-docs/_rb5009_enable_ops1_zabbix.rsc`, then run its audit file. This
adds two exact-source TCP/10051 permits before the existing management deny;
it does not allow `ops1` to initiate management connections.

Run the complete Ansible deployment with only the selected Bitwarden project:

```bash
export BWS_ACCESS_TOKEN='<machine-account-token>'
bws run --project-id '<zabbix-project-id>' -- \
  'ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/zabbix.yml'
```

The playbook changes the default `Admin` password, disables the stock
`Zabbix server` host, and creates encrypted active-agent hosts for `ops1`,
`sec1`, `k3s-01`, `pve1`, and `pve2`. It links the stock active Linux template
and adds update-count and reboot-required checks. Run it a second time and
confirm that it completes without unexpected changes.

Enroll `ops1` into the existing Wazuh manager after the Zabbix deployment:

```bash
bws run --project-id '<wazuh-project-id>' -- \
  'ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/wazuh.yml --limit "sec1,ops1"'
```

Including `sec1` reconciles its source-restricted firewall before `ops1`
attempts Wazuh enrollment.

## Verify

```bash
ssh mario@192.168.60.21
sudo systemctl --no-pager --full status postgresql zabbix-server nginx zabbix-agent2
sudo ss -lntp | grep -E ':(443|10051)\b'
sudo zabbix_server --version
sudo zabbix_agent2 -t homelab.reboot_required
sudo zabbix_agent2 -t homelab.updates_available
sudo systemctl list-timers ops1-zabbix-backup.timer
```

In the dashboard, confirm all five hosts have recent active-agent data and no
PSK errors. Re-run the RouterOS audit and confirm both rules record traffic.

Trigger and inspect the first backup rather than waiting overnight:

```bash
sudo systemctl start ops1-zabbix-backup.service
sudo journalctl -u ops1-zabbix-backup.service --no-pager
sudo bash -c 'set -a; source /etc/ops1-backup/restic.env; set +a; restic snapshots --host ops1 --tag zabbix'
```

## Recovery

The backup contains a PostgreSQL custom-format dump, Zabbix configuration,
Nginx configuration, and certificate renewal configuration. Recreate an
isolated VM, install the pinned package version, restore a snapshot, validate
`SHA256SUMS`, import the database with `pg_restore`, restore configuration,
and start PostgreSQL, Zabbix, PHP-FPM, and Nginx in that order. Never start a
test copy with production integrations or the production IP enabled.
