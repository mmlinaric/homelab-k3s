# Rack cable labeling and tracing plan

**Prepared:** 2026-08-25<br>
**Printer:** Brother P-touch PT-H110<br>
**Status:** planning and initial inventory; rack-front photo reviewed; physical mappings marked `VERIFY` must not be treated as authoritative

## 1. Objective

Give every administered cable a readable label at both ends, label each patch-panel position with its CSS326 port and destination, and keep one cable register that answers:

- What is this cable?
- Where do both ends terminate?
- What service or VLAN does it carry?
- Can it be safely disconnected?

The working rule is: **identify first, record second, print third, attach fourth, validate last**. Never attach a label based only on an assumption or unplug more than one unknown network cable at a time.

## 2. PT-H110 setup

### Tape

- Cable flags: use **12 mm black-on-white Flexible ID laminated tape, Brother TZe-FX231**.
- Device, patch-panel, shelf, and power-brick surfaces: use ordinary **12 mm black-on-white laminated TZe-231**. If a flat surface is textured or labels lift, use **12 mm strong-adhesive TZe-S231**.
- The PT-H110 accepts TZe tape from 3.5 mm through 12 mm. Use 12 mm for the rack because it gives the most legible flags and allows two-line ordinary labels.
- Do not buy Brother HSe heat-shrink tube for this printer; PT-H110 specifications list TZe cassette support, not HSe tube support.

**Available tape confirmed:** approximately 24 m of `TZe-FX231`. This is the correct cassette for the first cable-labeling pass, and tape conservation is not a design constraint.

### Recommended cable-label format

For full endpoint pairs, use the built-in **Cable** key and **Cable Label template 2**. Template 2 places one endpoint on each face of the flag (`AAA | BBB`):

```text
Text 1: SW1-P04
Text 2: SW2-P01
```

Print **two copies** and put the same flag near both ends of the cable. One face shows `SW1-P04` and the other shows `SW2-P01`. Template 1 repeats the complete endpoint pair and measured approximately 223 mm for `SW1-P04/SW2-P01` at Large size, producing an unnecessarily long physical flag. Use template 1 only for a single short identifier that should be repeated on both faces.

Short names are used only for fast recognition, large readable type, and flags that do not physically crowd the rack. They are not intended to conserve tape. Do not include IP addresses, VLANs, or cable type on the physical flag; those details can change and belong in the register.

Use three levels of identification:

1. **Cable flag:** physical/logical endpoints only, for example `SW1-P06/PVE1`.
2. **Device label:** device name, short alias, and stable management IP, for example `SWITCH1 (SW1)` and `192.168.20.2` on two lines.
3. **Cable register/network documentation:** VLANs, trunk/access role, additional addresses, service purpose, and validation notes.

Do not put an IP address on a patch-panel window or cable. A trunk may carry several IP networks, a host may have several addresses, and addressing can change without the physical cable moving. A management IP on the device chassis remains useful for direct administration and is easy to replace independently.

Recommended text settings:

```text
Font:       Helsinki (plain sans serif)
Size:       Medium; use Small only if the preview truncates
Style:      Bold
Width:      Normal
Frame:      None
Case:       UPPERCASE
Alignment:  Center
```

For the `SW1-P06` to `PVE1` path, useful layout variants are:

| Variant | Mode | Printed text/layout | Benefit | Trade-off |
|---|---|---|---|---|
| A - separate endpoints | Cable template 2 | `SW1-P06 | PVE1` | Large text and a compact flag | Recommended default after physical print test |
| B - fuller name | Cable template 1 | `SWITCH1-P06/PVE1 | SWITCH1-P06/PVE1` | More self-explanatory | Longer physical flag or smaller effective type |
| C - repeated complete pair | Cable template 1 | `SW1-P06/PVE1 | SW1-P06/PVE1` | Entire path visible on either face | Very long flag; the comparable SW1/SW2 label measured 223 mm |
| D - stacked flat label | Normal text mode, two lines | `SW1-P06` above `PVE1` | Good for a panel window or device surface | Not a repeated two-face cable flag |
| E - far end only | Cable template 1, different label at each cable end | `TO SW1-P06` at PVE1; `TO PVE1` at SW1 | Extremely obvious at the connector | Labels are no longer identical and are easier to update incorrectly |

