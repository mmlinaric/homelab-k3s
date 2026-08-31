# Run in RouterOS Safe Mode. Permit only OPS-01 SNMP polling.
:local mgmtAnchor [/ip/firewall/filter/find where comment="MGMT: block initiating into private networks"]
:if ([:len $mgmtAnchor] != 1) do={ :error "Expected exactly one MGMT private-network deny anchor" }
:if ([:len [/ip/firewall/filter/find where comment="MGMT: allow OPS-01 SNMP to RB5009"]] = 0) do={
  /ip/firewall/filter/add chain=input action=accept connection-state=new protocol=udp src-address=192.168.60.21 dst-address=192.168.20.1 dst-port=161 place-before=[find where comment="SERVERS: block other router access"] comment="MGMT: allow OPS-01 SNMP to RB5009"
}
:if ([:len [/ip/firewall/filter/find where comment="MGMT: allow OPS-01 SNMP to CSS326"]] = 0) do={
  /ip/firewall/filter/add chain=forward action=accept connection-state=new protocol=udp src-address=192.168.60.21 dst-address=192.168.20.2 dst-port=161 place-before=$mgmtAnchor comment="MGMT: allow OPS-01 SNMP to CSS326"
}
