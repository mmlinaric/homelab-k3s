# Network security hardening handoff and master TODO

Date: 2026-08-23

Status: VLAN30 migration and retirement of the former `192.168.88.0/24` Layer-3 network are complete and validated. The network is operational. Remaining work is primarily security hardening, verification, cleanup, and documentation.

This document supersedes the previous network migration follow-up TODO.

## Operating rules

- [ ] Use RouterOS Safe Mode for every configuration mutation where practical.
- [ ] Make one small, independently reversible change at a time.
- [ ] Perform read-only discovery before every hardening change.
- [ ] Prepare an explicit rollback before applying changes.
- [ ] Validate both the intended change and unrelated critical paths before committing.
- [ ] Do not combine RouterOS upgrades, VLAN changes, firewall redesign, CAPsMAN changes, and switch trunk changes in one maintenance window.
- [ ] Maintain an independent recovery path before changing Wi-Fi, VLAN20, CAPsMAN, trunks, or firewall rules.
- [x] Use WireGuard or the validated dedicated RB5009 `ether3` IP recovery port as the independent recovery path.
- [ ] Prefix newly generated migration and maintenance files with `_`.
- [ ] Preserve existing user files and unrelated working-tree changes.
- [ ] Never read, display, log, or otherwise expose `pw.txt`. If it must temporarily be used with a tool such as `sshpass -f pw.txt`, pass it as a file only.
- [ ] Prefer eliminating password automation in favor of key/certificate-based SSH administration where practical.
- [ ] Store unencrypted RouterOS binary backups and `.rif` support files as sensitive material.

## Current baseline

### Router and AP

- RB5009: RouterOS `7.24`.
- wAP ax: RouterOS `7.21.2`.
- RB5009 is the Layer-3 gateway/firewall.
- CSS326, TL-SG108E, and wAP ax primarily provide Layer-2 transport.
- Inter-VLAN IPv4 traffic routes through the RB5009.

### VLANs

- VLAN10: `192.168.10.0/24` - OOB/KVM.
- VLAN20: `192.168.20.0/24` - infrastructure management.
- VLAN30: `192.168.30.0/24` - trusted endpoints/main Wi-Fi.
- VLAN40: `192.168.40.0/24` - guest Wi-Fi.
- VLAN60: `192.168.60.0/24` - servers/Kubernetes.
- VLAN90: `192.168.90.0/24` - WireGuard.
- VLAN99: reserved quarantine VLAN.
- VLAN100: ISP PPPoE.
- VLAN101: ISP VoIP.

The former `192.168.88.0/24` Layer-3 network has been removed.

### Important addresses

VLAN20:

- RB5009: `192.168.20.1`
- CSS326: `192.168.20.2`
- TL-SG108E: `192.168.20.3`
- PVE1: `192.168.20.10`
- PVE2: `192.168.20.11`
- wAP ax: `192.168.20.20`

VLAN30:

- Fedora admin workstation: `192.168.30.43`
- HP printer: `192.168.30.123`
- Apple TV most recently: `192.168.30.107`

VLAN60 examples:

- K3s node: `192.168.60.10`
- VIP: `192.168.60.5`
- ingress VIP: `192.168.60.100`

WireGuard:

- Pixel: `192.168.90.2`
- ThinkPad: `192.168.90.3`

### Important topology

- RB5009 ether2 -> CSS326 port 1.
- RB5009 ether8 -> wAP ax ether1.
- CSS326 port 4 -> TL-SG108E port 1.
- CSS326 port 6 -> PVE1.
- TL-SG108E port 6 -> PVE2.
- Wired workstation uses VLAN30 through TL-SG108E.
- Main Wi-Fi uses VLAN30.
- Guest Wi-Fi uses VLAN40.
- wAP management and CAPsMAN control use VLAN20.

### Current CSS326 state that must not be broken

Explicit VLAN memberships:

- VLAN20: ports `1,4,6`
- VLAN30: ports `1,4,8`
- VLAN60: ports `1,4,6`

CSS326 port 4 now uses:

- VLAN Mode: `strict`
- VLAN Receive: `only tagged`
- Default VLAN ID: `1`
- Force VLAN ID: disabled

VLAN10 is explicitly modeled across this path: CSS326 ports 1 and 4 are VLAN10 members, TL-SG108E port 1 carries VLAN10 tagged, and TL-SG108E port 7 carries VLAN10 untagged with PVID 10.

TL-SG108E port 1 is not a VLAN 1 member and carries VLANs 10, 20, 30, and 60 tagged. TL-SG108E port 4 is untagged in VLAN 1 with PVID 1, has no routed service, and has no assigned future role.

A previous removal of port 4 from the VLAN rows took down the entire TL-SG108E branch.

---

# Phase 0: RouterOS failure investigation resolved

## Automatic support dumps

