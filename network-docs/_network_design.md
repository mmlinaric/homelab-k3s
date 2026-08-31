# Home network design and isolation guide

This document describes the network as it exists after the VLAN30 migration on 2026-08-23. It is based on `__latest.rsc`, the final RB5009 hidden-secrets export, plus the validated switch and wAP ax state.

It explains both the intended design and the effective behavior of the current firewall. Where those differ, the difference is called out explicitly.

## High-level design

The RB5009 is the Layer-3 router and firewall. It provides the gateways, DHCP, DNS forwarding, Internet NAT, VPN termination, and policy between VLANs.

The CSS326, TL-SG108E, and wAP ax primarily provide Layer-2 transport:

```text
Internet / ISP
      |
  SFP VLAN100 (PPPoE)
      |
   RB5009
      |-- ether2: tagged trunk --> CSS326 port 1
      |                              |
      |                              |-- port 4 --> TL-SG108E port 1
      |                              |               |-- VLAN30 workstation
      |                              |               `-- PVE2 VLAN20/VLAN60
      |                              |
      |                              |-- port 6 --> PVE1 VLAN20/VLAN60
      |                              `-- port 8 --> VLAN30 Apple TV
      |
      |-- ether8: tagged trunk --> wAP ax ether1
      |                              |-- main Wi-Fi --> VLAN30
      |                              `-- guest Wi-Fi --> VLAN40
      |
      `-- ether7 / VLAN101 --> VoIP bridge
```

Traffic between different VLANs must pass through the RB5009 firewall. Traffic between devices in the same VLAN is normally switched directly and does not pass through the IP firewall.

## VLANs and their roles

| VLAN | IPv4 subnet | Gateway | Purpose | Address assignment |
|---:|---|---|---|---|
| 10 | `192.168.10.0/24` | `192.168.10.1` | OOB/KVM management | DHCP `.100-.200` plus static devices |
| 20 | `192.168.20.0/24` | `192.168.20.1` | Infrastructure management | Primarily static addresses |
| 30 | `192.168.30.0/24` | `192.168.30.1` | Trusted clients and main Wi-Fi | DHCP `.100-.199` plus reservations |
| 40 | `192.168.40.0/24` | `192.168.40.1` | Guest Wi-Fi | DHCP `.10-.254` |
| 60 | `192.168.60.0/24` | `192.168.60.1` | Servers and Kubernetes services | Static/server-managed addressing |
| 90 | `192.168.90.0/24` | `192.168.90.1` | WireGuard VPN clients | Per-peer `/32` addresses |
| 99 | No active client gateway policy | — | Reserved quarantine VLAN | Not currently deployed to access ports |
| 100 | ISP-facing | PPPoE | Internet service over SFP | ISP/PPPoE |
| 101 | ISP-facing | DHCP from provider | VoIP service | Provider DHCP |

`192.168.88.0/24`, the former untagged/default network, has been retired. Its gateway, DHCP service, pool, lease, DNS references, and policy references were deleted.

The firewall address lists still mention `192.168.50.0/24` and `192.168.65.0/24`, but the final export does not show local VLAN gateway interfaces for those networks. Treat them as historical or externally routed references until separately inventoried.

## Why VLAN1 still appears on the switches

Retiring `192.168.88.0/24` and completely erasing VLAN1 from every switch are two different operations.

The former VLAN1 Layer-3 service is retired:

- The RB5009 no longer has `192.168.88.1`.
- There is no VLAN1 DHCP server or pool.
- There is no active `192.168.88.0/24` route.
- The RB5009 trunks on ether2 and ether8 reject untagged traffic.
- Ingress filtering does not permit VLAN1 on either trunk.

However, VLAN1 remains on several CSS326 and TL-SG108E ports as their default/native Layer-2 VLAN or PVID. A frame entering one of those ports untagged may still be classified internally as VLAN1 and switched to another VLAN1 member port.

The resulting VLAN1 is therefore an isolated Layer-2 island:

- VLAN1 devices on remaining member ports may still communicate directly with each other.
- They cannot obtain an address from the retired RB5009 DHCP service.
- They have no RB5009 gateway for Internet or inter-VLAN routing.
- Untagged VLAN1 traffic sent toward RB5009 ether2 or ether8 is dropped.
- Tagged VLAN1 arriving on those RB5009 trunks is also rejected because the trunks are not VLAN1 members.

For example, an untagged device on a CSS326 VLAN1 port can potentially reach another local VLAN1 device. If its traffic travels toward CSS port 1 and RB5009 ether2, the RB5009 drops it at the bridge-port admission boundary before IP routing occurs.

Keeping these remnants temporarily avoids changing native/PVID behavior on multiple switch and hypervisor trunks during the client migration. It is containment, not complete Layer-2 removal.

Fully eliminating VLAN1 is a later coordinated hardening stage. It requires:

1. Inventorying every switch port and every untagged/native dependency.
2. Explicitly modeling VLAN10 across the CSS326-to-TL-SG108E link.
3. Moving unused/access ports to a quarantine VLAN or disabling them.
4. Removing VLAN1 from inter-switch and hypervisor trunks.
5. Changing trunk admission from permissive/native behavior to tagged-only.
6. Validating switch management, both Proxmox hosts, VLAN10, VLAN20, VLAN30, and VLAN60 before committing.

Do not simply delete the VLAN1 rows from both switches. A device or trunk may still rely on its current native/PVID behavior even though `192.168.88.0/24` is gone.

## Trunks and Layer-2 transport

### RB5009 to CSS326

RB5009 `ether2` admits tagged frames only and carries:

- VLAN10
- VLAN20
- VLAN30
- VLAN60

Ingress filtering is enabled. Untagged VLAN1 traffic is rejected at the RB5009 edge.

### RB5009 to wAP ax

RB5009 `ether8` admits tagged frames only and carries:

- VLAN20 for AP management and CAPsMAN control
- VLAN30 for the main SSID
- VLAN40 for the guest SSID

The AP processes client traffic locally and tags it according to the CAPsMAN datapath. CAPsMAN controls the radios, but client data is not tunneled centrally through CAPsMAN.

### CSS326 to TL-SG108E

CSS326 port 4 connects to TL-SG108E port 1. The currently validated explicit CSS memberships are:

- VLAN20: CSS ports `1,4,6`
- VLAN30: CSS ports `1,4,8`
- VLAN60: CSS ports `1,4,6`

CSS port 4 is hardened as a tagged-only trunk:

- VLAN Mode: `strict`
- VLAN Receive: `only tagged`
- Default VLAN ID: `1`
- Force VLAN ID: disabled

VLAN10 is explicitly carried through CSS326 ports 1 and 4 and TL-SG108E port 1. TL-SG108E port 1 is not a VLAN1 member and carries VLANs 10, 20, 30, and 60 tagged. TL-SG108E port 4 is currently untagged in VLAN1 with PVID 1, has no routed gateway or DHCP service, and has no assigned future role.

CSS port 3 was the temporary Fedora VLAN20 recovery port. It is no longer a VLAN20 member and is disabled.

### TL-SG108E

The last recorded TL-SG108E design was:

- Port 1: uplink trunk toward CSS326
- Port 2: VLAN30 untagged access for the workstation, PVID 30
- Port 6: tagged VLAN20 and VLAN60 for PVE2
- Port 7: VLAN10 access

The TL configuration should be backed up and re-audited before hardening the CSS-to-TL trunk.

## Wi-Fi operation

CAPsMAN on the RB5009 provisions both AP radios.

### Main Wi-Fi

- SSID: `WFJW2PS6A`
- 2.4 GHz and 5 GHz
- WPA2-PSK/WPA3-PSK
- CAPsMAN datapath: `main-datapath`
- VLAN: 30

Main Wi-Fi clients receive `192.168.30.x` addresses from `dhcp-trusted`.

Known reservations include:

- Fedora: `192.168.30.43`
- HP printer: `192.168.30.123`

### Guest Wi-Fi