On 12 mm tape, one-line `Large` text uses the available print height most effectively. A two-line label is created by pressing Enter; it does not make one character stretch across two rows, and each line must be smaller because both share the same tape height. Brother allows at most two lines on 9 mm and 12 mm tape. The documented Cable templates are repeated/different flag fields, not a stacked two-line cable layout, so use normal text mode for variant D.

Brother does not allow the cable-template label length to be set, and cable-template labels cannot be saved in the PT-H110 memory. Preview every new label pattern before printing. The printer can make 1-9 copies; use two for the two cable ends.

For ordinary flat labels, choose margins based on the available surface rather than tape consumption. `Narrow` is useful for small patch-panel windows; `Half` or `Full` is acceptable for equipment labels. The cable template controls its own automatic layout.

### Placement

- Put each flag approximately 20-40 mm behind the connector or strain-relief boot.
- The label must be readable without unplugging the connector and must not cover the latch, port number, LEDs, ventilation, or a bend point.
- Align flags consistently so the text faces outward/upward when the cable is installed.
- Wipe dust and grease from the jacket, allow it to dry, then press the two flag halves together firmly with their edges aligned.
- Label both ends before moving to the next cable.

## 3. Naming convention

### Device IDs

| ID | Device | Management address | Status |
|---|---|---|---|
| `RTR01` | MikroTik RB5009UG+S+ | `192.168.20.1` | documented |
| `SW01` | MikroTik CSS326 | `192.168.20.2` | documented |
| `SW02` | TP-Link TL-SG108E v6, remote room | `192.168.20.3` | location confirmed; local port map `VERIFY` |
| `PATCH` | Single 24-position patch panel immediately above CSS326 | n/a | no printed panel name needed; rear and exact mapping `VERIFY` |
| `PVE01` | GMKtec Proxmox host | `192.168.20.10` | documented |
| `PVE02` | Proxmox host connected to remote `SW02` | `192.168.20.11` | location confirmed; hardware identity `VERIFY` |
| `AP01` | MikroTik wAP ax | `192.168.20.20` | documented |
| `KVM01` | NanoKVM | DHCP/static address `VERIFY` | role documented |
| `PDU01` | Primary rack PDU/UPS outlet bank | n/a | model and outlet numbering `VERIFY` |
| `DEV-UNK01` | Lenovo Tiny visible on rack shelf | `VERIFY` | role and relationship to `PVE01`/`PVE02` `VERIFY` |

Add new equipment with a stable role-based ID rather than a vendor name alone. Put a flat device-ID label on the front and rear when the rear is not easy to correlate with the front.

For physical labels, use `SW1` for the CSS326 and `SW2` for the TL-SG108E. Other short names are `RB`, `PVE1`, `PVE2`, `AP`, `KVM`, and `PC`. Use `Pnn` for switch ports, `Enn` for RB5009 Ethernet ports, and `/` between endpoints: `SW1-P04/SW2-P01`, `SW2-P06/PVE2`, and `RB-E02/SW1-P01`.

### Port and cable notation

- Router Ethernet port: `RB-E02`
- Switch port: `SW1-P04` or `SW2-P06`
- Patch-panel position in documentation only: `PATCH-03`; print only the switch port and destination in its label window
- Named host NIC: `PVE01-NIC1`
- PDU outlet: `PDU01-05`
- Optional network cable ID, only when needed: `N001`, `N002`, ...
- AC power cable ID: `P001`, `P002`, ...
- DC power/adapter cable ID: `D001`, `D002`, ...
- USB/KVM/console cable ID: `K001`, `K002`, ...

