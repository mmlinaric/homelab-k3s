# Remaining network-security hardening

Date recorded: 2026-08-24

This is a concise continuation list. The detailed master TODO contains many stale unchecked validation boxes and should not be interpreted as hundreds of separate outstanding jobs.

## Completed

- RB5009 IPv4 input and forwarding now use explicit final-deny rules.
- Administrative authorization was removed from the Fedora VLAN30 address.
- Router administration is restricted to the two authenticated WireGuard peers.
- WireGuard access to the router, VLAN10, VLAN20, VLAN60, and WAN is explicitly documented and filtered.
- RB5009 SSH and WinBox are restricted to `192.168.90.2/32` and `192.168.90.3/32`.
- SSH strong cryptography is enabled.
- The unused reverse-proxy listener and RouterOS SMB server are disabled.
- MAC-Telnet, MAC-WinBox, MAC-Ping, and neighbor discovery are disabled on the RB5009.
- Unused RB5009 interfaces `ether3` through `ether6` are disabled.
- Pre-change and post-change RB5009 recovery checkpoints were created, downloaded, and hashed.
- The wAP CAP certificate is active and CAPsMAN requires authenticated CAP peers. Main and guest Wi-Fi were validated afterward.
- VLAN10 is explicitly modeled across the CSS326-to-TL-SG108E branch: CSS326 ports 1 and 4 are members, TL-SG108E port 1 is tagged, and port 7 is untagged with PVID 10. The NanoKVM HTTP/HTTPS path was validated afterward.
- A dedicated physical recovery path is active on RB5009 `ether3`: router `192.168.254.1/30`, Fedora `192.168.254.2/30`, IP-only SSH/WinBox and ICMP, no bridge membership, and no forwarding. Direct access was validated and documented in `__physical_recovery_port.md`.
- Guest VLAN40 DNS to the RB5009 is allowed over both UDP and TCP port 53; other guest access to the router remains denied.
- The stale one-time `Reconnect PPPoE` scheduler was removed after confirming `interval=0s`, `run-count=0`, and automatic PPPoE reconnection through the client itself.
- The three automatic RouterOS support dumps were submitted privately to
  MikroTik with proof-of-concept reproduction scripts. MikroTik fixed the
  underlying defect in the newest RouterOS release.

## Remaining major workstreams

There are 11 remaining major workstreams:

1. Complete RB5009, wAP, and switch RouterOS, RouterBOOT, and firmware maintenance in separate maintenance windows. The RB5009 window must include the release containing MikroTik's confirmed support-dump fix and a recurrence check.
2. Constrain CAPsMAN provisioning further if needed and perform a separate wAP reboot-persistence test. Certificate authentication is complete.
3. Harden the wAP management plane: IP services, source restrictions, MAC services, discovery, and management addressing.
4. Decide whether IPv6 will be deliberately supported or disabled, then enforce that decision.
5. Inventory and remove unintended VLAN1 participation and secure unused physical ports on both switches.
6. Save fresh post-change CSS326 and TL-SG108E backups. Tagged-only inter-switch configuration and critical-path validation are complete; the future role of TL-SG108E port 4 belongs to the broader VLAN1/physical-port inventory.
7. Harden switch management protocols, source access, credentials, and discovery services.
8. Complete useful centralized security-log retention. SNMP monitoring and Linux time synchronization are operational.
9. Remove confirmed-unused OpenVPN, PPP/IPsec, SMB-user, firewall, NAT, RAW, and address-list leftovers.
10. Improve IoT/media separation and host-level east-west controls on VLAN20 and VLAN60.
11. Run the final validation matrix, create final backups and hashes, and update topology, isolation, recovery, and disaster-recovery documentation.

DNS enforcement is optional and is not counted above.

## Recommended next session

Do not combine these operations into one change window.

1. Complete the separately planned RB5009 RouterBOOT maintenance and validate the network.
2. Upgrade and validate the wAP separately before enforcing CAP certificates, if practical.
3. Follow `__cap_cert.md` from the Pixel using mobile data and WireGuard.
4. After CAP authentication is stable, create a new wAP and RB5009 checkpoint.
5. Continue with a read-only wAP management-service audit before making further changes.

The CAP certificate procedure is recorded in `__cap_cert.md`.
