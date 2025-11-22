# Blog GitOps Repository

This repository contains Kubernetes manifests and ArgoCD applications for the PeteDillo.com blog infrastructure.

## Structure

```
argocd/
├── projects/              # ArgoCD projects
└── applications/          # ArgoCD applications
    ├── blog-dev.yaml      # Blog dev environment
    └── argocd-image-updater.yaml  # Image updater

kubernetes/
├── base/                  # Base Kubernetes manifests
│   ├── blog-api/
│   ├── blog-ui/
│   ├── postgres/
│   └── argocd-image-updater/  # Image updater config
└── overlays/              # Environment-specific overlays
    ├── dev/
    │   └── .argocd-source-blog-dev.yaml  # Auto-generated image overrides
    └── prod/
```

## Automated Image Updates

This repository uses **ArgoCD Image Updater** to automatically deploy new container images.

### How It Works

1. Push code to `blog-api` or `blog-ui` repository
2. GitHub Actions builds and pushes Docker image with `develop-latest` tag
3. ArgoCD Image Updater polls the registry every 2 minutes
4. When a new image digest is detected, it commits to `.argocd-source-blog-dev.yaml`
5. ArgoCD syncs the new image to the cluster

### Configuration

Image updater annotations are defined in `argocd/applications/blog-dev.yaml`:

### Registry Configuration

Private registry credentials are stored in `argocd/nexus-registry-creds` secret and configured in the Image Updater Helm values.

## Deployment

Applications are deployed via ArgoCD:
- UI: https://argocd-dev.toastedbytes.com

## Environments

- **dev**: Development environment (dev.petedillo.com)
- **prod**: Production environment (petedillo.com)