- [x] Leave the network otherwise unchanged long enough to establish that the VLAN30 migration itself is stable.
- [x] Investigate the three automatic RouterOS support dumps:
  - `autosupout.old.rif` generated at 2026-08-23 14:24:28.
  - `autosupout.rif` generated at 2026-08-23 17:50:12.
  - `autosupout.rif` generated at 2026-08-24 21:30:45 while opening an interactive maintenance session; no configuration mutation had been applied.
- [x] Preserve the downloaded copies:
  - `_rb5009_autosupout_2026-08-23_142428.rif`
  - SHA-256 `677bf7b54d60c47f4229f687fcf1284ce328381baa3ebe8ae471f95ee0810c41`
  - `_rb5009_autosupout_2026-08-23_175012.rif`
  - SHA-256 `09b0efb92a06541d5ececc1ab1a5eefbb1a5486814d2fb43f67c86ff0030a533`
  - `_rb5009_autosupout_2026-08-24_213045.rif`
  - SHA-256 `36a0981bc789b7c746d1d07e5dc764c0c79fc0da1ced99dee5c975a06dd6716a`
- [x] Keep the `.rif` files mode `600` inside the mode `700` `support/` directory.
- [x] Submit the files only through a private MikroTik support channel.
- [x] Supply proof-of-concept reproduction scripts and the interactive-session context to MikroTik.
- [x] Determine whether this is a RouterOS defect before performing extensive configuration work.

MikroTik confirmed and fixed the underlying defect in the newest RouterOS
release. The support investigation is closed. Upgrade the RB5009 in its own
maintenance window and verify afterward that automatic support dumps do not
recur.

---

# Phase 1: establish a fresh security baseline and recovery point

## Backups

Existing RB5009 files:

- `_config_final_vlan30_migration.rsc`
  - SHA-256 `6109aa4fab7386d8036da5bebe5ded4177738530fa6b18b50989363ca431d65e`
- `_rb5009_final_vlan30_migration.backup`
  - SHA-256 `06d3c4239d7a88c73d883c75e8765c7c24b197302ff8ae97ab92cfebd85fcd2e`
- `__latest.rsc`
  - sanitized with `/export hide-sensitive`
  - SHA-256 `1149e215820566587fa4aebe5b1d12df940b7cd4a0703b70b0ad962f674f7ba9`
- `_rb5009_pre_physical_recovery_port_20260824.rsc`
  - SHA-256 `f02cdd3a1786435bf8b45b06e62f3dec8e7bc1361ffa3643ae435b063f52f059`
- `_rb5009_pre_physical_recovery_port_20260824.backup`
  - SHA-256 `19bc881785728d2c5f06f88ede45eb2cbc4f45c1f3f692ddcbe13387e07248a2`
- `_rb5009_after_physical_recovery_port_20260824.rsc`
  - SHA-256 `81072120d2c6fbfa67209b808f2e5ae0b3082ff2901cb795416f940431893759`
- `_rb5009_after_physical_recovery_port_20260824.backup`
  - SHA-256 `0abd2735028962ebd5781618e69c0ce8d83c82906a163027158b1795440cfdf6`

- [x] Create a new RB5009 binary backup matching the current post-migration state.
- [x] Create a new sanitized text export at the same checkpoint.
- [x] Download and hash both.
- [x] Confirm mode `600` or equivalent secure local permissions.
- [ ] Preserve at least one earlier known-good backup.

## wAP ax checkpoint

- [ ] Create:
  - `_wap_ax_final_vlan30_migration.rsc`
  - `_wap_ax_final_vlan30_migration.backup`
- [ ] Download them.
- [ ] Calculate SHA-256 hashes.
- [ ] Store the binary backup securely.

## Switch checkpoints

- [ ] Save a fresh CSS326 configuration after port-4 restoration and port-3 retirement.
- [ ] Save a fresh TL-SG108E configuration.
- [ ] Record switch firmware versions.
- [ ] Capture screenshots/exports of VLAN membership, PVID, ingress filtering, and management settings where a machine-readable export is unavailable.

## Read-only inventory

Before hardening:

- [ ] Capture the complete RB5009 bridge VLAN table, including dynamic entries.
- [ ] Capture all bridge-port PVID/frame-type/ingress-filtering state.
- [ ] Inventory all physical switch ports and connected devices.
- [ ] Inventory currently enabled RouterOS services.
- [ ] Inventory MAC services.
- [ ] Inventory neighbor-discovery interfaces.
- [ ] Inventory active VPN profiles/peers/secrets.
- [ ] Inventory IPv6 addresses, routes, RAs, neighbors, and firewall counters.
- [ ] Inventory all current DHCP leases/reservations.
- [ ] Inventory firewall address lists and identify stale networks such as historical `192.168.50.0/24` or `192.168.65.0/24` entries before deleting anything.

---

