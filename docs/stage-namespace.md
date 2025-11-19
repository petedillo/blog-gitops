# Stage Namespace Configuration

## Overview
The `stage` namespace provides a pre-production environment for final testing before production deployment. It mirrors production configuration but with relaxed resource limits and potentially uses test data.

## Purpose
- Final validation before production
- Integration testing with production-like configuration
- Stakeholder demos and UAT (User Acceptance Testing)
- Performance testing under realistic conditions

## Namespace Configuration

### File Structure
```
kubernetes/overlays/stage/
├── kustomization.yaml
├── namespace.yaml
├── deployment.yaml (patches)
├── service.yaml (patches if needed)
├── ingress.yaml
└── configmap.yaml (stage-specific configs)
```

### 1. Namespace Definition

**File:** `kubernetes/overlays/stage/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: stage
  labels:
    name: stage
    environment: staging
    managed-by: argocd
  annotations:
    description: "Staging environment for pre-production testing"
```

### 2. Kustomization

**File:** `kubernetes/overlays/stage/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: stage

resources:
  - ../../base
  - namespace.yaml
  - ingress.yaml

patches:
  - path: deployment.yaml
    target:
      kind: Deployment

configMapGenerator:
  - name: app-config
    behavior: merge
    literals:
      - ENVIRONMENT=stage
      - LOG_LEVEL=info

secretGenerator:
  - name: postgres-credentials
    behavior: replace
    literals:
      - POSTGRES_PASSWORD=stage-password-change-me

images:
  - name: blog-api
    newTag: stage-latest
  - name: blog-ui
    newTag: stage-latest

commonLabels:
  environment: staging
  tier: application
```

### 3. Deployment Patches

**File:** `kubernetes/overlays/stage/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blog-api
spec:
  replicas: 2  # More replicas than dev, less than prod
  template:
    spec:
      containers:
      - name: blog-api
        env:
        - name: APP_ENVIRONMENT
          value: "stage"
        - name: SPRING_PROFILES_ACTIVE
          value: "stage"
        - name: LOGGING_LEVEL_ROOT
          value: "INFO"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blog-ui
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: blog-ui
        env:
        - name: NODE_ENV
          value: "production"  # Use production build
        - name: API_URL
          value: "http://blog-api.stage.svc.cluster.local:8080"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: postgres
        env:
        - name: POSTGRES_DB
          value: "blog_stage"
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
          subPath: stage  # Separate data directory
```

### 4. Ingress Configuration

**File:** `kubernetes/overlays/stage/ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: blog-ingress
  namespace: stage
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-staging"  # Use staging certs
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - stage.petedio-labs.com
    secretName: blog-stage-tls
  rules:
  - host: stage.petedio-labs.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: blog-ui
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: blog-api
            port:
              number: 8080
```

## Resource Quotas

**File:** `kubernetes/overlays/stage/resourcequota.yaml`

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: stage-quota
  namespace: stage
spec:
  hard:
    requests.cpu: "4"
    requests.memory: "8Gi"
    limits.cpu: "8"
    limits.memory: "16Gi"
    persistentvolumeclaims: "5"
    services.loadbalancers: "1"
```

## Network Policies

**File:** `kubernetes/overlays/stage/networkpolicy.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: stage-network-policy
  namespace: stage
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow from nginx ingress
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  # Allow from monitoring namespace
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
  # Allow internal namespace traffic
  - from:
    - podSelector: {}
  egress:
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  # Allow external traffic (internet)
  - to:
    - namespaceSelector: {}
  # Allow internal namespace traffic
  - to:
    - podSelector: {}
```

## ArgoCD Application

**File:** `argocd/stage-application.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: blog-stage
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/pedrodelgadillo/blog-gitops.git
    targetRevision: main
    path: kubernetes/overlays/stage
  destination:
    server: https://kubernetes.default.svc
    namespace: stage
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
  # Require manual approval for stage deploys
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
```

## Monitoring Configuration

### ServiceMonitor

**File:** `kubernetes/overlays/stage/servicemonitor.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: blog-api-stage
  namespace: stage
  labels:
    environment: staging
spec:
  selector:
    matchLabels:
      app: blog-api
  endpoints:
  - port: http
    path: /actuator/prometheus
    interval: 30s
```

## Database Management

### Initialization
```bash
# Create stage database
kubectl exec -n stage postgres-0 -- psql -U postgres -c "CREATE DATABASE blog_stage;"

# Import sanitized production data (optional)
kubectl exec -n stage postgres-0 -- psql -U postgres blog_stage < stage-data.sql

# Or start fresh with test data
kubectl exec -n stage postgres-0 -- psql -U postgres blog_stage < test-data.sql
```

### Backup Strategy
- Daily automated backups
- Retained for 7 days
- Can restore from production (sanitized)

## Deployment Process

### 1. Apply Namespace
```bash
kubectl apply -f kubernetes/overlays/stage/namespace.yaml
```

### 2. Deploy via ArgoCD
```bash
# Create ArgoCD application
kubectl apply -f argocd/stage-application.yaml

# Or sync via CLI
argocd app create blog-stage \
  --repo https://github.com/pedrodelgadillo/blog-gitops.git \
  --path kubernetes/overlays/stage \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace stage \
  --sync-policy automated

# Sync application
argocd app sync blog-stage
```

### 3. Verify Deployment
```bash
# Check namespace
kubectl get all -n stage

# Check pods
kubectl get pods -n stage

# Check services
kubectl get svc -n stage

# Check ingress
kubectl get ingress -n stage

# Test API health
curl https://stage.petedio-labs.com/api/v1/health
```

## Environment-Specific Configuration

### Database Connection
```properties
# Stage database (separate from dev and prod)
spring.datasource.url=jdbc:postgresql://postgres.stage.svc.cluster.local:5432/blog_stage
spring.datasource.username=postgres
spring.datasource.password=${POSTGRES_PASSWORD}
```

### External Services
- Use staging APIs for third-party services
- Separate analytics tracking
- Test email configuration (catch-all or mailtrap)

## Testing in Stage

### Smoke Tests
```bash
# Health check
curl https://stage.petedio-labs.com/api/v1/health

# Get posts
curl https://stage.petedio-labs.com/api/v1/posts

# UI accessibility
curl -I https://stage.petedio-labs.com
```

### Load Testing
```bash
# Run load tests against stage
k6 run --vus 50 --duration 5m load-test.js
```

## Promotion Workflow

Stage → Prod promotion process:
1. Deploy to stage automatically on merge to `main`
2. Run automated tests
3. Manual UAT sign-off required
4. Tag release: `v1.2.3`
5. Promote to prod (see [promotion-workflow.md](./promotion-workflow.md))

## Access Control

### Who Can Access Stage?
- Development team (full access)
- QA team (read/write for testing)
- Stakeholders (read-only UI access)
- CI/CD pipelines (automated testing)

### Kubectl Access
```bash
# Get stage namespace access
kubectl config set-context --current --namespace=stage

# View stage resources
kubectl get all
```

## Related Documentation
- [Dev Namespace](../overlays/dev/namespace.yaml)
- [Prod Namespace](./prod-namespace.md)
- [Promotion Workflow](./promotion-workflow.md)
- [Network Policies](./network-policies.md)
