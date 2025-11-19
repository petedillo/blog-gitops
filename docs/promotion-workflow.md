# Environment Promotion Workflow

## Overview
This document defines the promotion process for deploying code changes through dev → stage → prod environments with proper gates and validations.

## Promotion Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     DEVELOPMENT (dev)                           │
│                                                                 │
│  • Auto-deploy on every commit to 'main'                       │
│  • Accessible via Tailscale only                               │
│  • Test data, frequent changes                                 │
│  • No approval required                                        │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         │ Automated Tests Pass
                         │ Manual QA Sign-off
                         ↓
┌─────────────────────────────────────────────────────────────────┐
│                      STAGING (stage)                            │
│                                                                 │
│  • Auto-deploy on merge to 'main' after tests pass            │
│  • Public access (stage.petedio-labs.com)                     │
│  • Sanitized production-like data                             │
│  • Requires: Automated tests + Manual approval                │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         │ UAT Sign-off
                         │ Release Tag Created
                         │ Manual Promotion
                         ↓
┌─────────────────────────────────────────────────────────────────┐
│                    PRODUCTION (prod)                            │
│                                                                 │
│  • Manual sync only (via ArgoCD)                               │
│  • Public access (petedio-labs.com)                           │
│  • Real customer data                                          │
│  • Requires: Full approval chain + release tag                │
└─────────────────────────────────────────────────────────────────┘
```

## Deployment Gates

### Dev → Stage
**Automated** promotion if all conditions met:

1. ✅ All unit tests pass
2. ✅ All integration tests pass
3. ✅ Build succeeds
4. ✅ Code merged to `main` branch

**Manual** gates (optional):
- Developer sign-off (optional)
- Basic smoke tests completed

### Stage → Prod
**Manual** promotion required with:

1. ✅ All automated tests pass in stage
2. ✅ Manual UAT (User Acceptance Testing) completed
3. ✅ QA sign-off received
4. ✅ Release notes prepared
5. ✅ Git tag created (e.g., `v1.2.3`)
6. ✅ Change advisory sent to team
7. ✅ Rollback plan documented
8. ✅ On-call engineer notified

## Promotion Process

### Step 1: Development

```bash
# Developer workflow
git checkout -b feature/new-blog-post-feature
# ... make changes ...
git add .
git commit -m "Add new blog post feature"
git push origin feature/new-blog-post-feature

# Create PR
gh pr create --title "Add new blog post feature" --body "Description..."

# After review and approval
gh pr merge
```

**Result:** Auto-deploys to `dev` namespace via ArgoCD

### Step 2: Verify in Dev

```bash
# Connect to Tailscale
tailscale up

# Access dev environment
curl http://blog-dev.tail-xxxxx.ts.net/api/v1/health

# Manual testing
# Open http://blog-dev.tail-xxxxx.ts.net in browser
# Test new feature functionality
```

### Step 3: Promote to Stage

**Automated** (if tests pass):

```bash
# CI/CD automatically promotes to stage on merge to main
# GitHub Actions workflow handles this:

# .github/workflows/deploy-stage.yml
name: Deploy to Stage
on:
  push:
    branches: [main]
jobs:
  test-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Run tests
        run: ./mvnw test

      - name: Build and push image
        run: |
          docker build -t blog-api:stage-${GITHUB_SHA::8} .
          docker push blog-api:stage-${GITHUB_SHA::8}

      - name: Update GitOps repo
        run: |
          cd blog-gitops
          kustomize edit set image blog-api=blog-api:stage-${GITHUB_SHA::8}
          git commit -am "Deploy ${GITHUB_SHA::8} to stage"
          git push
```

**Result:** Auto-deploys to `stage` namespace via ArgoCD

### Step 4: Verify in Stage

```bash
# Access stage environment (public)
curl https://stage.petedio-labs.com/api/v1/health

# Run automated tests against stage
npm run test:e2e --env=stage

