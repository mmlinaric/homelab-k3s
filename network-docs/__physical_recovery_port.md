# RB5009 physical recovery port

Date validated: 2026-08-24

## Design

- RB5009 physical interface: `ether3`
- Router address: `192.168.254.1/30`
- Recovery laptop address: `192.168.254.2/30`
- `ether3` is excluded from the main bridge.
- No default gateway or DNS is provided on the recovery link.
- No forwarding from the recovery interface is allowed.
- Router input permits only ICMP, SSH `22/tcp`, and WinBox `8291/tcp` from `192.168.254.2/32` on `ether3`.
- RouterOS SSH and WinBox source restrictions include only the two WireGuard peers and `192.168.254.2/32`.
- MAC-Telnet, MAC-WinBox, MAC-Ping, and neighbor discovery remain disabled.
- Keep the recovery cable unplugged during normal operation.

## Fedora procedure

Connect the Fedora Ethernet interface directly to RB5009 `ether3`, leaving Wi-Fi connected if desired.

The NetworkManager profile `rb5009-recovery` already exists with autoconnect disabled. Activate it with:

```bash
nmcli connection up rb5009-recovery
```

Validate:

```bash
ping -c 3 192.168.254.1
ssh mario@192.168.254.1
nc -zv 192.168.254.1 8291
```

WinBox should connect to `192.168.254.1` by IP.

After recovery work:

```bash
nmcli connection down rb5009-recovery
```

Unplug the direct recovery cable. The profile does not install a default route and does not autoconnect.

## RouterOS maintenance files

- Apply: `_rb5009_enable_physical_recovery_port.rsc`
- Audit: `_rb5009_enable_physical_recovery_port_audit.rsc`
- Rollback: `_rb5009_enable_physical_recovery_port_rollback.rsc`

## Validation evidence

The direct Fedora-to-RB5009 connection successfully passed ICMP, TCP/22, TCP/8291, and an authenticated SSH login. PPPoE, CAPsMAN, CSS326, TL-SG108E, VLAN10, and NanoKVM reachability were validated afterward.
