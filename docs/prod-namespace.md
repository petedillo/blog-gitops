# Production Namespace Configuration

## Overview
The `prod` namespace hosts the production environment with maximum security, reliability, and performance configurations. This is the customer-facing environment.

## Purpose
- Serve live traffic to end users
- Maximum uptime and reliability (99.9%+ SLA target)
- Enhanced security and monitoring
- Optimized resource allocation

## Namespace Configuration

### File Structure
```
kubernetes/overlays/prod/
├── kustomization.yaml
├── namespace.yaml
├── deployment.yaml (patches)
├── service.yaml (patches if needed)
├── ingress.yaml
├── configmap.yaml
├── resourcequota.yaml
├── networkpolicy.yaml
├── poddisruptionbudget.yaml
└── horizontalpodautoscaler.yaml
```

### 1. Namespace Definition

**File:** `kubernetes/overlays/prod/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: prod
  labels:
    name: prod
    environment: production
    managed-by: argocd
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
  annotations:
    description: "Production environment - live customer traffic"
```

### 2. Kustomization

**File:** `kubernetes/overlays/prod/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: prod

resources:
  - ../../base
  - namespace.yaml
  - ingress.yaml
  - resourcequota.yaml
  - networkpolicy.yaml
  - poddisruptionbudget.yaml
  - horizontalpodautoscaler.yaml

patches:
  - path: deployment.yaml
    target:
      kind: Deployment

configMapGenerator:
  - name: app-config
    behavior: merge
    literals:
      - ENVIRONMENT=prod
      - LOG_LEVEL=warn

# Production secrets managed via sealed-secrets or external secrets operator
secretGenerator: []

images:
  - name: blog-api
    newTag: v1.0.0  # Use explicit version tags, never 'latest'
  - name: blog-ui
    newTag: v1.0.0

commonLabels:
  environment: production
  tier: application

replicas:
  - name: blog-api
    count: 3
  - name: blog-ui
    count: 3
```

### 3. Deployment Patches

**File:** `kubernetes/overlays/prod/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blog-api
spec:
  replicas: 3  # High availability
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # Zero downtime deployments
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/actuator/prometheus"
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - blog-api
            topologyKey: kubernetes.io/hostname
      containers:
      - name: blog-api
        env:
        - name: APP_ENVIRONMENT
          value: "prod"
        - name: SPRING_PROFILES_ACTIVE
          value: "prod"
        - name: LOGGING_LEVEL_ROOT
          value: "WARN"
        - name: JAVA_OPTS
          value: "-Xms512m -Xmx1024m -XX:+UseG1GC"
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /api/v1/health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /api/v1/health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blog-ui
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "false"  # Static content, no metrics
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - blog-ui
            topologyKey: kubernetes.io/hostname
      containers:
      - name: blog-ui
        env:
        - name: NODE_ENV
          value: "production"
        - name: API_URL
          value: "http://blog-api.prod.svc.cluster.local:8080"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
        securityContext:
          runAsNonRoot: true
          runAsUser: 101  # nginx user
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true

---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  replicas: 1  # Single instance, future: HA with replication
  template:
    spec:
      containers:
      - name: postgres
        env:
        - name: POSTGRES_DB
          value: "blog_prod"
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 50Gi  # Larger storage for production
```

### 4. Ingress Configuration

**File:** `kubernetes/overlays/prod/ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: blog-ingress
  namespace: prod
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # Production certs
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rate-limit: "100"  # Rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "20"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - petedio-labs.com
    - www.petedio-labs.com
    secretName: blog-prod-tls
  rules:
  - host: petedio-labs.com
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
  - host: www.petedio-labs.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: blog-ui
            port:
              number: 80
```

### 5. Resource Quotas

**File:** `kubernetes/overlays/prod/resourcequota.yaml`

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: prod-quota
  namespace: prod
spec:
  hard:
    requests.cpu: "8"
    requests.memory: "16Gi"
    limits.cpu: "16"
    limits.memory: "32Gi"
    persistentvolumeclaims: "10"
    services.loadbalancers: "2"
```

### 6. Pod Disruption Budget

**File:** `kubernetes/overlays/prod/poddisruptionbudget.yaml`

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: blog-api-pdb
  namespace: prod
spec:
  minAvailable: 2  # Always keep at least 2 API pods running
  selector:
    matchLabels:
      app: blog-api

---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: blog-ui-pdb
  namespace: prod
spec:
  minAvailable: 2  # Always keep at least 2 UI pods running
  selector:
    matchLabels:
      app: blog-ui
```

### 7. Horizontal Pod Autoscaler

**File:** `kubernetes/overlays/prod/horizontalpodautoscaler.yaml`

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: blog-api-hpa
  namespace: prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: blog-api
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # Wait 5 min before scaling down
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0  # Scale up immediately
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15

---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: blog-ui-hpa
  namespace: prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: blog-ui
  minReplicas: 3
  maxReplicas: 8
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### 8. Network Policies

