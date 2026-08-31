# RB5009 hardening review of `__latest.rsc`

Date: 2026-08-23

Status: static review complete. No command in this bundle has been run on the
RB5009. Every `.rsc` file is a review draft, not an approved change.

## Bottom line

The master TODO is directionally strong and correctly prioritizes recovery,
default-deny policy, WireGuard administration, IPv6 discovery, CAPsMAN
authentication, and VLAN1 cleanup. Comparison with the current export confirms
six concrete weaknesses and several items that cannot be decided from an
export alone.

## Validated findings

### 1. VLAN10 reaches enabled router services by input-chain fall-through

Severity: medium. Confidence: high.

`vlan10-oob-kvm` is in the `LAN` interface list (`__latest.rsc:126`). The last
input drop applies only to interfaces outside `LAN` (`__latest.rsc:279-280`),
and there is no unconditional final input drop. Unmatched VLAN10 traffic is
therefore accepted at the end of the chain. SSH, HTTPS, and WinBox are enabled.

Target control: explicit VLAN10 DHCP/DNS/ICMP permits as actually required,
then deny other VLAN10 router input and finish with an unconditional input deny.

### 2. A VLAN30 IPv4 address is an administrator identity

Severity: medium. Confidence: high.

The DHCP-reserved Fedora address `192.168.30.43` is in `HOST-ADMIN`
(`__latest.rsc:178-179,218`). That list grants access to router management,
infrastructure management, server SSH/web services, and Kubernetes port 6443.
A DHCP reservation does not authenticate possession of an address on the same
Layer-2 network.

Target control: keep only the two WireGuard peer `/32`s in `HOST-ADMIN` and bind
privileged rules to `in-interface=wireguard1` as well as the source list.
Application credentials remain required; this finding concerns unnecessary
network reachability, not a direct login bypass.

### 3. WireGuard peers have broad VLAN10 and VLAN30 access by fall-through

Severity: medium. Confidence: high.

The peers have explicit narrow permits to VLAN20 and VLAN60, and guest access is
denied, but no rule accepts or denies WireGuard traffic to VLAN10 or VLAN30.
Because the forward chain has no unconditional final drop, both peers can reach
both zones on arbitrary ports (`__latest.rsc:281-334`).

Target control: create an explicit per-peer destination/port policy bound to
`wireguard1`, then deny every unmatched forward. The local stage-1 draft assumes
both current peers may reach selected VLAN10 services and must not reach VLAN30;
that is a proposed policy, not a fact established by the export.

### 4. MAC management is exposed through the broad bridge

Severity: medium. Confidence: high.

ether3 through ether6 are enabled bridge access ports with default behavior
(`__latest.rsc:94-97`). The bridge belongs to `LAN` (`__latest.rsc:121`), and
MAC-Telnet plus MAC-WinBox are allowed on `LAN` (`__latest.rsc:430-433`). This
creates an IP-firewall-independent management surface from adjacent Layer-2
segments and potentially from physically accessible unused ports.

Target control: after live port inventory, disable unused ports or place them in
VLAN99; disable MAC management during normal operation or bind it only to one
explicit recovery port.

### 5. CAPsMAN does not authenticate CAP peers

Severity: medium. Confidence: medium.

CAPsMAN is enabled with `require-peer-certificate=no` and both band-wide rules
use `create-dynamic-enabled` without a CAP identity selector
(`__latest.rsc:129-140`). A compatible device that can reach the CAPsMAN control
plane may be enrolled and provisioned. Reachability from an untrusted zone is
not proven by the export, which limits confidence and severity.

Target control: enroll and test CAP/CAPsMAN certificates, restrict the intended
CAP identity/radios, then require peer certificates. This is deliberately not
encoded in an import draft because certificate deployment and AP reconnection
must be proven live first.

### 6. Neighbor discovery is broader than the management plane

Severity: low. Confidence: high.

Discovery and detailed LLDP metadata are enabled on `LAN`, which includes the
whole primary bridge (`__latest.rsc:104-106,121`). This exposes useful topology
and VLAN metadata to adjacent non-management devices.

Target control: disable discovery or bind it to a purpose-built list containing
only the deliberate management/recovery interface.

## Important architecture gaps (hardening, not separately proven exploits)

- The IPv4 forward chain has no unconditional final deny. Today's known zones
  have substantial specific controls, but a future interface/subnet can fall
  through to acceptance. This should be corrected only after the complete
  reachability matrix is tested.
- The broad `allow WireGuard traffic` input rule trusts `192.168.90.0/24` without
  requiring `wireguard1` and without limiting services. Replace it with exact
  peer `/32`, interface-bound permits.
