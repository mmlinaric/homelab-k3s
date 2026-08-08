# Expanding to three nodes

Do not increase application replicas merely because nodes were joined. First convert the control plane and storage to tolerate node loss.

## Join two server nodes

Give each node a static LAN address, the same K3s token, matching K3s version, and `server: https://192.168.70.5:6443` in its K3s config. Remove `cluster-init` from joining nodes. Install the same host prerequisites and kube-vip static pod manifest. Embedded etcd then forms a three-member quorum.

Keep an odd number of server nodes. Spread them across independent Proxmox failure domains when possible.

## Storage

Add a Longhorn disk on each node, verify replica scheduling, then change the default replica count from 1 to 3. Rebuild existing volumes to three healthy replicas before testing a node shutdown. Capacity must cover three copies plus backup and rebuild headroom.

Velero deploys one node-agent pod per node automatically. Keep data movement concurrency at one per node until backup duration and workload impact have been measured. The GitLab and Keycloak staging PVCs remain ReadWriteOnce and move with their owning pods.

## Workloads

- Increase Keycloak to at least two instances.
- Increase CNPG to three instances and verify synchronous replication policy and backups.
- Keep GitLab Omnibus at one replica. Omnibus is stateful and cannot become highly available by changing the StatefulSet replica count. True GitLab HA requires decomposing PostgreSQL, Redis, Gitaly, object storage, and web components.
- Run two Traefik and Cloudflared replicas with topology spread constraints.
- Add disruption budgets only after replica counts can satisfy them.

## Validation

Cordon and drain one node, then verify login, Git operations, ingress, database health, and Longhorn replica health. Repeat for each node. Finally test an abrupt single-node power loss and confirm etcd retains quorum.
