# Run in RouterOS Safe Mode after OPS-01 is reachable at 192.168.60.21.
# These two exact-source rules permit only encrypted active-agent submissions.

:local anchor [/ip/firewall/filter/find where comment="MGMT: block initiating into private networks"]
:if ([:len $anchor] != 1) do={ :error "Expected exactly one MGMT private-network deny anchor" }
:if ([:len [/ip/firewall/filter/find where comment="MGMT: allow pve1 Zabbix active agent"]] = 0) do={
  /ip/firewall/filter/add chain=forward action=accept connection-state=new protocol=tcp src-address=192.168.20.10 dst-address=192.168.60.21 dst-port=10051 place-before=$anchor comment="MGMT: allow pve1 Zabbix active agent"
}
:if ([:len [/ip/firewall/filter/find where comment="MGMT: allow pve2 Zabbix active agent"]] = 0) do={
  /ip/firewall/filter/add chain=forward action=accept connection-state=new protocol=tcp src-address=192.168.20.11 dst-address=192.168.60.21 dst-port=10051 place-before=$anchor comment="MGMT: allow pve2 Zabbix active agent"
}
