terraform {
  required_version = "= 1.12.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"
    }
  }

  backend "s3" {}
}