# Phase 2: convert IPv4 firewall policy to true default-deny

This is the most important firewall architecture change.

The current rules successfully isolate the known VLANs in most cases, but internal forwarding still relies on numerous specific drop rules and eventual rule-chain fall-through.

The desired model is:

1. accept established/related traffic
2. drop invalid traffic
3. allow explicitly approved inter-zone traffic
4. allow explicitly approved Internet access
5. handle WAN/DSTNAT policy
6. drop everything else

## Forward chain

- [ ] Design a complete zone/reachability matrix before changing rules.
- [ ] Explicitly define zones:
  - WAN
  - OOB/KVM
  - management
  - trusted clients
  - guest
  - servers
  - WireGuard administration
  - future IoT/media
- [ ] Move connection-state handling to a predictable position near the beginning of the chain.
- [ ] Ensure `established,related` is accepted early.
- [ ] Ensure `invalid` is dropped early.
- [ ] Preserve required IPsec behavior if still used.
- [ ] Preserve WAN unsolicited-traffic protection.
- [ ] Explicitly permit only required admin -> infrastructure ports.
- [ ] Explicitly permit only required admin -> server ports.
- [ ] Explicitly permit trusted -> ingress VIP TCP 80/443.
- [ ] Explicitly permit each zone that requires Internet access.
- [ ] Add an explicit final forward-chain drop.
- [ ] Verify that creation of a future VLAN automatically results in no access until an allow rule is deliberately added.
- [ ] Keep broad FastTrack disabled until its interaction with isolation and visibility has been deliberately reviewed.
- [ ] Keep broad LAN-to-LAN RAW `notrack` disabled.

## Input chain

Apply the same principle to traffic terminating on the RB5009:

- [ ] Define exactly which zones may reach which router services.
- [ ] Explicitly allow required DHCP/DNS/ICMP per VLAN.
- [ ] Explicitly allow management services only from authenticated administration paths.
- [ ] Replace reliance on membership in a broad `LAN` interface list with deliberate input policy.
- [ ] Add a final input-chain drop after all necessary exceptions.
- [ ] Validate WireGuard handshake traffic from WAN separately from traffic coming through the WireGuard tunnel.

## Validation

For every source zone test:

- [ ] Internet.
- [ ] Router DNS.
- [ ] Router management.
- [ ] VLAN10.
- [ ] VLAN20.
- [ ] VLAN30.
- [ ] VLAN40.
- [ ] VLAN60.
- [ ] WireGuard.
- [ ] Expected denied ports.
- [ ] Expected permitted ports.
- [ ] Established return traffic.
- [ ] Firewall counters for every expected path.

---

# Phase 3: stop treating a VLAN30 IPv4 address as an administrator identity

Fedora `192.168.30.43` is currently in `HOST-ADMIN`.

A DHCP reservation does not authenticate ownership of an address. A compromised device with Layer-2 access to VLAN30 may potentially impersonate or interfere with that IPv4 identity.

Preferred design: administrative authorization should derive from an authenticated tunnel/device identity rather than from a normal endpoint VLAN address.

- [ ] Confirm WireGuard administration works reliably from the ThinkPad.
- [ ] Confirm WireGuard administration works reliably from the Pixel.
- [ ] Decide whether all privileged administration can be performed through WireGuard even while at home.
- [ ] If yes, remove `192.168.30.43` from `HOST-ADMIN`.
- [ ] Keep the Fedora DHCP reservation if useful for ordinary networking, but do not use it as an authorization credential.
- [ ] Express admin rules using the WireGuard interface and/or exact peer `/32` addresses.
- [ ] Ensure only the intended WireGuard peers are in the administrative source list.
- [ ] Test loss/reconnection behavior so local administration remains practical.
- [ ] Maintain a separate physical emergency/recovery method.

Alternative longer-term option:

- [ ] Consider a dedicated admin-device VLAN if WireGuard-for-local-admin becomes undesirable.

---

# Phase 4: harden the RB5009 management plane and VLAN10

## VLAN10 OOB/KVM

VLAN10 should not have broad access to the router simply because it is considered `LAN`.

- [ ] Inventory exactly what KVM/OOB devices require from the RB5009.
- [ ] Allow only required DHCP/DNS/ICMP if necessary.
- [ ] Block other VLAN10 -> router input.
- [ ] Do not allow OOB devices to administer the RB5009 unless explicitly required.
- [ ] Preserve admin -> VLAN10 access from the authenticated administration path.
- [ ] Keep VLAN10 -> Internet blocked unless a justified update/download requirement exists.
- [ ] Keep VLAN10 -> other internal networks blocked by default.

## MAC management

- [ ] Determine whether MAC-Telnet is needed.
- [ ] Determine whether MAC-WinBox is needed.
- [ ] Determine whether MAC-Ping is needed.
- [ ] Prefer disabling all three during normal operation.
- [ ] If a MAC recovery path is retained, constrain it to one explicitly trusted recovery interface rather than the general `LAN` interface list.
- [ ] Document how to deliberately enable the recovery path if needed.

