# Home Infrastructure Security, Monitoring, Network Segmentation, and Recovery Plan

**Environment:** MikroTik RB5009, CSS326/SwOS switching, GMKtec Proxmox host, ThinkCentre M920q, Raspberry Pi 5, Docker-based applications, Cloudflare Tunnel, Keycloak, GitLab, BookStack, SonarQube, Contabo S3 backups
**Prepared:** 2026-07-13
**Current-state snapshot:** 2026-08-23, reconciled with the validated migration and hardening handoff records
**Status:** VLAN 30 migration and retirement of the former `192.168.88.0/24` Layer-3 network are complete; remaining work is Layer-2, management-plane, monitoring, and recovery hardening
**Primary objective:** Make the environment understandable, observable, recoverable, and reasonably secure without turning it into an unnecessarily complex enterprise platform.

---

## 1. Executive summary

VLAN 20 carries infrastructure management, VLAN 30 carries trusted clients and the main Wi-Fi SSID, VLAN 40 carries guest Wi-Fi, and VLAN 60 carries the active K3s server workload. The former `192.168.88.0/24` Layer-3 network has been retired. RB5009 trunks toward the CSS326 and wAP ax are tagged-only with ingress filtering enabled.

The RB5009 IPv4 input and forwarding chains now have explicit final-deny rules. Router administration is restricted to the two authenticated WireGuard peers, router IP services are source-restricted, unused RB5009 Ethernet ports are disabled, and router MAC management and neighbor discovery are disabled. CAPsMAN certificate authentication is active and both Wi-Fi networks were validated afterward.

The next priorities are:

1. Preserve and verify router, switch, and Proxmox backups and recovery access.
2. Preserve and periodically retest the dedicated RB5009 `ether3` physical recovery path documented in `__physical_recovery_port.md`.
3. Explicitly model VLAN 10 on the CSS326-to-TL-SG108E link, then harden that trunk.
4. Remove unintended residual VLAN 1 participation and disable or quarantine unused switch ports.
5. Keep Zabbix for infrastructure and patch/reboot monitoring.
6. Add Wazuh on the M920q for security monitoring, vulnerability visibility, file-integrity monitoring, authentication events, and audit data.
7. Send router, switch, Proxmox, Linux, Keycloak, GitLab, and Cloudflare-related logs away from the system being monitored.
8. Automate rebuilding VM100 and other important VMs using Ansible, Docker Compose, SOPS, and documented restore procedures.
9. Keep daily application-aware backups in Contabo S3, add local Proxmox backups, and test restores.
10. Use self-hosted NetBird for convenient remote access only after the network is segmented. Keep RouterOS WireGuard as a permanent break-glass path.

### 1.1 Completed network-security work as of 2026-08-23

- VLAN 20 management, VLAN 30 trusted clients, VLAN 40 guest Wi-Fi, and VLAN 60 servers are operational.
- The main Wi-Fi SSID and wired workstation use VLAN 30; wAP ax management uses static VLAN 20 address `192.168.20.20`.
- The former `192.168.88.0/24` gateway, DHCP service, pool, lease, DNS references, and firewall references are removed.
- RB5009 trunks to the CSS326 and wAP ax are tagged-only with ingress filtering enabled.
- IPv4 input and forwarding use explicit final-deny rules; broad RAW `notrack` and broad FastTrack remain disabled.
- Router administration is authorized only for WireGuard peers `192.168.90.2/32` and `192.168.90.3/32`; the Fedora VLAN 30 address is no longer an administrative identity.
- RB5009 SSH and WinBox are source-restricted, SSH strong cryptography is enabled, and unused router services are disabled.
- RB5009 MAC-Telnet, MAC-WinBox, MAC-Ping, and neighbor discovery are disabled.
- Unused RB5009 interfaces `ether3` through `ether6` are disabled.
- CAPsMAN requires authenticated CAP certificates; the main and guest Wi-Fi services were validated afterward.
- Pre-change and post-change RB5009 recovery checkpoints were created, downloaded, and hashed.

The M920q should run Proxmox as an independent node. It should host monitoring and security workloads and act as a recovery destination. It should not become required for normal application operation.

The Raspberry Pi is optional but useful as a small independent watchdog, secondary `cloudflared` connector, secondary NetBird routing peer, and secondary receiver for critical router logs.

---

## 2. Important safety and privacy notes

### 2.1 The uploaded export contains identifying information

Even with `export hide-sensitive`, a RouterOS export can contain:

- Router model and serial number
- Software ID
- ISP username
- Public WireGuard keys
- Internal addressing and host information
- Service names
- Certificate references
- Comments containing device names

These are not all passwords, but they should still be removed before sharing a configuration publicly.

Create two versions of future exports:

- **Private recovery export:** complete `hide-sensitive` export, stored encrypted.
- **Sanitized support export:** remove serial number, software ID, ISP username, hostnames, public keys, internal comments, and public domain names.

### 2.2 Always prepare a recovery method before changing VLANs

Before enabling or modifying VLAN filtering:

- Export the RouterOS configuration.
- Create a RouterOS binary backup.
- Export the CSS326/SwOS configuration.
- Confirm physical access to the router and switches.
- Identify one dedicated recovery Ethernet port.
- Confirm that MAC WinBox or an IP recovery address works on that port.
- Keep a laptop with a configured static recovery address.
- Use RouterOS Safe Mode for risky changes.
- Do not perform the initial migration remotely.

### 2.3 Preserve the ISP and VoIP configuration initially

The current WAN path uses:

- ISP VLAN 100
- PPPoE
- A separate VLAN 101/VoIP bridge arrangement
- Custom MTU values

Do not redesign WAN, PPPoE, GPON access, VoIP, or MTU settings during the LAN migration. Treat those as a separate project after the LAN is stable.

---

## 3. Current implementation state

This is a point-in-time description reconciled with the validated migration and hardening handoff records. It records the resulting state, not the individual migration attempts. The detailed unchecked checklists later in this document may include stale validation items; the current-state sections and `__remaining_hardening.md` take precedence.

### 3.1 Routed networks and VLANs

| Network | Router interface | Gateway | Current state |
|---|---|---|---|
| OOB-KVM / VLAN 10 | `vlan10-oob-kvm` | `192.168.10.1/24` | Operational; NanoKVM isolation network |
| Management / VLAN 20 | `vlan20-mgmt` | `192.168.20.1/24` | Operational as a real tagged VLAN |
| Trusted / VLAN 30 | `vlan30-trusted` | `192.168.30.1/24` | Operational; trusted wired clients and the main Wi-Fi SSID |
| Guest / VLAN 40 | `vlan40-guest` | `192.168.40.1/24` | Operational; guest Wi-Fi is tagged by the AP datapath |
| Servers / VLAN 60 | `vlan60-infra` | `192.168.60.1/24` | Operational as a real tagged VLAN |
| Quarantine / VLAN 99 | `vlan99-quarantine` | None | VLAN interface exists but is not yet deployed to unused ports |
| WireGuard | `wireguard1` | `192.168.90.1/24` | Operational routed break-glass VPN; not an Ethernet VLAN |
| ISP / VLAN 100 | `vlan100-internet` | PPPoE | Operational; unchanged by the LAN migration |
| VoIP / VLAN 101 | `vlan101-voip`, `bridge-voip` | DHCP | Operational; unchanged by the LAN migration |

The former `192.168.88.0/24` legacy gateway, DHCP service, pool, lease, DNS references, and policy references have been removed. The former `192.168.70.0/24` bridge gateway has also been removed. VLANs 50, 70, 75, and 80 are not currently deployed.

### 3.2 Management plane

The management VLAN uses static addressing:

| Address | Device |
|---|---|
| `192.168.20.1` | RB5009 router |
| `192.168.20.2` | CSS326 `SW-01` |
| `192.168.20.3` | TP-Link TL-SG108E `SW-02` |
| `192.168.20.10` | Proxmox `PVE-01` |
| `192.168.20.11` | Proxmox `PVE-02` |
| `192.168.20.20` | wAP ax management |

Both Proxmox hosts use `vmbr0.20` for host management. Their former `192.168.60.2` and `192.168.60.3` host addresses have been removed. Host default routes use `192.168.20.1`, both web interfaces are reachable from an authorized administrator device, and both hosts remain standalone rather than forming a Proxmox cluster.

### 3.3 Physical path and VLAN carriage

```text
RB5009 ether2
  -> CSS326 port1
     -> CSS326 port6 -> PVE-01
     -> CSS326 port4 -> TL-SG108E port1
                           -> TL-SG108E port6 -> PVE-02
```

