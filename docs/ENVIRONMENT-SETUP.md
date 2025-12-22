# Environment Setup Guide

## Overview

Infrastructure for PeteDillo blog platform using GitOps (ArgoCD) and Kubernetes (k3s). This guide covers setting up dev and stage environments, with production documented but not yet implemented.

## Environments

| Environment | Namespace | Domain | Auto-Sync | Purpose |
|-------------|-----------|--------|-----------|---------|
| Dev | blog-dev | dev.petedillo.com | Yes | Development/testing |
| Stage | blog-stage | stage.petedillo.com | Yes | Pre-prod validation |
| Prod | blog-prod | petedillo.com | Manual | Production (planned) |

## Prerequisites

### Required Tools

- kubectl v1.27+
- kubeseal v0.18.0+
- kustomize v5.0+
- Access to k3s cluster
- GitHub repository access

### Install kubeseal

macOS:
```bash
brew install kubeseal
```

Linux:
```bash
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### Verify Cluster Access

```bash
# Verify kubectl access
kubectl get nodes

# Verify sealed-secrets controller is running
kubectl get pods -n kube-system -l name=sealed-secrets-controller

# Check SealedSecret CRD version
kubectl get crd sealedsecrets.bitnami.com -o jsonpath='{.spec.versions[0].name}'
# Should output: v1alpha1
```

## Dev Environment

### Purpose

- Development and testing
- Accessed via VPN/Tailscale or direct ingress
- Auto-deploys on git changes via ArgoCD

### Secrets Required

The dev environment needs 5 sealed secrets:

1. **jwt-secret** - JWT authentication token for API
2. **postgres-credentials** - PostgreSQL root password
3. **blog-app-credentials** - blog_app DB role username/password
4. **admin-credentials** - API admin username/password
5. **nexus-registry** - Docker registry credentials for pulling images

### Generate Dev Secrets

**Option 1: Use the script (generates all 5 secrets)**

```bash
cd /path/to/blog-gitops

# Generate all dev sealed secrets
./scripts/generate-sealed-secrets.sh dev

# You'll be prompted for:
# - Nexus registry username
# - Nexus registry password
# - Nexus registry email

# The script generates random passwords for other secrets
# SAVE THE OUTPUT CREDENTIALS SECURELY!
```

The script creates these files:
- `kubernetes/overlays/dev/sealed-secrets/jwt-secret.yaml`
- `kubernetes/overlays/dev/sealed-secrets/postgres-credentials.yaml`
- `kubernetes/overlays/dev/sealed-secrets/admin-credentials.yaml`
- `kubernetes/overlays/dev/sealed-secrets/blog-app-credentials.yaml`
- `kubernetes/overlays/dev/sealed-secrets/nexus-registry.yaml`

**Option 2: Generate manually**

If you need to create individual secrets:

```bash
# Set namespace
NAMESPACE="blog-dev"
OVERLAY_PATH="kubernetes/overlays/dev/sealed-secrets"

# 1. JWT Secret
kubectl create secret generic jwt-secret \
  --from-literal=JWT_SECRET=$(openssl rand -base64 32) \
  --namespace=${NAMESPACE} \
  --dry-run=client -o yaml | kubeseal -o yaml > ${OVERLAY_PATH}/jwt-secret.yaml

# 2. Postgres credentials
kubectl create secret generic postgres-credentials \
  --from-literal=password=$(openssl rand -base64 32) \
  --namespace=${NAMESPACE} \
  --dry-run=client -o yaml | kubeseal -o yaml > ${OVERLAY_PATH}/postgres-credentials.yaml

# 3. Blog app credentials
kubectl create secret generic blog-app-credentials \
  --from-literal=username=blog_app \
  --from-literal=password=$(openssl rand -base64 32) \
  --namespace=${NAMESPACE} \
  --dry-run=client -o yaml | kubeseal -o yaml > ${OVERLAY_PATH}/blog-app-credentials.yaml

# 4. Admin credentials
kubectl create secret generic admin-credentials \
  --from-literal=ADMIN_USERNAME=admin \
  --from-literal=ADMIN_PASSWORD=$(openssl rand -base64 32) \
  --namespace=${NAMESPACE} \
  --dry-run=client -o yaml | kubeseal -o yaml > ${OVERLAY_PATH}/admin-credentials.yaml