## Neighbor discovery

- [ ] Audit LLDP/MNDP/CDP discovery scope.
- [ ] Limit discovery to interfaces where topology disclosure is intentional.
- [ ] Prefer management-only discovery rather than broad endpoint-facing discovery.

## Router services

Audit:

- SSH
- HTTPS/WebFig
- WinBox
- FTP
- Telnet
- HTTP
- API
- API-SSL
- SMB
- bandwidth server
- any other RouterOS management/listening service

- [ ] Leave FTP disabled.
- [ ] Leave Telnet disabled.
- [ ] Leave plain HTTP disabled.
- [ ] Leave API disabled unless genuinely required.
- [ ] Leave API-SSL disabled unless genuinely required.
- [ ] Verify SMB server state.
- [ ] If SMB is unused, disable it and remove stale SMB users such as `mario`.
- [ ] Keep bandwidth server disabled.
- [ ] Restrict SSH/WebFig/WinBox to authenticated administration sources.
- [ ] Use `/ip service address=` restrictions as defense in depth where practical.
- [ ] Enable stronger SSH crypto settings where compatible.
- [ ] Verify HTTPS uses the intended certificate.

---

# Phase 5: identify and secure remaining VLAN1 Layer-2 behavior

The old `192.168.88.0/24` Layer-3 network is gone, but this does not automatically mean VLAN1 no longer exists anywhere at Layer 2.

## RB5009

- [ ] Inspect dynamic bridge VLAN entries.
- [ ] Determine whether ether3, ether4, ether5, ether6, or the bridge CPU are dynamically participating in untagged VLAN1 because of default PVID behavior.
- [ ] Inventory whether ether3-ether6 are currently used.
- [ ] Disable unused physical ports.
- [ ] For used ports, configure explicit intended PVID/frame-type behavior.
- [ ] Avoid leaving future access ports implicitly on VLAN1.
- [ ] Ensure the bridge CPU is not unintentionally reachable from a residual VLAN1 segment.
- [ ] Retest MAC management after VLAN1 changes.

## Switches

- [ ] Inventory all remaining VLAN1 members on CSS326.
- [ ] Inventory all remaining VLAN1 members on TL-SG108E.
- [ ] Identify whether any device or trunk genuinely relies on native VLAN1.
- [ ] Do not blindly delete VLAN1 before all dependencies are understood.
- [ ] Move unused switch ports to VLAN99 or disable them.
- [ ] Remove unnecessary VLAN1 participation after explicit VLAN configuration has replaced it.

---

# Phase 6: audit and deliberately configure IPv6

IPv6 must be treated as an independent security policy.

Fedora has observed a ULA IPv6 address on VLAN30, so IPv6 is active somewhere in the environment.

## Discovery

- [ ] Identify the source of router advertisements.
- [ ] Identify all advertised prefixes.
- [ ] Identify whether the RB5009 is routing IPv6 between VLANs.
- [ ] Determine whether clients have IPv6 Internet connectivity.
- [ ] Determine whether IPv6 DNS servers are advertised.
- [ ] Determine whether any VPN carries IPv6.
- [ ] Inspect IPv6 routes.
- [ ] Inspect IPv6 neighbors.
- [ ] Inspect IPv6 firewall counters.
- [ ] Inspect all relevant interface-list membership.

## Decision

Choose one:

- [ ] Deliberately support IPv6 and implement equivalent zone isolation.

or

- [ ] Deliberately disable IPv6/RA behavior until it is ready to be designed.

Do not leave IPv6 in an accidental partially working state.

## If IPv6 remains enabled

- [ ] Reproduce the IPv4 zone/reachability policy in IPv6.
- [ ] Keep required ICMPv6 functionality.
- [ ] Explicitly control router input.
- [ ] Explicitly control inter-VLAN forwarding.
- [ ] Explicitly control guest access.
- [ ] Explicitly control server access.
- [ ] Explicitly control VPN access.
- [ ] Add deliberate final-drop behavior.
- [ ] Validate IPv4 and IPv6 independently.

---

# Phase 7: harden CAPsMAN and wAP ax

## CAPsMAN

Current operation correctly uses VLAN20 for AP management/control, but CAP authentication and listener scope should be hardened.

- [ ] Restrict CAPsMAN control/listening to the intended VLAN20 management interface where supported.
- [x] Enable authenticated CAP/certificate validation.
- [x] Set `require-peer-certificate=yes` after certificates have been deployed and tested.
- [x] Ensure the wAP trusts/connects only to the intended CAPsMAN.
- [ ] Restrict provisioning rules so an arbitrary compatible CAP cannot automatically become trusted infrastructure.
- [ ] Test CAP reconnection after RB5009 reboot.
- [ ] Test CAP reconnection after wAP reboot.
- [ ] Verify VLAN30 and VLAN40 client datapaths remain local and correctly tagged.

