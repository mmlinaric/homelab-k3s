locals {
  node_name        = "pve1"
  disk_datastore   = "local-lvm"
  image_datastore  = "local"
  ubuntu_image_url = "https://cloud-images.ubuntu.com/releases/resolute/release-20260731/ubuntu-26.04-server-cloudimg-amd64.img"
  ubuntu_image_sha = "9dc7c5363c0146a08ba0c9aa834d82c2c6dfbb1c471ad9a2f0aba1189e21be05"
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure
}

resource "proxmox_download_file" "ubuntu_2604" {
  content_type       = "import"
  datastore_id       = local.image_datastore
  node_name          = local.node_name
  url                = local.ubuntu_image_url
  file_name          = "ubuntu-26.04-server-cloudimg-amd64.qcow2"
  checksum           = local.ubuntu_image_sha
  checksum_algorithm = "sha256"
}

resource "proxmox_virtual_environment_vm" "sec1" {
  vm_id     = 120
  name      = "sec1"
  node_name = local.node_name
  on_boot   = true

  description     = "Wazuh security monitoring. Managed by OpenTofu and Ansible."
  scsi_hardware   = "virtio-scsi-single"
  stop_on_destroy = true

  agent {
    enabled = true
    trim    = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192
    floating  = 8192
  }

  disk {
    datastore_id = local.disk_datastore
    import_from  = proxmox_download_file.ubuntu_2604.id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    serial       = "sec1-system"
    size         = 64
  }

  disk {
    datastore_id = local.disk_datastore
    interface    = "scsi1"
    iothread     = true
    discard      = "on"
    serial       = "wazuh-backup"
    size         = 32
  }

  initialization {
    datastore_id = local.disk_datastore

    dns {
      servers = ["192.168.60.1"]
    }

    ip_config {
      ipv4 {
        address = "192.168.60.20/24"
        gateway = "192.168.60.1"
      }
    }

    user_account {
      keys     = [trimspace(var.ssh_public_key)]
      username = "mario"
    }
  }

  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 60
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  startup {
    order      = "3"
    up_delay   = "30"
    down_delay = "60"
  }
}
