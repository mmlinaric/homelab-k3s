output "ipv4_address" {
  value = "192.168.60.21"
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.ops1.vm_id
}