## wAP management

Audit:

- `/ip service`
- MAC server
- MAC WinBox
- neighbor discovery
- SSH
- WinBox
- HTTP/HTTPS
- API/API-SSL
- Telnet/FTP
- CAP settings
- bridge VLAN state

- [ ] Disable unused management services.
- [ ] Restrict SSH/WinBox to the intended management/admin sources.
- [ ] Disable or tightly restrict MAC management.
- [ ] Restrict neighbor discovery.
- [ ] Ensure the AP does not regain a DHCP/default-VLAN fallback.
- [ ] Ensure `192.168.20.20` remains its sole intended management address.

Perform this separately from an AP RouterOS upgrade.

---

# Phase 8: explicitly model and harden the CSS326 <-> TL-SG108E trunk

This change has a proven large failure domain.

## Discovery first

- [ ] Back up both switches.
- [ ] Inventory every device downstream of TL-SG108E.
- [x] Verify VLAN10 current behavior and NanoKVM HTTP/HTTPS reachability after adding the explicit CSS326 VLAN10 row.
- [x] Verify VLAN20 current behavior.
- [x] Verify VLAN30 current behavior and Internet/DNS access.
- [x] Verify VLAN60 current behavior.
- [x] Determine the intended tagged/untagged behavior in both directions.
- [x] Confirm the dedicated RB5009 `ether3` recovery path.

## VLAN10

- [x] Add explicit VLAN10 membership on CSS326 ports 1 and 4.
- [x] Verify explicit VLAN10 handling on the TL-SG108E: port 1 tagged and port 7 untagged with PVID 10.
- [x] Verify the VLAN10 endpoint before changing trunk admission.

## Trunk hardening

After explicit modeling:

- [x] Configure CSS326 port 4 as `strict` and `only tagged`.
- [x] Remove TL-SG108E port 1 from VLAN 1 while retaining tagged VLANs 10, 20, 30, and 60.
- [x] Remove native VLAN1 behavior from the inter-switch link.
- [x] Enable the strongest available ingress filtering/strict VLAN handling on CSS326 port 4.
- [x] Verify VLAN20.
- [x] Verify VLAN30 Internet and DNS behavior.
- [x] Verify VLAN60.
- [x] Verify VLAN10 and NanoKVM HTTP/HTTPS.
- [x] Verify switch management.
- [x] Verify PVE2.
- [x] Verify the wired workstation receives VLAN30 address `192.168.30.104` and reaches the Internet.
- [x] Verify current trunk membership and strict CSS326 admission expose only VLANs 10, 20, 30, and 60 across the inter-switch link.

---

# Phase 9: harden switch management

CSS326 and TL-SG108E management currently lives appropriately on VLAN20, but the management protocols themselves should be audited.

- [ ] Inventory all enabled switch management protocols.
- [ ] Determine whether HTTPS is supported.
- [ ] Use HTTPS instead of HTTP if supported and reasonably secure.
- [ ] If a device only supports HTTP, document that limitation.
- [ ] In that case, ensure the device remains reachable only through the isolated management network.
- [ ] Do not expose switch management to normal VLAN30 clients.
- [ ] Do not expose switch management to guests or servers.
- [ ] Change default/admin credentials where applicable.
- [ ] Use unique credentials per infrastructure device.
- [ ] Disable unused discovery/management protocols where supported.
- [ ] Check for available management ACL/source restrictions.
- [ ] Back up configuration after hardening.

---

# Phase 10: resolve VLAN20 -> VLAN60 administrative policy

Current firewall ordering means a future `HOST-ADMIN` host physically located inside VLAN20 can be blocked by the VLAN20 private-network deny before reaching the later server-admin rules.

Make an explicit policy decision.

## Option A: administration is WireGuard-only

Preferred if Phase 3 is adopted.

- [ ] Do not put normal administrative workstations in VLAN20.
- [ ] Preserve VLAN20 infrastructure -> private-network denial.
- [ ] Document that VLAN20 is a management-device network, not an admin-workstation network.
- [ ] Remove any misleading expectation that a VLAN20 `HOST-ADMIN` host should manage servers.

## Option B: VLAN20 admin workstations are required

- [ ] Place narrowly scoped `HOST-ADMIN` -> VLAN60 permits before the VLAN20 private-network drop.
- [ ] Allow only required ports.
- [ ] Validate rule counters.
- [ ] Verify non-admin VLAN20 devices remain unable to initiate connections into VLAN60.

---

# Phase 11: audit and restrict WireGuard

WireGuard is the preferred authenticated administration path, but its forwarding/input scope should be explicit.

## Peer testing