VLANs 20 and 60 are tagged end-to-end across the RB5009/CSS326 uplink and both Proxmox paths. VLAN 30 is carried to the CSS326 and downstream trusted access ports. The Proxmox bridges are VLAN-aware; host management uses VLAN 20 and server VM NICs use VLAN 60.

RB5009 `ether2` toward the CSS326 is tagged-only and carries VLANs 10, 20, 30, and 60 with ingress filtering enabled. RB5009 `ether8` toward the wAP ax is tagged-only and carries VLANs 20, 30, and 40 with ingress filtering enabled. Residual VLAN 1 behavior remains possible inside the switches and must be inventoried and removed without disrupting the downstream TL-SG108E branch.

CSS326 port 4 to TL-SG108E port 1 is a hardened tagged-only inter-switch trunk. CSS326 port 4 uses `strict` VLAN mode and `only tagged` receive admission. TL-SG108E port 1 is not a VLAN 1 member and carries VLANs 10, 20, 30, and 60 tagged. VLAN 10 is explicitly modeled across the link: CSS326 ports 1 and 4 are members, TL-SG108E port 1 is tagged, and TL-SG108E port 7 is untagged with PVID 10. Switch management, PVE2, NanoKVM, the VLAN 30 wired workstation, VLAN 60 services, PPPoE, CAPsMAN, Internet, and DNS are validated. The workstation uses `192.168.30.104` and reaches the Internet. TL-SG108E port 4 is currently untagged in VLAN 1 with PVID 1, has no routed gateway or DHCP service, and has no assigned future role.

### 3.4 Server network and K3s

The active K3s workload is on VLAN 60:

| Address | Purpose |
|---|---|
| `192.168.60.1` | Router gateway and DNS resolver |
| `192.168.60.5` | K3s API virtual IP |
| `192.168.60.10` | `k3s-01` node |
| `192.168.60.100` | K3s ingress virtual IP |

The node reports `Ready`, its internal address is `192.168.60.10`, and no unhealthy pods were reported during post-migration validation. Internet access and DNS resolution from the node work. Public DNS records were updated separately and are expected to follow normal DNS propagation.

### 3.5 Current firewall state

The broad RAW LAN-to-LAN `notrack` rule and broad FastTrack rule remain disabled. Connection tracking is active. IPv4 input and forwarding now use explicit allow rules followed by final-deny rules.

VLAN 20 policy provides:

- Administrator TCP access to management devices on ports `22,80,443,8006,8291`.
- Administrator ICMP access to management devices.
- Management-device internet access.
- A block on management devices initiating new connections into routed private networks.
- A block on unauthorized new connections to `NET-MGMT`.

VLAN 60 policy provides:

- ICMP and router DNS over UDP/TCP from VLAN 60, followed by a drop of other VLAN 60 access to the router.
- Administrator TCP access to servers on ports `22,80,443,6443` and administrator ICMP.
- Trusted-client access to `192.168.60.100` on ports `80,443`.
- A private-network block placed before the server-to-WAN allow, preventing servers from initiating new connections into RFC1918 networks.
- Server internet access.
- A block on unauthorized new connections to `NET-SERVERS`.

Administrative authorization no longer comes from the Fedora VLAN 30 address. `HOST-ADMIN` is restricted to the authenticated WireGuard peers `192.168.90.2/32` and `192.168.90.3/32`. WireGuard access to the router and VLANs 10, 20, and 60 is explicitly filtered; unmatched forwarding reaches the final deny.

Validated behavior includes:

- A trusted VLAN 30 client can reach approved ingress services but cannot use router or infrastructure administrative services.
- The Kubelet port `192.168.60.10:10250` is not reachable from the trusted client network.
- The K3s node can reach the internet but cannot reach Proxmox management at `192.168.20.10:8006` or router SSH at `192.168.60.1:22`.
- Router DNS over both UDP and TCP works from VLAN 60.
- Guest-to-protected-network access is blocked.
- The firewall rule counters recorded hits for the intended allow and deny paths.

Current policy objects include `NET-MGMT`, `NET-SERVERS`, `NET-PRIVATE`, `NET-TRUSTED`, and `HOST-ADMIN`. A policy-ordering question remains for any future administrative workstation placed directly in VLAN 20: either keep administration WireGuard-only or add narrow VLAN20-admin-to-server permits before the management private-network deny.

### 3.6 Router services and remaining hardening

FTP, Telnet, HTTP, API, API-SSL, the unused reverse-proxy listener, and RouterOS SMB are disabled. SSH strong cryptography is enabled. RB5009 SSH and WinBox are restricted to `192.168.90.2/32` and `192.168.90.3/32`. MAC-Telnet, MAC-WinBox, MAC-Ping, and neighbor discovery are disabled on the RB5009.

The following items remain for later review rather than removal without verification:

- Residual Layer-2 VLAN 1 participation and unused physical ports on the CSS326 and TL-SG108E.
- Explicit VLAN 10 modeling and tagged-only admission on the CSS326-to-TL-SG108E trunk.
- wAP and switch management-plane hardening.
- A deliberate IPv6 support-or-disable decision.
- OpenVPN, old PPP/IPsec objects, disabled destination-NAT rules, stale address-list entries, and other confirmed-unused leftovers. The stale one-time `Reconnect PPPoE` scheduler has been removed.
- SNMP, time synchronization, centralized logging, IoT/media separation, and host-level east-west controls.

### 3.7 MTU should be treated as a separate investigation

The WAN configuration uses:

```text
SFP MTU:       1492
ISP VLAN MTU:  1488
PPPoE MTU:     1480
```

These may be required by the ISP/GPON design, but they are unusual enough to document.

Do not change them during the VLAN migration.

After the network is stable, test:

- PPPoE negotiated MTU/MRU
- Path MTU to several internet destinations
- TCP MSS behavior
- Interface FCS/errors/drops
- Whether large HTTPS transfers stall
- Whether IPv4 fragmentation-needed messages are blocked
- Whether the historical “slow IP/drop” problem was LAN connection tracking rather than WAN MTU

---

## 4. Target network architecture

### 4.1 VLAN and subnet plan

Use VLANs for security roles, not physical servers.

| VLAN/network | Name | Subnet | Gateway | Purpose |
|---:|---|---|---|---|
| 10 | `OOB-KVM` | `192.168.10.0/24` | `192.168.10.1` | NanoKVM only |
| 20 | `MGMT` | `192.168.20.0/24` | `192.168.20.1` | Router, switches, Proxmox, AP management |
| 30 | `TRUSTED` | `192.168.30.0/24` | `192.168.30.1` | PCs, laptops, phones, normal trusted clients |
| 40 | `GUEST` | `192.168.40.0/24` | `192.168.40.1` | Guest Wi-Fi, internet only |
| 50 | `IOT` | `192.168.50.0/24` | `192.168.50.1` | Optional IoT/untrusted devices |
| 60 | `SERVERS` | `192.168.60.0/24` | `192.168.60.1` | Application VMs and internal services |
| 70 | `VPN-GW` | `192.168.70.0/24` | `192.168.70.1` | NetBird routing peers only |
| 75 | `EDGE-DMZ` | `192.168.75.0/24` | `192.168.75.1` | Internet-facing control/edge services |
| 80 | `BACKUP` | `192.168.80.0/24` | Optional | Future backup/replication network |
| 90 | `WIREGUARD` | `192.168.90.0/24` | `192.168.90.1` | Existing routed break-glass VPN |
| 99 | `QUARANTINE` | `192.168.99.0/24` | Optional | Unused/default physical ports |

Notes:

- `192.168.90.0/24` is a routed WireGuard network, not necessarily Ethernet VLAN 90.
- VLAN 80 is optional and should not be added until there is a concrete backup-network use.
- VLAN 50 can be added later.
- VLAN 75 is recommended because an internet-exposed NetBird control server should not also be the privileged routing peer.

### 4.2 Core IP allocation

#### VLAN 20 — management

| Address | Device |
|---|---|
| `192.168.20.1` | RB5009 router |
| `192.168.20.2` | CSS326 `SW-01` |
| `192.168.20.3` | Second managed switch `SW-02` |
| `192.168.20.10` | GMKtec Proxmox `PVE-01` |
| `192.168.20.11` | M920q Proxmox `PVE-02` |
| `192.168.20.12` | Raspberry Pi management, if used |
| `192.168.20.20-29` | APs, UPS, future infrastructure |

These should be static addresses configured directly on infrastructure devices.

#### VLAN 60 — servers

