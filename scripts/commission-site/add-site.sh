#!/bin/bash
# Commission a new site by creating configuration files
set -e

# Configuration
VALUES_DIR="values"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Parse command line arguments
TARGET_ENV="${1:-}"
SITE_NAME="${2:-}"
SITE_LOCATION="${3:-}"
BLOCK_COUNT="${4:-}"
INVERTER_COUNT="${5:-}"

# Validate required arguments
if [[ -z "$TARGET_ENV" ]]; then
  echo "Error: TARGET_ENV is required as first argument"
  exit 1
fi

if [[ ! "$TARGET_ENV" =~ ^(dev|stg|prd)$ ]]; then
  echo "Error: TARGET_ENV must be dev, stg, or prd"
  exit 1
fi

if [[ -z "$SITE_NAME" ]]; then
  echo "Error: SITE_NAME is required as second argument"
  exit 1
fi

if [[ -z "$SITE_LOCATION" ]]; then
  echo "Error: SITE_LOCATION is required as third argument"
  exit 1
fi

if [[ -z "$BLOCK_COUNT" || ! "$BLOCK_COUNT" =~ ^[1-6]$ ]]; then
  echo "Error: BLOCK_COUNT must be between 1 and 6"
  exit 1
fi

if [[ -z "$INVERTER_COUNT" || ! "$INVERTER_COUNT" =~ ^[1-2]$ ]]; then
  echo "Error: INVERTER_COUNT must be between 1 and 2"
  exit 1
fi

# Navigate to repo root
cd "$REPO_ROOT"

# Find appropriate site number
# 1. Check if any existing sites are missing the target environment
# 2. If yes, use that site; if no, create a new site
echo "Determining site number for $TARGET_ENV environment..."
SITE_NUM=""
SITE_EXISTS=false

# Check existing sites for missing target environment
SITE_CHECK=1
while [[ -d "$VALUES_DIR/site${SITE_CHECK}" ]]; do
  if [[ ! -d "$VALUES_DIR/site${SITE_CHECK}/${TARGET_ENV}" ]]; then
    SITE_NUM=$SITE_CHECK
    SITE_EXISTS=true
    echo "Found existing site${SITE_NUM} without $TARGET_ENV environment"
    break
  fi
  SITE_CHECK=$((SITE_CHECK + 1))
done

# If no existing site is missing the target environment, create a new site
if [[ -z "$SITE_NUM" ]]; then
  SITE_NUM=$SITE_CHECK
  SITE_EXISTS=false
  echo "Creating new site: site${SITE_NUM}"
fi

# Validate maximum site count (max 4 sites)
if [[ "$SITE_EXISTS" == "false" && $SITE_NUM -gt 4 ]]; then
  echo "Error: Maximum of 4 sites allowed. Cannot create site${SITE_NUM}."
  echo "All existing sites (1-4) already have the $TARGET_ENV environment."
  exit 1
fi

SITE_DIR="$VALUES_DIR/site${SITE_NUM}"
echo "  Site Number: $SITE_NUM"
echo "  Name: $SITE_NAME"
echo "  Location: $SITE_LOCATION"
echo "  Target Environment: $TARGET_ENV"
echo "  Block Count: $BLOCK_COUNT"
echo "  Inverter Count: $INVERTER_COUNT"

# Create directory structure for target environment only
echo ""
echo "Creating directory structure for $TARGET_ENV environment..."
mkdir -p "$SITE_DIR/${TARGET_ENV}"

# Generate common-values.yaml only if this is a new site
if [[ "$SITE_EXISTS" == "false" ]]; then
  echo ""
  echo "Generating $SITE_DIR/common-values.yaml..."
  cat > "$SITE_DIR/common-values.yaml" << EOF
# Site ${SITE_NUM} common configuration (shared across all environments)
siteNumber: ${SITE_NUM}

# Stoker git repository (same for all environments, ref is set per-environment via Kargo)
stoker:
  git:
    repo: "git@github.com:example-org/app.git"

# External Secrets - use shared secret for all sites
externalSecrets:
  secretName: "example/platform/ignition-site"