- [ ] Validate a fresh Pixel handshake.
- [ ] Validate a fresh ThinkPad handshake.
- [ ] Confirm bidirectional traffic.
- [ ] Confirm router management.
- [ ] Confirm infrastructure management.
- [ ] Confirm server administration.
- [ ] Confirm guest VLAN remains inaccessible.
- [ ] Test all other routed subnets.

## Least privilege

- [ ] Replace broad router-input acceptance from `192.168.90.0/24` with only required router services.
- [ ] Restrict privileged rules to actual admin peer `/32` addresses.
- [ ] Add explicit WireGuard inter-zone policy.
- [ ] Ensure unmatched WireGuard forwarding hits the final default-deny.
- [ ] Decide whether VPN clients should reach VLAN30 at all.
- [ ] Decide whether VPN clients should reach VLAN10.
- [ ] Decide whether VPN clients should reach only selected VLAN20/VLAN60 services.
- [ ] Document allowed reachability per peer.

## Peer lifecycle

- [ ] Remove old/unused peers.
- [ ] Rotate keys if a device is lost or decommissioned.
- [ ] Keep private keys only on their intended endpoint.
- [ ] Maintain names/comments mapping each public key to its device.

---

# Phase 12: improve endpoint and IoT/media segmentation

VLAN30 currently contains trusted personal endpoints plus devices such as the printer and Apple TV.

Traffic between devices in the same VLAN does not traverse the RB5009 Layer-3 firewall.

Longer-term:

- [ ] Inventory every VLAN30 device.
- [ ] Classify each as:
  - personal trusted endpoint
  - administrative endpoint
  - printer
  - media/TV
  - IoT
  - family/unmanaged
- [ ] Keep personal computers/phones on the trusted-client VLAN.
- [ ] Move printers, TVs, and similar less-trusted devices to a separate IoT/media network where practical.
- [ ] Do not automatically reuse historical VLAN50/VLAN65 numbering until their stale references have been inventoried.
- [ ] Permit IoT/media -> Internet only as needed.
- [ ] Block IoT/media -> management.
- [ ] Block IoT/media -> servers unless explicitly required.
- [ ] Permit trusted -> printer/media services selectively.
- [ ] Introduce mDNS reflection only if actual service discovery requires it.
- [ ] Avoid broad inter-VLAN multicast forwarding.

This is useful hardening, but lower priority than fixing administrative identity and default-deny behavior.

---

# Phase 13: SNMP, monitoring, logging, and visibility

## SNMP

Current Checkmk SNMP configuration should be verified end to end.

- [ ] Confirm whether Checkmk at `192.168.60.104` can currently poll the RB5009.
- [ ] Inspect firewall counters while polling.
- [ ] If required, add a narrowly scoped UDP/161 input allow from `192.168.60.104/32` before the VLAN60 router-input drop.
- [ ] Change SNMPv3 security from authentication-only to authenticated + encrypted privacy if supported by the monitoring client.
- [ ] Prefer `authPriv`/RouterOS `security=private`.
- [ ] Keep the SNMP source restricted to the exact monitoring host.
- [ ] Remove the default SNMP community if not already disabled.
- [ ] Use unique strong SNMPv3 credentials.

## Central logging

- [ ] Decide on a central syslog/security-log destination.
- [ ] Send important RB5009 logs remotely.
- [ ] Send important wAP logs remotely if useful.
- [ ] Capture:
  - login/authentication failures
  - account changes
  - critical/system errors
  - configuration-relevant warnings
  - interface failures
  - VPN events
  - selected firewall drops
- [ ] Avoid logging every denied Internet packet and creating unusable log volume.
- [ ] Add log prefixes to important security-deny rules where useful.
- [ ] Monitor repeated failed management logins.
- [ ] Monitor WireGuard availability.
- [ ] Monitor unexpected interface/VLAN state changes.

## Time

- [ ] Verify RB5009 time synchronization.
- [ ] Verify wAP time synchronization.
- [ ] Verify switches/servers use consistent time sources where possible.
- [ ] Ensure centralized logs have useful, comparable timestamps.

---

# Phase 14: clean up legacy VPN and unused services

## OpenVPN

An OpenVPN server/profile/secret remains configured.

- [ ] Determine whether OpenVPN is still used.
- [ ] If unused, disable the OpenVPN server.
- [ ] Remove stale OpenVPN PPP secrets only after confirming no dependency.
- [ ] Remove stale profiles only after confirming no dependency.
- [ ] If OpenVPN remains necessary, review its algorithms and configure the strongest mutually supported modern options.
- [ ] Confirm it is not unintentionally reachable from untrusted interfaces.

## PPP/IPsec leftovers

- [ ] Inventory old PPP profiles such as former phone VPN profiles.
- [ ] Inventory unused IPsec proposals/configuration.
- [ ] Remove stale configuration only after determining it is not supporting an active service.