# 5. Nexus registry (Docker registry)
kubectl create secret docker-registry nexus-registry \
  --docker-server=docker.toastedbytes.com \
  --docker-username=admin \
  --docker-password='your-password' \
  --docker-email=admin@toastedbytes.com \
  --namespace=${NAMESPACE} \
  --dry-run=client -o yaml | kubeseal -o yaml > ${OVERLAY_PATH}/nexus-registry.yaml
```

### Deploy Dev Environment

```bash
# 1. Commit sealed secrets (they're encrypted, safe to commit)
git add kubernetes/overlays/dev/sealed-secrets/
git commit -m "Generate dev sealed secrets"
git push

# 2. ArgoCD will auto-sync (or manually sync)
kubectl patch application blog-dev -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# 3. Wait for deployment
kubectl get pods -n blog-dev -w

# 4. Verify all sealed secrets exist
kubectl get sealedsecrets -n blog-dev

# 5. Verify underlying secrets were created
kubectl get secrets -n blog-dev

# 6. Check application health
curl https://dev.petedillo.com/api/v1/health
```

### Verify Dev Secrets

```bash
# Check all 5 SealedSecrets exist
kubectl get sealedsecrets -n blog-dev
# Should show: admin-credentials, blog-app-credentials, jwt-secret, nexus-registry, postgres-credentials

# Check all 5 Secrets exist
kubectl get secrets -n blog-dev | grep -E "admin|blog-app|jwt|nexus|postgres"

# Verify nexus-registry has correct type
kubectl get secret nexus-registry -n blog-dev -o jsonpath='{.type}'
# Should output: kubernetes.io/dockerconfigjson

# Check pods are healthy
kubectl get pods -n blog-dev
# All should be Running
```

## Stage Environment

### Purpose

- Pre-production validation
- Public access (stage.petedillo.com)
- Auto-deploys via ArgoCD Image Updater on `stage-latest` tag
- Production-like data (sanitized)

### Secrets Required

Same 5 secrets as dev, plus:

6. **cloudflare-cert** - TLS certificate (type: kubernetes.io/tls)

### Generate Stage Secrets

```bash
# Generate all stage sealed secrets
./scripts/generate-sealed-secrets.sh stage

# For TLS certificate (if not using script)
kubectl create secret tls cloudflare-cert \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem \
  --namespace=blog-stage \
  --dry-run=client -o yaml | kubeseal -o yaml > kubernetes/overlays/stage/sealed-secrets/cloudflare-cert.yaml
```

### Deploy Stage Environment

```bash
git add kubernetes/overlays/stage/sealed-secrets/
git commit -m "Generate stage sealed secrets"
git push

kubectl patch application blog-stage -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Verify
kubectl get pods -n blog-stage
curl https://stage.petedillo.com/api/v1/health
```

## Production Environment (Planned)

### Overview

Production environment is **documented but not yet implemented**. When ready, it will follow the same pattern as stage with stricter controls.

### When Ready to Implement

Production will require:

1. **Infrastructure**
   - Create prod overlay structure (`kubernetes/overlays/prod/`)
   - Higher resource limits and replica counts
   - Pod disruption budgets for high availability
   - Horizontal pod autoscaling

2. **Secrets**
   - Generate prod sealed secrets (unique passwords, not reused from stage)
   - Separate Nexus registry credentials (optional)
   - Production TLS certificates

3. **ArgoCD Configuration**
   - Create ArgoCD Application with manual sync only (no auto-sync)
   - Require approvals for all production changes
   - Configure sync waves for ordered deployment

4. **Security & Networking**
   - Stricter network policies
   - Resource quotas
   - Pod security standards (restricted)

5. **Monitoring & Alerting**
   - Production-specific Prometheus alerts
   - PagerDuty integration
   - Enhanced logging and tracing

### Production Domains & Scaling

- **Domain:** petedillo.com
- **API Replicas:** 3 (minimum)
- **UI Replicas:** 2 (minimum)
- **Database:** Consider managed PostgreSQL or HA setup
- **Backup Strategy:** Automated daily backups with 30-day retention

### Reference Implementation

Use stage overlay as template:
```bash
# Copy stage structure as starting point
cp -r kubernetes/overlays/stage kubernetes/overlays/prod