| Address | VM/service |
|---|---|
| `192.168.60.5` | Current K3s API virtual IP |
| `192.168.60.10` | Current `k3s-01` node |
| `192.168.60.15` | Reserved for `AI-01` if that workload is enabled |
| `192.168.60.20` | `sec1`, Wazuh |
| `192.168.60.21` | `OPS-01`, Zabbix/syslog |
| `192.168.60.30` | Internal utility VM if needed |
| `192.168.60.100` | Current K3s ingress virtual IP |

Long-lived VMs can use DHCP reservations tied to stable Proxmox virtual MAC addresses. Infrastructure hypervisors, routers, and switches should use static addresses.

#### VLAN 70 — NetBird routing peers

| Address | Device |
|---|---|
| `192.168.70.10` | `NB-RTR-01` on M920q |
| `192.168.70.11` | `NB-RTR-02` on Raspberry Pi or GMKtec |

These machines should have no broad internal access.

#### VLAN 75 — edge DMZ

| Address | Device |
|---|---|
| `192.168.75.10` | `NB-CTRL-01`, self-hosted NetBird control plane |
| `192.168.75.20` | Optional dedicated `cloudflared` connector |

The edge VM should not also be a management routing peer.

### 4.3 Address allocation policy

Use consistent ranges:

```text
.1              Router/gateway
.2-.9           Switches and core network equipment
.10-.19         Physical hosts
.20-.39         Infrastructure services
.40-.99         Fixed servers/devices
.100-.199       Dynamic DHCP clients
.200-.229       Temporary/test systems
.230-.254       Reserved
```

Use `home.arpa` for internal DNS, for example:

```text
router.home.arpa
sw-01.home.arpa
pve-01.home.arpa
app-01.home.arpa
sec1.home.arpa
```

---

## 5. Physical and switch-port design

### 5.1 Router-to-switch uplink

The RB5009-to-CSS326 link should be a tagged trunk carrying only the VLANs needed on the CSS326:

```text
10,20,30,40,50,60,70,75,99
```

Do not use VLAN 1 as a trusted/native user network.

During migration, it is acceptable to temporarily retain the old untagged `192.168.88.0/24` network on the trunk, but remove it after all devices move.

**Current:** RB5009 `ether2` connects to CSS326 port 1 and is a tagged-only trunk carrying VLANs 10, 20, 30, and 60 with ingress filtering enabled. VLAN 40 is carried through the separate tagged-only RB5009 `ether8` trunk to the wAP ax, together with VLANs 20 and 30. The former untagged Layer-3 LAN has been retired; residual Layer-2 VLAN 1 behavior remains to be removed from the switches.

### 5.2 Proxmox switch ports

Each Proxmox host should use a tagged trunk:

```text
VLAN 20  Proxmox host management
VLAN 60  application VMs
VLAN 70  routing-peer VM
VLAN 75  edge VM, if hosted there
VLAN 80  future backup
```

On Proxmox:

```text
Physical NIC
  └── vmbr0 (VLAN-aware)
      ├── vmbr0.20: host management
      ├── VM NIC tag 60: server VMs
      ├── VM NIC tag 70: NetBird routing peer
      └── VM NIC tag 75: NetBird control/edge
```

Use the same bridge name and VLAN design on both Proxmox hosts to simplify restores.

**Current:** PVE-01 is connected to CSS326 port 6. PVE-02 is reached through CSS326 port 4, TL-SG108E port 1, and TL-SG108E port 6. Both paths carry tagged VLANs 20 and 60 successfully. Both hosts use `vmbr0.20` for management, and VLAN 60 is available for tagged VM NICs.

### 5.3 Ordinary access ports

| Port purpose | Untagged/PVID | Tagged VLANs |
|---|---:|---|
| Trusted PC | 30 | None |
| NanoKVM | 10 | None |
| Normal server with one network | 60 | None |
| Managed AP | 20 management/native or tagged, plus SSID VLANs | 30,40,50 as required |
| Unused port | 99 or disabled | None |
| Switch uplink | None or explicit native migration VLAN | Required tagged VLANs |

For access ports:

- Enable ingress filtering.
- Accept only untagged and priority-tagged frames.
- Force the intended PVID.
- Do not allow clients to inject arbitrary tagged VLANs.

For trunk ports:

- Enable ingress filtering.
- Accept only VLAN-tagged frames after migration.
- Explicitly list allowed VLANs.
- Avoid “all VLANs” unless required.

### 5.4 CSS326 management

`SW-01` has been moved from `192.168.88.2` to `192.168.20.2` on VLAN 20.

Migration safety:

1. Add VLAN 20 to the trunk.
2. Configure one known CSS326 access port as untagged VLAN 20.
3. Connect a laptop and verify `192.168.20.1`.
4. Change the switch management VLAN/IP.
5. Verify access through the VLAN 20 port.
6. Only then continue.

### 5.5 Second switch

The second switch is a managed, VLAN-aware TP-Link TL-SG108E v6.0. It now uses `192.168.20.3` on VLAN 20. Port 1 is its uplink to CSS326 port 4, and port 6 connects to PVE-02.

For its final policy:

- Use a tagged trunk uplink.
- Put its management IP in VLAN 20.
- Assign individual access ports to VLAN 10, 30, 60, or 99.

---

## 6. Firewall policy

### 6.1 General model

Use:

```text
Allow explicitly required traffic
Drop everything else
Log selected denied traffic at a controlled rate
```

The router has two relevant paths:

- `input`: traffic destined to the MikroTik itself
- `forward`: traffic passing through the MikroTik between VLANs or to/from the internet

### 6.2 Router input policy

Allow only:

1. Established and related traffic.
2. ICMP from approved internal networks.
3. DHCP and DNS from client VLANs where the router provides those services.
4. WireGuard UDP from WAN.
5. WinBox/SSH/HTTPS from:
   - Dedicated administrator device addresses in VLAN 30, or
   - NetBird routing-peer addresses in VLAN 70, or
   - The WireGuard break-glass network.
6. SNMP from `OPS-01`.
7. CAPsMAN/Wi-Fi control traffic where required.
8. NTP/DNS requests from approved internal networks.

Then drop everything else.

Do not broadly accept all traffic from the WireGuard subnet. Allow only required management and service destinations.

Restrict `/ip service` by source address where possible, in addition to firewall rules.

Example intent:

```text
HOST-ADMIN        -> router: WinBox, SSH, HTTPS, ICMP
HOST-NETBIRD-RTR  -> router: WinBox, SSH, HTTPS, ICMP
WIREGUARD-ADMIN   -> router: WinBox, SSH, HTTPS, ICMP
OPS-01            -> router: SNMP, ICMP
TRUSTED clients   -> router: DNS, DHCP, ICMP
GUEST clients     -> router: DHCP, DNS only
Everything else   -> drop
```

### 6.3 Forward policy matrix

| Source | Destination | Policy |
|---|---|---|
| MGMT | Infrastructure management IPs | Allow required management ports |
| TRUSTED | Internet | Allow |
| TRUSTED | SERVERS | Allow selected application ports |
| TRUSTED | MGMT | Deny by default |
| GUEST | Internet | Allow |
| GUEST | Any private network | Deny |
| IOT | Internet | Allow only as needed |
| IOT | Internal networks | Deny except explicit controller/services |
| OOB-KVM | Internet | Deny |
| OOB-KVM | Internal networks | Deny initiated connections |
| MGMT/admin | OOB-KVM | Allow KVM management ports |
| SERVERS | Internet | Allow DNS, NTP, updates, external APIs as required |
| SERVERS | MGMT | Deny except explicit monitoring/backup requirements |
| VPN-GW | MGMT | Allow exact management hosts/ports only |
| VPN-GW | SERVERS | Allow exact published NetBird resources only |
| EDGE-DMZ | SERVERS | Allow exact origin ports only |
| EDGE-DMZ | MGMT | Deny |
| QUARANTINE | Internet | Optional |
| QUARANTINE | Internal networks | Deny |
| WireGuard admin | MGMT/SERVERS | Allow explicit admin destinations |
| WAN | Internal | Deny unless explicitly destination-NATed |

### 6.4 Recommended address lists

Use address lists for stable policy groups:

```text
HOST-ADMIN
HOST-PROXMOX
HOST-SWITCHES
HOST-NETBIRD-ROUTERS
HOST-MONITORING
NET-MGMT
NET-SERVERS
NET-PRIVATE
NET-GUEST
NET-QUARANTINE
```

Do not use one broad address list named `LAN` as both a trust label and a performance workaround.

### 6.5 Remove the broad RAW `notrack` rule

**Current:** the broad LAN-to-LAN RAW `notrack` rule is disabled and the validated VLAN 20/VLAN 60 policy operates with connection tracking. Do not re-enable it; doing so causes matching traffic to be accepted as `untracked` by the existing established/related/untracked rules and bypasses the intended segmentation checks.

