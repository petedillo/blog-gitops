# Blog GitOps Repository

This repository contains Kubernetes manifests and ArgoCD applications for the PeteDillo.com blog infrastructure.

## Structure

```
argocd/
├── projects/          # ArgoCD projects
└── applications/      # ArgoCD applications

kubernetes/
├── base/             # Base Kubernetes manifests
│   ├── blog-api/
│   ├── blog-ui/
│   └── postgres/
└── overlays/         # Environment-specific overlays
    ├── dev/
    └── prod/

sealed-secrets/       # Encrypted secrets (safe for Git)
├── dev/
└── prod/
```

## Secrets Management

This repository uses Sealed Secrets for managing sensitive data:

1. **Never** commit plain Kubernetes secrets
2. All secrets must be sealed using `kubeseal`
3. Only `sealed-*.yaml` files should be committed
4. The cluster's Sealed Secrets controller decrypts them at runtime

### Creating a Sealed Secret

```bash
# Create secret locally (not committed)
kubectl create secret generic my-secret \
  --from-literal=key=value \
  --dry-run=client -o yaml > /tmp/secret.yaml

# Seal it (safe to commit)
kubeseal --format=yaml < /tmp/secret.yaml > sealed-secrets/dev/my-secret.yaml

# Clean up
rm /tmp/secret.yaml

# Commit sealed secret
git add sealed-secrets/dev/my-secret.yaml
git commit -m "Add sealed secret for..."
```

## Deployment

Applications are deployed via ArgoCD:
- UI: https://argocd-dev.toastedbytes.com
- User: admin
- Namespace: argocd

## Environments

- **dev**: Development environment (dev.petedillo.com)
- **prod**: Production environment (petedillo.com)
