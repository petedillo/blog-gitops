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

---

## Comprehensive Troubleshooting Guide

### Understanding SealedSecret Behavior

#### Empty encryptedData in SealedSecret

**Symptom:** Running `kubectl get sealedsecret <name> -o yaml` shows `encryptedData: {}` or `template: {}`

**Is this a problem?** Usually **NO** - this is normal after successful decryption.

**What happens:**
1. SealedSecret applied with encrypted data
2. Controller decrypts and creates Secret
3. Controller clears the SealedSecret spec (sets to `{}`)
4. The underlying Secret remains and works fine

**Verify it's working:**
```bash
# Check if Secret exists
kubectl get secret <name> -n <namespace>

# Verify Secret has data
kubectl get secret <name> -n <namespace> -o jsonpath='{.data}' | jq

# Check pods using the secret
kubectl get pods -n <namespace>
```

**When it IS a problem:**
- Secret doesn't exist
- Secret exists but empty data
- Pods failing with "secret not found"

---

### Common Error #1: Strict Decoding Error

**Error Message:**
```
Error from server (BadRequest): error when creating "...": SealedSecret in version "v1alpha1" cannot be handled as a SealedSecret: strict decoding error: unknown field "spec.encryptedData..dockerconfigjson", unknown field "spec.template.metadata", unknown field "spec.template.type"
```

**Root Cause:** Outdated SealedSecret CRD missing `x-kubernetes-preserve-unknown-fields: true`

**Solution:**
```bash
# Update to latest SealedSecret CRD
kubectl apply -f https://raw.githubusercontent.com/bitnami-labs/sealed-secrets/main/helm/sealed-secrets/crds/bitnami.com_sealedsecrets.yaml

# Verify CRD updated
kubectl get crd sealedsecrets.bitnami.com -o yaml | grep -A 2 "encryptedData:"
# Should show: x-kubernetes-preserve-unknown-fields: true

# Now try applying your SealedSecret again
kubectl apply -f kubernetes/overlays/dev/sealed-secrets/nexus-registry.yaml
```

**Why this happens:**
- Old CRD versions had overly strict schemas
- apiextensions/v1 enforces structural schemas by default
- Requires explicit `x-kubernetes-preserve-unknown-fields` for flexible nested fields
- Affects fields like `.dockerconfigjson` (dot-prefixed keys) and template metadata

**Verification:**
```bash
# Check CRD has preserve-unknown-fields
kubectl get crd sealedsecrets.bitnami.com -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.encryptedData}' | jq

# Should show: "x-kubernetes-preserve-unknown-fields": true
```

---

### Common Error #2: Resource Already Exists

**Error Message:**
```
Resource "nexus-registry" already exists and is not managed by SealedSecret
```

**Root Cause:** Manually-created Secret conflicts with SealedSecret controller

**Solution:**
```bash
# 1. Backup existing secret (if contains important data)
kubectl get secret nexus-registry -n <namespace> -o yaml > nexus-registry-backup.yaml

# 2. Delete the manual secret
kubectl delete secret nexus-registry -n <namespace>

# 3. Wait 10-30 seconds for sealed-secrets controller to recreate it
sleep 15

# 4. Verify Secret recreated from SealedSecret
kubectl get secret nexus-registry -n <namespace>
```

**Prevention:**
- Never manually create Secrets that have corresponding SealedSecrets
- Always use SealedSecrets for GitOps-managed environments
- Delete both Secret AND SealedSecret if you need to start fresh

---

### Common Error #3: Immutable Type Field

**Error Message:**
```
Secret "nexus-registry" is invalid: type: Invalid value: "kubernetes.io/dockerconfigjson": field is immutable
```

**Root Cause:** Trying to change a Secret's type after creation

**Common scenarios:**
- Created as `Opaque`, trying to change to `kubernetes.io/tls`
- Created as `Opaque`, trying to change to `kubernetes.io/dockerconfigjson`
- Secret was created before template.type was specified in SealedSecret