The rule may be removed entirely after the remaining migration and rollback window. Continue to validate:

- Trusted-to-server connections
- Management-to-KVM connections
- NetBird-to-management connections
- DNS
- Git access
- SSH
- Large file transfers
- Cloudflare origins
- Zabbix and Wazuh agents

If problems return, investigate the specific flow instead of restoring broad `notrack`.

Possible causes to test:

- Incorrect subnet mask
- Incorrect default gateway
- Duplicate IP address
- Same VM restored twice
- Proxmox bridge/VLAN tag mismatch
- Switch trunk membership error
- MTU mismatch
- FastTrack interaction
- Asymmetric policy routing
- Host firewall
- Application binding to the wrong address

### 6.6 FastTrack policy

FastTrack can remain for normal trusted-to-internet traffic, but exclude flows that need detailed firewall accounting, queues, or troubleshooting.

**Current:** the broad default FastTrack rule is disabled so inter-VLAN policy and counters remain predictable during migration. Do not re-enable that broad rule. Add a narrower rule only after VLAN 30 and the final forward policy are stable.

Initially exclude:

- Management VLAN traffic
- NetBird routing-peer traffic
- Inter-VLAN traffic during migration
- IPsec traffic
- Any traffic requiring queues or accurate per-rule counters

A conservative first target is to FastTrack only established/related connections from trusted clients to WAN.

### 6.7 Physical recovery, MAC services, and discovery

The dedicated physical recovery path uses IP rather than RouterOS MAC services:

- RB5009 `ether3` is excluded from the bridge.
- Router address: `192.168.254.1/30`.
- Recovery laptop: `192.168.254.2/30`.
- Only ICMP, SSH, and WinBox to the router are permitted from the recovery laptop.
- No forwarding is permitted from the recovery interface.
- MAC-Telnet, MAC-WinBox, MAC-Ping, and neighbor discovery remain disabled.
- Keep the cable unplugged during normal operation.

The complete activation and validation procedure is recorded in `__physical_recovery_port.md`.

---

## 7. Remote access and NetBird design

### 7.1 Keep WireGuard permanently

Do not remove the current RouterOS WireGuard service.

Reduce it to a small, stable break-glass system:

- One laptop
- One phone
- Optionally one secondary laptop
- Store tested profiles securely
- Document the DDNS name and recovery procedure
- Restrict firewall access to required management hosts/ports
- Test it quarterly

WireGuard should not be the main onboarding workflow, but it remains valuable because it is independent of:

- Proxmox
- M920q
- NetBird
- Keycloak
- Docker
- Cloudflare Tunnel

### 7.2 Split the NetBird control server and routing peer

Do not combine these in the final design.

#### `NB-CTRL-01` — control plane

- VLAN 75 `EDGE-DMZ`
- Example address `192.168.75.10`
- Publicly reachable on required NetBird ports
- No direct access to VLAN 20
- No router or Proxmox credentials
- Backed up
- Monitored
- Hardened Linux VM

#### `NB-RTR-01` — routing peer

- VLAN 70 `VPN-GW`
- Example address `192.168.70.10`
- No inbound internet port forwarding
- Runs only minimal Debian/Ubuntu and NetBird client
- Limited MikroTik firewall access to exact infrastructure destinations and ports
- No stored infrastructure passwords

This split matters because compromise of an internet-exposed control server should not automatically provide a network path to management systems.

### 7.3 NetBird access path

```text
Remote laptop
    |
Encrypted NetBird overlay
    |
NB-RTR-01 in VLAN 70
    |
MikroTik forward firewall
    |
Exact allowed infrastructure address and port
```

Example allowed access:

```text
192.168.70.10 -> 192.168.20.1 TCP 8291,22,443
192.168.70.10 -> 192.168.20.2 TCP 443
192.168.70.10 -> 192.168.20.10 TCP 8006,22
192.168.70.10 -> 192.168.20.11 TCP 8006,22
```

Everything else from VLAN 70 should be denied unless a NetBird resource is deliberately added.

### 7.4 NetBird policies

Create groups:

```text
net-admins
trusted-remote-devices
ordinary-remote-users
routing-peers
```

Only `net-admins` should access management resources.

Publish individual resources first:

```text
192.168.20.1/32
192.168.20.2/32
192.168.20.3/32
192.168.20.10/32
192.168.20.11/32
```

Do not initially publish the whole `192.168.20.0/24`.

### 7.5 Masquerading

Start with NetBird route masquerading enabled.

Advantages:

- MikroTik sees traffic as coming from the routing peer, for example `192.168.70.10`.
- No overlay return route is required.
- Firewall design is simple.

Disadvantage:

- MikroTik cannot identify the individual NetBird client by source IP.
- Individual identity remains visible in NetBird logs rather than RouterOS logs.

This is acceptable initially.

### 7.6 Authentication dependency

Keycloak currently runs on the GMKtec. If NetBird authentication depends only on that Keycloak instance, a GMKtec/Keycloak failure can block new NetBird sign-ins during the incident.

Recommended sequence:

1. Deploy NetBird initially with its built-in authentication.
2. Keep a local NetBird administrator.
3. Test control-plane backup and restore.
4. Add Keycloak OIDC later if desired.
5. Preserve a non-Keycloak break-glass path.
6. Keep RouterOS WireGuard regardless.

### 7.7 Public exposure and DDNS

The self-hosted NetBird control plane requires public reachability for its documented TCP/UDP ports. Use:

```text
netbird.example.com
  -> Cloudflare DNS-only record
  -> current public IP
  -> MikroTik port forwards
  -> NB-CTRL-01 in VLAN 75
```

Use a Cloudflare API token restricted to:

- One zone
- DNS record editing only

Run the DDNS updater on the router or a small management utility.

After verifying custom DDNS, optionally disable MikroTik IP Cloud DDNS.

A direct UDP service exposes the public IP. A sufficiently large DDoS can saturate the ISP link before the MikroTik can help. This is an accepted limitation of self-hosting a public coordination/STUN service at home.

### 7.8 NetBird failure cases

| Failure | Effect | Recovery |
|---|---|---|
| Routing peer VM fails | Routed LAN resources unavailable through that peer | Use second peer or WireGuard |
| Control server fails | Management/enrollment affected; existing sessions may continue depending on path | Restore control VM, use WireGuard |
| Keycloak fails | OIDC login affected | Local NetBird admin and WireGuard |
| M920q fails | Primary routing/control/monitoring may fail | Pi/GMKtec secondary peer and WireGuard |
| Public IP changes | DNS temporarily stale | Scoped DDNS updater |
| Router firewall error | NetBird cannot reach resources | Physical recovery port or WireGuard |
| Routing peer compromised | Attacker receives only its MikroTik-allowed network path | Isolate VLAN 70, revoke peer, rebuild VM |

---

## 8. Proxmox and compute design

### 8.1 Run Proxmox on both x86 systems

#### `PVE-01` — GMKtec

Current state:

- Standalone Proxmox host at `192.168.20.10`.
- VLAN-aware `vmbr0`; host management is on `vmbr0.20`.
- No QEMU VM configuration files were present when the host was inventoried.

Planned role:

- `sec1` / VM120
  - Wazuh manager/indexer/dashboard
- `APP-01` / VM100
  - Keycloak
  - GitLab
  - BookStack
  - SonarQube
  - Cloudflare origins/connectors as currently arranged
- `AI-01` / VM105
  - Hermes agent
- Other application VMs

#### `PVE-02` — ThinkCentre M920q

Current state:

- Standalone Proxmox host at `192.168.20.11`.
- VLAN-aware `vmbr0`; host management is on `vmbr0.20`.
- VM101 `k3s-1` and VM102 `agent` were running during the migration validation.
- VM103 `jenkins-agent-01` and VM105 `assistant` were intentionally stopped.

Planned independent operational workloads:

- `OPS-01`
  - Zabbix server
  - Rsyslog receiver
  - Supporting dashboards/scripts
- `NB-RTR-01`
  - NetBird routing peer
- `NB-CTRL-01`
  - NetBird control plane, if resources permit
- Local backup target
- Temporary restore target

### 8.2 Do not form a two-node Proxmox cluster initially

Keep them standalone:

```text
PVE-01: standalone
PVE-02: standalone
```

Reasons:

- A two-node cluster introduces quorum concerns.
- It does not create application HA.
- It does not create replicated storage.
- Independent recovery is more valuable at this stage.
- Either node can be rebuilt without affecting the other’s cluster membership.

### 8.3 Standardize the hosts

Use:

- Same Proxmox major version
- Same `vmbr0` name
- Same VLAN-aware bridge design
- Same VLAN IDs
- Similar storage naming where practical
- Documented CPU type choices
- No undocumented host mounts
- VM IDs:
  - GMKtec: 100–199
  - M920q: 200–299
  - Temporary restores: 300–399

### 8.4 Restore safety

Never start an original VM and its restored copy simultaneously on the production VLAN with the same:

- IP
- MAC address
- Hostname
- Database identity
- Cloudflare Tunnel token
- Keycloak node identity

For test restores:

- Start with the NIC disconnected, or
- Put the VM on an isolated restore VLAN, or
- Use temporary IPs and disabled external connectors

---

## 9. Monitoring architecture

### 9.1 Keep Zabbix

Zabbix is suitable for operational monitoring. The problem is not that it is inherently poor; the current configuration monitors too few meaningful states.

Use Zabbix for:

- Availability
- CPU/memory/load
- Disk usage and growth
- SMART/NVMe health
- Proxmox status
- Interface state/errors/drops
- Backup success and age
- Patch status
- Reboot requirement
- Failed systemd services
- Container state
- Cloudflare connector count/process
- Certificate expiry
- SNMP monitoring
- Public/internal service probes

### 9.2 Add Wazuh

Use Wazuh for:

- Security event correlation
- Vulnerability detection
- File-integrity monitoring
- Authentication failures
- Privileged commands
- User/group changes
- SSH key changes
- Docker/container events
- Auditd events
- Security configuration assessment
- Agent-disconnected alerts
- Event-driven YARA malware detection
- Scheduled ClamAV malware scanning

Run Wazuh centrally on `sec1` on the GMKtec.

Install agents on:

- GMKtec Proxmox host
- M920q Proxmox host
- `APP-01`
- `AI-01`
- NetBird VMs
- Raspberry Pi
- Any future Linux VM

### 9.3 Central syslog

The initial production path sends a curated RouterOS stream directly to the
source-restricted Wazuh listener on `sec1`. This provides useful network events
without making the future `OPS-01` a dependency:

```text
RB5009 192.168.20.1 -> BSD syslog/UDP 514 -> sec1 192.168.60.20 -> Wazuh rules
```

When `OPS-01` exists, use it for longer-form central syslog retention and Linux
log fan-in while keeping the direct security-event path deliberately small:

```text
RouterOS -> selected second remote syslog action -> OPS-01 file
Linux/Proxmox -> journald/rsyslog -> OPS-01
OPS-01 files -> Wazuh agent or Wazuh syslog ingestion
```

Keep RouterOS local memory logging as well. The direct Wazuh action binds its
source to `192.168.20.1`; Wazuh `allowed-ips` and the sec1 firewall independently
enforce that exact sender.

For RouterOS, start with:

- `critical`
- `error`
- `warning`
- `account`
- `system`
- `interface`
- `dhcp`
- `dns`
- `wireguard`
- `ipsec`
- selected firewall events
- script/configuration-related events

Do not log every WAN drop. Rate-limit security drop logs.

### 9.4 Raspberry Pi watchdog

The Pi can run lightweight independent checks:

- Ping router
- Check GMKtec
- Check M920q
- Check public application URLs
- Check NetBird control endpoint
- Check Keycloak discovery endpoint
- Send an alert if M920q monitoring disappears
- Receive a second copy of only critical RouterOS syslog
- Run secondary `cloudflared`
- Run secondary NetBird routing peer

It should not run the full Wazuh indexer.

### 9.5 External failure signal

At least one alert source must exist outside the home environment:

- Cloudflare account/tunnel notifications
- Email from Zabbix/Wazuh
- A minimal external HTTP check
- Contabo backup alerts
- GitHub security notifications

A home-hosted monitoring platform cannot detect a total home power/ISP failure by itself.

---

## 10. Security monitoring details

### 10.1 Wazuh file-integrity scope

Start with:

```text
/etc/passwd
/etc/shadow
/etc/group
/etc/sudoers
/etc/sudoers.d/
/etc/ssh/
/etc/pam.d/
/etc/systemd/system/
/etc/cron.d/
/var/spool/cron/
/root/.ssh/
/home/*/.ssh/
/etc/docker/
/etc/cloudflared/
/etc/ufw/
/etc/nftables.conf
/srv/compose/
/opt/stacks/
```

Also monitor:

- Compose files
- Deployment scripts
- Backup scripts
- SOPS-encrypted files
- Keycloak configuration
- GitLab configuration
- Reverse-proxy configuration
- NetBird configuration

Avoid collecting secret file contents. Monitor checksums, metadata, and modification identity.

Use FIM additions and modifications to trigger local YARA scans on the affected
file. Maintain a validated, versioned rules bundle with last-known-good rollback
instead of executing mutable rules directly from an upstream feed. Complement
this with low-priority daily ClamAV scans of regular files in system,
administrator-home, user-home, and temporary paths. Keep VM disks, container
layers, index data, and backup mounts outside the scheduled scan scope. Malware
detections are immediate-notification events; automated deletion remains
disabled until false-positive behavior is understood.

### 10.2 Auditd scope

Alert on:

- User and group database changes
- Sudoers changes
- SSH authorized-key changes
- Docker socket access
- Firewall changes
- Systemd unit creation/modification
- Cron creation
- Kernel module activity
- Audit configuration changes
- Execution of selected high-risk administrative commands

Treat access to the Docker socket as high severity.

### 10.3 High-priority alerts

Immediate notification:

- New privileged user
- User added to `sudo` or `docker`
- New SSH authorized key
- Successful root SSH login
- Unexpected successful SSH login
- Repeated authentication failures
- New listening port
- New privileged container
- Container using host networking unexpectedly
- Security agent stopped
- Audit logging stopped
- Critical CVE with an available fix
- Cloudflare API token/tunnel change
- Keycloak administrator or authentication-flow change
- GitLab administrator/token/runner change
- Backup failure
- Reboot pending longer than policy
- Router account/configuration change
- Proxmox administrator login from an unusual source

### 10.4 Alert tuning

First two weeks:

- Send most alerts to a low-priority channel.
- Identify recurring expected events.
- Add exclusions narrowly.
- Escalate only high-confidence events to immediate mobile alerts.
- Review the dashboard daily during tuning.
- Never globally suppress a category because one application is noisy.

---

## 11. Keycloak, GitLab, BookStack, SonarQube, and Cloudflare

### 11.1 Authentication model

Preferred:

```text
User
  -> Cloudflare Tunnel
  -> application
  -> application redirects to Keycloak using OIDC/SAML
  -> application validates identity/session
```

The application should still enforce authentication.

Do not rely solely on a reverse proxy inserting trusted identity headers unless:

- The origin is reachable only through the proxy path.
- The application validates signed identity tokens.
- Untrusted clients cannot inject or preserve identity headers.
- Host firewall and container networking prevent bypass.

### 11.2 Keycloak

Enable:

- User events
- Admin events
- Login failure retention
- Metrics
- MFA/passkeys for administrators
- Recovery codes
- A local break-glass administrative procedure

Alert on:

- New realm administrator
- Admin role changes
- Client creation
- Client secret changes
- Redirect URI changes
- Identity-provider changes
- MFA removal
- Authentication-flow changes
- Successful login after repeated failures
- Event logging disabled

Do not place Cloudflare Access in front of Keycloak without testing every OIDC redirect and token flow. Keycloak itself must remain reachable for application authentication.

### 11.3 GitLab

Collect:

- Authentication logs
- Application logs
- Audit events available in the installed tier
- SSH key changes
- Access-token creation
- Runner registration
- Administrator changes
- Project visibility changes
- Webhook changes
- Repository deletion
- Backup status

Do not expose GitLab SSH publicly unless required. If Git-over-SSH is needed, document and protect that path separately.

### 11.4 BookStack

Monitor:

- Successful and failed OIDC login
- User and role changes
- Application configuration changes
- Database health
- Uploaded-file backup
- Unexpected admin actions
- Public shelf/page permissions

### 11.5 SonarQube

Keep LAN-only unless a business need requires remote publication.

Monitor:

- Admin changes
- Token creation
- Plugin installation
- Database state
- Search/index health
- Background-task failures
- Version and vulnerability status

### 11.6 Cloudflare Tunnel

Use two connectors for important public hostnames:

```text
cloudflared-1: GMKtec/APP environment
cloudflared-2: Raspberry Pi or separate edge VM
```

This protects against a connector failure, not an application-host failure.

Restrict each connector:

```text
cloudflared -> exact application origin IP:port
cloudflared -> management VLAN: deny
cloudflared -> unrelated servers: deny
```

Review:

- Account audit logs
- Tunnel audit logs
- Tunnel connector status
- Access authentication logs, if Cloudflare Access is used
- DNS changes
- API token activity

Use scoped API tokens and MFA/passkeys on the Cloudflare account.

---

## 12. Patch and reboot management

### 12.1 Ubuntu guests

Enable and monitor:

- `unattended-upgrades`
- `needrestart`
- `/var/run/reboot-required`
- `/var/run/reboot-required.pkgs`
- Failed APT/systemd timers
- Last successful security-upgrade time

Zabbix triggers:

| Condition | Severity |
|---|---|
| Reboot required | Information |
| Reboot required for more than 72 hours | Warning |
| Reboot required for more than 7 days | High |
| Unattended upgrades failed | High |
| No successful upgrade in 48 hours | Warning |
| Critical vulnerability with fix available | High |
| Failed systemd unit | Warning/High |

Policy:

- Install normal security updates automatically.
- Allow safe service restarts where tested.
- Reboot during a defined maintenance window.
- Reboot sooner for critical kernel/security fixes.
- Confirm backups before major application upgrades.
- Do not auto-upgrade major GitLab, Keycloak, or SonarQube versions without release-note and migration review.

### 12.2 Proxmox hosts

Do not auto-reboot.

Monitor:

- Available package updates
- Running kernel versus newest installed kernel
- Reboot requirement
- SMART/NVMe health
- Storage pool status
- Failed backup tasks
- Failed replication/restore tasks
- Temperature
- Network errors
- Proxmox task failures

### 12.3 Container images

Continue Renovate, but use it as update discovery rather than unconditional deployment.

Pipeline:

```text
Renovate merge request
  -> review release notes
  -> vulnerability scan
  -> backup verification
  -> staging/test where practical
  -> controlled deployment
  -> health and login tests
  -> rollback if needed
```

Add Trivy or an equivalent scanner to CI for container images and dependency lock files.

---

## 13. Backup and recovery design

### 13.1 Recovery objectives

Initial targets:

```text
RPO: up to 24 hours
RTO: 2-4 hours for core applications
```

These are appropriate for non-mission-critical personal services.

### 13.2 Backup layers

#### Layer 1 — application-aware off-site backup

Continue daily backup to Contabo S3:

- Keycloak database/configuration
- GitLab repositories/database/secrets/configuration
- BookStack database/uploads
- SonarQube database
- Compose files
- Persistent volumes
- SOPS-encrypted configuration
- Cloudflare/NetBird configuration
- RouterOS and SwOS exports
- Documentation

#### Layer 2 — local VM backup

From GMKtec to M920q storage:

- Nightly VM100 backup
- Nightly or scheduled VM105 backup
- Retention such as 7 daily and 4 weekly
- Encryption where supported
- Monitor job age and result

A local copy provides fast recovery. Contabo remains the off-site copy.

#### Layer 3 — configuration repository

GitHub:

- Ansible
- Compose
- Network plans
- Firewall intent
- Runbooks
- Monitoring templates
- Restore scripts
- Sanitized configuration examples

Do not depend on self-hosted GitLab for the only recovery documentation.

### 13.3 SOPS key handling

Keep:

1. Primary copy in a password manager.
2. Encrypted offline copy on removable media.
3. Documented key-recovery procedure.

Do not keep the only decryption key:

- On VM100
- In the same S3 bucket as backups
- In unencrypted Git
- Only in your memory

### 13.4 Restore automation

Target workflow:

```text
Create Ubuntu VM
  -> configure VLAN/IP
  -> clone GitHub infrastructure repository
  -> provide SOPS key securely
  -> run Ansible
  -> restore database and files
  -> start Compose stack
  -> run health checks
  -> re-enable Cloudflare origin
```

Ansible should configure:

- Users and SSH keys
- Hostname/timezone
- Packages
- Docker
- Firewall
- Wazuh agent
- Zabbix agent
- Auditd
- Unattended upgrades
- Journald retention
- Syslog forwarding
- Backup timers
- Compose directories

### 13.5 Restore testing

Schedule:

- Monthly: verify backup age, size, and object readability.
- Quarterly: restore one application into an isolated network.
- Twice yearly: restore VM100 or a replacement VM from scratch.
- Annually: simulate GMKtec hardware failure.

A backup is not proven until restored.

---

## 14. Failure and edge-case matrix

| Event | Expected result | Required response |
|---|---|---|
| GMKtec hardware failure | Applications down; M920q monitoring remains | Restore VM100 to M920q or rebuild from GitHub/S3 |
| M920q failure | Apps remain; monitoring/security dashboard down | Pi/external alert; restore OPS/SEC temporarily on GMKtec |
| Raspberry Pi failure | Secondary checks/connectors/peer lost | No application outage; replace/rebuild |
| Router failure | Site connectivity and inter-VLAN routing down | Restore RB5009 backup to replacement; use printed recovery sheet |
| CSS326 failure | Connected wired devices down | Replace switch; restore SwOS backup and port map |
| Keycloak failure | New application logins fail | Use application break-glass account/CLI; restore Keycloak |
| NetBird control failure | Enrollment/policy/admin affected | Use WireGuard; restore control VM |
| NetBird routing-peer compromise | Access limited to firewall permits | Disable peer IP/VLAN, revoke key, preserve logs, rebuild |
| APP-01 compromise | Public apps and secrets at risk | Disable tunnel routes, firewall VM, preserve evidence, rotate secrets, rebuild |
| Contabo credentials stolen | Backup confidentiality/integrity risk | Revoke credentials, inspect access, rotate keys, validate backups |
| SOPS key lost | Automated restore blocked | Retrieve password-manager/offline copy |
| Duplicate VM restore | IP/MAC/service conflicts | Keep restored NIC disconnected or use isolated VLAN |
| Public IP change | NetBird DNS temporarily stale | DDNS updater; WireGuard/Cloud DNS monitoring |
| ISP DDoS | Internet link saturated | ISP/upstream mitigation; no local firewall can restore bandwidth |
| Power outage | All local systems may stop | UPS monitoring, automatic shutdown, external outage alert |
| Firewall lockout | Remote management unavailable | Dedicated `ether3` IP recovery path or Safe Mode rollback |
| VLAN trunk error | Management/VM access loss | Direct recovery port; rollback switch/router changes |
| Wazuh unavailable | Live correlation lost | Local persistent logs continue; restore Wazuh later |
| Zabbix unavailable | Operational alerts lost | Pi watchdog/external checks continue |
| Backup job falsely reports success | Restore may fail | Periodic isolated restore tests |
| Cloudflare account compromise | Public DNS/tunnels/policies at risk | Hardware MFA, scoped tokens, audit logs, recovery codes |

---

## 15. Incident-response procedure

For suspected compromise of an application VM:

1. Do not immediately delete or reinstall it.
2. Disable the affected Cloudflare hostname or tunnel route.
3. Block the VM at the MikroTik firewall.
4. Preserve Wazuh and central syslog records.
5. Snapshot or back up the affected VM for investigation.
6. Record current network connections, processes, containers, users, and listening ports.
7. Revoke relevant Cloudflare Tunnel credentials.
8. Revoke Keycloak sessions/client secrets if exposed.
9. Revoke GitLab tokens, runners, and SSH keys if exposed.
10. Rotate SOPS-managed secrets accessible to the host.
11. Rebuild from known configuration rather than “cleaning” an untrusted system.
12. Restore data from the last known-good backup.
13. Verify application and authentication logs.
14. Document entry point, impact, and corrective action.

Prepare separate one-page runbooks for:

- Keycloak unavailable
- Cloudflare account compromise
- GMKtec hardware failure
- M920q hardware failure
- Router failure
- Lost SOPS key
- Compromised GitLab administrator
- NetBird failure
- S3 credential compromise

---

## 16. Migration sequence

### Phase 0 — inventory and backups

- [ ] Photograph front and back of all equipment.
- [ ] Record every switch port and cable.
- [x] Save a current RouterOS 7.24 export (`backup_v7.24_hidden_secrets.rsc`); retain `config_after_vlan60_firewall.rsc` as the 7.23.2 recovery snapshot.
- [x] Save and securely download a current RouterOS binary backup.
- [ ] Save CSS326/SwOS backup.
- [ ] Export Proxmox VM list and network config.
- [ ] Verify Contabo backups.
- [ ] Confirm SOPS key recovery.
- [x] Create the dedicated `ether3` physical recovery port at `192.168.254.1/30`.
- [x] Test direct ICMP, SSH, and WinBox access from Fedora at `192.168.254.2/30`.
- [ ] Print a recovery sheet.

