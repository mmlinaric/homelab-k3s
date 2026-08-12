# Reusable Jenkins Docker agent

These NoCloud files provision a project-neutral Ubuntu 24.04 Jenkins SSH agent
with label `docker-agent`.

- Hostname: `jenkins-agent-01`
- Network: `ens18`, `192.168.60.104/24`, gateway `192.168.60.1`
- DNS: `192.168.60.1`, `1.1.1.1`
- Recommended size: 4 vCPU, 8 GiB RAM, 80 GiB disk

Pass `user-data.yaml` and `network-config.yaml` separately to the VM platform.
Store the matching private key in Bitwarden and expose it through the
`jenkins-runtime` ExternalSecret as `docker-agent-ssh-private-key`. Never commit
the private key. Expected key fingerprint:

`SHA256:M4tPQ3PThsC+tM7JTsLPNAhPeGDP4icRqAI8D+0a9T8`

Before syncing Jenkins, add the Bitwarden item mapping to
`apps/jenkins/secrets.yaml`. After provisioning, verify:

```sh
ssh jenkins@192.168.60.104 'java -version; git --version; docker version; docker buildx version; docker run --rm hello-world'
```

Restart Jenkins for plugin/JCasC changes. On first node launch, compare the SSH
host-key fingerprint with `ssh-keyscan 192.168.60.104 | ssh-keygen -lf -`, then
approve it in Jenkins.

Docker socket access is root-equivalent. Keep this a dedicated CI VM; workspaces
and `/var/cache/jenkins-ci` are disposable.