**Solution:**
```bash
# 1. Delete both Secret and SealedSecret
kubectl delete secret <name> -n <namespace>
kubectl delete sealedsecret <name> -n <namespace>

# 2. Fix the SealedSecret YAML to include correct type in template
# For TLS certificates:
spec:
  template:
    type: kubernetes.io/tls
    metadata:
      name: cloudflare-cert
      namespace: <namespace>

# For Docker registry:
spec:
  template:
    type: kubernetes.io/dockerconfigjson
    metadata:
      name: nexus-registry
      namespace: <namespace>

# 3. Reapply the corrected SealedSecret
kubectl apply -f <sealed-secret-file>.yaml

# 4. Verify correct type
kubectl get secret <name> -n <namespace> -o jsonpath='{.type}' && echo
```

**Important:** Secret type field is **immutable** in Kubernetes. You cannot change it after creation - you must delete and recreate.

---

### Common Error #4: SealedSecret Not Decrypting

**Symptom:** SealedSecret exists but Secret never gets created

**Debug steps:**
```bash
# 1. Check controller logs
kubectl logs -n kube-system -l name=sealed-secrets-controller --tail=100

# 2. Check SealedSecret events
kubectl describe sealedsecret <name> -n <namespace>

# 3. Verify controller is running
kubectl get pods -n kube-system -l name=sealed-secrets-controller

# 4. Verify namespace matches
# The namespace in metadata must match the namespace you're targeting
kubectl get sealedsecret <name> -n <namespace> -o yaml | grep namespace
```

**Common causes:**

1. **Namespace mismatch**
   - Sealed for `blog-stage`, applying to `blog-dev`
   - Solution: Regenerate with correct namespace

2. **Controller not running**
   - Check: `kubectl get pods -n kube-system -l name=sealed-secrets-controller`
   - Solution: Reinstall sealed-secrets controller

3. **Cluster encryption key changed**
   - Happens if sealed-secrets controller was reinstalled
   - Solution: Re-seal all secrets with new cluster key

4. **Invalid base64 in encryptedData**
   - Corrupted YAML file
   - Solution: Regenerate the SealedSecret

5. **Wrong secret type in template**
   - Missing `type:` field for non-Opaque secrets
   - Solution: Add correct type to template section

---

### Common Error #5: Pods Can't Pull Images

**Symptom:** `ImagePullBackOff` error, "failed to pull image"

**Debug steps:**
```bash
# 1. Check nexus-registry secret exists
kubectl get secret nexus-registry -n <namespace>

# 2. Verify secret type is correct
kubectl get secret nexus-registry -n <namespace> -o jsonpath='{.type}'
# Must output: kubernetes.io/dockerconfigjson

# 3. Check deployment references the secret
kubectl get deployment <name> -n <namespace> -o yaml | grep imagePullSecrets -A 2

# 4. Verify secret has .dockerconfigjson key
kubectl get secret nexus-registry -n <namespace> -o jsonpath='{.data}' | jq
# Should show: { ".dockerconfigjson": "..." }

# 5. Decode and verify docker config format
kubectl get secret nexus-registry -n <namespace> -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq
```

**Common fixes:**

1. **Wrong secret type (Opaque instead of dockerconfigjson)**
```bash
# Delete and recreate with correct type
kubectl delete secret nexus-registry -n <namespace>
# Wait for controller to recreate from SealedSecret
sleep 10
kubectl get secret nexus-registry -n <namespace> -o jsonpath='{.type}'
```

2. **Missing imagePullSecrets reference**
```bash
# Add to deployment
spec:
  template:
    spec:
      imagePullSecrets:
      - name: nexus-registry
```

3. **Wrong credentials**
```bash
# Regenerate with correct credentials
kubectl create secret docker-registry nexus-registry \
  --docker-server=docker.toastedbytes.com \
  --docker-username=admin \
  --docker-password='correct-password' \
  --docker-email=admin@toastedbytes.com \
  --namespace=<namespace> \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-secrets/nexus-registry.yaml
```

