# Runbook

## Provision from zero

    # 1. infra
    cd infra/terraform
    terraform init
    terraform apply

    # 2. cluster
    cd ../ansible
    ansible-playbook -i inventory.ini install-k3s.yml

    # 3. kubeconfig (pull from control plane, fix the server address)
    mkdir -p ~/.kube
    ssh -i ~/.ssh/phoenix-key ubuntu@<control-plane-ip> "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config
    chmod 600 ~/.kube/config
    sed -i "s/127.0.0.1/<control-plane-ip>/g" ~/.kube/config
    kubectl get nodes

    # 4. platform components
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/manifests/install.yaml

    # 5. secrets (NOT in git - create by hand, once, per environment)
    kubectl create secret generic taskapp-secret -n taskapp \
      --from-literal=DATABASE_HOST=postgres \
      --from-literal=DATABASE_PORT=5432 \
      --from-literal=DATABASE_NAME=taskapp \
      --from-literal=DATABASE_USER=taskapp_user \
      --from-literal=DATABASE_PASSWORD="$(openssl rand -base64 24)" \
      --from-literal=SECRET_KEY="$(openssl rand -base64 32)"

    # 6. GitOps takes over
    kubectl apply -f gitops/   # Argo CD Application pointing at manifests/
    # Argo syncs everything else: postgres, backend, frontend, ingress, HPA, NetworkPolicy

## Day-2 operations

- **Scale a tier:** edit `replicas:` in the Deployment manifest, commit, push - let
  Argo sync it (don't `kubectl scale` directly, selfHeal will revert it). Note: HPA
  already auto-scales backend (2-5) and frontend (2-4) based on CPU/memory, so manual
  scaling is rarely needed.
- **Roll back a bad deploy:** `git revert` the bad commit and push - Argo re-syncs to
  the reverted state automatically. For an immediate rollback without waiting for git,
  `argocd app rollback taskapp <revision>` via the Argo CLI/UI.
- **Run a new migration safely:** migrations run automatically as an Argo `PreSync`
  hook (`manifests/migration-job.yml`) before every sync - alembic migrations are
  idempotent, so this is safe to run repeatedly. To add a new migration, generate it
  with alembic in the backend repo, merge, and let the image rebuild/redeploy trigger
  the hook.
- **Access Argo CD UI:** `kubectl port-forward svc/argocd-server -n argocd 8080:443`,
  then browse to `https://localhost:8080`. Get the initial admin password with:
  `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
- **SSH tunnel to the API server (if kubectl times out from your dev machine):**

      screen -dmS tunnel bash -c 'while true; do ssh -i ~/.ssh/phoenix-key \
        -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
        -L 6443:localhost:6443 -N ubuntu@<control-plane-ip>; sleep 3; done'

## Incident log (real issues hit and fixed during this deployment)

1. **Wrong container images** - deployment manifests referenced a personal GHCR
   namespace/tag that didn't exist. Fixed by pointing at the instructor org's actual
   published tags.
2. **Missing Postgres entirely** - no StatefulSet had ever been applied; secret
   contained a `DATABASE_URL` shape the app didn't read. Fixed by deploying a proper
   StatefulSet + PVC and rebuilding the secret with the exact env vars the app expects
   (`DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USER`,
   `DATABASE_PASSWORD`).
3. **Frontend nginx hardcoded `backend` as upstream hostname** (baked into the image
   at build time) but the Service was named `backend-service`. Fixed by adding a
   second Service literally named `backend`.
4. **Worker node OOM/CPU starvation** (`t3.micro`, load average 30+) - traced to a
   duplicate, crash-looping Argo CD ApplicationSet controller left over in the
   `default` namespace from an earlier install attempt, restarting 1600+ times.
   Deleted the duplicate; load dropped to near-zero immediately.
5. **NetworkPolicy caused a full outage (502s)** - the k3s install actively enforces
   NetworkPolicy (don't assume Flannel never enforces it - verify per-cluster). Root
   cause was twofold: `frontend`/`backend` policies didn't grant the `ingress-nginx`
   namespace explicit access, and the migration Job's pods weren't labeled `app:
   backend`, so they were silently blocked from reaching Postgres. Fixed by adding a
   `namespaceSelector` for `ingress-nginx` and labeling the Job's pod template.
6. **Plaintext `SECRET_KEY` committed to git** - removed from git, added
   `argocd.argoproj.io/sync-options: Prune=false` to the live secret so Argo's
   selfHeal wouldn't delete it, then rotated the key.
