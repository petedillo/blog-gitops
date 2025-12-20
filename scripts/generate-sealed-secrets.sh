#!/bin/bash

# generate-sealed-secrets.sh
# Securely generates sealed secrets for stage and production environments
# These sealed secrets can be safely committed to Git

set -e

ENVIRONMENT="${1:-stage}"
NAMESPACE="blog-${ENVIRONMENT}"
OVERLAY_PATH="kubernetes/overlays/${ENVIRONMENT}/sealed-secrets"

echo "🔐 Generating sealed secrets for: ${ENVIRONMENT}"
echo "📦 Namespace: ${NAMESPACE}"
echo "📁 Output: ${OVERLAY_PATH}"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create sealed-secrets directory if it doesn't exist
mkdir -p "${OVERLAY_PATH}"

# 1. Generate JWT Secret
echo -e "${YELLOW}[1/3]${NC} Generating JWT Secret..."
JWT_SECRET=$(openssl rand -base64 48)
kubectl create secret generic jwt-secret \
  --namespace="${NAMESPACE}" \
  --from-literal=JWT_SECRET="${JWT_SECRET}" \
  --dry-run=client \
  -o yaml | kubeseal -o yaml > "${OVERLAY_PATH}/jwt-secret.yaml"
echo -e "${GREEN}✓${NC} JWT Secret sealed"

# 2. Generate Postgres Credentials
echo -e "${YELLOW}[2/3]${NC} Generating Postgres Credentials..."
POSTGRES_PASS=$(openssl rand -base64 32)
kubectl create secret generic postgres-credentials \
  --namespace="${NAMESPACE}" \
  --from-literal=password="${POSTGRES_PASS}" \
  --dry-run=client \
  -o yaml | kubeseal -o yaml > "${OVERLAY_PATH}/postgres-credentials.yaml"
echo -e "${GREEN}✓${NC} Postgres credentials sealed"

# 3. Generate Admin App Credentials
echo -e "${YELLOW}[3/3]${NC} Generating Admin App Credentials..."
ADMIN_USER="admin"
ADMIN_PASS=$(openssl rand -base64 32)
kubectl create secret generic blog-app-credentials \
  --namespace="${NAMESPACE}" \
  --from-literal=ADMIN_USERNAME="${ADMIN_USER}" \
  --from-literal=ADMIN_PASSWORD="${ADMIN_PASS}" \
  --dry-run=client \
  -o yaml | kubeseal -o yaml > "${OVERLAY_PATH}/blog-app-credentials.yaml"
echo -e "${GREEN}✓${NC} Admin credentials sealed"

echo ""
echo -e "${GREEN}✅ All sealed secrets generated successfully!${NC}"
echo ""
echo "📋 Generated Files:"
echo "  - ${OVERLAY_PATH}/jwt-secret.yaml"
echo "  - ${OVERLAY_PATH}/postgres-credentials.yaml"
echo "  - ${OVERLAY_PATH}/blog-app-credentials.yaml"
echo ""
echo "⚠️  IMPORTANT - Save these credentials securely:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "JWT_SECRET: ${JWT_SECRET}"
echo "POSTGRES_PASSWORD: ${POSTGRES_PASS}"
echo "ADMIN_USERNAME: ${ADMIN_USER}"
echo "ADMIN_PASSWORD: ${ADMIN_PASS}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ These sealed secrets are encrypted and safe to commit to Git"
echo "ℹ️  Share the credentials above securely with your team"