---

### Common Error #6: Database Connection Failures

**Symptom:** API pods failing to connect, "password authentication failed"

**Debug steps:**
```bash
# 1. Check postgres-credentials secret exists
kubectl get secret postgres-credentials -n <namespace>

# 2. Get password from secret
kubectl get secret postgres-credentials -n <namespace> -o jsonpath='{.data.password}' | base64 -d

# 3. Check postgres pod is running
kubectl get pods -n <namespace> | grep postgres

# 4. Test database connection from API pod
kubectl exec -n <namespace> deployment/blog-api -- \
  curl -s localhost:8080/actuator/health/db

# 5. Check deployment uses correct secret
kubectl get deployment blog-api -n <namespace> -o yaml | grep -A 10 secretKeyRef
```

**Common fixes:**

1. **Password mismatch between secret and postgres**
```bash
# Option A: Update postgres password to match secret
kubectl exec -it -n <namespace> deployment/postgres -- psql -U postgres
# In psql:
ALTER USER postgres WITH PASSWORD 'password-from-secret';
\q

# Option B: Regenerate secret with known password
kubectl create secret generic postgres-credentials \
  --from-literal=password='your-password' \
  --namespace=<namespace> \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-secrets/postgres-credentials.yaml
```

2. **Secret key name mismatch**
```bash
# Verify key name in secret
kubectl get secret postgres-credentials -n <namespace> -o jsonpath='{.data}' | jq -r 'keys[]'

# Ensure deployment references correct key
env:
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-credentials
      key: password  # Must match key in secret
```

3. **Postgres pod not ready yet**
```bash
# Wait for postgres to be ready
kubectl wait --for=condition=ready pod -l app=postgres -n <namespace> --timeout=60s
```

---

### Controller Error Patterns in Logs

**Error: "cannot unseal: no key could decrypt secret"**
- SealedSecret was encrypted with different cluster key
- Solution: Regenerate with current cluster's public key

**Error: "failed update: Resource already exists"**
- Manual secret exists, blocking sealed-secrets controller
- Solution: Delete manual secret, let controller recreate

**Error: "Error updating SealedSecret status: not found"**
- Usually transient, controller will retry
- If persists: delete and recreate SealedSecret

---

## Emergency Secret Rotation

If secrets are compromised, follow this procedure:

```bash
# 1. Generate new sealed secrets
./scripts/generate-sealed-secrets.sh <environment>

# 2. CRITICAL: Save new credentials to password manager immediately!

# 3. Delete old SealedSecrets and Secrets
kubectl delete sealedsecrets -n blog-<env> --all
kubectl delete secrets -n blog-<env> postgres-credentials blog-app-credentials admin-credentials jwt-secret nexus-registry

# 4. Apply new sealed secrets
git add kubernetes/overlays/<env>/sealed-secrets/
git commit -m "security: Rotate <env> secrets"
git push

# 5. ArgoCD will sync and create new secrets
# Or manually apply:
kubectl apply -f kubernetes/overlays/<env>/sealed-secrets/

# 6. Update database passwords manually (if postgres already initialized)
kubectl exec -it -n blog-<env> deployment/postgres -- psql -U postgres
# In psql:
ALTER USER postgres WITH PASSWORD 'new-postgres-password';
ALTER USER blog_app WITH PASSWORD 'new-blog-app-password';
\q

# 7. Restart deployments
kubectl rollout restart deployment/blog-api -n blog-<env>
kubectl rollout restart deployment/blog-ui -n blog-<env>
kubectl rollout restart deployment/postgres -n blog-<env>

# 8. Verify all pods healthy
kubectl get pods -n blog-<env>
```

---

## Best Practices

### Secret Generation