# Update namespace references
find kubernetes/overlays/prod -type f -exec sed -i '' 's/blog-stage/blog-prod/g' {} +

# Update domains
find kubernetes/overlays/prod -type f -exec sed -i '' 's/stage\.petedillo\.com/petedillo.com/g' {} +

# Increase replicas and resources in patches
# Configure manual-sync ArgoCD application
```

## Sealed Secrets

### How It Works

1. **Generate plaintext secret** using `kubectl create secret --dry-run`
2. **Pipe through kubeseal** to encrypt with cluster public key
3. **Commit encrypted SealedSecret** to git (safe!)
4. **Sealed-secrets controller** decrypts in-cluster automatically
5. **Creates normal Kubernetes Secret** for pods to consume

### Secret Flow Diagram

```
Developer                    Git Repository              Kubernetes Cluster
    |                              |                              |
    | kubectl create secret        |                              |
    | --dry-run | kubeseal         |                              |
    |----------------------------->|                              |
    |     (encrypted YAML)         |                              |
    |                              |                              |
    |         git push             |                              |
    |----------------------------->|                              |
    |                              |                              |
    |                              |     ArgoCD detects change    |
    |                              |----------------------------->|
    |                              |                              |
    |                              |  Applies SealedSecret CR     |
    |                              |----------------------------->|
    |                              |                              |
    |                              |       sealed-secrets         |
    |                              |       controller decrypts    |
    |                              |       creates Secret         |
    |                              |              |               |
    |                              |              v               |
    |                              |         Secret (decrypted)   |
    |                              |              |               |
    |                              |         Pods consume         |
```

### Verify Sealed Secrets

```bash
# Check SealedSecrets exist
kubectl get sealedsecrets -n blog-dev

# Check underlying Secrets created
kubectl get secrets -n blog-dev

# Verify secret has data (without exposing value)
kubectl get secret postgres-credentials -n blog-dev -o jsonpath='{.data.password}' | wc -c
# Should output non-zero number

# Check sealed-secrets controller logs
kubectl logs -n kube-system -l name=sealed-secrets-controller --tail=50
```

### Secret Types

Kubernetes supports different secret types. The `type` field must be specified in the SealedSecret `template` section:

**Opaque (default)** - Generic secrets
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: postgres-credentials
  namespace: blog-dev
spec:
  encryptedData:
    password: AgC...
  template:
    metadata:
      name: postgres-credentials
      namespace: blog-dev
    # No type specified = Opaque (default)
```

**TLS certificates**
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: cloudflare-cert
  namespace: blog-stage
spec:
  encryptedData:
    tls.crt: AgC...
    tls.key: AgC...
  template:
    type: kubernetes.io/tls  # Must specify type!
    metadata:
      name: cloudflare-cert
      namespace: blog-stage
```

**Docker registry**
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: nexus-registry
  namespace: blog-dev
spec:
  encryptedData:
    .dockerconfigjson: AgC...
  template:
    type: kubernetes.io/dockerconfigjson  # Must specify type!
    metadata:
      name: nexus-registry
      namespace: blog-dev
```

### Important Notes on Secret Types

- The `type` field is **immutable** - once a Secret is created, you cannot change its type
- If you need to change a Secret's type, you must delete the Secret and SealedSecret, then recreate
- Always specify the correct type in the SealedSecret `template` section
- Docker registry secrets MUST use `type: kubernetes.io/dockerconfigjson` with key `.dockerconfigjson`

## ArgoCD Applications

### Dev Application

- **Name:** blog-dev
- **Source:** This repository
- **Path:** kubernetes/overlays/dev
- **Sync:** Automated (prune: true, selfHeal: true)
- **Image Updater:** Disabled

### Stage Application

- **Name:** blog-stage
- **Source:** This repository
- **Path:** kubernetes/overlays/stage
- **Sync:** Automated (prune: true, selfHeal: true)
- **Image Updater:** Enabled (tracks `stage-latest` tag)

### Prod Application (Future)

- **Name:** blog-prod
- **Source:** This repository
- **Path:** kubernetes/overlays/prod
- **Sync:** Manual only (no auto-sync)
- **Image Updater:** Disabled
- **Approvals:** Required for all changes