# Manual UAT
# Invite stakeholders to test: https://stage.petedio-labs.com
# Fill out UAT checklist (see below)
```

**UAT Checklist:**
- [ ] All features work as expected
- [ ] No regressions in existing functionality
- [ ] Performance is acceptable
- [ ] UI/UX is correct
- [ ] Mobile responsiveness works
- [ ] No console errors
- [ ] Analytics tracking works

### Step 5: Prepare for Production

```bash
# Create release tag
git tag -a v1.2.3 -m "Release v1.2.3: Add new blog post feature"
git push origin v1.2.3

# Generate release notes
gh release create v1.2.3 --generate-notes

# Update changelog
echo "## v1.2.3 - $(date +%Y-%m-%d)" >> CHANGELOG.md
echo "### Added" >> CHANGELOG.md
echo "- New blog post feature" >> CHANGELOG.md
git add CHANGELOG.md
git commit -m "Update changelog for v1.2.3"
git push
```

### Step 6: Deploy to Production

**Manual sync via ArgoCD:**

```bash
# 1. Update image tag in prod kustomization
cd blog-gitops/kubernetes/overlays/prod
kustomize edit set image blog-api=blog-api:v1.2.3
kustomize edit set image blog-ui=blog-ui:v1.2.3
git add kustomization.yaml
git commit -m "Promote v1.2.3 to production"
git push

# 2. Create PR for production deployment
gh pr create \
  --title "Deploy v1.2.3 to Production" \
  --body "UAT Completed ✅\nRelease notes: https://github.com/.../releases/v1.2.3"

# 3. After approval, merge PR
gh pr merge

# 4. Manually sync via ArgoCD (does NOT auto-sync)
argocd app sync blog-prod

# 5. Monitor deployment
kubectl rollout status deployment/blog-api -n prod
kubectl rollout status deployment/blog-ui -n prod

# 6. Verify production
curl https://petedio-labs.com/api/v1/health
```

### Step 7: Post-Deployment Verification

```bash
# Check application health
curl https://petedio-labs.com/api/v1/info

# Monitor error rates in Grafana
# https://grafana.local/d/app-prod

# Check logs for errors
kubectl logs -f -n prod deployment/blog-api --tail=100

# Monitor metrics
kubectl top pods -n prod

# Verify database connectivity
kubectl exec -n prod blog-api-xxx -- curl localhost:8080/api/v1/health
```

**Monitoring Checklist (first 30 minutes):**
- [ ] Error rate < 1%
- [ ] Response time p95 < 2 seconds
- [ ] No 500 errors
- [ ] Database connections healthy
- [ ] Memory usage normal
- [ ] CPU usage normal
- [ ] No pod restarts

### Step 8: Rollback (if needed)

```bash
# Quick rollback to previous version
kubectl rollout undo deployment/blog-api -n prod
kubectl rollout undo deployment/blog-ui -n prod

# Or revert GitOps repo
cd blog-gitops
git revert HEAD
git push

# ArgoCD will automatically sync to previous version
argocd app sync blog-prod
```

## Automation with GitHub Actions

### Dev Deployment (Automatic)

**File:** `.github/workflows/deploy-dev.yml`

```yaml
name: Deploy to Dev
on:
  push:
    branches: [main]
jobs:
  deploy-dev:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Build and push dev image
        run: |
          docker build -t blog-api:dev-${GITHUB_SHA::8} .
          docker push blog-api:dev-${GITHUB_SHA::8}

      - name: Update dev kustomization
        run: |
          cd blog-gitops/kubernetes/overlays/dev
          kustomize edit set image blog-api=blog-api:dev-${GITHUB_SHA::8}
          git commit -am "Deploy ${GITHUB_SHA::8} to dev"
          git push
```

### Stage Deployment (Automatic after tests)

**File:** `.github/workflows/deploy-stage.yml`

```yaml
name: Deploy to Stage
on:
  push:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run unit tests
        run: ./mvnw test
      - name: Run integration tests
        run: ./mvnw verify

  deploy-stage:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - name: Build and push stage image
        run: |
          docker build -t blog-api:stage-${GITHUB_SHA::8} .
          docker push blog-api:stage-${GITHUB_SHA::8}

      - name: Update stage kustomization
        run: |
          cd blog-gitops/kubernetes/overlays/stage
          kustomize edit set image blog-api=blog-api:stage-${GITHUB_SHA::8}
          git commit -am "Deploy ${GITHUB_SHA::8} to stage"
          git push