- SSID: `WFJW2PS6G`
- 2.4 GHz and 5 GHz
- WPA2-PSK/WPA3-PSK
- CAPsMAN datapath: `guest-datapath`
- VLAN: 40
- AP client isolation enabled

Guest client isolation has two layers:

1. The AP datapath prevents direct local client-to-client communication where supported.
2. The RB5009 firewall blocks routed guest-to-guest and guest-to-LAN traffic.

### AP management

The wAP ax has:

- Static management address `192.168.20.20/24`
- Gateway `192.168.20.1`
- DNS server `192.168.20.1`
- CAPsMAN discovery on `vlan20-mgmt`

It has no remaining DHCP client or `192.168.88.x` fallback address.

## DHCP and DNS

The RB5009 provides DHCP for VLAN10, VLAN30, and VLAN40.

VLAN20 infrastructure uses static addressing. A DHCP network entry exists for VLAN20, but there is no VLAN20 DHCP server in the final configuration.

Clients that use the router for DNS send queries to their VLAN gateway. The RB5009 forwards DNS through Cloudflare Security DNS-over-HTTPS:

- Bootstrap servers: `1.1.1.2` and `1.0.0.2`
- DoH endpoint: `https://security.cloudflare-dns.com/dns-query`
- Certificate verification enabled

`router.lan` resolves to `192.168.20.1`.

## How the firewall works

RouterOS has two important IPv4 filter paths:

- `input`: traffic whose destination is the RB5009 itself.
- `forward`: traffic routed through the RB5009, including inter-VLAN and Internet traffic.

Firewall rules are evaluated from top to bottom. The first matching action wins. This rule ordering is essential to understanding the effective policy.

### Access to the router itself

#### VLAN30 trusted clients

All VLAN30 clients may use:

- DHCP to the router
- DNS over UDP/TCP to the router
- ICMP/ping to the router

All other VLAN30-to-router access is dropped, except when an earlier rule matches `HOST-ADMIN`.

Fedora `192.168.30.43` is in `HOST-ADMIN`, so it may additionally reach router TCP ports:

- 22: SSH
- 443: HTTPS
- 8291: WinBox

#### VLAN40 guests

Guests may use DHCP and router DNS over both UDP and TCP. Other access to the
router is dropped.

#### VLAN20 management devices

VLAN20 devices may ping the router and use router DNS. TCP 22, 443, and 8291 requires the source address to be in `HOST-ADMIN`.

There is currently no VLAN20 address in `HOST-ADMIN`, because the temporary Fedora `192.168.20.250` entry was removed.

#### VLAN60 servers

Servers may ping the router and use router DNS. Other server-to-router access is dropped.

#### WireGuard

Traffic sourced from `192.168.90.0/24` is accepted early in the input chain. WireGuard peers therefore have broad access to the router itself, subject to which RouterOS services are enabled.

#### VLAN10 nuance

`vlan10-oob-kvm` is a member of the RouterOS `LAN` interface list. The input chain ends by dropping traffic not coming from that interface list, but it does not contain a final drop for unmatched traffic from members of `LAN`.

As a result, VLAN10 currently has broader router-input access than VLAN20, VLAN30, VLAN40, or VLAN60. This may be intentional for OOB administration, but it should not be mistaken for a narrowly restricted policy.

## Effective IPv4 isolation matrix

The table summarizes new connections. Return traffic for permitted connections is allowed through connection tracking.

