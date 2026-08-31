# IPv6 audit and decision

Date: 2026-08-23

## Decision

Pending Route64 tunnel design. Do not disable IPv6 and do not deploy routed IPv6 yet.

The original recommendation was to disable the unused RB5009 IPv6 stack. The owner subsequently identified an existing Route64 WireGuard tunnelbroker allocation. Route64 currently provides a routed `/56`, which can support a proper `/64` for each selected VLAN. Deliberate routed IPv6 is therefore a viable alternative, provided the tunnel and a replacement default-deny IPv6 firewall are deployed and validated together.

## RB5009 evidence

- RouterOS IPv6 is globally enabled and forwarding is enabled.
- The router has only automatic link-local addresses and loopback `::1`.
- There is no global or ULA address assigned to the router.
- There is no IPv6 default route.
- There is no ISP-delegated prefix.
- There is no DHCPv6 client, DHCPv6 server, or IPv6 pool.
- There are no IPv6 DNS servers configured or learned.
- IPv6 fast-path and forwarding counters are zero.
- All IPv6 forward-chain counters are zero.
- The existing IPv6 firewall is the generic RouterOS default policy rather than an IPv6 equivalent of the deliberate IPv4 zone policy.
- The WireGuard peers advertise `::/0` to clients but the RB5009 has no usable IPv6 route, so the tunnel does not currently provide routed IPv6.

## VLAN30 router advertisements

Fedora receives IPv6 router advertisements from:

```text
fe80::14ef:fca3:5a4c:caa9
MAC C0:95:6D:A4:44:32
IPv4 192.168.30.107
DHCP hostname Marios-Apple-TV
```

The advertisements result in:

- Fedora ULA address `fd41:1c26:3fe0:492a:.../64`.
- On-link route `fd41:1c26:3fe0:492a::/64`.
- Route `fd97:621d:6313::/64` through the Apple TV link-local address.
- No IPv6 default route.
- No IPv6 Internet route.

This behavior is local to VLAN30 and is consistent with an Apple TV acting as a local IPv6/Thread border router. It is not routed by the RB5009 and has not bypassed RB5009 inter-VLAN policy.

## Important limitation

Disabling IPv6 on the RB5009 disables the router's IPv6 Layer-3 stack and automatic link-local addresses after reboot. It does not stop Ethernet bridges and switches from carrying IPv6 frames between devices in the same VLAN.

Therefore, the Apple TV advertisements require a separate decision:

- Keep them if Apple Home, Matter, or Thread functionality is required.
- Otherwise disable the relevant Apple Home/Thread role if the platform provides an appropriate control.
- Longer term, move the Apple TV and other media/IoT devices to a dedicated VLAN, containing their local advertisements to that broadcast domain.

Do not attempt to solve this with the RB5009 routed IPv6 firewall because same-VLAN traffic does not traverse that firewall.

## If Route64 is not deployed

The recommended router setting is:

```routeros
/ipv6 settings set disable-ipv6=yes forward=no accept-router-advertisements=no
```

MikroTik documents that a reboot is required for the setting to remove existing automatic SLAAC/link-local state. Apply it in a dedicated maintenance step with a current checkpoint, verify the settings, commit Safe Mode, then reboot and validate IPv4, WireGuard, PPPoE, VoIP, CAPsMAN, VLANs, and DNS.

Do not apply this while the Route64 option remains under consideration.

## If Route64 is deployed

Treat the Route64 WireGuard interface as a separate IPv6 WAN. Before assigning any public prefix to a LAN:

1. Record the tunnel endpoint, public key, transport addresses, routed `/56`, and provider MTU without exposing private keys.
2. Build a separate WireGuard interface rather than reusing the administrative `wireguard1` interface.
3. Establish and test the tunnel on the RB5009 without advertising a public prefix to clients.
4. Replace the generic IPv6 firewall with explicit input and forwarding policy, preserving required ICMPv6.
5. Add final input and forward denies before enabling client prefixes.
6. Allocate one complete `/64` from the routed `/56` to each deliberately enabled VLAN.
7. Begin with one pilot VLAN and verify outbound, unsolicited inbound denial, inter-VLAN denial, DNS, PMTU, and fail-closed behavior when the tunnel drops.
8. Do not use NAT66.

## Future IPv6 reintroduction requirements

Before re-enabling IPv6:

1. Confirm ISP IPv6 service and prefix-delegation behavior.
2. Allocate a unique `/64` to every supported VLAN.
3. Define an IPv6 reachability matrix equivalent to IPv4.
4. Retain required ICMPv6 while restricting router input deliberately.
5. Add explicit per-zone Internet and inter-VLAN permits.
6. Add unconditional final input and forward denies.
7. Decide whether WireGuard should carry IPv6 and allocate exact peer addresses.
8. Test every VLAN independently over IPv4 and IPv6.
