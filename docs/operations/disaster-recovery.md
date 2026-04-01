# Disaster Recovery Runbook

## Overview
This runbook provides procedures for recovering from catastrophic failures including complete cluster loss, data corruption, or regional outages.

## Recovery Objectives

| Metric | Target | Current Status |
|--------|--------|----------------|
| RTO (Recovery Time Objective) | 30 minutes | ⏱️ |
| RPO (Recovery Point Objective) | 15 minutes | ⏱️ |
| Data Loss Tolerance | < 15 minutes | 📊 |
| Uptime SLA | 99.9% | 📈 |

## Backup Strategy

### What We Back Up

#### 1. Database Backups
- **Frequency:** Every 15 minutes
- **Retention:** 30 days
- **Location:** Persistent volume + offsite storage
- **Method:** pg_dump automated

#### 2. Kubernetes Manifests
- **Frequency:** Continuous (Git)
- **Retention:** Infinite (Git history)
- **Location:** GitHub repository
- **Method:** GitOps (ArgoCD)

#### 3. Secrets & ConfigMaps
- **Frequency:** Daily
- **Retention:** 7 days
- **Location:** Encrypted offsite storage
- **Method:** Sealed Secrets + backup script

#### 4. Persistent Volumes
- **Frequency:** Daily snapshots
- **Retention:** 7 days
- **Location:** Storage provider snapshots
- **Method:** CSI snapshots

### What We DON'T Back Up
- Prometheus metrics (ephemeral)
- Grafana dashboards (stored in Git)
- Loki logs (retained 7 days)
- Container images (stored in registry)

## Disaster Scenarios

### Scenario 1: Single Pod Failure

**Severity:** Low
**RTO:** < 1 minute (automatic)
**RPO:** 0 (no data loss)

#### Recovery Steps

```bash
# Kubernetes automatically recreates pod
# No action needed unless pod is stuck

# If pod is stuck:
kubectl delete pod <pod-name> -n <namespace>

# Verify recovery
kubectl get pods -n <namespace>
```

---

### Scenario 2: Node Failure

**Severity:** Medium
**RTO:** < 5 minutes
**RPO:** 0 (no data loss)

#### Automatic Recovery
Kubernetes automatically reschedules pods to healthy nodes.

#### Manual Intervention (if needed)

```bash
# 1. Verify node status
kubectl get nodes

# 2. Check affected pods
kubectl get pods --all-namespaces -o wide | grep <failed-node>

# 3. Cordon node (prevent new pods)
kubectl cordon <node-name>

# 4. Drain node safely
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# 5. Investigate node
ssh user@<node-ip>

# 6. If unrecoverable, remove node
kubectl delete node <node-name>

# 7. Provision new node and join cluster
# (See cluster expansion guide)
```

---

### Scenario 3: Database Corruption

**Severity:** Critical
**RTO:** < 15 minutes
**RPO:** < 15 minutes

#### Recovery Steps

```bash
# 1. STOP all applications immediately
kubectl scale deployment/blog-api --replicas=0 -n prod

# 2. Verify database state
kubectl exec -n prod postgres-0 -- psql -U postgres blog_prod -c "SELECT version();"

# 3. List available backups
kubectl exec -n prod postgres-0 -- ls -lh /backups

# 4. Create emergency backup of current state (if possible)
kubectl exec -n prod postgres-0 -- pg_dump -U postgres blog_prod > /backups/emergency-$(date +%Y%m%d-%H%M%S).sql

# 5. Restore from latest backup
LATEST_BACKUP=$(kubectl exec -n prod postgres-0 -- ls -t /backups/*.sql | head -1)

kubectl exec -n prod postgres-0 -- psql -U postgres -c "DROP DATABASE blog_prod;"
kubectl exec -n prod postgres-0 -- psql -U postgres -c "CREATE DATABASE blog_prod;"
kubectl exec -i -n prod postgres-0 -- psql -U postgres blog_prod < /backups/$LATEST_BACKUP

# 6. Verify data integrity
kubectl exec -n prod postgres-0 -- psql -U postgres blog_prod -c "SELECT count(*) FROM blog_posts;"

# 7. Restart applications
kubectl scale deployment/blog-api --replicas=3 -n prod

# 8. Verify application health
curl https://petedio-labs.com/api/v1/health

# 9. Monitor error rates
# Check Grafana for error spikes
```

---

### Scenario 4: Complete Cluster Loss

**Severity:** Critical
**RTO:** < 30 minutes
**RPO:** < 15 minutes

#### Prerequisites
- [ ] New Kubernetes cluster provisioned
- [ ] kubectl access configured
- [ ] Database backup accessible
- [ ] GitOps repository accessible

