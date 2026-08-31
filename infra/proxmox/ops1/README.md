# ops1 OpenTofu stack

This stack creates VM 220 on `pve2` from the checksum-pinned Ubuntu Server
26.04 cloud image. Ansible installs Zabbix after cloud-init and SSH are ready.

Create the state bucket first with versioning and server-side encryption. Keep
Object Lock disabled and expire incomplete multipart uploads after seven days.

```bash
export AWS_ACCESS_KEY_ID='<state-access-key>'
export AWS_SECRET_ACCESS_KEY='<state-secret-key>'
export TF_VAR_proxmox_api_token='<user@realm!token=secret>'
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
tofu init -backend-config=backend.hcl
tofu plan -out=ops1.tfplan
tofu apply ops1.tfplan
```

Keep backend configuration, variable values, plan files, and state out of Git.
