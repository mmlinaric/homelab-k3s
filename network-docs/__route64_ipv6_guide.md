# Route64 IPv6 clean installation manual

Prepared: 2026-08-23<br>
Target: RB5009UG, RouterOS 7.24<br>
Scope: router-only IPv6 through Route64; no VLAN receives IPv6 in this stage

## Known working values

```text
Interface:           route64-wg-tb34746
Listen port:         20191/UDP
MTU:                 1420
Endpoint:            178.215.228.222:20191
Route64 public key:  Mpi96MW79ZRKjcM+yh/+6JpiIfwnMK9KnIC1IhEkWj0=
RB5009 public key:   /mSFarGrHKKt75yIyp4QpDVS8a7nMSIpj8JzqnObBVQ=
Tunnel address:      2a11:6c7:f05:477::2/64
Tunnel peer:         2a11:6c7:f05:477::1
Routed LAN prefix:   2a11:6c7:1104:7700::/56
Allowed address:     ::/0
Keepalive:           15 seconds
```

The generated `::/1,8000::/1` setting did not select the peer correctly on
this router. The tunnel worked with the transport `/64` and remained working
with `::/0`. RouterOS does not create a route from the peer's
`allowed-address`; the IPv6 default route is added separately.

Never put the Route64 private key in this repository, chat, an export, or shell
history. Paste it only into RouterOS locally.

## Current leftovers found after rollback

The read-only inventory on 2026-08-23 found:

- disabled interface `route64-wg-tb34746`;
- disabled peer `peer8` attached to it;
- no static Route64 IPv6 address;
- no IPv6 default route;
- no IPv4 or IPv6 firewall rules containing `Route64`;
- only the interface's invalid dynamic link-local address.

Remove these two disabled configuration objects before making the checkpoint.

## 1. Remove the disabled leftovers

Enter Safe Mode with `Ctrl+X`. Confirm `<SAFE>` appears, then run:

```routeros
/interface wireguard peers remove \
    [find where interface="route64-wg-tb34746"]

/interface wireguard remove \
    [find where name="route64-wg-tb34746"]
```

Verify that every command below prints nothing:

```routeros
/interface wireguard print detail without-paging where name~"route64"
/interface wireguard peers print detail without-paging where interface="route64-wg-tb34746"
/ipv6 address print detail without-paging where interface="route64-wg-tb34746"
/ipv6 route print detail without-paging where dst-address="::/0"
/ip firewall filter print detail without-paging where comment~"Route64"
/ipv6 firewall filter print detail without-paging where comment~"Route64"
```

Press `Ctrl+X` once to commit this cleanup. Confirm `<SAFE>` disappears.

If instead you need to discard changes made in Safe Mode, press `Ctrl+D` at an
empty prompt. Do not use `/quit` for rollback: MikroTik documents that
`Ctrl+D` rolls back Safe Mode changes, while `/quit` does not.

## 2. Create the pre-IPv6 checkpoint

Run outside Safe Mode:

```routeros
/system backup save \
    name=_rb5009_before_route64_ipv6_20260823 \
    dont-encrypt=yes

/export hide-sensitive \
    file=_rb5009_before_route64_ipv6_20260823

/file print where name~"^_rb5009_before_route64_ipv6_20260823"
```

Download both files before proceeding. The unencrypted binary backup contains
secrets and must be stored as sensitive. Hash the downloaded files locally:

```bash
sha256sum _rb5009_before_route64_ipv6_20260823.backup \
  _rb5009_before_route64_ipv6_20260823.rsc
```

## 3. Enter Safe Mode for installation

Connect through the existing administrative WireGuard tunnel. Confirm the
identity and that the administrative peer is working:

```routeros
/system identity print
/interface wireguard peers print detail without-paging \
    where interface="wireguard1"
```

Press `Ctrl+X` once. Do not continue unless `<SAFE>` appears.

## 4. Create the dedicated tunnel, initially disabled

Replace `<ROUTE64_PRIVATE_KEY>` locally with the private key supplied by
Route64:

```routeros
/interface wireguard add \
    name=route64-wg-tb34746 \
    comment="Route64 IPv6 tunnel" \
    disabled=yes \
    listen-port=20191 \
    mtu=1420 \
    private-key="<ROUTE64_PRIVATE_KEY>"
```

Verify that the derived public key is exactly
`/mSFarGrHKKt75yIyp4QpDVS8a7nMSIpj8JzqnObBVQ=`:

```routeros
/interface wireguard print detail without-paging \
    where name="route64-wg-tb34746"
```

Stop and roll back if it differs.

## 5. Add the peer and transport address

```routeros
/interface wireguard peers add \
    interface=route64-wg-tb34746 \
    name="Route64 IPv6 endpoint" \
    public-key="Mpi96MW79ZRKjcM+yh/+6JpiIfwnMK9KnIC1IhEkWj0=" \
    endpoint-address=178.215.228.222 \
    endpoint-port=20191 \
    allowed-address=::/0 \
    persistent-keepalive=15s

/ipv6 address add \
    address=2a11:6c7:f05:477::2/64 \
    interface=route64-wg-tb34746 \
    advertise=no \
    comment="Route64 tunnel address"
```

Do not assign the routed `/56` to this interface. Do not assign a global IPv6
address to a VLAN in this stage.

## 6. Install the permanent router-only boundary

