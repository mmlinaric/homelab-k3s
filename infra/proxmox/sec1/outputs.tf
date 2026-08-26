output "ipv4_address" {
  value = "192.168.60.20"
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.sec1.vm_id
}
