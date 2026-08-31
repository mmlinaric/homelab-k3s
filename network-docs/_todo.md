# Network migration handoff and follow-up TODO

Date: 2026-08-23<br>
Status: VLAN30 migration and legacy VLAN1 retirement are complete and validated.

## Important operating notes

- The RB5009 runs RouterOS 7.24.
- The wAP ax runs RouterOS 7.21.2.
- Use Safe Mode for every RouterOS mutation and validate before committing.
- Make one small, independently reversible change at a time.
- Prefix newly generated migration or maintenance files with `_`.
- Fedora currently administers the network over the main Wi-Fi from `192.168.30.43`.
- CSS326 port 3, formerly the temporary wired recovery port, is disabled and no longer a VLAN20 member.
- The RB5009 login is `mario`; `pw.txt` can be passed directly to tools such as `sshpass -f pw.txt` but must never be read or displayed.
- The wAP ax uses the `admin` account with a separate password entered interactively by the user.
- Preserve existing user files and unrelated working-tree changes.

## Completed network state

- Main Wi-Fi `WFJW2PS6A` uses VLAN30 on both 2.4 GHz and 5 GHz.
- Guest Wi-Fi `WFJW2PS6G` remains on VLAN40.
- VLAN30 gateway and DNS: `192.168.30.1`.
- Fedora has a static DHCP reservation at `192.168.30.43` and is in `HOST-ADMIN`.
- HP printer has a static DHCP reservation at `192.168.30.123`.
- Apple TV was migrated to VLAN30 and most recently used `192.168.30.107`.
- Wired workstation `DESKTOP-P6QVR8P` uses VLAN30 through the TL-SG108E.
- wAP ax management is static `192.168.20.20/24` on `vlan20-mgmt`.
- wAP ax default route and DNS use `192.168.20.1`.
- CAPsMAN discovery/control uses `vlan20-mgmt`.
- The AP's legacy `bridgeLocal` DHCP client and `192.168.88.253` fallback were removed.
- RB5009 legacy `192.168.88.0/24` gateway, DHCP server/network/pool/lease, address-list entries, and firewall reference were deleted.
- RB5009 ether2 (CSS326 trunk) and ether8 (wAP ax trunk) use `frame-types=admit-only-vlan-tagged` with ingress filtering enabled.
- Broad RAW LAN-to-LAN notrack and broad FastTrack remain disabled.
- VLAN isolation rules remain enabled.
- CSS326 port 3 was removed from VLAN20 and disabled after Wi-Fi administration was validated.

## Relevant topology and addresses

- RB5009 ether2 -> CSS326 port 1.
- RB5009 ether8 -> wAP ax ether1.
- CSS326 port 4 -> TL-SG108E port 1.
- CSS326 port 6 -> PVE1.
- TL-SG108E port 6 -> PVE2.
- VLAN20 management:
  - RB5009: `192.168.20.1`
  - CSS326: `192.168.20.2`
  - TL-SG108E: `192.168.20.3`
  - PVE1: `192.168.20.10`
  - PVE2: `192.168.20.11`
  - wAP ax: `192.168.20.20`
- VLAN60 examples:
  - K3s node: `192.168.60.10`
  - VIP: `192.168.60.5`
  - ingress VIP: `192.168.60.100`

## CSS326 state that must be preserved

An accidental removal of CSS326 port 4 from the VLAN rows took down the entire TL-SG108E branch. It was restored and fully validated.

Current explicit CSS326 VLAN membership:

- VLAN20: ports `1,4,6`
- VLAN30: ports `1,4,8`
- VLAN60: ports `1,4,6`

CSS326 port 4 now uses:

- VLAN Mode: `strict`
- VLAN Receive: `only tagged`
- Default VLAN ID: `1`
- Force VLAN ID: unchecked

VLAN10 is explicitly modeled across the hardened tagged-only trunk: CSS326 ports 1 and 4 are VLAN10 members, TL-SG108E port 1 is tagged, and port 7 is untagged with PVID 10. TL-SG108E port 1 is not a VLAN1 member. TL-SG108E port 4 is currently untagged in VLAN1 with PVID 1, has no routed service, and has no assigned future role.

## Final validation evidence

From Fedora Wi-Fi `192.168.30.43`, all of these passed:

- RB5009 WinBox at `192.168.30.1:8291`.
- CSS326 HTTP at `192.168.20.2:80`.
- TL-SG108E HTTP at `192.168.20.3:80`.
- PVE1 and PVE2 HTTPS at ports 8006.
- wAP ax SSH at `192.168.20.20:22`.
- Approved server SSH and ingress HTTPS.
- Router DNS and Internet access.
- TCP 10250 to the K3s node timed out as intended.
- CAPsMAN remained connected through VLAN20 and Wi-Fi clients remained registered on VLAN30/VLAN40.

## Recovery checkpoints

Final RB5009 files downloaded locally:

- `_config_final_vlan30_migration.rsc`
  - SHA-256: `6109aa4fab7386d8036da5bebe5ded4177738530fa6b18b50989363ca431d65e`
- `_rb5009_final_vlan30_migration.backup`
  - SHA-256: `06d3c4239d7a88c73d883c75e8765c7c24b197302ff8ae97ab92cfebd85fcd2e`

Current authoritative sanitized RB5009 export:

- `__latest.rsc`
  - generated with `/export hide-sensitive`
  - checked locally for secret-bearing fields; none were detected
  - SHA-256: `1149e215820566587fa4aebe5b1d12df940b7cd4a0703b70b0ad962f674f7ba9`