| Source | Internet | Router | VLAN10 | VLAN20 | VLAN30 | VLAN40 | VLAN60 |
|---|---|---|---|---|---|---|---|
| VLAN10 OOB | Blocked | Broadly allowed | Same VLAN | New connections to `192.168.x.x` blocked | Blocked | Blocked | Blocked |
| VLAN20 management | Allowed | ICMP/DNS; admin TCP only for `HOST-ADMIN` | Blocked | Same VLAN | Blocked | Blocked | Blocked by current rule order |
| VLAN30 normal client | Allowed | DHCP/DNS/ICMP | Blocked | Blocked | Same VLAN | Blocked | Only ingress VIP TCP 80/443 |
| Fedora VLAN30 admin | Allowed | Plus SSH/HTTPS/WinBox | No general allow | Approved management ports and ICMP | Same VLAN | Blocked | TCP 22/80/443/6443 and ICMP |
| VLAN40 guest | Allowed | DHCP/DNS only | Blocked | Blocked | Blocked | Client-to-client blocked | Blocked |
| VLAN60 server | Allowed | DNS/ICMP only | Blocked | Blocked | Blocked | Blocked | Same VLAN |
| WireGuard admin peer | Allowed | Broad router access | Not comprehensively restricted | Approved ports and ICMP | Potentially reachable | Blocked by LAN-to-guest rule | Approved ports and ICMP |

### VLAN20 management isolation

VLAN20 infrastructure may access the Internet but is prevented from initiating new connections to RFC1918 private networks.

New access into VLAN20 is denied unless it matches the earlier `HOST-ADMIN` rules:

- TCP 22, 80, 443, 8006, 8291
- ICMP

### VLAN30 trusted-client isolation

Normal VLAN30 clients may:

- Access the Internet
- Access the ingress VIP `192.168.60.100` on TCP 80/443
- Use their local router services described above

They may not initiate other connections to RFC1918 private networks.

This is why a normal phone can browse the Internet but cannot open a Proxmox interface at `192.168.20.10:8006`.

The Fedora admin exception is based on its exact address in `HOST-ADMIN`, not merely on being connected to the trusted SSID.

### VLAN40 guest isolation

Guest traffic is blocked:

- From guest addresses to addresses in the `LAN` address list
- From `LAN` addresses to guests
- Between routed guest clients

Internet access is explicitly permitted. VLAN20 is protected separately by the management destination-drop rule.

### VLAN60 server isolation

Servers may access the Internet but cannot initiate new connections into RFC1918 private networks.

New connections into VLAN60 are dropped unless they match one of these earlier exceptions:

- `HOST-ADMIN` to TCP 22, 80, 443, or 6443
- `HOST-ADMIN` ICMP
- `NET-TRUSTED` to ingress VIP `192.168.60.100` on TCP 80/443

This keeps administrative services limited while allowing trusted clients to reach published applications.

### Known firewall-order issue

The rules allowing `HOST-ADMIN` access to VLAN60 appear after `MGMT: block initiating into private networks`.

Therefore, if a future `HOST-ADMIN` device is placed inside VLAN20, its server connection is dropped before the later server-admin allow can match. Fedora works because it is now in VLAN30, whose private-network drop appears after the server-admin allows.

This should be corrected only if VLAN20 admin workstations are intended to manage VLAN60.

### WireGuard scope caveat

The two WireGuard peer addresses are in `HOST-ADMIN`. Destination-specific rules protect VLAN20, VLAN40, and VLAN60, but there is no general WireGuard-to-private-networks deny rule.

Unmatched WireGuard forwarding can fall through the chain and be accepted. Before describing the VPN as least-privilege, perform a dedicated reachability audit against every routed subnet.

## Internet access and NAT

Internet service uses PPPoE over SFP VLAN100. The PPPoE interface supplies the active default route.

Outbound IPv4 traffic is masqueraded when it leaves through the `WAN` interface list.

New unsolicited traffic arriving from WAN is dropped unless destination NAT applies. The existing TCP 80 and 443 destination-NAT rules are disabled, so there are no enabled web port forwards in the final export.

WireGuard UDP port 13231 is explicitly accepted on the router.

## Connection tracking, FastTrack, and RAW

Established and related traffic is accepted through connection tracking.

The broad FastTrack rule is disabled. The broad RAW LAN-to-LAN `notrack` rule is also disabled. Keeping both disabled ensures inter-VLAN flows remain visible to connection tracking, firewall policy, and counters.

Do not enable either rule without reviewing how it would interact with isolation and observability.

## IPv6 status

IPv6 is not yet documented to the same assurance level as IPv4.

