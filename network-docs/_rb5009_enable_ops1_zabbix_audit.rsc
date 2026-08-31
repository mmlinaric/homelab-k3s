:put "=== OPS-01 Zabbix forward rules ==="
/ip/firewall/filter/print detail where comment~"Zabbix active agent"
:put "Expected: two enabled TCP/10051 accepts from 192.168.20.10 and .11 to 192.168.60.21 before the MGMT private-network deny."