## SMB/storage

- [ ] Verify whether RouterOS SMB is actually used.
- [ ] Disable SMB if not needed.
- [ ] Delete unused SMB users if SMB is disabled.
- [ ] Confirm no USB/storage sharing service is exposed unintentionally.

---

# Phase 15: host-level and east-west security

VLAN isolation does not protect devices from other devices inside the same VLAN.

## VLAN20

A compromise of a management-plane device may expose other VLAN20 devices directly.

- [ ] Restrict Proxmox management services with host firewall rules.
- [ ] Allow Proxmox 8006 only from intended admin sources.
- [ ] Allow Proxmox SSH only from intended admin sources.
- [ ] Restrict switch/AP management at the devices themselves where possible.
- [ ] Avoid treating VLAN20 membership alone as sufficient authorization.

## VLAN60

- [ ] Enable/verify host firewalls on servers.
- [ ] Restrict SSH to administrative sources.
- [ ] Restrict Kubernetes API `6443` to intended administration sources.
- [ ] Restrict kubelet and other cluster management ports.
- [ ] Review whether server-to-server communication is broader than necessary.
- [ ] Introduce Kubernetes NetworkPolicies for workloads where useful.
- [ ] Avoid creating one VLAN per server unless a real risk justifies the complexity.

---

# Phase 16: DNS policy review

Current router DNS using Cloudflare Security DoH with certificate verification is a useful baseline.

- [ ] Keep router DoH certificate verification enabled.
- [ ] Decide whether the goal is merely to offer filtered DNS or actually enforce it.
- [ ] If enforcement is desired, determine how normal UDP/TCP DNS to external resolvers should be handled.
- [ ] Decide separately whether to block/limit DoT.
- [ ] Recognize that arbitrary external DoH cannot be reliably blocked without substantially more invasive controls.
- [ ] Do not introduce complex DNS interception unless there is a clear security requirement.

This is optional and should not delay the higher-priority segmentation work.

---

# Phase 17: software and firmware maintenance

Keep updates separate from configuration/security migrations.

## RB5009

- [ ] Check current RouterOS stable release at maintenance time.
- [ ] Check release notes.
- [ ] Check relevant MikroTik security advisories.
- [ ] Verify RouterBOOT version.
- [ ] Upgrade RouterBOOT if appropriate after RouterOS upgrade.
- [ ] Reboot only in a defined maintenance window.
- [ ] Validate the full network afterward.

## wAP ax

- [ ] Check current stable RouterOS release.
- [ ] Check Wi-Fi/CAPsMAN compatibility with RB5009.
- [ ] Back up first.
- [ ] Upgrade independently from CAPsMAN hardening.
- [ ] Validate CAPsMAN, VLAN20 management, VLAN30 Wi-Fi, and VLAN40 Wi-Fi afterward.

## Switches

- [ ] Check CSS326 firmware.
- [ ] Check TL-SG108E firmware.
- [ ] Review changelogs/security fixes.
- [ ] Back up first.
- [ ] Upgrade separately from trunk/VLAN changes.

---

# Phase 18: physical-port and quarantine policy

- [ ] Inventory every RB5009 Ethernet port.
- [ ] Inventory every CSS326 port.
- [ ] Inventory every TL-SG108E port.
- [ ] Disable physically unused ports where practical.
- [ ] Alternatively place unused switch access ports into VLAN99 with no useful network access.
- [ ] Avoid leaving unused ports in VLAN1.
- [ ] Explicitly configure each active access port's PVID.
- [ ] Explicitly configure each active trunk's allowed VLANs.
- [ ] Label/document port purpose.
- [ ] Periodically compare documented and actual port state.

---

# Phase 19: documentation and housekeeping

- [ ] Preserve migration scripts locally.
- [ ] Preserve hashes for authoritative checkpoints.
- [ ] Delete old files from device storage only after local copies and hashes are confirmed.
- [ ] Keep sensitive binary backups separate from sanitized exports.
- [ ] Keep `.rif` support files private.
- [ ] Update the topology diagram after every VLAN change.
- [ ] Update the isolation matrix after every firewall change.
- [ ] Document the intended management path.
- [ ] Document the emergency recovery path.
- [ ] Document which WireGuard peer corresponds to each physical device.
- [ ] Document VLAN purpose and trust level.
- [ ] Document every intentional inter-VLAN exception.
- [ ] Document devices that cannot use encrypted management protocols.
- [ ] Keep a short disaster-recovery procedure for replacing/restoring the RB5009.

---

# Standard validation matrix after major security changes

From the normal trusted client:

- [ ] Internet works.
- [ ] Router DNS works.
- [ ] Router administrative services are denied.
- [ ] VLAN20 management services are denied.
- [ ] VLAN60 administrative services are denied.
- [ ] Ingress VIP 80/443 works.
- [ ] Guest VLAN is unreachable.