### Phase 1 — power and prepare the M920q

- [x] Install Proxmox on M920q.
- [x] Keep it standalone.
- [x] Configure temporary legacy LAN access first.
- [x] Add VLAN-aware `vmbr0`.
- [x] Configure VLAN 20 management at `192.168.20.11`.
- [ ] Create `OPS-01`.
- [ ] Move or rebuild Zabbix.
- [x] Configure the initial direct RB5009-to-Wazuh syslog path.
- [x] Create `sec1`.
- [x] Install Wazuh.

### Phase 2 — create VLANs without removing legacy LAN

On RouterOS:

- [x] Create VLAN interfaces 20, 60, and 99.
- [x] Create the VLAN 30 interface.
- [ ] Create VLAN interfaces 70 and 75 when their migrations begin.
- [x] Add gateway addresses for VLANs 20 and 60.
- [x] Add the VLAN 30 gateway address and DHCP service.
- [ ] Add DHCP servers for future VLANs where required.
- [x] Add the VLAN 20 network entry; VLAN 20 infrastructure uses static addresses.
- [x] Add VLANs 20 and 60 to the router-switch trunk.
- [x] Keep `192.168.88.0/24` temporarily during migration.
- [x] Remove `192.168.88.0/24` after the VLAN 30 migration validated successfully.

On CSS326:

- [x] Add VLAN 20 and VLAN 60 membership on the required paths.
- [x] Configure and validate a VLAN 20 test port.
- [x] Configure the current Proxmox and inter-switch trunks.
- [x] Preserve unaffected access ports during staged migration.
- [x] Explicitly add VLAN 10 membership on CSS326 ports 1 and 4; retain permissive admission until the separate trunk-hardening stage.

### Phase 3 — move infrastructure management

- [x] Move CSS326 to `192.168.20.2`.
- [x] Move second switch to `192.168.20.3`.
- [x] Move GMKtec Proxmox to `192.168.20.10`.
- [x] Move M920q Proxmox to `192.168.20.11`.
- [x] Move AP management to VLAN 20 at `192.168.20.20`.
- [x] Restrict management access with the current VLAN 20 policy.
- [x] Test local administrator access to the router, switches, and Proxmox hosts.
- [ ] Re-test all required management paths through WireGuard after the final default-deny policy is installed.

### Phase 4 — move server workloads

- [x] Add VLAN 60 to both Proxmox trunks.
- [x] Move the active K3s node to `192.168.60.10` with API VIP `.5` and ingress VIP `.100`.
- [x] Verify K3s node health, pod health, internet access, DNS, and ingress HTTPS.
- [ ] Move other enabled server workloads to VLAN 60 as required.
- [ ] Verify Cloudflare origins after DNS propagation.
- [ ] Verify Keycloak redirects.
- [ ] Verify GitLab clone/push.
- [ ] Verify BookStack uploads.
- [ ] Verify SonarQube.
- [ ] Add Wazuh/Zabbix agents.

### Phase 5 — move trusted clients

- [x] Create VLAN 30 DHCP.
- [x] Move main Wi-Fi SSID to VLAN 30.
- [x] Move the wired workstation port to VLAN 30.
- [x] Verify access to allowed server services.
- [x] Confirm normal VLAN 30 clients cannot administer the router or VLAN 20 infrastructure.

### Phase 6 — formalize NanoKVM and guest policy

- [x] Rename VLAN 10 purpose in RouterOS and documentation to OOB-KVM.
- [x] Keep no internet from VLAN 10.
- [x] Permit legacy administrator access to the NanoKVM while blocking KVM-initiated private traffic.
- [ ] Verify guest internet.
- [x] Verify guest cannot reach protected private networks.
- [x] Configure Wi-Fi client isolation in the guest datapath.

### Phase 7 — quarantine unused ports

- [x] Disable unused RB5009 interfaces `ether3` through `ether6`.
- [ ] Put unused ports in VLAN 99 or disable them.
- [ ] Enable ingress filtering.
- [ ] Restrict frame types.
- [ ] Verify arbitrary VLAN tags are rejected.
- [ ] Alert when an unused port becomes active.

### Phase 8 — replace firewall and remove `notrack`

- [x] Install explicit VLAN 20 and VLAN 60 input policy.
- [x] Install explicit VLAN 20 and VLAN 60 forward policy.
- [x] Add final IPv4 input and forward drop rules.
- [x] Disable RB5009 MAC-Telnet, MAC-WinBox, and MAC-Ping.
- [x] Disable RB5009 neighbor discovery.
- [x] Disable broad LAN-to-LAN RAW `notrack`.
- [x] Test the required VLAN 20 and VLAN 60 flows.
- [x] Test the currently deployed VLANs after the VLAN 30 migration and final-deny changes.
- [ ] Tune FastTrack.
- [ ] Monitor invalid-state counters and logs.

### Phase 9 — retire legacy VLAN 1 / `192.168.88.0/24`

- [x] Confirm the Layer-3 migration no longer depends on a legacy lease or ARP entry.
- [x] Confirm migrated devices no longer use `192.168.88.x`.
- [x] Remove the legacy DHCP pool/server/network/lease.
- [x] Remove the legacy router address from the bridge.
- [ ] Remove VLAN 1 from ordinary ports.
- [x] Remove `192.168.88.0/24` firewall and DNS references.
- [ ] Remove other confirmed-stale address-list entries and DNS records.
- [x] Keep the recovery port intentionally documented in `__physical_recovery_port.md`.

### Phase 10 — NetBird pilot

- [ ] Deploy `NB-CTRL-01` in VLAN 75.
- [ ] Configure custom DNS-only hostname/DDNS.
- [ ] Forward only required NetBird ports.
- [ ] Deploy `NB-RTR-01` in VLAN 70.
- [ ] Add one laptop.
- [ ] Publish router `/32` only.
- [ ] Add narrow NetBird and MikroTik policies.
- [ ] Test compromise blast radius.
- [ ] Add second routing peer.
- [ ] Keep WireGuard.

### Phase 11 — recovery automation

- [ ] Build Ansible roles.
- [ ] Rebuild a test VM.
- [ ] Restore BookStack.
- [ ] Restore Keycloak test copy.
- [ ] Restore GitLab test copy.
- [ ] Document exact commands and durations.
- [ ] Measure actual RPO/RTO.

---

## 17. Verification checklist

### Network

- [x] Every currently routed VLAN has one router gateway interface.
- [x] No role-based IPv4 subnet remains directly on the untagged bridge.
- [ ] Access ports accept only untagged traffic.
- [ ] Trunks accept only required tags.
- [ ] Unused ports are disabled or quarantined.
- [x] Normal VLAN 30 clients cannot manage the router or VLAN 20 infrastructure.
- [x] VLAN 40 cannot reach protected private networks.
- [x] VLAN 10 cannot initiate internal/internet connections.
- [ ] VLAN 70 can reach only explicit management resources.
- [ ] VLAN 75 cannot reach management.
- [x] Pixel WireGuard administrative access works.
- [ ] Revalidate ThinkPad WireGuard administrative access.

### Router security

- [x] Final IPv4 input drop exists.
- [x] Final IPv4 forward drop exists.
- [x] Broad LAN-to-LAN RAW `notrack` is disabled.
- [x] Broad FastTrack is disabled during migration.
- [x] Router services are source-restricted to the two WireGuard peers.
- [x] MAC Telnet disabled.
- [x] MAC WinBox and MAC Ping disabled.
- [x] Neighbor discovery disabled on the RB5009.
- [x] RouterOS SMB server disabled.
- [ ] Unused OpenVPN, PPP/IPsec, and related leftovers removed.
- [x] Curated RB5009 remote logs enabled to the source-restricted Wazuh listener.
- [ ] SNMP source and credentials restricted.
- [ ] MikroTik admin accounts reviewed.
- [x] CAPsMAN requires authenticated CAP certificates and the intended wAP reconnects successfully.

### Hosts and applications

- [ ] MFA/passkeys enabled for Cloudflare, GitHub, Contabo, Keycloak admin.
- [x] Wazuh agents connected on `k3s-01`, `pve1`, and `pve2`.
- [x] Auditd enabled on the initial monitored Linux hosts.
- [x] Persistent journald enabled on `sec1`.
- [x] Event-driven YARA and daily ClamAV scanning enabled on the initial monitored hosts.
- [ ] Unattended upgrades monitored.
- [ ] Reboot-required monitored.
- [ ] Docker socket access monitored.
- [ ] Containers do not mount unnecessary host paths.
- [ ] Cloudflare connector cannot reach management VLAN.
- [ ] Application OIDC remains enforced.
- [ ] Break-glass local accounts documented.