Use two digits for physical port numbers so labels sort naturally. A cable label carries both endpoints; the register carries cable type, VLAN/service, and validation evidence. The single patch panel is an intermediate connection and does not need a printed identifier.

### Patch-panel rule

The rack-front photo is consistent with short blue leads connecting patch-panel positions to the CSS326's lower/even-numbered ports. If physical inspection confirms that patch position `n` is connected to CSS326 port `2n`, record the mapping as:

```text
PATCH-01 = SW1-P02
PATCH-02 = SW1-P04
PATCH-03 = SW1-P06
...
PATCH-12 = SW1-P24
```

Do not print the full series until positions 1, 2, 3, and 12 have been checked. The front photo cannot prove the rear termination or one-to-one order.

### Rack-front labeling based on the photo

- Use the patch panel's white label windows for the SW1 port and destination port/device, for example `P04/SW2-P01` or `P06/PVE1`. Do not print a patch-panel name and do not cover the existing position numbers.
- The CSS326 is physically labeled `SWITCH1 (SW1)`. The patch panel itself needs no name because there is only one.
- The short blue panel-to-switch leads are fully visible and closely packed. Do **not** label each short lead unless one crosses out of sequence. The panel window and CSS326's printed port number already identify both ends without obstructing neighbouring jacks and LEDs.
- Continue to use two labels, one at each end, for rear equipment cables, room-to-room runs, the `SW1` to remote `SW2` run, and any cable whose entire route is not visible.
- Do not infer service from cable colour. Record blue/yellow/other only as a tracing aid unless a future colour policy is deliberately adopted.

## 4. Known logical topology and initial verification queue

The following comes from the current network documentation and the user's location clarification. `DOCUMENTED` means the logical path has previously been validated; it does not mean there is one uninterrupted physical cable. Paths through the panel must be divided into their front patch cord and rear equipment/home-run cable in the physical cable register.

| Path ref | Logical end A | Logical end B | Function | Likely intermediate point | Evidence/status |
|---|---|---|---|---|---|
| `L001` | `RB-E02` | `SW1-P01` | Tagged trunk, VLANs 10/20/30/60 | probably direct | `DOCUMENTED`; physical `VERIFY` |
| `L002` | `SW1-P04` | remote `SW2-P01` | Tagged inter-switch trunk, VLANs 10/20/30/60 | panel position 2 expected | endpoints physically confirmed by owner; panel position still `VERIFY` |
| `L003` | `SW1-P06` | `PVE1-NIC1` | Proxmox trunk, VLANs 20/60 | likely panel position 3 | `DOCUMENTED`; device identity and panel position `VERIFY` |
| `L004` | remote `SW2-P06` | remote `PVE2-NIC1` | Proxmox trunk, VLANs 20/60 | none expected | `DOCUMENTED`; physical `VERIFY` |
| `L005` | remote `SW2-P07` | remote `KVM-NIC1` | NanoKVM access, VLAN 10 | none expected | logical role documented; physical `VERIFY` |
| `L006` | `RTR01-E08` | `AP01-ETH1` | Tagged AP trunk, VLANs 20/30/40 | `VERIFY` | `DOCUMENTED`; physical `VERIFY` |
| `L007` | `RTR01-E07` | `VOICE-END` | ISP voice handoff, VLAN 101 bridge | `VERIFY` | remote endpoint `VERIFY` |
| `L008` | `RTR01-SFP1` | `ISP-ONT` | ISP VLAN 100/101 transport | `VERIFY` | media and remote endpoint `VERIFY` |
| `L009` | `RTR01-E03` | `RECOVERY` | Direct recovery laptop cable; normally unplugged | none | documented; cable storage location `VERIFY` |

`SW2-P04` is documented as an unassigned VLAN 1 access port. Treat any cable found there as unknown and investigate; do not give it a permanent service label until its purpose is decided.

## 5. Physical tracing procedure

### Phase A - prepare without disconnecting anything

