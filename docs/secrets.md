# Secrets and configuration

No secret value belongs in Git. Bitwarden Secrets Manager is the online source of truth, and External Secrets Operator materializes Kubernetes Secrets.

## OVH Object Storage

Create these two private S3-compatible buckets in one OVH Public Cloud region:

```text
mmlinaric-homelab-etcd
mmlinaric-homelab-velero
```

The names are already unique to this deployment and should be used exactly. Configure them as follows:

- Enable OVHcloud Managed Key encryption on both buckets.
- Enable versioning on both buckets.
- Do not enable Object Lock initially. Velero repository maintenance and K3s retention must be able to delete objects. Add lock only after a restore and retention test proves the selected mode does not break cleanup.
- Keep current versions in the Velero bucket for at least 400 days. Its monthly backup TTL is 366 days.
- Let K3s retain 28 snapshots. Keep non-current versions for 30 days if lifecycle rules are available.

The prefixes are already declared in Git:

| Bucket | Prefix |
| --- | --- |
| `mmlinaric-homelab-etcd` | `homelab/etcd` |
| `mmlinaric-homelab-velero` | `homelab` |

Use separate OVH S3 users and keys per bucket if the OVH project permissions allow useful bucket isolation. If they do not, the manifests still use distinct Bitwarden entries so the credentials can be separated later without changing workloads.

The Velero endpoint placeholder requires the full HTTPS URL:

```text
https://s3.<region-in-lowercase>.io.cloud.ovh.net
```

The K3s endpoint Bitwarden entry must contain only the host name, without `https://`:

```text
s3.<region-in-lowercase>.io.cloud.ovh.net
```

Kopia encrypts GitLab, Forgejo, and Keycloak staging-volume data before upload. OVH managed encryption adds storage-side encryption and also covers Velero metadata and K3s snapshots. Do not remove either layer.

## Bootstrap values

Edit `ansible/group_vars/all.yml` and set the Bitwarden organization and project IDs. Confirm `ansible/inventory/hosts.yml` contains the correct SSH user and node address. The expected primary interface is `ens18`.

Export these variables on the Ansible controller before bootstrap:

```bash
export K3S_SERVER_TOKEN='a-long-random-cluster-token'
export BWS_ACCESS_TOKEN='your-machine-account-access-token'
export GITHUB_REPO_USERNAME='your-github-user'
export GITHUB_REPO_TOKEN='a-fine-grained-read-only-token'
```

The GitHub token only needs read access to the private repository. The Bitwarden machine account should only see the homelab project.

## Bitwarden entries

Create one Bitwarden secret per value below. Replace each `CHANGE_ME_BWS_*_ID` in the repository with the UUID of that secret, not its value.

| Area | Required values |
| --- | --- |
| Cloudflare | API token with DNS edit rights for the zone, tunnel credentials JSON |
| Keycloak | database credentials, PostgreSQL superuser credentials, bootstrap admin credentials |
| GitLab | existing `gitlab-secrets.json`, OIDC client secret |
| Forgejo | database credentials, OIDC client secret, bootstrap administrator credentials |
| Velero | Velero S3 access key and secret key, permanent Kopia repository password |
| Grafana | admin credentials, Keycloak OIDC client secret |
| Jenkins | Keycloak OIDC client secret, escape-hatch username and password |
| Alertmanager | Telegram bot token and numeric chat ID |
| K3s etcd | etcd S3 access key, secret key, bucket name, OVH endpoint host name, OVH region |
| Argo CD | Keycloak OIDC client secret |
| Longhorn | Keycloak OIDC client secret, OAuth2 Proxy cookie secret |

Generate the Kopia repository password once, before the first Velero backup:

```bash
openssl rand -base64 48
```

Store it in Bitwarden and in the encrypted offline recovery kit. Never rotate it for an existing repository.

Generate the Longhorn OAuth2 Proxy cookie secret once and store its Base64 output in Bitwarden. The Longhorn `ExternalSecret` decodes it to the 32 raw bytes required by OAuth2 Proxy:

```bash
openssl rand -base64 32
```

Generate the Jenkins OIDC escape-hatch password and keep it only in Bitwarden and the encrypted offline recovery kit:

```bash
openssl rand -base64 32
```

Replace the three Jenkins placeholders in `apps/jenkins/secrets.yaml` with the UUIDs of the Jenkins OIDC client secret, escape-hatch username, and escape-hatch password before merging the deployment.

Replace these non-secret placeholders directly in Git:

```text
CHANGE_ME_BITWARDEN_ORGANIZATION_ID
CHANGE_ME_BITWARDEN_PROJECT_ID
CHANGE_ME_OVH_S3_ENDPOINT
CHANGE_ME_OVH_REGION
```