```

### Production Deployment (Manual)

**File:** `.github/workflows/deploy-prod.yml`

```yaml
name: Deploy to Production
on:
  workflow_dispatch:  # Manual trigger only
    inputs:
      tag:
        description: 'Release tag (e.g., v1.2.3)'
        required: true
jobs:
  deploy-prod:
    runs-on: ubuntu-latest
    environment: production  # Requires approval in GitHub
    steps:
      - uses: actions/checkout@v3

      - name: Update prod kustomization
        run: |
          cd blog-gitops/kubernetes/overlays/prod
          kustomize edit set image blog-api=blog-api:${{ github.event.inputs.tag }}
          kustomize edit set image blog-ui=blog-ui:${{ github.event.inputs.tag }}
          git commit -am "Deploy ${{ github.event.inputs.tag }} to production"
          git push

      - name: Create deployment record
        run: |
          echo "Deployed ${{ github.event.inputs.tag }} at $(date)" >> deployments.log
          git add deployments.log
          git commit -m "Record production deployment"
          git push
```

## Rollback Procedures

### Emergency Rollback (< 5 minutes)

```bash
# Immediate rollback to previous deployment
kubectl rollout undo deployment/blog-api -n prod
kubectl rollout undo deployment/blog-ui -n prod
kubectl rollout undo deployment/postgres -n prod
```

### Controlled Rollback (< 15 minutes)

```bash
# 1. Identify previous working version
kubectl rollout history deployment/blog-api -n prod

# 2. Revert to specific revision
kubectl rollout undo deployment/blog-api -n prod --to-revision=5

# 3. Or revert GitOps repo to previous tag
cd blog-gitops
git log --oneline
git revert <commit-sha>
git push

# 4. Sync via ArgoCD
argocd app sync blog-prod
```

## Communication Templates

### Deployment Notification

```
Subject: Production Deployment - v1.2.3 - [DATE] at [TIME]

Team,

We will be deploying v1.2.3 to production on [DATE] at [TIME].

Release: https://github.com/.../releases/v1.2.3

Changes:
- Added new blog post feature
- Fixed image loading bug
- Performance improvements

Testing Status:
✅ Unit tests passed
✅ Integration tests passed
✅ UAT completed
✅ Stage verification done

Rollback Plan:
- Immediate: `kubectl rollout undo`
- Controlled: Revert to v1.2.2

On-call: [NAME]

Questions? Reply to this thread.
```

### Rollback Notification

```
Subject: URGENT - Production Rollback - v1.2.3 → v1.2.2

Team,

We have rolled back production from v1.2.3 to v1.2.2 due to [REASON].

Rollback completed at [TIME].
Production is now stable.

Root cause: [DESCRIPTION]
Action items: [TICKETS]

Post-mortem scheduled for [DATE/TIME].
```

## Best Practices

### Version Tagging
- ✅ Use semantic versioning (v1.2.3)
- ✅ Tag after stage validation
- ✅ Never reuse tags
- ✅ Include release notes

### Testing
- ✅ Run full test suite before stage
- ✅ Manual UAT in stage required
- ✅ Load test critical paths
- ✅ Security scan before prod

### Communication
- ✅ Notify team before prod deploys
- ✅ Document changes in changelog
- ✅ Update release notes
- ✅ Communicate rollbacks immediately

### Monitoring
- ✅ Monitor for 30 minutes post-deploy
- ✅ Check error rates and latency
- ✅ Verify database health
- ✅ Watch for pod restarts

## Related Documentation
- [Dev Namespace](../overlays/dev/namespace.yaml)
- [Stage Namespace](./stage-namespace.md)
- [Prod Namespace](./prod-namespace.md)
- [Operations Runbook](./operations/daily-operations.md)
- [Disaster Recovery](./operations/disaster-recovery.md)
