# Stage & Production Deployment Guide

This guide provides a **reproducible, automated process** for deploying to stage and production environments.

## Overview

Our deployment uses:
- **ArgoCD** for GitOps continuous deployment
- **Sealed Secrets** for secure credential management (encrypted, safe to commit)
- **Kustomize** for environment-specific configurations
- **Cloudflare Tunnel** for secure ingress

## Quick Start

### 1. Generate Sealed Secrets (One-time per environment)

```bash
# For Stage
./scripts/generate-sealed-secrets.sh stage

# For Production (DO THIS SEPARATELY - different secrets!)
./scripts/generate-sealed-secrets.sh prod
```

This will:
- Generate random JWT secret (48 characters)
- Generate random Postgres password (32 characters)
- Generate random admin password (32 characters)
- Encrypt them with Sealed Secrets (safe to commit)
- Display credentials for your records

**⚠️ CRITICAL**: Save the displayed credentials in your password manager! You won't be able to recover them.

### 2. Update Kustomization Files

After generating secrets, add them to the kustomization.yaml:

#### Stage (`kubernetes/overlays/stage/kustomization.yaml`)
```yaml
resources:
  - sealed-secrets/jwt-secret.yaml
  - sealed-secrets/postgres-credentials.yaml
  - sealed-secrets/blog-app-credentials.yaml
  - sealed-secrets/cloudflare-cert.yaml
```

#### Production (`kubernetes/overlays/prod/kustomization.yaml`)
```yaml
resources:
  - sealed-secrets/jwt-secret.yaml
  - sealed-secrets/postgres-credentials.yaml
  - sealed-secrets/blog-app-credentials.yaml
  - sealed-secrets/cloudflare-cert.yaml
```

### 3. Deploy via ArgoCD

#### Stage (Automatic deployment)
```bash
# ArgoCD will automatically deploy when changes are pushed to main
git add kubernetes/overlays/stage/
git commit -m "feat: deploy stage with sealed secrets"
git push
```

#### Production (Manual deployment)
```bash
# ArgoCD requires manual sync for production
argocd app sync blog-prod --prune

# Or via kubectl patch
kubectl patch application blog-prod -n argocd \
  --type merge \
  -p '{"spec":{"syncPolicy":{"syncOptions":["Prune=true"]}}}'
```

---

## Environment Checklist

### Pre-Deployment

- [ ] All sealed secrets generated and saved
- [ ] Credentials stored in password manager
- [ ] Docker images built and tagged
- [ ] DNS records pointing to ingress (if applicable)
- [ ] Cloudflare tunnel configured
- [ ] Network policies reviewed

### Post-Deployment

```bash
# Check deployment status
kubectl get all -n blog-stage
kubectl get all -n blog-prod

# Check sealed secrets are decrypted
kubectl get secrets -n blog-stage
kubectl get secrets -n blog-prod

# Verify database initialization
kubectl logs -n blog-stage postgres-0 | grep "Flyway"
kubectl logs -n blog-prod postgres-0 | grep "Flyway"

# Test API health
curl https://stage.petedillo.com/api/v1/health
curl https://petedillo.com/api/v1/health
```

---

## Troubleshooting

### Sealed Secrets Not Decrypting

```bash
# Verify Sealed Secrets controller is running
kubectl get pods -n kube-system | grep sealed

# Check secret encryption key
kubectl get sealedsecrets.bitnami.com -n kube-system

# Reseal a secret if key changed
kubectl create secret generic my-secret -n my-namespace \
  --dry-run=client -o yaml | kubeseal -o yaml
```

### Database Migration Failed

```bash
# Check Flyway migration status
kubectl logs deployment/blog-api -n blog-stage | grep -i flyway

# View migration files in container
kubectl exec -it postgres-0 -n blog-stage -- \
  psql -U petedillo -d petedillo_blog \
  -c "SELECT * FROM flyway_schema_history;"
```

### Credentials Not Working

```bash
# Verify sealed secret contains credentials
kubectl get secret postgres-credentials -n blog-stage -o yaml

# Check environment variables in pod
kubectl set env pods -n blog-stage --all --list | grep POSTGRES

# If wrong, regenerate:
./scripts/generate-sealed-secrets.sh stage
```

---

## Security Best Practices

1. **Never commit unencrypted secrets** to Git
2. **Use different secrets** for each environment
3. **Rotate secrets regularly** (quarterly recommended)
4. **Store credentials** in password manager or Vault
5. **Monitor access** to production credentials
6. **Use sealed secrets** which are namespace-bound (can't be reused)

---

## Reproducible Production Deployment

To deploy to production on a new cluster:

```bash
# 1. Install prerequisites
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml -n kube-system

# 2. Generate prod secrets (with different values than stage!)
./scripts/generate-sealed-secrets.sh prod

# 3. Create ArgoCD application
kubectl apply -f argocd/applications/blog-prod.yaml

# 4. Monitor deployment
kubectl get application blog-prod -n argocd -w

# 5. Verify
curl https://petedillo.com/api/v1/health
```

That's it! The entire production deployment is reproducible and automated.

