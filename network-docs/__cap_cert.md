# wAP ax CAP certificate activation

Date prepared: 2026-08-23

## Completed state

Completed and validated on 2026-08-24:

- The wAP actively uses `CAP-F41E576637FF`.
- The RB5009 reports `common-name="CAP-F41E576637FF"` and CAP state `Ok`.
- CAPsMAN has `require-peer-certificate=yes`.
- Both VLAN30 main radios and both VLAN40 guest radios returned bound.
- Main and guest Wi-Fi connectivity was tested successfully.
- Retain the pre-change checkpoints and create post-change checkpoints after
  validation.

The remaining validation is a later, separate wAP reboot test. Do not request a
new certificate during that test.

Current known state:

- RB5009 CAPsMAN: RouterOS 7.24
- wAP ax: RouterOS 7.21.2
- CAP certificate already enrolled: `CAP-F41E576637FF`
- The certificate contains its private key and was signed by the RB5009 CAPsMAN CA.
- The same certificate fingerprint exists on the wAP and RB5009.
- CAPsMAN originally had `require-peer-certificate=no`; it is now `yes`.
- Requesting the certificate previously caused a temporary Wi-Fi interruption.

This procedure is therefore expected to interrupt Wi-Fi while the CAP reconnects. It is not guaranteed to be interruption-free.

## Preparation

Use the Pixel on mobile data, not through the wAP Wi-Fi:

1. Disable Wi-Fi on the Pixel.
2. Enable the Pixel WireGuard tunnel.
3. Confirm access to the RB5009 at `192.168.90.1`.
4. Confirm access through the RB5009 to the wAP at `192.168.20.20`.
5. Keep separate sessions open to the wAP and RB5009.
6. Do not run `certificate=request` again; enrollment is already complete.

## Step 1: make the wAP use its enrolled certificate

On the wAP, enter Safe Mode using `Ctrl+X`. The terminal should report that Safe Mode was taken.

Then run:

```routeros
/interface wifi cap set certificate=CAP-F41E576637FF
```

Allow approximately 30–60 seconds for CAP and Wi-Fi reconnection. Reconnect to the wAP through the Pixel/WireGuard path if necessary, then run on the wAP:

```routeros
/interface wifi cap print
/certificate print detail without-paging
```

On the RB5009, run:

```routeros
/interface wifi capsman remote-cap print detail without-paging
```

Proceed only when all of the following are true:

- The remote CAP state is `Ok`.
- The remote CAP shows `common-name="CAP-F41E576637FF"`.
- The managed Wi-Fi interfaces have returned.
- Main and guest Wi-Fi clients reconnect and pass traffic.

If these checks pass, commit Safe Mode on the wAP using `Ctrl+X`.

If the CAP does not reconnect correctly, do not change CAPsMAN certificate enforcement. Allow the wAP Safe Mode session to terminate so RouterOS rolls back the certificate-selection change.

## Step 2: require authenticated CAPs on the RB5009

Do this only after Step 1 succeeds and the RB5009 displays the expected non-empty CAP common name.

On the RB5009, enter Safe Mode using `Ctrl+X`, then run:

```routeros
/interface wifi capsman set require-peer-certificate=yes
```

Verify immediately:

```routeros
/interface wifi capsman print
/interface wifi capsman remote-cap print detail without-paging
/interface wifi print detail without-paging
```

Confirm all of the following:

- `require-peer-certificate: yes`
- Remote CAP state remains `Ok`.
- Its common name remains `CAP-F41E576637FF`.
- All four managed Wi-Fi interfaces return.
- VLAN30 main Wi-Fi works.
- VLAN40 guest Wi-Fi works.

If all checks pass, commit RB5009 Safe Mode using `Ctrl+X`.

If the CAP disconnects or Wi-Fi does not recover, do not commit. Allow the RB5009 Safe Mode session to terminate so certificate enforcement rolls back.

## Later validation

In a separate maintenance window, test CAP reconnection after an RB5009 reboot and after a wAP reboot. Do not combine those tests with firmware upgrades or trunk/VLAN changes.