## Deployment Workflow

### Development Flow

1. Code changes merged to `main`
2. CI/CD builds and pushes image to Nexus with dev tag
3. Update image tag in git (manual or automated)
4. ArgoCD detects change and auto-syncs to dev namespace
5. Pods restart with new image

### Stage Flow

1. Push image tagged `stage-latest` to Nexus
2. ArgoCD Image Updater detects new digest
3. Updates `kubernetes/overlays/stage/kustomization.yaml` in git
4. Commits change automatically
5. ArgoCD auto-syncs to stage namespace

### Production Flow (Future)

1. Tag release (e.g., v1.2.3)
2. Update prod kustomization manually
3. Create PR for review
4. Team approval required
5. Manual ArgoCD sync after merge

## Validation & Health Checks

### Pod Health

```bash
# Check all pods in namespace
kubectl get pods -n blog-dev

# Detailed pod status
kubectl describe pod <pod-name> -n blog-dev

# Pod logs
kubectl logs -f deployment/blog-api -n blog-dev
kubectl logs -f deployment/blog-ui -n blog-dev
kubectl logs -f deployment/postgres -n blog-dev
```

### Application Health

```bash
# API health endpoint
curl https://dev.petedillo.com/api/v1/health

# Check from within cluster
kubectl run curl-test --image=curlimages/curl -i --rm --restart=Never -- \
  curl -s http://blog-api.blog-dev.svc.cluster.local:8080/api/v1/health
```

### Database Health

```bash
# Connect to postgres
kubectl exec -it -n blog-dev deployment/postgres -- psql -U postgres

# In psql:
\l                          # List databases
\c blog_dev                 # Connect to blog_dev database
\du                         # List users
SELECT version();           # Check version
\q                          # Quit

# Test connectivity from API pod
kubectl exec -n blog-dev deployment/blog-api -- \
  curl -s localhost:8080/actuator/health/db
```

### Secret Validation

```bash
# Verify SealedSecret exists
kubectl get sealedsecret postgres-credentials -n blog-dev

# Verify underlying Secret exists
kubectl get secret postgres-credentials -n blog-dev

# Check secret type
kubectl get secret nexus-registry -n blog-dev -o jsonpath='{.type}'
# Should output: kubernetes.io/dockerconfigjson

# Verify secret has data (without exposing value)
kubectl get secret postgres-credentials -n blog-dev -o jsonpath='{.data.password}' | wc -c
# Should output non-zero number (base64 encoded length)

# Decode and check password (careful - shows plaintext!)
kubectl get secret postgres-credentials -n blog-dev -o jsonpath='{.data.password}' | base64 -d
```

### ArgoCD Sync Status

```bash
# Check application sync status
kubectl get application blog-dev -n argocd -o jsonpath='{.status.sync.status}{"  "}{.status.health.status}' && echo

# View detailed application status
kubectl describe application blog-dev -n argocd

# Check for sync errors
kubectl get application blog-dev -n argocd -o jsonpath='{.status.conditions}' | jq
```

## Troubleshooting

See [SEALED-SECRETS-DEPLOYMENT.md](../SEALED-SECRETS-DEPLOYMENT.md) for detailed sealed secrets troubleshooting.

### Common Issues

#### Pods Can't Pull Images

**Symptom:** `ImagePullBackOff` error

**Check:**
```bash
# Verify nexus-registry secret exists
kubectl get secret nexus-registry -n blog-dev

# Verify secret type is correct
kubectl get secret nexus-registry -n blog-dev -o jsonpath='{.type}'
# Must output: kubernetes.io/dockerconfigjson

# Check deployment references the secret
kubectl get deployment blog-api -n blog-dev -o yaml | grep imagePullSecrets -A 2
```

**Fix:**
```bash
# If secret has wrong type, delete and recreate
kubectl delete secret nexus-registry -n blog-dev
# Wait 10 seconds for sealed-secrets controller to recreate it
kubectl get secret nexus-registry -n blog-dev -o jsonpath='{.type}'
```

#### Database Connection Failures

**Symptom:** API logs show "password authentication failed"

