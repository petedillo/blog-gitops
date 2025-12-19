# Deploy Sprint 3 to Dev Environment

## Changes Made

### Network Security
- Added IP whitelist to dev Ingress: `192.168.50.0/24`
- Dev environment now only accessible from:
  - Local network (192.168.50.X)
  - VPN connected to local network
- Public internet access: **BLOCKED**

### Files Updated
1. `kubernetes/overlays/dev/ingress-patch.yaml` - Added whitelist for blog-api
2. `kubernetes/overlays/dev/ui-ingress-patch.yaml` - Added whitelist for blog-ui
3. `kubernetes/overlays/dev/kustomization.yaml` - Added UI ingress patch

## Deployment Steps

### 1. Commit and Push GitOps Changes
```bash
cd blog-gitops
git add kubernetes/overlays/dev/
git commit -m "feat: restrict dev environment to local network (192.168.50.0/24)"
git push
```

### 2. ArgoCD Auto-Sync
ArgoCD will automatically detect the changes and deploy within 3 minutes.

**Monitor deployment:**
```bash
# Watch ArgoCD app status
kubectl get application blog-dev -n argocd -w

# Watch pods
kubectl get pods -n blog-dev -w
```

### 3. Verify Deployment

**From local network (192.168.50.X):**
```bash
# Should work
curl -I http://dev.petedillo.com

# Test API health
curl http://dev.petedillo.com/api/v1/health
```

**From public internet:**
```bash
# Should return 403 Forbidden
curl -I http://dev.petedillo.com
```

### 4. Manual Testing Checklist

#### Authentication
- [ ] Access https://dev.petedillo.com (from VPN)
- [ ] Verify environment badge shows "DEV" in green/cyan
- [ ] Login with admin credentials
- [ ] Verify JWT cookies set (check browser DevTools)
- [ ] Navigate to /admin/posts
- [ ] Logout and verify redirect to login

#### Posts Management (Sprint 3)
- [ ] Create new post with title, content, tags
- [ ] Upload markdown content
- [ ] Save as DRAFT
- [ ] Edit post and change status to PUBLISHED
- [ ] Verify post appears in public list
- [ ] Delete post
- [ ] Search/filter posts

#### Media Management (Sprint 3 - Task 16)
- [ ] Edit existing post
- [ ] Upload single image via drag-and-drop
- [ ] Upload multiple images
- [ ] Verify images appear in gallery
- [ ] Drag to reorder media
- [ ] Delete media item
- [ ] Verify first image is cover (note in UI)

#### UI/UX (Sprint 3 - Tasks 17-19)
- [ ] Verify neon theme consistent
- [ ] Check Button, Card, Badge, Modal components
- [ ] Verify admin nav shows "Posts" link when logged in
- [ ] Verify logout button works
- [ ] Test mobile responsive (375px, 768px, 1920px)
- [ ] Verify Header environment badge

#### Security
- [ ] Verify public internet blocked (403 Forbidden)
- [ ] Verify VPN access works
- [ ] Check JWT refresh happens automatically
- [ ] Verify protected routes redirect to login
- [ ] Test CORS from allowed origins

### 5. Database Verification

```bash
# Connect to postgres pod
kubectl exec -it -n blog-dev deployment/postgres -- psql -U petedillo petedillo_blog

# Check migrations applied
SELECT * FROM flyway_schema_history ORDER BY installed_rank;

# Verify admin user exists
SELECT id, username, email, enabled FROM admin_users;

# Check tags normalization
SELECT * FROM tags ORDER BY post_count DESC LIMIT 10;

# Verify refresh tokens table exists
\dt refresh_tokens
```

### 6. Log Verification

```bash
# Check API logs
kubectl logs -n blog-dev deployment/blog-api --tail=100 -f

# Check UI logs
kubectl logs -n blog-dev deployment/blog-ui --tail=100 -f

# Check for errors
kubectl logs -n blog-dev deployment/blog-api | grep -i error
```

## Rollback Procedure

If issues are found:

```bash
# Option 1: Revert git commit
cd blog-gitops
git revert HEAD
git push

# Option 2: Manual rollback in ArgoCD UI
# Navigate to Argocd UI -> blog-dev -> History -> Rollback

# Option 3: Delete deployment and re-sync
kubectl delete application blog-dev -n argocd
kubectl apply -f argocd/applications/blog-dev.yaml
```

## Known Issues / TODO

- [ ] Test token refresh flow (wait 14 minutes)
- [ ] Verify media files persist across pod restarts (NFS mount)
- [ ] Test high-resolution image uploads
- [ ] Verify tag post counts update correctly
- [ ] Test concurrent admin users (if applicable)

## Next Steps

Once dev is validated:
1. Create **stage** environment (public facing)
2. Set up automated testing against stage
3. Deploy to production

## Sprint 3 Completion Status

- [x] Task 16: Media Components
- [x] Task 17: Shared Components
- [x] Task 18: Styling Update
- [x] Task 19: Header & Footer
- [x] Task 20: Deployment Config
- [ ] Task 21: Dev Deployment & Validation (IN PROGRESS)
- [x] Task 22: Documentation

---

**Last Updated:** December 19, 2025
**Environment:** dev (blog-dev namespace)
**Access:** http://dev.petedillo.com (192.168.50.0/24 only)