Allow only the exact Route64 endpoint to reach the UDP listener:

```routeros
/ip firewall filter add \
    action=accept \
    chain=input \
    protocol=udp \
    in-interface-list=WAN \
    src-address=178.215.228.222 \
    src-port=20191 \
    dst-port=20191 \
    comment="Allow Route64 WireGuard handshake" \
    place-before=[find where chain="input" and comment="defconf: drop invalid"]
```

Allow the existing earlier ICMPv6 rule to process required control messages,
then reject other new input from the tunnel:

```routeros
/ipv6 firewall filter add \
    action=drop \
    chain=input \
    in-interface=route64-wg-tb34746 \
    comment="Drop non-ICMP IPv6 from Route64" \
    place-before=[find where chain="input" and comment="defconf: accept UDP traceroute"]
```

Keep all VLAN forwarding isolated until the complete per-VLAN IPv6 policy is
installed:

```routeros
/ipv6 firewall filter add \
    action=drop \
    chain=forward \
    in-interface=route64-wg-tb34746 \
    comment="Block forwarded IPv6 from Route64" \
    place-before=[find where chain="forward" and comment="defconf: accept established,related,untracked"]

/ipv6 firewall filter add \
    action=drop \
    chain=forward \
    out-interface=route64-wg-tb34746 \
    comment="Block forwarded IPv6 to Route64 until VLAN policy exists" \
    place-before=[find where chain="forward" and comment="defconf: accept established,related,untracked"]
```

These forwarding rules are deliberate security boundaries, not test
leftovers. The outbound block is replaced by explicit VLAN permits in the next
stage. The inbound block remains the unsolicited-Internet deny.

## 7. Enable and verify the tunnel

```routeros
/interface wireguard enable \
    [find where name="route64-wg-tb34746"]

/ping 2a11:6c7:f05:477::1 \
    src-address=2a11:6c7:f05:477::2 \
    count=5

/interface wireguard peers print detail without-paging \
    where interface="route64-wg-tb34746"
```

Required result:

- five replies from `2a11:6c7:f05:477::1`;
- `current-endpoint-address=178.215.228.222`;
- nonzero `rx` and `tx`;
- a recent `last-handshake`.

If it fails, press `Ctrl+D` to discard the installation. Do not add the default
route.

## 8. Add and test router-only IPv6 Internet

```routeros
/ipv6 route add \
    dst-address=::/0 \
    gateway=route64-wg-tb34746 \
    distance=1 \
    comment="IPv6 default route via Route64"

/ipv6 route print detail without-paging where dst-address="::/0"

/ping 2606:4700:4700::1111 \
    src-address=2a11:6c7:f05:477::2 \
    count=5
```

The default route must be active and the external ping must succeed.

## 9. Audit isolation before committing

```routeros
/interface wireguard print detail without-paging \
    where name="route64-wg-tb34746"
/interface wireguard peers print detail without-paging \
    where interface="route64-wg-tb34746"
/ipv6 address print detail without-paging where global
/ipv6 route print detail without-paging where dst-address="::/0"
/ip firewall filter print stats detail without-paging where comment~"Route64"
/ipv6 firewall filter print stats detail without-paging where comment~"Route64"
```

The Route64 transport address must be the only Route64 global address. There
must be no Route64 address on VLAN10, VLAN20, VLAN30, VLAN40, VLAN60, VLAN99,
`bridge`, or `wireguard1`.

Also verify that IPv4 Internet, DNS, administrative WireGuard, SSH, and WinBox
still work.

## 10. Commit and checkpoint

Press `Ctrl+X` once to commit. Confirm `<SAFE>` disappears.

Create a post-installation checkpoint:

```routeros
/system backup save \
    name=_rb5009_after_route64_router_only_20260823 \
    dont-encrypt=yes

/export hide-sensitive \
    file=_rb5009_after_route64_router_only_20260823

/file print where name~"^_rb5009_after_route64_router_only_20260823"
```

Download, protect, and hash both files.

## Result

```text
RB5009 -> IPv6 Internet through Route64: allowed
Route64 -> RB5009: established traffic and required ICMPv6 only
Any VLAN -> Route64: blocked
Route64 -> any VLAN: blocked
Route64 prefix advertised by RB5009: none
IPv4 and administrative WireGuard: unchanged
```

## Emergency disable after committing

```routeros
/ipv6 route disable \
    [find where comment="IPv6 default route via Route64"]
/interface wireguard disable \
    [find where name="route64-wg-tb34746"]
```

## Next stage—not included here

Route64 routes `2a11:6c7:1104:7700::/56` through this tunnel. The first pilot
allocation is reserved as follows:

```text
VLAN30 prefix:  2a11:6c7:1104:7730::/64
RB5009:         2a11:6c7:1104:7730::1
Fedora pilot:   2a11:6c7:1104:7730::43
```

The RB5009 address will initially use `advertise=no`, and Fedora will receive a
manual address and route. No other VLAN30 device will receive this prefix. The
IPv6 firewall must first be reordered so established return traffic precedes
the Route64 inbound block, with an exact Fedora `/128` outbound permit before
the general Route64 outbound block.

Do not use NAT66 and do not enable router advertisements until the one-device
pilot has passed inbound-denial, inter-VLAN, DNS, HTTPS, MTU, and tunnel-failure
tests.