**File:** `kubernetes/overlays/prod/networkpolicy.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prod-default-deny
  namespace: prod
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prod-allow-ingress
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: blog-ui
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prod-allow-monitoring
  namespace: prod
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 8080

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prod-allow-internal
  namespace: prod
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector: {}
  egress:
  - to:
    - podSelector: {}
  - to:  # DNS
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  - to: []  # Allow all egress (for external APIs, etc.)
```

## ArgoCD Application

**File:** `argocd/prod-application.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: blog-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/pedrodelgadillo/blog-gitops.git
    targetRevision: main
    path: kubernetes/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: prod
  syncPolicy:
    automated:
      prune: false  # Manual pruning in prod
      selfHeal: false  # Manual sync required
    syncOptions:
    - CreateNamespace=true
  # Require manual approval for ALL prod changes
```

## Deployment Process

### Prerequisites
- [ ] All tests passing in stage
- [ ] UAT sign-off received
- [ ] Release notes prepared
- [ ] Rollback plan documented
- [ ] Team notified of deployment window

### Deployment Steps

```bash
# 1. Tag release
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0

# 2. Update image tags in kustomization.yaml
# (Should be done via PR and approved)

# 3. Manual sync via ArgoCD UI or CLI
argocd app sync blog-prod --prune=false

# 4. Monitor deployment
kubectl rollout status deployment/blog-api -n prod
kubectl rollout status deployment/blog-ui -n prod

# 5. Verify health
curl https://petedio-labs.com/api/v1/health

# 6. Monitor metrics and logs
# Check Grafana dashboards
# Review error rates in Prometheus
```

### Rollback Procedure

```bash
# Quick rollback
kubectl rollout undo deployment/blog-api -n prod
kubectl rollout undo deployment/blog-ui -n prod

# Or revert to specific revision
kubectl rollout undo deployment/blog-api -n prod --to-revision=2

# Or sync to previous Git commit
argocd app sync blog-prod --revision <previous-commit-sha>
```

## Database Management

### Production Database
- Daily automated backups (retained 30 days)
- Point-in-time recovery enabled
- Read replicas for reporting (future)
- Connection pooling configured

### Backup Commands
```bash
# Manual backup
kubectl exec -n prod postgres-0 -- pg_dump -U postgres blog_prod > backup-$(date +%Y%m%d).sql

# Restore (CAREFUL!)
kubectl exec -i -n prod postgres-0 -- psql -U postgres blog_prod < backup.sql
```

## Monitoring & Alerts

### Critical Alerts (PagerDuty)
- Pod down > 2 minutes
- Error rate > 1%
- Response time > 2 seconds (p95)
- Database connections > 80%
- Disk usage > 80%

### Dashboard Links
- Application Dashboard: `https://grafana.local/d/app-prod`
- Infrastructure Dashboard: `https://grafana.local/d/infra-prod`
- Database Dashboard: `https://grafana.local/d/db-prod`

## Security Hardening

### Pod Security
- Run as non-root user
- Read-only root filesystem
- Drop all capabilities
- No privilege escalation

### Network Security
- Default deny all traffic
- Explicit allow rules only
- No direct external access (only via ingress)
- Monitoring namespace access only

### Secrets Management
- Use Sealed Secrets or External Secrets Operator
- Rotate database passwords quarterly
- TLS certificates auto-renewed via cert-manager

## Access Control

### Production Access Policy
- **NO** direct kubectl access except in emergencies
- All changes via GitOps (PR → Review → Merge → Auto-deploy)
- Read-only access for most team members
- Audit logging enabled

### Emergency Access
```bash
# Break glass - production access
kubectl config use-context production
kubectl config set-context --current --namespace=prod

# View only
kubectl get all
kubectl logs -f deployment/blog-api

# Emergency rollback only (requires approval)
kubectl rollout undo deployment/blog-api
```

## Performance Tuning

### Database
- Configured connection pool: 20 connections
- Query timeout: 30 seconds
- Index optimization monthly
- Vacuum analyze weekly

### API
- JVM heap: 1-2GB
- G1GC garbage collector
- Request timeout: 30 seconds
- Thread pool: 200 threads

### UI
- Gzip compression enabled
- Static asset caching: 1 year
- CDN enabled (future)

## Disaster Recovery

### RTO (Recovery Time Objective)
- Target: 30 minutes

### RPO (Recovery Point Objective)
- Target: 15 minutes (database backups every 15 min)

### DR Runbook
See [disaster-recovery.md](./operations/disaster-recovery.md)

## Maintenance Windows

### Planned Maintenance
- Schedule: Sunday 2:00 AM - 4:00 AM UTC
- Frequency: Monthly
- User notification: 1 week advance

### Emergency Maintenance
- On-call rotation available 24/7
- Escalation path documented

## Related Documentation
- [Dev Namespace](../overlays/dev/namespace.yaml)
- [Stage Namespace](./stage-namespace.md)
- [Promotion Workflow](./promotion-workflow.md)
- [Disaster Recovery](./operations/disaster-recovery.md)
- [Monitoring Runbook](./operations/monitoring-alerts.md)