### Recovery

- [ ] Contabo backup less than 24 hours old.
- [ ] Local VM backup successful.
- [ ] SOPS key recoverable.
- [ ] GitHub repository sufficient to rebuild.
- [ ] Router and switch configs stored off-device.
- [ ] Restore tested in isolation.
- [ ] Printed recovery sheet current.

---

## 18. Troubleshooting historical slow connections and drops

After migration, if performance issues remain:

### 18.1 Check Layer 1 and Layer 2

- Interface link speed/duplex
- FCS errors
- RX/TX drops
- Bad SFP/cable
- Switch port errors
- Bridge host-table instability
- MAC address moving between ports
- Duplicate MAC from cloned VMs

### 18.2 Check addressing

- Duplicate IP
- Wrong subnet mask
- Wrong default gateway
- Static address inside DHCP pool
- Old DHCP reservation
- Restored VM running with original MAC
- Device using an address from the old `192.168.88.0/24`

Use ARP inspection and `arping` from the same VLAN. A ping alone cannot detect an offline owner.

### 18.3 Check routing and firewall

- Route table
- Firewall counters
- Invalid-state drops
- Asymmetric path
- FastTrack exclusions
- Host firewall
- NetBird route/masquerade behavior
- ICMP redirects
- Multiple default routes

### 18.4 Check MTU

Test packet sizes with “do not fragment” where supported.

Check:

- PPPoE negotiated MTU
- ISP VLAN/SFP MTU
- WireGuard MTU
- NetBird tunnel MTU
- Cloudflare origin behavior
- Large Git operations
- HTTPS uploads/downloads

Do not add a global MSS clamp without confirming an MTU problem.

### 18.5 Capture one failing flow

Capture simultaneously:

- Client
- Router ingress
- Router egress
- Destination host

Record:

- Source/destination
- SYN/SYN-ACK
- Retransmissions
- ICMP errors
- ARP behavior
- MSS
- VLAN tags
- Firewall rule counters

Do not reintroduce broad `notrack` as a permanent fix.

---

## 19. Documentation and labeling

Maintain:

```text
Infrastructure/
├── network-inventory.xlsx
├── topology.drawio
├── recovery-guide.md
├── firewall-matrix.md
├── switch-port-map.csv
├── backups/
└── photos/
```

Physical labels:

```text
RTR-01
SW-01
SW-02
PVE-01
PVE-02
APP-01
AI-01
sec1
OPS-01
NB-CTRL-01
NB-RTR-01
RPI-01
KVM-01
```

Cable labels should identify both endpoints:

```text
RTR-01 etherX <-> SW-01 portY
SW-01 portX <-> PVE-01 NIC1
SW-01 portX <-> SW-02 portY
```

Do not put permanent IP addresses on every cable label. Put stable device IDs and ports on the cable; keep IPs in the inventory.

---

## 20. Recommended final state

```text
Internet
   |
RB5009 RTR-01
   |
   +-- VLAN 10  OOB-KVM
   +-- VLAN 20  infrastructure management
   +-- VLAN 30  trusted clients
   +-- VLAN 40  guests
   +-- VLAN 50  IoT, optional
   +-- VLAN 60  application servers
   +-- VLAN 70  NetBird routing peers
   +-- VLAN 75  internet-facing edge/control
   +-- VLAN 99  quarantine
   +-- WireGuard 192.168.90.0/24 break-glass
   |
CSS326 SW-01
   |
   +-- PVE-01 GMKtec
   |     +-- APP-01
   |     +-- AI-01
   |
   +-- PVE-02 M920q
   |     +-- sec1 Wazuh
   |     +-- OPS-01 Zabbix/syslog
   |     +-- NB-RTR-01
   |     +-- NB-CTRL-01
   |
   +-- RPI-01
         +-- watchdog
         +-- secondary cloudflared
         +-- secondary NetBird routing peer
         +-- critical secondary syslog
```

Availability target:

- Applications can be temporarily unavailable.
- Monitoring should normally survive application-host failure.
- Application operation should survive monitoring-host failure.
- Backups and documentation must survive both hosts.
- Remote recovery must not depend on one VPN platform.
- A single compromised VM must not have unrestricted access to management infrastructure.

---

## 21. Official documentation references

- [MikroTik — Bridge VLAN Table](https://help.mikrotik.com/docs/spaces/ROS/pages/28606465/Bridge%2BVLAN%2BTable)
- [MikroTik — Connection tracking](https://help.mikrotik.com/docs/spaces/ROS/pages/130220087/Connection%2Btracking)
- [MikroTik — Firewall Filter](https://help.mikrotik.com/docs/spaces/ROS/pages/48660574/Filter)
- [MikroTik — Interface Lists](https://help.mikrotik.com/docs/spaces/ROS/pages/47579180/Interface%2BLists)
- [MikroTik — MAC server](https://help.mikrotik.com/docs/spaces/ROS/pages/98795539/MAC%2Bserver)
- [MikroTik — Securing your router](https://help.mikrotik.com/docs/spaces/ROS/pages/328353/Securing%2Byour%2Brouter)
- [MikroTik — RouterOS Logging](https://help.mikrotik.com/docs/spaces/ROS/pages/328094/Log)
- [NetBird — Self-hosting quickstart](https://docs.netbird.io/selfhosted/selfhosted-quickstart)
- [NetBird — Networks and routing peers](https://docs.netbird.io/manage/networks)
- [NetBird — How routing peers work](https://docs.netbird.io/manage/networks/how-routing-peers-work)
- [NetBird — Masquerade](https://docs.netbird.io/manage/networks/masquerade)
- [NetBird — Ports and firewalls](https://docs.netbird.io/about-netbird/ports-and-firewalls)
- [NetBird — Keycloak integration](https://docs.netbird.io/selfhosted/identity-providers/keycloak)
- [Wazuh — File integrity monitoring](https://documentation.wazuh.com/current/user-manual/capabilities/file-integrity/index.html)
- [Wazuh — Vulnerability detection](https://documentation.wazuh.com/current/user-manual/capabilities/vulnerability-detection/how-it-works.html)
- [Wazuh — Container security](https://documentation.wazuh.com/current/user-manual/capabilities/container-security/index.html)
- [Wazuh — Audit/system-call monitoring](https://documentation.wazuh.com/current/user-manual/capabilities/system-calls-monitoring/audit-configuration.html)
- [Proxmox VE — Backup and restore](https://pve.proxmox.com/wiki/Backup_and_Restore)
- [Proxmox VE — Administration guide](https://pve.proxmox.com/pve-docs/pve-admin-guide.html)
- [Cloudflare — Tunnel audit logs](https://developers.cloudflare.com/cloudflare-one/insights/logs/dashboard-logs/tunnel-audit-logs/)
- [Cloudflare — Access authentication logs](https://developers.cloudflare.com/cloudflare-one/insights/logs/dashboard-logs/access-authentication-logs/)
- [Cloudflare — Tunnel log streams](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/monitor-tunnels/logs/)
- [Keycloak — User event metrics](https://www.keycloak.org/observability/event-metrics)
- [Keycloak — Server administration guide](https://www.keycloak.org/docs/latest/server_admin/)

---

## 22. Next concrete actions from the current state

1. Investigate the three automatic RouterOS support dumps through MikroTik's private support channel before extensive additional configuration work; the third occurred on 2026-08-24 while opening an interactive maintenance session before any mutation was applied.
2. Revalidate the ThinkPad WireGuard peer and periodically retest the documented physical recovery path.
3. Save fresh RB5009, wAP ax, CSS326, and TL-SG108E checkpoints and hashes before their next maintenance stages.
4. Inventory every CSS326 and TL-SG108E port, including VLAN membership, PVID, tagged/untagged behavior, ingress filtering, connected device, and residual VLAN 1 participation.
5. Save fresh post-change CSS326 and TL-SG108E backups; decide the future role of currently unassigned ports during the broader VLAN1/physical-port inventory.
6. Disable unused switch ports or place them in VLAN 99, remove unnecessary Layer-2 VLAN 1 participation, and verify that access ports reject injected VLAN tags.
7. Harden wAP and switch management protocols, sources, credentials, MAC services, and discovery in separate maintenance windows.
8. Decide whether to deploy Route64 IPv6 with equivalent default-deny isolation or disable routed IPv6 until that design is ready.
9. Resolve SNMP, time synchronization, and centralized security logging; then clean up confirmed-unused OpenVPN, PPP/IPsec, NAT, scheduler, and address-list leftovers.
10. Improve IoT/media separation and VLAN 20/VLAN 60 east-west controls, run the final validation matrix, and create final backups and documentation.
