# Architecture

## 1. Topology diagram

    Internet --DNS(duckdns)--> phoenix-chantel.duckdns.org
          |
          v
    ingress-nginx controller (node: ip-10-0-1-55, control-plane)
          |  TLS terminated here - cert-manager + Let's Encrypt (ClusterIssuer: letsencrypt-prod)
          |
          |-- /    --> frontend Service --> frontend Pods (nodes: ip-10-0-1-55, ip-10-0-1-235)
          |
          `-- /api --> backend Service  --> backend Pods (spread via topologySpreadConstraints
                            |                across all 3 nodes, 2-5 replicas via HPA)
                            v
                  postgres Service (headless) --> postgres-0 StatefulSet
                                                    (PVC on node ip-10-0-1-85)

## 2. Cluster

- 3-node k3s cluster on AWS EC2: 1 control-plane + 2 workers, all `t3.small`
- Provisioned with Terraform (VPC, subnet, security groups, EC2 instances, S3+DynamoDB
  remote state), configured with Ansible (k3s-server / k3s-agent roles)
- CNI: Flannel (k3s default). **Note:** this k3s install does enforce NetworkPolicy
  (not all Flannel setups do - this cost real debugging time to confirm, see RUNBOOK
  incident log)

## 3. Application tiers

- **frontend**: React (Vite) served by nginx, 2 replicas, HPA-capable (2-4)
- **backend**: Flask + gunicorn (3 workers per pod), 2 replicas baseline, HPA to 5
  under load, connects to Postgres via `DATABASE_HOST=postgres`
- **postgres**: single-instance StatefulSet, persistent volume (2Gi), headless Service
  for stable DNS (`postgres.taskapp.svc.cluster.local`)
- **migrations**: run as a dedicated Kubernetes Job (`backend-migrate`), wired as an
  Argo CD `PreSync` hook - runs once before each sync, not baked into the app
  container's entrypoint (avoids replica race conditions at 2+ backend replicas)

## 4. GitOps

- Argo CD watches `chantel50/capstone-phoenix` main branch, `manifests/` path
- `automated: {prune: true, selfHeal: true}` - cluster state is enforced to match git
- Secrets are **not** stored in git (see RUNBOOK) - managed out-of-band via `kubectl`

## 5. Security posture

- All 3 backend/frontend/postgres pods run with `securityContext`: dropped Linux
  capabilities (`ALL`, with narrow explicit re-adds where required - e.g. frontend
  nginx needs `NET_BIND_SERVICE`, `CHOWN`, `SETUID`, `SETGID` to bind port 80 and
  manage its cache dirs as root; backend runs fully non-root as UID 10001)
- NetworkPolicy restricts ingress traffic per tier: postgres only accepts traffic from
  `app=backend` pods; backend only accepts traffic from `app=frontend` pods and the
  `ingress-nginx` namespace (the ingress controller talks to backend directly for
  `/api` routes, bypassing frontend)
- TLS via cert-manager + Let's Encrypt, auto-renewed