The binary backup above predates the current sanitized export. Create a new binary
checkpoint in a future maintenance window if a byte-for-byte restoration point for
the present state is desired.

The AP final checkpoint should also be created and downloaded if this has not yet been confirmed:

```routeros
/export hide-sensitive file=_wap_ax_final_vlan30_migration
/system backup save name=_wap_ax_final_vlan30_migration dont-encrypt=yes
```

```bash
scp admin@192.168.20.20:_wap_ax_final_vlan30_migration.rsc .
scp admin@192.168.20.20:_wap_ax_final_vlan30_migration.backup .
sha256sum _wap_ax_final_vlan30_migration.*
```

Binary backups created with `dont-encrypt=yes` contain sensitive configuration and must be stored securely.

## Prioritized optional follow-up

### 0. Resolved — RouterOS automatic support dumps

- The RB5009 generated support dumps at 2026-08-23 14:24:28, 2026-08-23 17:50:12, and 2026-08-24 21:30:45 with `system,error,critical: Automatic supout.rif file generated due to service malfunction`.
- The third event occurred while opening an interactive maintenance session before any recovery-port mutation was applied.
- All three files were downloaded without being opened into the mode-`700` local
  `support/` directory; each file is mode `600`:
  - `support/_rb5009_autosupout_2026-08-23_142428.rif`, SHA-256 `677bf7b54d60c47f4229f687fcf1284ce328381baa3ebe8ae471f95ee0810c41`
  - `support/_rb5009_autosupout_2026-08-23_175012.rif`, SHA-256 `09b0efb92a06541d5ececc1ab1a5eefbb1a5486814d2fb43f67c86ff0030a533`
  - `support/_rb5009_autosupout_2026-08-24_213045.rif`, SHA-256 `36a0981bc789b7c746d1d07e5dc764c0c79fc0da1ced99dee5c975a06dd6716a`
- The sensitive `.rif` files were submitted privately to MikroTik together
  with proof-of-concept reproduction scripts and the interactive-session
  context.
- MikroTik fixed the underlying defect in the newest RouterOS release. The
  remaining action is a dedicated RB5009 upgrade window followed by a check
  that automatic support dumps do not recur.

### 1. Audit IPv6 segmentation

- Fedora received a ULA IPv6 address while connected to VLAN30.
- Confirm that IPv6 forwarding and router-input behavior match the intended VLAN30, VLAN40, VLAN20, and VLAN60 isolation policy.
- Check router advertisements, prefixes, DNS, interface-list membership, and IPv6 firewall counters.
- Do not assume IPv4 firewall rules provide IPv6 isolation.
- Perform read-only discovery first and prepare explicit rollback scripts for any changes.

### 2. Complete validation of the hardened CSS326-to-TL-SG108E trunk

- Inventory the current VLAN10 path and all active/downstream ports first.
- Explicit VLAN10 membership is complete and the NanoKVM HTTP/HTTPS path has been validated.
- Coordinate both ends of CSS326 port 4 <-> TL-SG108E port 1.
- Preserve VLAN20, VLAN30, VLAN60, switch management, PVE2, workstation, and any VLAN10 endpoint.
- Harden only after a wired or WireGuard recovery path is confirmed.
- The prior accidental port-4 membership removal proved that VLAN20/30/60 on this link are all production-critical.

### 3. Harden wAP ax management exposure

- Review `/ip service`, MAC server, MAC WinBox, neighbor discovery, and allowed source interfaces.
- Disable unused Telnet, FTP, HTTP, API, and API-SSL services.
- Restrict SSH/WinBox and MAC management to the intended VLAN20 management path.
- Do not combine service hardening with RouterOS upgrades or radio/CAPsMAN changes.

### 4. Resolve the shadowed VLAN20-to-server admin policy

- `MGMT: block initiating into private networks` currently appears before `SERVERS: admin TCP access`.
- Consequently, a future `HOST-ADMIN` address inside VLAN20 will hit the MGMT drop before the server-admin allow rule.
- Fedora on VLAN30 is unaffected and currently reaches approved server services.
- Decide whether VLAN20 `HOST-ADMIN` devices should administer servers; if yes, move or duplicate narrowly scoped server-admin allows before the MGMT drop and validate counters.

### 5. Test the ThinkPad WireGuard peer

- The Pixel WireGuard peer was previously validated.
- Confirm a recent ThinkPad handshake, bidirectional traffic, router reachability, and only the intended management access.

### 6. Schedule software and firmware maintenance separately

- RB5009 RouterOS is 7.24, but RouterBOOT was previously behind and should be rechecked.
- wAP ax is on RouterOS 7.21.2.
- Check current stable releases and compatibility at maintenance time.
- Upgrades/reboots must be separate from VLAN/firewall changes and followed by complete validation.

### 7. Housekeeping

- Preserve the final local backups and at least one earlier known-good checkpoint.
- Save a fresh CSS326 configuration backup after the corrected port-4 memberships and port-3 retirement.
- Save a fresh TL-SG108E configuration backup.
- Archive migration scripts locally.
- Old scripts/backups may later be removed from device storage only after confirming local copies and hashes.
- Update topology and operating documentation to reflect VLAN30 trusted clients, VLAN20 AP management, tagged-only RB5009 trunks, and retired VLAN1.

## Recommended timing

Leave the network unchanged for at least a day or two and observe normal clients before beginning optional hardening. Start the next session with read-only audits, not mutations.