From an authenticated admin WireGuard peer:

- [ ] RB5009 SSH/HTTPS/WinBox works as intended.
- [ ] CSS326 management works.
- [ ] TL-SG108E management works.
- [ ] PVE1/PVE2 management works.
- [ ] wAP management works.
- [ ] Approved server SSH/HTTPS works.
- [ ] Kubernetes API works if intended.
- [ ] Unapproved server ports remain denied.
- [ ] Guest VLAN remains denied.
- [ ] VLAN10 behavior matches documented policy.

From guest Wi-Fi:

- [ ] DHCP works.
- [ ] DNS works.
- [ ] Internet works.
- [ ] RB5009 management is denied.
- [ ] VLAN10 is denied.
- [ ] VLAN20 is denied.
- [ ] VLAN30 is denied.
- [ ] VLAN60 is denied.
- [ ] Guest-to-guest communication is denied.

From VLAN60:

- [ ] Internet works.
- [ ] Router DNS works.
- [ ] Router management is denied.
- [ ] VLAN10 is denied.
- [ ] VLAN20 is denied.
- [ ] VLAN30 is denied.
- [ ] Guest is denied.
- [ ] Required monitoring paths work.

From VLAN10:

- [ ] Required local OOB function works.
- [ ] Router management is denied unless explicitly intended.
- [ ] Internet is denied unless explicitly intended.
- [ ] Other private VLANs are denied.

Also validate:

- [ ] CAPsMAN remains connected.
- [ ] Both Wi-Fi SSIDs work.
- [ ] VLAN30 gets correct DHCP.
- [ ] VLAN40 gets correct DHCP.
- [ ] PVE1 remains reachable.
- [ ] PVE2 remains reachable.
- [ ] Wired workstation remains reachable.
- [ ] Switch management remains reachable.
- [ ] VoIP remains functional.
- [ ] PPPoE remains functional.
- [ ] Firewall rule counters match the intended traffic paths.

---

# Recommended execution order

Do not attempt all of this at once.

1. Upgrade and validate the RouterOS release containing MikroTik's confirmed support-dump fix.
2. Create current backups/checkpoints.
3. Perform complete read-only discovery.
4. Validate both WireGuard peers.
5. Design the final IPv4 reachability matrix.
6. Move privileged administration toward WireGuard identities.
7. Convert input/forward firewall behavior to explicit allow + final deny.
8. Restrict VLAN10 router access and disable unnecessary MAC management.
9. Audit/fix IPv6.
10. Harden CAPsMAN and wAP management.
11. Harden the now-explicit VLAN10/CSS326/TL-SG108E trunk.
12. Remove residual VLAN1/unused-port behavior.
13. Harden switch management.
14. Complete central logging; SNMP monitoring is operational.
15. Clean up OpenVPN/SMB/PPP/other stale services.
16. Improve VLAN30 endpoint/IoT separation.
17. Improve host-level VLAN20/VLAN60 east-west security.
18. Perform RouterOS/RouterBOOT/AP/switch software maintenance.
19. Create final recovery checkpoints and update all documentation.

---

# Target end state

The network can be considered fully hardened against the currently identified issues when:

- [ ] Every routed zone uses explicit default-deny policy.
- [ ] Adding a new subnet does not automatically grant it internal access.
- [ ] Administrative privileges are not granted based solely on an ordinary LAN IPv4 address.
- [ ] Administrative access uses authenticated WireGuard/device identities or an equivalent dedicated management path.
- [ ] VLAN10 cannot broadly administer the router.
- [ ] MAC management is disabled or deliberately constrained.
- [x] CAPsMAN accepts only the intended authenticated CAP.
- [ ] IPv6 is either deliberately secured or deliberately disabled.
- [ ] VLAN1 is no longer unintentionally present on active infrastructure paths.
- [ ] Every trunk has explicitly defined VLAN membership.
- [ ] Unused physical ports are disabled or quarantined.
- [ ] Guest devices cannot reach internal networks or one another.
- [ ] IoT/media devices are separated from trusted workstations where practical.
- [ ] Servers cannot initiate arbitrary connections into management/client networks.
- [ ] Infrastructure devices cannot initiate arbitrary connections into unrelated private networks.
- [ ] WireGuard peer reachability is explicitly documented and restricted.
- [ ] Router, AP, hypervisor, switch, and server management services are limited to intended administrative sources.
- [ ] SNMP uses authenticated/encrypted transport where supported.
- [ ] Important security and system events are centrally logged with correct timestamps.
- [ ] Unused OpenVPN, PPP, SMB, API, and management services have been removed or disabled.
- [ ] Current configuration backups exist for RB5009, wAP ax, CSS326, and TL-SG108E.
- [ ] Recovery procedures and the isolation matrix accurately describe the actual network.
