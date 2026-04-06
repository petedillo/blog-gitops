# Blog GitOps Repository

Infrastructure as Code for PeteDillo blog platform using GitOps principles with ArgoCD and Kubernetes.

## Repository Structure (Post-Migration)

This directory contains **blog workload manifests only**.

### What's Managed Here:
- Kubernetes manifests for blog-api, blog-ui, postgres
- Environment-specific overlays (`dev`, `prod`)
- Application-specific configurations

### What's Managed in `infrastructure/kubernetes/` within the monorepo:
- ArgoCD Application and AppProject definitions
- SealedSecrets (cluster-level secret management)
- Observability (Prometheus, Grafana)
- ArgoCD Image Updater configuration

### Repository Dependencies:
- **Monorepo**: https://github.com/PeteDio-Labs/petedio-labs-gitops
- **Control Plane Path**: `infrastructure/kubernetes/`
- **This Directory Path**: `blog-infrastructure/kubernetes/`

## Quick Links

- [Environment Setup Guide](./knowledge/ENVIRONMENT-SETUP.md) - Complete setup for dev/stage/prod
- [Sealed Secrets Guide](./SEALED-SECRETS-DEPLOYMENT.md) - Secret management and troubleshooting
- [Network Policies](./knowledge/network-policies.md) - Network isolation configuration

## Architecture

```
GitHub (GitOps Source of Truth)
   ↓
ArgoCD (Continuous Delivery)
   ↓
Kubernetes Cluster (k3s)
   ├── blog-dev (namespace)
   └── blog-prod (namespace)

Docker Images:
  Nexus Registry (docker.toastedbytes.com)
    ├── blog-api (digest pinned per overlay)
    ├── blog-ui (digest pinned per overlay)
    └── blog-agent (digest pinned in dev)
```

## Repository Structure

```
blog-infrastructure/kubernetes/
├── argocd/
│   ├── applications/          # ArgoCD Application manifests
│   │   ├── blog-dev.yaml      # Dev environment
│   │   ├── blog-prod.yaml     # Production environment
│   │   └── argocd-image-updater.yaml
│   └── projects/              # ArgoCD Project definitions
│
├── kubernetes/
│   ├── base/                  # Base Kustomize configurations
│   │   ├── blog-api/          # API deployment, service, ingress
│   │   ├── blog-ui/           # UI deployment, service, ingress
│   │   ├── postgres/          # PostgreSQL database
│   │   ├── monitoring/        # Prometheus & Grafana
│   │   ├── media-storage/     # Persistent storage for media
│   │   └── argocd-image-updater/
│   │
│   └── overlays/              # Environment-specific configs
│       ├── dev/               # Development environment
│       │   ├── sealed-secrets/
│       │   │   ├── jwt-secret.yaml
│       │   │   ├── postgres-credentials.yaml
│       │   │   ├── blog-app-credentials.yaml
│       │   │   ├── admin-credentials.yaml
│       │   │   └── nexus-registry.yaml
│       │   ├── .argocd-source-blog-dev.yaml
│       │   ├── blog-api-ingress.yaml
│       │   ├── blog-ui-ingress.yaml
│       │   ├── blog-agent-configmap-patch.yaml
│       │   └── kustomization.yaml
│       │
│       └── prod/              # Production environment
│           ├── sealed-secrets/
│           ├── blog-ui-deployment-patch.yaml
│           ├── blog-api-service-patch.yaml
│           ├── blog-ui-service-patch.yaml
│           ├── deployment-patch.yaml
│           └── kustomization.yaml
│
├── scripts/
│   └── generate-sealed-secrets.sh  # Generate encrypted secrets
│
├── knowledge/
│   ├── ENVIRONMENT-SETUP.md   # Complete setup guide
│   └── network-policies.md    # Network security docs
│
└── SEALED-SECRETS-DEPLOYMENT.md  # Secret management guide
```

## Environments

| Environment | Namespace | Domain | Auto-Sync | Image Updater | Status |
|-------------|-----------|--------|-----------|---------------|--------|
| Dev | blog-dev | dev.petedillo.com | ✅ Yes | ❌ No | ✅ Active |
| Prod | blog-prod | petedillo.com | ❌ Manual | ❌ No | ⚙️ Configured |

### Dev Environment

- **Access:** `https://dev.petedillo.com` through Cloudflare Tunnel → public cluster ingress
- **Purpose:** Development and testing
- **Auto-Deploy:** Yes (ArgoCD auto-sync on git changes)
- **Routing:** `/` → `blog-ui`, `/api/v1` and `/admin` → `blog-api`
- **Image Updates:** Manual digest updates via `.argocd-source-blog-dev.yaml`
- **Secrets:** 5 sealed secrets (jwt, postgres, blog-app, admin, nexus-registry)

### Production Environment

- **Access:** Public (petedillo.com)
- **Purpose:** Live production site
- **Auto-Deploy:** No (manual sync required)
- **Image Tag:** Versioned tags (e.g., v1.2.3)
- **Secrets:** Dedicated prod sealed secrets and registry credentials