1. Freeze network changes for the tracing session and choose a maintenance window for any link-flap tests.
2. Print flat device labels `RB`, `SW1`, `SW2`, `PVE1`, `PVE2`, `AP`, and `KVM` after confirming each device in place. The single patch panel needs no name label.
3. Photograph the rack front and rear clearly enough to read all port numbers. Keep the photos private; they may expose serial numbers or physical security details.
4. Record every occupied router, CSS326, TL-SG108E, patch-panel, PDU, server, and peripheral port before moving any cable.
5. Capture read-only link state, negotiated speed, error counters, MAC/FDB entries, and LLDP/neighbour data from both switches and the router. This is evidence, not proof of a physical endpoint.

### Phase B - establish the patch-panel mapping

1. Confirm whether the patch panel is a feed-through panel and whether each position has the same number on its front and rear.
2. Test the claimed formula `panel position nn -> CSS port (2 x nn)` one position at a time.
3. Start with already documented active paths: CSS326 ports 4 and 6. Use the link LEDs and read-only switch state while a helper briefly disconnects only the selected patch position, then reconnect immediately.
4. Confirm the first, middle, and last positions. If any result violates the formula, stop using the formula and trace every position individually.
5. Label each confirmed panel window with the CSS port and destination, for example `06/PVE1`, and enter it in the register.

### Phase C - trace unknown network cables

For each occupied but unknown connection:

1. Write down its temporary location and cable colour/length.
2. Check switch link state, MAC addresses, VLAN/PVID, LLDP, ARP/DHCP leases, and host inventory.
3. If still ambiguous, announce the expected interruption and briefly disconnect exactly one end while watching for the corresponding link-down event. Reconnect it before investigating another cable.
4. Validate the restored service: link speed, ping or management access, and the relevant workload where practical.
5. Enter both endpoints, print two identical endpoint-pair flags, and attach one at each end. Allocate an `Nnn` ID only if endpoint text alone would be ambiguous.

Never casually flap paths `L001` through `L006`; they include core, inter-switch, Proxmox, NanoKVM, or AP connectivity. Trace them visually and from port state first, and interrupt them only in an agreed maintenance window.

### Phase D - power and non-network cables

1. Label both ends of each AC lead with its PDU outlet and powered device, for example `PDU-05` / `SW1-PSU`.
2. Label both the mains lead and the low-voltage lead of external power bricks; put a flat `DEVICE-PSU` label on the brick itself.
3. Use `Dnnn` for low-voltage DC leads and include voltage/polarity only if read directly from the supply/device, never from memory.
4. Use `Knnn` for NanoKVM, USB, HDMI, serial, and console paths and state the connector/function in the register.
5. Do not unplug redundant-looking power cables to identify them. Trace power visually or during a controlled shutdown.

### Phase E - close out

1. Compare every attached label with the register and the actual endpoints.
2. Verify all formerly active links are up at the expected speed and error counters are not increasing.
3. Validate Internet, DNS, Wi-Fi, switch management, both Proxmox hosts, VLAN 10 NanoKVM access, and key VLAN 60 services.
4. Update the topology documentation and date the cable register.
5. Keep spare preprinted blank-ID flags and the labeler in a known rack-maintenance kit. Update the register and labels in the same change whenever a cable moves.

## 6. Cable register

Complete one row per physical cable. For a patch-panel path, record each detachable patch/equipment cord separately and use the Notes column to connect it to the logical end-to-end service.

