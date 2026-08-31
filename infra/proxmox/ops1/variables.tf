variable "proxmox_endpoint" {
  description = "PVE-02 API endpoint, including https and port 8006."
  type        = string
  default     = "https://192.168.20.11:8006/"
}

variable "proxmox_api_token" {
  description = "Proxmox API token in user@realm!token=secret form."
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Allow an untrusted Proxmox API certificate. Prefer installing the PVE CA instead."
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = "OpenSSH public key installed for the mario cloud-init account."
  type        = string
}