- ✅ Generate unique secrets per environment
- ✅ Save plaintext values to password manager immediately
- ✅ Use strong random passwords (`openssl rand -base64 32`)
- ✅ Never commit plaintext secrets to git
- ✅ Always commit sealed secrets to git
- ✅ Test sealed secrets in dev before prod

### Secret Types

- ✅ Use `kubernetes.io/dockerconfigjson` for registry credentials
- ✅ Use `kubernetes.io/tls` for TLS certificates
- ✅ Use `Opaque` (default) for generic secrets
- ✅ **Always** specify type in `template` section of SealedSecret for non-Opaque types

### Troubleshooting Workflow

1. ✅ Check controller logs first: `kubectl logs -n kube-system -l name=sealed-secrets-controller --tail=100`
2. ✅ Verify namespace matches between SealedSecret and target
3. ✅ Use `describe` and `get` commands to inspect resources
4. ✅ Test secrets from within pods when possible
5. ✅ Delete and recreate if type needs to change (immutable field)

### Security

- ✅ Rotate secrets quarterly (or when compromised)
- ✅ Audit secret access regularly
- ✅ Keep sealed-secrets controller updated
- ✅ Monitor for unsealing errors
- ✅ Use different secrets for each environment
- ✅ Never reuse prod secrets in dev/stage

---

## Quick Reference Commands

### Check SealedSecret Status
```bash
# List all SealedSecrets
kubectl get sealedsecrets -n <namespace>

# View SealedSecret details
kubectl get sealedsecret <name> -n <namespace> -o yaml

# Check SealedSecret events
kubectl describe sealedsecret <name> -n <namespace>
```

### Check Secret Status
```bash
# List all Secrets
kubectl get secrets -n <namespace>

# Check Secret type
kubectl get secret <name> -n <namespace> -o jsonpath='{.type}' && echo

# View Secret data keys (not values)
kubectl get secret <name> -n <namespace> -o jsonpath='{.data}' | jq -r 'keys[]'

# Decode Secret value (careful - shows plaintext!)
kubectl get secret <name> -n <namespace> -o jsonpath='{.data.password}' | base64 -d
```

### Controller Operations
```bash
# Check controller status
kubectl get pods -n kube-system -l name=sealed-secrets-controller

# View controller logs
kubectl logs -n kube-system -l name=sealed-secrets-controller --tail=100

# Follow controller logs
kubectl logs -n kube-system -l name=sealed-secrets-controller -f

# Get controller version
kubectl get deployment sealed-secrets-controller -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### CRD Operations
```bash
# Check CRD version
kubectl get crd sealedsecrets.bitnami.com -o jsonpath='{.spec.versions[0].name}'

# Verify CRD has preserve-unknown-fields
kubectl get crd sealedsecrets.bitnami.com -o yaml | grep "x-kubernetes-preserve-unknown-fields"

# Update CRD to latest
kubectl apply -f https://raw.githubusercontent.com/bitnami-labs/sealed-secrets/main/helm/sealed-secrets/crds/bitnami.com_sealedsecrets.yaml
```

### Regenerate Secrets
```bash
# Single secret
kubectl create secret generic jwt-secret \
  --from-literal=JWT_SECRET=$(openssl rand -base64 32) \
  --namespace=<namespace> \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-secrets/jwt-secret.yaml

# Docker registry secret
kubectl create secret docker-registry nexus-registry \
  --docker-server=docker.toastedbytes.com \
  --docker-username=admin \
  --docker-password='password' \
  --docker-email=admin@toastedbytes.com \
  --namespace=<namespace> \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-secrets/nexus-registry.yaml

# All secrets for environment
./scripts/generate-sealed-secrets.sh <dev|stage|prod>
```

---

## Related Documentation

- [Environment Setup Guide](./knowledge/ENVIRONMENT-SETUP.md) - Complete environment setup
- [Network Policies](./knowledge/network-policies.md) - Network isolation
- [Bitnami Sealed Secrets GitHub](https://github.com/bitnami-labs/sealed-secrets) - Official documentation