#### Recovery Steps

##### Phase 1: Provision New Cluster (10 minutes)

```bash
# 1. Provision new MicroK8s cluster
# On master node:
sudo snap install microk8s --classic
sudo microk8s enable dns storage ingress

# 2. Configure kubectl
mkdir -p ~/.kube
sudo microk8s config > ~/.kube/config

# 3. Verify cluster
kubectl get nodes
```

##### Phase 2: Restore Core Infrastructure (5 minutes)

```bash
# 1. Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=600s \
  deployment/argocd-server -n argocd

# 3. Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# 4. Install monitoring stack
kubectl create namespace monitoring
kubectl apply -f blog-gitops/kubernetes/base/monitoring/
```

##### Phase 3: Restore Secrets (3 minutes)

```bash
# 1. Create namespaces
kubectl create namespace dev
kubectl create namespace stage
kubectl create namespace prod

# 2. Restore database credentials
kubectl create secret generic postgres-credentials \
  --from-literal=POSTGRES_PASSWORD=<password-from-backup> \
  -n prod

# 3. Restore other secrets
# (Retrieve from encrypted backup storage)
```

##### Phase 4: Restore Application (7 minutes)

```bash
# 1. Deploy via ArgoCD
argocd app create blog-prod \
  --repo https://github.com/PeteDio-Labs/petedio-labs-gitops.git \
  --path blog-gitops/kubernetes/overlays/prod \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace prod \
  --sync-policy automated

# 2. Sync application
argocd app sync blog-prod

# 3. Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=blog-api -n prod --timeout=300s
```

##### Phase 5: Restore Database (5 minutes)

```bash
# 1. Copy latest backup to new cluster
# (From offsite backup storage)
kubectl cp backup-latest.sql prod/postgres-0:/tmp/

# 2. Restore database
kubectl exec -n prod postgres-0 -- psql -U postgres -c "CREATE DATABASE blog_prod;"
kubectl exec -i -n prod postgres-0 -- psql -U postgres blog_prod < /tmp/backup-latest.sql

# 3. Verify data
kubectl exec -n prod postgres-0 -- psql -U postgres blog_prod -c "SELECT count(*) FROM blog_posts;"
```

##### Phase 6: Verify & Resume Service (5 minutes)

```bash
# 1. Update DNS (if needed)
# Point petedio-labs.com to new cluster IP

# 2. Test health endpoint
curl https://petedio-labs.com/api/v1/health

# 3. Verify critical flows
curl https://petedio-labs.com/api/v1/posts
curl https://petedio-labs.com/api/v1/posts/sprint-1-infrastructure-foundation

# 4. Monitor error rates
# Check Grafana dashboards

# 5. Announce recovery
# Send notification to team and users
```

---

### Scenario 5: Data Center Outage

**Severity:** Critical
**RTO:** Depends on multi-region setup
**RPO:** < 15 minutes

#### Current State
- Single data center deployment
- No automatic failover

#### Recovery Steps

```bash
# Same as "Complete Cluster Loss" scenario
# But provision in different region/data center

# Additional steps:
# 1. Update DNS to point to new region
# 2. Restore from offsite backups
# 3. Communicate downtime to users
```

#### Future Enhancement
- [ ] Implement multi-region deployment
- [ ] Set up geo-distributed database replication
- [ ] Configure automatic DNS failover

---

### Scenario 6: Compromised Cluster (Security Breach)

**Severity:** Critical
**RTO:** < 1 hour
**RPO:** < 15 minutes

#### Immediate Actions

```bash
# 1. ISOLATE cluster immediately
# Block all external traffic
kubectl delete ingress --all --all-namespaces

# 2. Snapshot current state for forensics
kubectl get all --all-namespaces -o yaml > compromised-state-$(date +%Y%m%d-%H%M%S).yaml

# 3. Capture logs
kubectl logs --all-containers --prefix --since=24h --all-namespaces > attack-logs-$(date +%Y%m%d-%H%M%S).log

# 4. Scale down all applications
kubectl scale deployment --all --replicas=0 --all-namespaces

# 5. Rotate ALL secrets
# (Detailed procedure below)

# 6. Notify security team
# Begin incident response procedure
```

#### Full Recovery

```bash
# 1. Provision new clean cluster
# 2. Restore from known-good backup (before breach)
# 3. Patch all vulnerabilities
# 4. Rotate all secrets and credentials
# 5. Enable additional security measures
# 6. Conduct post-mortem
```

---

## Backup & Restore Procedures

### Database Backup