The current IPv6 firewall is primarily the RouterOS default policy and relies on the `LAN` interface list. VLAN20, VLAN30, VLAN40, and VLAN60 are not all members of that interface list. The rules also allow ICMPv6 and IPsec-related traffic before the final interface-list drops.

Fedora received a ULA IPv6 address on VLAN30, so IPv6 is active somewhere in the environment. A dedicated audit is required to determine:

- Which device advertises the prefix
- Whether clients have IPv6 Internet access
- Whether inter-VLAN IPv6 routing occurs
- Whether IPv6 DNS is advertised
- Whether the effective IPv6 isolation matches the IPv4 matrix

Until that audit is complete, do not claim that IPv6 has identical isolation to IPv4.

## Management and recovery paths

Current administrative identities in `HOST-ADMIN` are:

- Fedora Wi-Fi: `192.168.30.43`
- Pixel WireGuard: `192.168.90.2`
- ThinkPad WireGuard: `192.168.90.3`

Normal management targets include:

- RB5009: `192.168.30.1` from VLAN30, or `192.168.20.1` from management paths
- CSS326: `192.168.20.2`
- TL-SG108E: `192.168.20.3`
- PVE1: `192.168.20.10:8006`
- PVE2: `192.168.20.11:8006`
- wAP ax: `192.168.20.20`

CSS326 port 3 is no longer an active recovery path. Before risky Wi-Fi, CAPsMAN, trunk, or firewall work, establish another independent recovery path—typically WireGuard or a deliberately re-enabled wired management port.

## Failure domains and troubleshooting

### If all Wi-Fi disappears

Check, in order:

1. wAP ax power and RB5009 ether8 link.
2. VLAN20 carriage on ether8.
3. CAPsMAN remote-CAP state.
4. AP route and DNS through `192.168.20.1`.
5. VLAN30 and VLAN40 membership on ether8.

The AP depends on VLAN20 for management/control, but client data uses VLAN30/VLAN40.

### If the TL-SG108E, PVE2, workstation, and some VLAN60 services all fail together

Check CSS326 port 4 membership first. That single link carries the entire TL-SG108E branch.

Removing CSS port 4 from VLAN20, VLAN30, and VLAN60 previously caused exactly this combined outage.

### If Internet works but private services fail

Check the source address and the firewall rule counters. Isolation is address-list and rule-order dependent.

For example:

- A normal VLAN30 client should be blocked from Proxmox.
- Fedora `192.168.30.43` should be allowed to approved management/server ports.
- A VLAN20 client will be blocked from initiating into server VLAN60 under the current ordering.

### If an IP answers locally but not from another VLAN

Test separately:

1. ARP/neighbor reachability from the RB5009
2. TCP port reachability rather than ICMP alone
3. Firewall counters for the expected accept/drop rule
4. The destination host's own firewall and return route

Some Windows hosts, printers, and virtual IPs may ignore ICMP even when their actual service works.

## Backups and safe changes

The definitive RB5009 recovery files are:

- `_config_final_vlan30_migration.rsc`
- `_rb5009_final_vlan30_migration.backup`

The binary backup is unencrypted and has been restricted locally to mode `600`. It still contains sensitive configuration and must be stored securely.

For future changes:

1. Collect read-only state first.
2. Create a text export and binary backup.
3. Prepare a mutation script, explicit rollback, and read-only audit.
4. Dry-run mutation and rollback.
5. Apply from an independent management path in Safe Mode.
6. Validate both intended behavior and unrelated critical paths.
7. Release Safe Mode only after validation.
8. Create a new checkpoint after committing.

## Remaining recommended work

See `_todo.md` for the prioritized follow-up list. The most important items are:

1. Audit IPv6 isolation.
2. Explicitly model VLAN10 and harden the CSS326-to-TL-SG108E trunk.
3. Restrict wAP ax management services.
4. Decide whether VLAN20 `HOST-ADMIN` devices should reach VLAN60 and correct rule order if required.
5. Audit WireGuard reachability for least privilege.
