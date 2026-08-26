# sec1 OpenTofu stack

This stack creates VM 120 on `pve1` from the checksum-pinned Ubuntu Server
26.04 cloud image. It does not install Wazuh; run the Ansible playbook after
cloud-init and SSH are available.

The S3 bucket must exist before backend initialization. Enable versioning and
SSE-OMK, disable Object Lock, expire incomplete multipart uploads after seven
days, and expire non-current versions after 30 days.

```bash
export AWS_ACCESS_KEY_ID='<state-access-key>'
export AWS_SECRET_ACCESS_KEY='<state-secret-key>'
export TF_VAR_proxmox_api_token='<user@realm!token=secret>'
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
tofu init -backend-config=backend.hcl
tofu plan
tofu apply
```

Keep `backend.hcl`, `terraform.tfvars`, plan files, and state out of Git.