- SNMP is configured as authentication-only (`security=authorized`) with SHA-1.
  The current VLAN60 input policy appears to block UDP/161, so first determine
  whether polling is intentionally broken. If enabled, use `security=private`
  with modern credentials and retain the `/32` source restriction.
- IPv6 policy cannot be concluded from this export. It contains generic IPv6
  firewall rules but no exported IPv6 address/route/RA state proving that the
  RB5009 routes the observed ULA. Live discovery remains mandatory.
- SMB has a stale named user, but the export does not prove an enabled listener.
  Verify the singleton `/ip smb` state before deleting anything.
- Live inventory confirmed an enabled RouterOS reverse-proxy service on TCP/443
  with no proxy mappings and no service certificate, while `www-ssl` is disabled.
  Disable the unused listener in the management stage unless a mapping is added
  deliberately.
- Disabled legacy DST-NAT and RAW `notrack` rules are not active findings, but
  should be removed later if confirmed obsolete.

## Local artifact hygiene observed without reading file contents

- `pw.txt` is mode `0644`, despite the handoff treating it as sensitive. Change
  it to `0600` before using it again; its contents were not read.
- `hermes-backup-2026-08-19-211704.zip` is also mode `0644`. Its contents were
  not inspected, so classify it and restrict it to `0600` if it contains backup
  credentials, kubeconfigs, keys, or other private state.
- `__latest.rsc` is already mode `0600`, and `support/` is mode `0700`.

## Local implementation drafts

None of these files has been executed:

- `_rb5009_hardening_read_only_inventory.rsc`: read-only evidence collection.
- `_rb5009_hardening_stage1_ipv4.rsc`: draft WireGuard-bound admin policy,
  explicit VLAN10 router services, and final IPv4 input/forward denies.
- `_rb5009_hardening_stage1_ipv4_audit.rsc`: read-only post-stage counters.
- `_rb5009_hardening_stage1_ipv4_rollback.rsc`: exact stage-1 rollback.
- `_rb5009_hardening_stage2_management.rsc`: draft `/ip service` source limits,
  stronger SSH crypto, and disabled MAC management/discovery.
- `_rb5009_hardening_stage2_management_rollback.rsc`: stage-2 rollback.

Stage 1 deliberately assumes both WireGuard peers need full-tunnel Internet,
management TCP `22,80,443,8006,8291`, server TCP `22,80,443,6443`, and VLAN10
TCP `22,80,443` plus ICMP. Those assumptions must be edited to the real
reachability matrix before any import. It permits authenticated WireGuard
handshakes from WAN and from VLAN30 because live evidence showed the Pixel's
local tunnel enters on `vlan30-trusted`; tunnel traffic remains authenticated
and separately authorized. Stage 2 deliberately removes the normal
MAC recovery path and therefore requires an independent recovery method.

## Required live evidence before approving any mutation

1. Both WireGuard peers show recent handshakes and can reconnect after a test
   disconnect.
2. Exact services needed from each WireGuard peer are recorded; do not assume
   both devices require identical privileges.
3. VLAN10 DHCP, DNS, ICMP, update, and management requirements are measured.
4. Dynamic bridge VLAN rows and physical use/link state of ether3-ether6 are
   captured.
5. IPv6 addresses, routes, RAs, neighbors, DNS, interface membership, and rule
   counters are captured from every zone.
6. CAPsMAN remote-CAP identity, certificate state, and reboot/reconnect behavior
   are captured from both the RB5009 and wAP.
7. SNMP polling and firewall counters are observed before changing its security
   level or adding UDP/161.
8. A current binary backup, sanitized export, hashes, and an independent recovery
   path are available.

Live inventory subsequently established that the RB5009 currently has only
link-local IPv6 routes and zero IPv6 forwarding counters. The IPv6 router seen on
VLAN30 is the Apple TV at `192.168.30.107`, so its ULA behavior is an endpoint/
IoT placement question rather than proof of RB5009 inter-VLAN IPv6 routing.

## Suggested order after review

1. Collect read-only evidence and finalize the reachability matrix.
2. Validate WireGuard and remove the VLAN30 address from administrator identity.
3. Introduce explicit IPv4 permits and final denies in Safe Mode.
4. Restrict IP services; then separately remove broad MAC management/discovery.
5. Decide and implement IPv6 policy.
6. Enroll CAP certificates and constrain provisioning.
7. Inventory and quarantine unused ports; explicitly replace residual VLAN1.
8. Harden the CSS326/TL-SG108E trunk only after VLAN10 is modeled end to end.