**Check:**
```bash
# Get password from secret
kubectl get secret postgres-credentials -n blog-dev -o jsonpath='{.data.password}' | base64 -d

# Check postgres logs
kubectl logs -n blog-dev deployment/postgres --tail=50

# Verify postgres is running
kubectl get pods -n blog-dev | grep postgres
```

**Fix:**
```bash
# Connect to postgres and update password to match secret
kubectl exec -it -n blog-dev deployment/postgres -- psql -U postgres

# In psql:
ALTER USER postgres WITH PASSWORD 'password-from-secret';
\q

# Restart API pods
kubectl rollout restart deployment/blog-api -n blog-dev
```

#### SealedSecret Not Decrypting

**Symptom:** SealedSecret exists but Secret never gets created

**Check:**
```bash
# Check controller logs
kubectl logs -n kube-system -l name=sealed-secrets-controller --tail=100

# Check SealedSecret events
kubectl describe sealedsecret <name> -n blog-dev

# Verify controller is running
kubectl get pods -n kube-system -l name=sealed-secrets-controller
```

**Common causes:**
- Namespace mismatch (sealed for blog-stage, applying to blog-dev)
- Controller not running
- Cluster encryption key changed (need to re-seal)
- CRD missing `x-kubernetes-preserve-unknown-fields` (update CRD)

#### ArgoCD Won't Sync

**Symptom:** Application stuck in "OutOfSync" or "Unknown" status

**Check:**
```bash
# Check application status
kubectl get application blog-dev -n argocd -o jsonpath='{.status.conditions}' | jq

# Check for manifest generation errors
kubectl get application blog-dev -n argocd -o jsonpath='{.status.operationState.message}'

# Verify kustomize builds locally
cd blog-gitops
kubectl kustomize kubernetes/overlays/dev
```

**Fix:**
```bash
# Force refresh
kubectl patch application blog-dev -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Or delete and recreate application
kubectl delete application blog-dev -n argocd
kubectl apply -f argocd/applications/blog-dev.yaml
```

## Resource Management

### View Resource Usage

```bash
# Pod resource usage
kubectl top pods -n blog-dev

# Node resource usage
kubectl top nodes

# Resource requests vs limits
kubectl describe pod <pod-name> -n blog-dev | grep -A 5 "Requests"
```

### Common Maintenance

```bash
# Restart deployment
kubectl rollout restart deployment/blog-api -n blog-dev

# Check rollout status
kubectl rollout status deployment/blog-api -n blog-dev

# View rollout history
kubectl rollout history deployment/blog-api -n blog-dev

# Rollback to previous version
kubectl rollout undo deployment/blog-api -n blog-dev

# Scale deployment
kubectl scale deployment/blog-api -n blog-dev --replicas=3
```

## Security Best Practices

### Sealed Secrets

- ✅ Generate unique secrets per environment
- ✅ Save plaintext values to password manager immediately
- ✅ Use strong random passwords (`openssl rand -base64 32`)
- ✅ Never commit plaintext secrets to git
- ✅ Always commit sealed secrets to git
- ✅ Rotate secrets quarterly (or when compromised)

### Secret Types

- ✅ Use `kubernetes.io/dockerconfigjson` for registry credentials
- ✅ Use `kubernetes.io/tls` for TLS certificates
- ✅ Use `Opaque` (default) for generic secrets
- ✅ Always specify type in template section of SealedSecret

### Access Control

- ✅ Limit kubectl access to production
- ✅ Use read-only access for most team members
- ✅ Require approvals for production changes
- ✅ Audit all production access

## Related Documentation

- [Sealed Secrets Deployment](../SEALED-SECRETS-DEPLOYMENT.md) - Detailed sealed secrets guide with troubleshooting
- [Network Policies](./network-policies.md) - Network isolation configuration
- [Daily Operations](./operations/daily-operations.md) - Common operational tasks (if exists)
- [ArgoCD Applications](../argocd/applications/) - Application definitions

## Support

For issues or questions:
1. Check this guide first
2. Review [SEALED-SECRETS-DEPLOYMENT.md](../SEALED-SECRETS-DEPLOYMENT.md) troubleshooting section
3. Check sealed-secrets controller logs
4. Check ArgoCD application status
5. Verify kustomize builds locally