# Common ingress configuration (shared ALB annotations)
x-ingress-common: &ingress-common
  enabled: true
  className: alb
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-3-PQ-2025-09
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/healthcheck-path: /StatusPing
    alb.ingress.kubernetes.io/healthcheck-protocol: HTTPS
    alb.ingress.kubernetes.io/success-codes: "200"
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-west-2:123456789012:certificate/00000000-0000-0000-0000-000000000000
    external-dns.alpha.kubernetes.io/ttl: "60"
  tls:
    enabled: false

# GAN anchor for site frontend and edge to connect to site backend gateway
x-gan-config: &gan-config
  gan:
    outgoingConnections:
      - host: site${SITE_NUM}-be
        port: 8060

be:
  ingress:
    <<: *ingress-common

fe:
  gateway:
    <<: *gan-config
  ingress:
    <<: *ingress-common

block1:
  gateway:
    <<: *gan-config
  ingress:
    <<: *ingress-common
EOF
else
  echo ""
  echo "Site ${SITE_NUM} already exists, skipping common-values.yaml"
fi

# Function to create environment-specific config.yaml
create_config_yaml() {
  local env=$1
  local config_file="$SITE_DIR/$env/config.yaml"

  echo "Generating $config_file..."
  cat > "$config_file" << EOF
# Use site chart for this deployment
chartPath: site
EOF
}

# Function to create environment-specific values.yaml
create_values_yaml() {
  local env=$1
  local values_file="$SITE_DIR/$env/values.yaml"
  local deployment_mode="${env}-cloud"
  local alb_group="alb-${env}-ext-group"
  local alb_name="alb-${env}-ext"
  local domain="${env}.example.com"

  echo "Generating $values_file..."
  cat > "$values_file" << EOF
# Site ${SITE_NUM} ${env} environment configuration
# Note: stoker.git.ref is managed via site-common by Kargo promotions

# Site configuration (all settings for easy site commissioning)
site:
  siteName: "$SITE_NAME"
  location: "$SITE_LOCATION"
  blockCount: ${BLOCK_COUNT}
  inverterCount: ${INVERTER_COUNT}

# Environment-specific gateway settings
# deploymentMode must match a directory in app repo: services/{site,block}/config/resources/{mode}/
x-gateway-env: &gateway-env
  deploymentMode: ${deployment_mode}

# Environment-specific ingress annotations
x-ingress-env: &ingress-env-annotations
  alb.ingress.kubernetes.io/group.name: ${alb_group}
  alb.ingress.kubernetes.io/load-balancer-name: ${alb_name}
  alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-3-PQ-2025-09

# Gateway Configuration
blockDefaults:
  gateway:
    <<: *gateway-env

be:
  gateway:
    <<: *gateway-env
  ingress:
    annotations:
      <<: *ingress-env-annotations
      external-dns.alpha.kubernetes.io/hostname: site${SITE_NUM}-be.${domain}
    hostOverride: site${SITE_NUM}-be.${domain}

fe:
  gateway:
    <<: *gateway-env
  ingress:
    annotations:
      <<: *ingress-env-annotations
      external-dns.alpha.kubernetes.io/hostname: site${SITE_NUM}-fe.${domain}
    hostOverride: site${SITE_NUM}-fe.${domain}

block1:
  gateway:
    <<: *gateway-env
  ingress:
    annotations:
      <<: *ingress-env-annotations
      external-dns.alpha.kubernetes.io/hostname: block1.site${SITE_NUM}.${domain}
    hostOverride: block1.site${SITE_NUM}.${domain}
EOF
}

# Create config.yaml and values.yaml for target environment only
echo ""
create_config_yaml "$TARGET_ENV"
create_values_yaml "$TARGET_ENV"

echo ""
if [[ "$SITE_EXISTS" == "true" ]]; then
  echo "✓ Added $TARGET_ENV environment to existing site${SITE_NUM}!"
else
  echo "✓ Site ${SITE_NUM} created with $TARGET_ENV environment!"
fi

# Output site number for GitHub Actions workflow
if [ -n "$GITHUB_OUTPUT" ]; then
  echo "site_num=$SITE_NUM" >> "$GITHUB_OUTPUT"
  echo "✓ Site number $SITE_NUM written to GitHub Actions output"
fi

echo ""
echo "Next steps:"
echo "  1. Review generated files in $SITE_DIR/$TARGET_ENV"
echo "  2. Commit and push changes to repository"
echo "  3. ArgoCD will deploy to the $TARGET_ENV environment"