#### Manual Backup
```bash
# Create backup
kubectl exec -n prod postgres-0 -- pg_dump -U postgres blog_prod > backup-$(date +%Y%m%d-%H%M%S).sql

# Verify backup
ls -lh backup-*.sql

# Upload to offsite storage
# (Configure based on your storage provider)
```

#### Automated Backup (CronJob)

**File:** `kubernetes/base/cronjobs/postgres-backup.yaml`

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: prod
spec:
  schedule: "*/15 * * * *"  # Every 15 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:15
            command:
            - /bin/bash
            - -c
            - |
              pg_dump -h postgres.prod.svc.cluster.local -U postgres blog_prod > /backups/backup-$(date +%Y%m%d-%H%M%S).sql
              # Keep only last 30 days
              find /backups -name "backup-*.sql" -mtime +30 -delete
            volumeMounts:
            - name: backups
              mountPath: /backups
          volumes:
          - name: backups
            persistentVolumeClaim:
              claimName: postgres-backups
          restartPolicy: OnFailure
```

### Kubernetes State Backup

```bash
# Backup all resources
kubectl get all --all-namespaces -o yaml > k8s-full-backup-$(date +%Y%m%d).yaml

# Backup specific namespace
kubectl get all -n prod -o yaml > k8s-prod-backup-$(date +%Y%m%d).yaml

# Backup secrets (encrypted)
kubectl get secrets --all-namespaces -o yaml > secrets-backup-$(date +%Y%m%d).yaml
# IMPORTANT: Encrypt this file before storing!
```

### Secret Rotation

```bash
# 1. Generate new database password
NEW_PW=$(openssl rand -base64 32)

# 2. Update database password
kubectl exec -n prod postgres-0 -- psql -U postgres -c "ALTER USER postgres PASSWORD '$NEW_PW';"

# 3. Update secret
kubectl create secret generic postgres-credentials \
  --from-literal=POSTGRES_PASSWORD=$NEW_PW \
  --dry-run=client -o yaml | kubectl apply -f -

# 4. Restart applications to pick up new secret
kubectl rollout restart deployment/blog-api -n prod

# 5. Verify connectivity
kubectl logs -f deployment/blog-api -n prod
```

## Testing DR Procedures

### Quarterly DR Drill

Execute this drill every quarter to validate DR procedures:

```bash
# 1. Schedule drill with team
# 2. Backup production state
# 3. Provision test environment
# 4. Practice full recovery
# 5. Document time taken for each step
# 6. Identify improvements
# 7. Update runbook
```

### Checklist

- [ ] Backup procedures tested
- [ ] Restore procedures tested
- [ ] RTO/RPO targets met
- [ ] Team trained on procedures
- [ ] Runbook updated with learnings

## Communication Templates

### Incident Declaration

```
Subject: INCIDENT: Production Database Unavailable

Severity: P0 - Critical
Start Time: [TIMESTAMP]
Status: Investigating

Impact:
- Production API returning 500 errors
- All users affected
- Data reads/writes unavailable

Actions:
- Incident commander: [NAME]
- On-call engineer investigating
- Updates every 15 minutes

Next update: [TIME]
```

### Recovery Complete

```
Subject: RESOLVED: Production Database Recovered

Severity: P0 - Critical
Start Time: [START_TIMESTAMP]
Resolution Time: [END_TIMESTAMP]
Duration: [DURATION]

Status: RESOLVED

Recovery Actions:
- Restored from backup (timestamp: [BACKUP_TIME])
- Data loss: < 15 minutes (within RPO)
- All services verified healthy

Post-Mortem:
- Scheduled for [DATE/TIME]
- Root cause analysis in progress
- Action items to be documented

Thank you for your patience.
```

## Post-Incident Procedures

### 1. Immediate (< 24 hours)
- [ ] Verify all systems fully recovered
- [ ] Document timeline of incident
- [ ] Collect all relevant logs and metrics
- [ ] Identify immediate action items

### 2. Post-Mortem (< 48 hours)
- [ ] Schedule post-mortem meeting
- [ ] Analyze root cause
- [ ] Identify preventive measures
- [ ] Create JIRA tickets for action items
- [ ] Update runbooks

### 3. Follow-up (< 1 week)
- [ ] Implement preventive measures
- [ ] Update documentation
- [ ] Train team on lessons learned
- [ ] Review and update DR procedures

## Related Documentation
- [Daily Operations](./daily-operations.md)
- [Monitoring & Alerts](./monitoring-alerts.md)
- [Promotion Workflow](../promotion-workflow.md)
- [Cluster Expansion](../../sprint-2/4-cluster-expansion/node-expansion.md)
