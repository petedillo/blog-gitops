# Network Policies & Tailscale Integration

## Overview
Network policies provide pod-level network segmentation and security within the Kubernetes cluster. This document covers both standard Kubernetes NetworkPolicies and Tailscale integration for secure remote access.

## Goals
- Restrict dev namespace access to Tailscale network only
- Implement zero-trust networking
- Prevent lateral movement between namespaces
- Allow monitoring and logging from dedicated namespace
- Maintain production isolation

## Tailscale Integration

### Why Tailscale for Dev?
- Secure remote access without exposing dev environment publicly
- Zero-trust authentication via Tailscale
- Easy team member onboarding/offboarding
- Works seamlessly with remote development
- No VPN configuration required

### Tailscale Setup

#### 1. Install Tailscale Operator

**File:** `kubernetes/base/tailscale/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: tailscale
```

**File:** `kubernetes/base/tailscale/operator.yaml`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tailscale-operator
  namespace: tailscale

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: tailscale-operator
rules:
- apiGroups: [""]
  resources: ["services", "secrets", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tailscale-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: tailscale-operator
subjects:
- kind: ServiceAccount
  name: tailscale-operator
  namespace: tailscale

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tailscale-operator
  namespace: tailscale
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tailscale-operator
  template:
    metadata:
      labels:
        app: tailscale-operator
    spec:
      serviceAccountName: tailscale-operator
      containers:
      - name: operator
        image: tailscale/k8s-operator:latest
        env:
        - name: TS_AUTHKEY
          valueFrom:
            secretKeyRef:
              name: tailscale-auth
              key: authkey
        - name: TS_KUBE_SECRET
          value: tailscale-state
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
```

#### 2. Create Tailscale Auth Secret

```bash
# Generate auth key from Tailscale admin console
# https://login.tailscale.com/admin/settings/keys

# Create secret
kubectl create secret generic tailscale-auth \
  --from-literal=authkey=tskey-auth-xxxx \
  -n tailscale
```

#### 3. Expose Dev Services via Tailscale

**File:** `kubernetes/overlays/dev/ingress-tailscale.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: blog-dev-tailscale
  namespace: dev
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "blog-dev"
    tailscale.com/tags: "tag:k8s,tag:dev"
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
  selector:
    app: blog-ui
  ports:
  - port: 80
    targetPort: 80
    name: http

---
apiVersion: v1
kind: Service
metadata:
  name: blog-api-dev-tailscale
  namespace: dev
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "blog-api-dev"
    tailscale.com/tags: "tag:k8s,tag:dev"
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
  selector:
    app: blog-api
  ports:
  - port: 8080
    targetPort: 8080
    name: http
```

## Network Policies

### Dev Namespace Policies

#### 1. Default Deny All Traffic

**File:** `kubernetes/overlays/dev/networkpolicy-default-deny.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: dev
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

#### 2. Allow Tailscale Ingress Only

**File:** `kubernetes/overlays/dev/networkpolicy-allow-tailscale.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-tailscale-ingress
  namespace: dev
spec:
  podSelector:
    matchLabels:
      app: blog-ui
  policyTypes:
  - Ingress
  ingress:
  # Allow from Tailscale operator
  - from:
    - namespaceSelector:
        matchLabels:
          name: tailscale
  # Allow from other pods in same namespace
  - from:
    - podSelector: {}

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-from-ui
  namespace: dev
spec:
  podSelector:
    matchLabels:
      app: blog-api
  policyTypes:
  - Ingress
  ingress:
  # Allow from UI pods
  - from:
    - podSelector:
        matchLabels:
          app: blog-ui
  # Allow from Tailscale
  - from:
    - namespaceSelector:
        matchLabels:
          name: tailscale
```

#### 3. Allow Egress for External Services

**File:** `kubernetes/overlays/dev/networkpolicy-allow-egress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress
  namespace: dev
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  # Allow to other pods in namespace
  - to:
    - podSelector: {}
  # Allow external traffic (Internet)
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443  # HTTPS
    - protocol: TCP
      port: 80   # HTTP
```

#### 4. Allow Monitoring

**File:** `kubernetes/overlays/dev/networkpolicy-allow-monitoring.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: dev
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
      port: 8080  # Metrics port
```

### Stage Namespace Policies

**File:** `kubernetes/overlays/stage/networkpolicy.yaml`

```yaml
# Default deny
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: stage
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

---
# Allow from nginx ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-controller
  namespace: stage
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
# Allow internal communication
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-internal
  namespace: stage
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

---
# Allow egress to internet and DNS
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress
  namespace: stage
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  - to: []  # Allow all egress

---
# Allow monitoring
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: stage
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
```

### Production Namespace Policies

See [prod-namespace.md](./prod-namespace.md) for production-specific network policies with stricter controls.

## Access Patterns

### Dev Environment Access
```
Developer (Tailscale)
    ↓
Tailscale Network (100.x.x.x)
    ↓
Tailscale LoadBalancer Service
    ↓
Blog UI Pod (dev namespace)
    ↓
Blog API Pod (dev namespace)
    ↓
Postgres Pod (dev namespace)
```

### Stage Environment Access
```
Public Internet
    ↓
NGINX Ingress Controller
    ↓
Blog UI Pod (stage namespace)
    ↓
Blog API Pod (stage namespace)
    ↓
Postgres Pod (stage namespace)
```

### Production Environment Access
```
Public Internet
    ↓
NGINX Ingress Controller (rate limited)
    ↓
Blog UI Pod (prod namespace)
    ↓
Blog API Pod (prod namespace)
    ↓
Postgres Pod (prod namespace)
```

## Testing Network Policies

### Test Dev Namespace Isolation

```bash
# Should FAIL - external access blocked
curl http://blog-dev.local

# Should SUCCEED - Tailscale access
# First, connect to Tailscale network
tailscale up

# Then access via Tailscale hostname
curl http://blog-dev.tail-xxxxx.ts.net
```

### Test Internal Communication

```bash
# From UI pod, should reach API
kubectl exec -n dev -it blog-ui-xxx -- curl http://blog-api.dev.svc.cluster.local:8080/api/v1/health

# From API pod, should reach Postgres
kubectl exec -n dev -it blog-api-xxx -- curl postgres.dev.svc.cluster.local:5432
```

### Test Cross-Namespace Isolation

```bash
# From dev pod, should NOT reach stage API
kubectl exec -n dev -it blog-api-xxx -- curl http://blog-api.stage.svc.cluster.local:8080/api/v1/health
# Expected: Connection timeout
```

### Test Monitoring Access

```bash
# From Prometheus pod, should reach all namespaces
kubectl exec -n monitoring prometheus-0 -- curl http://blog-api.dev.svc.cluster.local:8080/actuator/prometheus
kubectl exec -n monitoring prometheus-0 -- curl http://blog-api.stage.svc.cluster.local:8080/actuator/prometheus
kubectl exec -n monitoring prometheus-0 -- curl http://blog-api.prod.svc.cluster.local:8080/actuator/prometheus
```

## Troubleshooting

### Network Policy Not Working

```bash
# Check if network plugin supports NetworkPolicy
kubectl get nodes -o wide

# Verify CNI (should be Calico, Cilium, or Weave)
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave'

# Check NetworkPolicy is applied
kubectl get networkpolicies -n dev

# Describe NetworkPolicy
kubectl describe networkpolicy default-deny-all -n dev
```

### Tailscale Connection Issues

```bash
# Check Tailscale operator status
kubectl get pods -n tailscale

# Check Tailscale operator logs
kubectl logs -n tailscale deployment/tailscale-operator

# Verify Tailscale service
kubectl get svc -n dev | grep tailscale

# Check service annotations
kubectl describe svc blog-dev-tailscale -n dev
```

### Debugging Connection Failures

```bash
# Test from a debug pod
kubectl run debug --image=nicolaka/netshoot -it --rm -n dev -- bash

# Inside debug pod:
# Test DNS
nslookup blog-api.dev.svc.cluster.local

# Test connectivity
curl http://blog-api.dev.svc.cluster.local:8080/api/v1/health

# Test external connectivity
curl https://google.com
```

## Best Practices

### Network Policy Design
- ✅ Start with deny-all, then explicitly allow
- ✅ Use labels for pod selection
- ✅ Separate policies for ingress and egress
- ✅ Document why each policy exists
- ❌ Don't use overly broad selectors
- ❌ Don't allow all egress unless necessary

### Tailscale Security
- ✅ Use auth keys with expiration
- ✅ Tag services appropriately
- ✅ Rotate auth keys quarterly
- ✅ Use ACLs in Tailscale admin console
- ❌ Don't share auth keys
- ❌ Don't use overly permissive tags

### Testing
- ✅ Test policies before production
- ✅ Use network policy auditing tools
- ✅ Document expected behavior
- ✅ Test negative cases (should fail)
- ❌ Don't assume policies work without testing

## Future Enhancements

- [ ] Implement Cilium for advanced network policies
- [ ] Add network policy auditing/visualization
- [ ] Implement service mesh (Istio/Linkerd)
- [ ] Add WAF (Web Application Firewall)
- [ ] Implement DDoS protection
- [ ] Add geographic restrictions

## Related Documentation
- [Dev Namespace](../overlays/dev/namespace.yaml)
- [Stage Namespace](./stage-namespace.md)
- [Prod Namespace](./prod-namespace.md)
- [Operations Runbook](./operations/daily-operations.md)