Find every unresolved value with:

```bash
rg -n CHANGE_ME .
```

## Keycloak clients

Create confidential clients in the `homelab` realm:

| Client | Redirect URI |
| --- | --- |
| `gitlab` | `https://gitlab.mmlinaric.com/users/auth/openid_connect/callback` |
| `forgejo` | `https://git.mmlinaric.com/user/oauth2/Keycloak/callback` |
| `grafana` | `https://grafana.mmlinaric.com/login/generic_oauth` |
| `argocd` | `https://argocd.mmlinaric.com/auth/callback` |
| `longhorn` | `https://longhorn.mmlinaric.com/oauth2/callback` |
| `dependency-track` | `https://dependency-track.mmlinaric.com/static/oidc-callback.html` |
| `jenkins` | `https://jenkins.mmlinaric.com/securityRealm/finishLogin` |

For Grafana, add a client role named `admin` and assign it only to administrators. The default mapped role is Viewer.

For Longhorn, enable client authentication and the standard authorization-code flow, require PKCE with method `S256`, and disable direct access grants. Add a client role named `admin` and assign it only to Longhorn administrators. Add an audience mapper that includes `longhorn` in both the ID and access tokens. OAuth2 Proxy rejects authenticated users who do not have the `longhorn:admin` client role.

For Dependency-Track, use a public client with client authentication disabled, the standard authorization-code flow enabled, direct access grants disabled, and PKCE method `S256`. Set the web origin to `https://dependency-track.mmlinaric.com`. No post-logout redirect URI is required. Add an `admin` client role and assign it to the `homelab-admins` group. Add a User Client Role mapper for the `dependency-track` client that emits a multivalued string claim named `dependency_track_roles` in ID tokens, access tokens, and UserInfo. Dependency-Track maps the `admin` claim value to its Administrators team.

For Jenkins, use a confidential client with client authentication enabled, the standard authorization-code flow enabled, direct access grants disabled, and required PKCE method `S256`. Set the web origin to `https://jenkins.mmlinaric.com`; add both `https://jenkins.mmlinaric.com/` and `https://jenkins.mmlinaric.com/OicLogout` as valid post-logout redirect URIs. Add an `admin` client role assigned to the `homelab-admins` group. Add a User Client Role mapper that emits the Jenkins client roles as the multivalued `jenkins_roles` claim in ID tokens, access tokens, and UserInfo. Jenkins rejects login unless that claim contains `admin`.

For Forgejo, use a confidential client with client authentication enabled, the standard authorization-code flow enabled, direct access grants disabled, and required PKCE method `S256`. Forgejo 15's OpenID Connect client automatically sends an S256 code challenge and the matching verifier. Set the web origin to `https://git.mmlinaric.com`. Add client roles named `user` and `admin`; make `admin` a composite client role that includes `user`. Assign only `admin` to `homelab-admins`, and assign `user` to every other group permitted to use Forgejo. Add a User Client Role mapper that emits the expanded client roles as the multivalued `forgejo_roles` claim in ID tokens, access tokens, and UserInfo. The mapper claim is not an OAuth scope; Forgejo requests only `openid email profile`. Forgejo rejects login without `user` and grants site administration when `admin` is present. Automatic OIDC registration is disabled: after Keycloak authenticates and authorizes a new user, Forgejo asks them to select their permanent local username without creating a local password. The authentication source does not enable `allow-username-change`, so external users cannot rename themselves later. The local bootstrap administrator remains the recovery path if Keycloak is unavailable.

Replace the five Forgejo placeholders in `apps/forgejo/secrets.yaml` with the Bitwarden UUIDs before enabling the Argo CD application. Generate the database and bootstrap administrator passwords with at least 32 random bytes.

## Offline recovery kit

Keep an encrypted copy outside the cluster and outside Bitwarden. It must contain:

- K3s server token and the K3s S3 endpoint, region, bucket, access key, and secret key
- Velero S3 credentials and Kopia repository password
- `gitlab-secrets.json`
- Forgejo bootstrap administrator credentials
- Jenkins OIDC escape-hatch credentials
- Bitwarden organization, project, and recovery details
- the Git repository URL and a read-only deploy credential
- the pinned K3s, Velero, GitLab, and CNPG versions
- a copy of `restore.md`

Update and decrypt-test the kit quarterly. Never leave a decrypted copy on the cluster node.

## Rotation

External Secrets refreshes values hourly. Most applications need a rollout after credential rotation because environment variables are read at process start. Restart only the affected workload, then verify login and backup access. The Kopia repository password is not a rotatable application credential.