See [knowledge/ENVIRONMENT-SETUP.md](./knowledge/ENVIRONMENT-SETUP.md) for production setup instructions when ready to deploy.

## Quick Start

### Prerequisites

```bash
# Install required tools
brew install kubectl kubeseal kustomize

# Verify cluster access
kubectl get nodes

# Verify ArgoCD access
kubectl get applications -n argocd
```

### Deploy to Dev

```bash
# 1. Generate dev sealed secrets
./scripts/generate-sealed-secrets.sh dev
# Save the output credentials to your password manager!

# 2. Commit and push
git add kubernetes/overlays/dev/sealed-secrets/
git commit -m "Generate dev sealed secrets"
git push

# 3. Sync via ArgoCD (auto-syncs by default)
kubectl patch application blog-dev -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# 4. Verify deployment
kubectl get pods -n blog-dev
curl https://dev.petedillo.com/api/v1/health
```

### Dev Routing Notes

The dev overlay now owns explicit ingress resources:

- `kubernetes/overlays/dev/blog-ui-ingress.yaml` routes `https://dev.petedillo.com/` to `blog-ui`
- `kubernetes/overlays/dev/blog-api-ingress.yaml` routes `https://dev.petedillo.com/api/v1` and `/admin` to `blog-api`
- The Cloudflare tunnel points `dev.petedillo.com` at the cluster ingress address, not the standalone UI service IP

## Secret Management

Secrets are managed using [Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets):

- **Encrypted with cluster public key** - secrets can only be decrypted in target cluster
- **Safe to commit to Git** - encrypted secrets stored in repository
- **Namespace-scoped** - dev secrets can't be used in stage or prod
- **Automatically decrypted** - sealed-secrets controller creates Kubernetes Secrets

### Generate Secrets

```bash
# Generate all secrets for an environment
./scripts/generate-sealed-secrets.sh <dev|stage|prod>

# Or generate individual secrets manually
kubectl create secret generic jwt-secret \
  --from-literal=JWT_SECRET=$(openssl rand -base64 32) \
  --namespace=blog-dev \
  --dry-run=client -o yaml | kubeseal -o yaml > kubernetes/overlays/dev/sealed-secrets/jwt-secret.yaml
```

### Secret Types

The repository uses three types of Kubernetes secrets:

1. **Opaque** (default) - Generic secrets
   - `jwt-secret`, `postgres-credentials`, `blog-app-credentials`, `admin-credentials`

2. **kubernetes.io/dockerconfigjson** - Docker registry credentials
   - `nexus-registry` - pulls images from private Nexus registry

3. **kubernetes.io/tls** - TLS certificates (stage/prod only)
   - `cloudflare-cert` - HTTPS certificates

See [SEALED-SECRETS-DEPLOYMENT.md](./SEALED-SECRETS-DEPLOYMENT.md) for detailed information and troubleshooting.

## GitOps Workflow

### Development Workflow

1. Code changes merged to `main` branch
2. CI/CD builds and pushes image to Nexus registry
3. Image tag updated in git (manual or automated)
4. ArgoCD detects git change
5. ArgoCD auto-syncs to dev namespace
6. Pods restart with new image

### Production Workflow (Manual - Planned)

1. Tag release (e.g., `v1.2.3`)
2. Update prod kustomization with release tag
3. Create PR for team review
4. Approvals required
5. Manual ArgoCD sync after merge
6. Monitor deployment for 30 minutes

## Key Components

### Base Configurations

- **blog-api** - Spring Boot REST API (port 8080)
- **blog-ui** - React frontend (port 80)
- **postgres** - PostgreSQL 15 database with persistent storage
- **monitoring** - Prometheus & Grafana stack for observability
- **media-storage** - Persistent volume for uploaded images/media

### Environment Overlays

Each overlay (`dev`/`prod`) customizes:

- **Sealed secrets** - Encrypted credentials specific to environment
- **Domain names** - `dev.petedillo.com` vs `petedillo.com`
- **Resource limits** - Higher in production
- **Replicas** - More replicas in production
- **Network policies** - Stricter isolation in prod
- **Ingress configuration** - Dev uses explicit ingress manifests; prod stays overlay-driven

## ArgoCD Applications

### blog-dev

- **Repository:** https://github.com/PeteDio-Labs/petedio-labs-gitops
- **Path:** blog-infrastructure/kubernetes/kubernetes/overlays/dev
- **Sync:** Automated (prune + self-heal enabled)
- **Image Updater:** Disabled (manual image updates)

### blog-prod

- **Repository:** https://github.com/PeteDio-Labs/petedio-labs-gitops
- **Path:** blog-infrastructure/kubernetes/kubernetes/overlays/prod
- **Sync:** Manual only (no auto-sync or self-heal)
- **Image Updater:** Disabled (versioned tags only)

## Common Operations

### View Application Status