| ID | Type | End A | Port A | End B | Port B | Service/VLAN | Colour/length | Verified by | Date | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| optional | Ethernet | `RB` | `E02` | `SW1` | `P01` | trunk 10/20/30/60 | `VERIFY` | docs + physical pending | 2026-08-25 | label `RB-E02/SW1-P01` |
| optional | Ethernet | `SW1` | `P04` | panel | likely `02-F` | trunk 10/20/30/60 | blue/short | photo + physical pending | 2026-08-25 | visible jumper; normally no cable flag |
| optional | Ethernet | panel | likely `02-R` | remote `SW2` | `P01` | trunk 10/20/30/60 | approximately 10 m | owner confirmed endpoints | 2026-08-25 | label `SW1-P04/SW2-P01` at both ends; panel position pending |
| optional | Ethernet | `SW1` | `P06` | panel | likely `03-F` | trunk 20/60 | blue/short | photo + physical pending | 2026-08-25 | visible jumper; normally no cable flag |
| optional | Ethernet | panel | likely `03-R` | `PVE1` | `NIC1` | trunk 20/60 | `VERIFY` | physical pending | 2026-08-25 | label `SW1-P06/PVE1` at both ends |
| optional | Ethernet | remote `SW2` | `P06` | remote `PVE2` | `NIC1` | trunk 20/60 | `VERIFY` | physical pending | 2026-08-25 | label `SW2-P06/PVE2` |
| optional | Ethernet | remote `SW2` | `P07` | remote `KVM` | `NIC1` | access VLAN 10 | `VERIFY` | physical pending | 2026-08-25 | label `SW2-P07/KVM` |

## 7. Questions to resolve before printing the batch

1. Is it a pass-through/coupler panel, and do the short blue front leads follow panel position 1 to `SW1-P02`, position 2 to `SW1-P04`, through position 12 to `SW1-P24`?
2. What is the Lenovo Tiny visible on the rack shelf? Earlier documentation associates a ThinkCentre M920q with `PVE2`, but `PVE2` is now confirmed to be in the remote `SW2` room.
3. Which devices are connected at the rear of every occupied patch-panel position? A straight-on rear photo is the safest next source.
4. What are the actual NIC labels on both Proxmox hosts (`eno1`, `enp...`, etc.), and should the physical labels use those names or the simpler `NIC1`?
5. What is connected to remote TL-SG108E ports 2, 3, 4, 5, and 8? In particular, is port 4 physically empty?
6. Where do RB5009 `ether7` and `sfp-sfpplus1` physically terminate, and what wording is most useful for those ISP/voice endpoints?
7. Is the direct `ether3` recovery cable kept connected, coiled in the rack, or stored elsewhere?
8. Do you want power, USB/KVM, HDMI, storage, and console cables included in this first pass, or should the first session cover Ethernet only?

## 8. Research basis

- Brother's PT-H110 user guide and product material specify TZe tapes from 3.5-12 mm, a maximum 12 mm label width, two-line labels on 9/12 mm tape, and a dedicated cable-label function.
- Brother's PT-H110 cable-label instructions describe template 1 as repeated text (`AAA | AAA`) and template 2 as two different fields (`AAA | BBB`). Cable label length is automatic, 1-9 copies are supported, and template labels cannot be saved.
- Brother recommends Flexible ID laminated tape for labels attached to cables and wires. The compatible 12 mm black-on-white cassette is TZe-FX231.
- ANSI/TIA-606-C-oriented practice calls for machine-printed, legible, durable labels at both ends, termination-point identification, and matching administration records. This plan uses those principles without imposing a commercial-building identifier hierarchy on a single home rack.

Sources:

- [Brother PT-H110 User's Guide](https://download.brother.com/welcome/docp100243/pth110_use_ug_d0123y001_02.pdf)
- [Brother: How to create a cable label on the PT-H110](https://support.brother.com/g/b/faqend.aspx?c=us&faqid=faqp00100279_000&lang=en&pfs=1&prod=h110eus)
- [Brother PT-H110 features and specifications](https://www.brother.eu/-/media/product-downloads/devices/nordics/eu_en/labelling-machines/pt-h110-leaflet.pdf)
- [Brother TZe tape type and width chart](https://www.brother.eu/-/media/product-downloads/devices/nordics/eu_en/labelling-machines/tze-tapeoversigt.pdf)
- [Brady summary of ANSI/TIA-606-C administration and labeling practice](https://www.bradyid.com/resources/tia-606-c-cable-labeling-standards)