```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# View detailed status
kubectl describe application blog-dev -n argocd

# Check sync status
kubectl get application blog-dev -n argocd -o jsonpath='{.status.sync.status}{"  "}{.status.health.status}' && echo
```

### View Logs

```bash
# API logs
kubectl logs -f -n blog-dev deployment/blog-api

# UI logs
kubectl logs -f -n blog-dev deployment/blog-ui

# Database logs
kubectl logs -f -n blog-dev deployment/postgres

# All pods in namespace
kubectl logs -f -n blog-dev --all-containers=true
```

### Restart Deployments

```bash
# Restart API
kubectl rollout restart deployment/blog-api -n blog-dev

# Restart UI
kubectl rollout restart deployment/blog-ui -n blog-dev

# Check rollout status
kubectl rollout status deployment/blog-api -n blog-dev
```

### Check Resource Usage

```bash
# Pod resource usage
kubectl top pods -n blog-dev

# Node resource usage
kubectl top nodes

# Describe pod resources
kubectl describe pod <pod-name> -n blog-dev | grep -A 5 "Requests"
```

### Manual ArgoCD Sync

```bash
# Sync dev environment
kubectl patch application blog-dev -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Check sync result
kubectl get application blog-dev -n argocd
```

### Verify Secrets

```bash
# List all SealedSecrets
kubectl get sealedsecrets -n blog-dev

# List all Secrets
kubectl get secrets -n blog-dev

# Check specific secret type
kubectl get secret nexus-registry -n blog-dev -o jsonpath='{.type}' && echo

# Verify secret has data (without exposing)
kubectl get secret postgres-credentials -n blog-dev -o jsonpath='{.data.password}' | wc -c
```

## Monitoring

### Access Grafana

```bash
# Port-forward to Grafana
kubectl port-forward -n blog-dev svc/grafana 3000:80

# Open http://localhost:3000
# Credentials in admin-credentials sealed secret
```

### Access Prometheus

```bash
# Port-forward to Prometheus
kubectl port-forward -n blog-dev svc/prometheus 9090:9090

# Open http://localhost:9090
```

### Health Checks

```bash
# API health
curl https://dev.petedillo.com/api/v1/health

# From within cluster
kubectl run curl-test --image=curlimages/curl -i --rm --restart=Never -- \
  curl -s http://blog-api.blog-dev.svc.cluster.local:8080/api/v1/health
```

## Security

- **Sealed Secrets** - All sensitive data encrypted at rest
- **Network Policies** - Restricts pod-to-pod communication
- **RBAC** - Role-based access control configured
- **Private Registry** - Images pulled from private Nexus registry
- **TLS** - All ingresses use HTTPS (Cloudflare origin certificates)
- **Pod Security** - Non-root users, read-only filesystems (planned for prod)

## Troubleshooting

### Common Issues

**Pods can't pull images**
- Check `nexus-registry` secret exists and has correct type
- Verify `imagePullSecrets` reference in deployment
- See [SEALED-SECRETS-DEPLOYMENT.md](./SEALED-SECRETS-DEPLOYMENT.md#troubleshooting)

**Database connection failures**
- Verify `postgres-credentials` secret exists
- Check postgres pod is running
- Ensure secret is mounted in API deployment
- See [knowledge/ENVIRONMENT-SETUP.md](./knowledge/ENVIRONMENT-SETUP.md#database-connection-failures)

**SealedSecret not decrypting**
- Check sealed-secrets controller logs
- Verify namespace matches between SealedSecret and target
- Update CRD if getting "strict decoding" errors
- See [SEALED-SECRETS-DEPLOYMENT.md](./SEALED-SECRETS-DEPLOYMENT.md#troubleshooting)

**ArgoCD won't sync**
- Check application conditions for errors
- Verify kustomize builds locally
- Look for manifest generation errors
- See [knowledge/ENVIRONMENT-SETUP.md](./knowledge/ENVIRONMENT-SETUP.md#argocd-wont-sync)

### Get Help

1. Check [knowledge/ENVIRONMENT-SETUP.md](./knowledge/ENVIRONMENT-SETUP.md) for detailed setup instructions
2. Review [SEALED-SECRETS-DEPLOYMENT.md](./SEALED-SECRETS-DEPLOYMENT.md) for secret troubleshooting
3. Check sealed-secrets controller logs: `kubectl logs -n kube-system -l name=sealed-secrets-controller`
4. Check ArgoCD application status: `kubectl describe application blog-dev -n argocd`
5. Verify kustomize builds: `kubectl kustomize kubernetes/overlays/dev`

## Contributing

1. Create feature branch from `main`
2. Make changes
3. Test in dev environment
4. Create PR for review
5. Merge to `main` after approval
6. ArgoCD auto-syncs to dev

## Related Repositories

- **blog-api** - Spring Boot REST API backend
- **blog-ui** - React frontend application
- **petedio-labs-gitops** - Monorepo containing this `blog-infrastructure/kubernetes/` workload directory

## License

Private repository - All rights reserved
