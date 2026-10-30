# Cluster Bootstrapping Guide

This guide covers bootstrapping the Solar Discovery Day platform clusters after IT has completed initial cluster provisioning with IRSA, networking, and base infrastructure.

## Prerequisites

Before bootstrapping, ensure the following are complete:

- [ ] EKS clusters provisioned (dev, stg, prd, mgmt)
- [ ] IRSA roles configured for each cluster
- [ ] VPCs and networking configured
- [ ] ACM certificates created
- [ ] External Secrets Operator installed with ClusterSecretStore configured
- [ ] kubectl access to target cluster

## Required AWS Secrets

The following secrets must exist in AWS Secrets Manager before bootstrapping. The platform uses External Secrets Operator to sync these into the cluster.

| Secret Path | Properties | Used By | Description |
|-------------|------------|---------|-------------|
| `example/platform/platform-repo-ro` | `ssh_key` | ArgoCD | SSH deploy key for reading platform repo |
| `example/platform/platform-repo-readwrite` | `sshPrivateKey`, `url` | Kargo | SSH key for Kargo to push promotions to platform repo |
| `example/platform/app-repo-readonly` | `sshPrivateKey`, `url` | Kargo | SSH key for Kargo warehouse to read app repo tags |
| `example/platform/kargo-admin` | `ADMIN_ACCOUNT_PASSWORD_HASH`, `ADMIN_ACCOUNT_TOKEN_SIGNING_KEY` | Kargo | Bcrypt hash of the Kargo admin password and token signing key |
| `example/platform/ignition-site` | `GIT_SYNC_SSH`, `GIT_SYNC_KNOWN_HOSTS`, `IGNITION_API_KEY` | Site deployments | Shared credentials for git-sync and Ignition API |

### Verifying Secrets

```bash
# List all example secrets
aws secretsmanager list-secrets --filter Key="name",Values="example/" \
  --query 'SecretList[].Name' --output yaml

# Verify a specific secret exists and has expected keys
aws secretsmanager get-secret-value --secret-id example/platform/ignition-site \
  --query 'SecretString' | jq -r 'fromjson | keys'
```

### Creating Secrets (if needed)

```bash
# Example: Create platform repo readonly secret
aws secretsmanager create-secret \
  --name "example/platform/platform-repo-ro" \
  --secret-string '{"ssh_key": "<private-key-content>"}'

# Example: Create site credentials secret
aws secretsmanager create-secret \
  --name "example/platform/ignition-site" \
  --secret-string '{"GIT_SYNC_SSH": "<ssh-key>", "GIT_SYNC_KNOWN_HOSTS": "<known-hosts>", "IGNITION_API_KEY": "<api-key>"}'
```

## Bootstrapping Steps

### 1. Configure Cluster Context

Set your kubectl context to the target cluster. See [SETUP.md](./SETUP.md) for recommended context naming conventions.

```bash
# Verify you're targeting the correct cluster
kubectl config current-context
# Expected: example:example-eks-mgmt (or dev/stg/prd)
```

### 2. Bootstrap with Helmfile

The helmfile installs ArgoCD which includes a root Application that automatically deploys all ApplicationSets from the `appsets/` directory.

```bash
cd bootstrapping

# Preview what will be installed
helmfile diff

# Install ArgoCD
helmfile apply
```

This single command:

1. Installs ArgoCD with the configured values
2. Creates the `root-appsets` Application that watches `appsets/`
3. ArgoCD automatically syncs all ApplicationSets (mgmt, dev, stg, prd)
4. ApplicationSets generate Applications for each component (keycloak, pgo, kargo, sites)

### 3. Verify Deployment

```bash
# Check ArgoCD pods are running
kubectl get pods -n argocd

# Check ApplicationSets are created
kubectl get applicationsets -n argocd

# Check Applications are syncing
kubectl get applications -n argocd
```

### 4. Access ArgoCD UI

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward to access UI locally
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then navigate to `https://localhost:8080` and login with username `admin`.

## Architecture Overview

```text
helmfile.yaml
    └── ArgoCD (Helm chart)
            └── root-appsets Application
                    └── appsets/*.yaml
                            ├── appset-mgmt.yaml → mgmt Applications
                            ├── appset-dev.yaml  → dev Applications
                            ├── appset-stg.yaml  → stg Applications
                            └── appset-prd.yaml  → prd Applications
```

The ApplicationSets use git generators to discover components:

- `values/*/mgmt/config.yaml` → generates mgmt-cluster apps
- `values/*/dev/config.yaml` → generates dev-cluster apps
- etc.

## Cluster-Specific Notes

### Management Cluster (mgmt)

The management cluster hosts:

- ArgoCD (manages all clusters)
- Keycloak (OIDC provider)
- Kargo (GitOps promotion)
- PostgreSQL Operator (Keycloak database)

### Workload Clusters (dev, stg, prd)

Workload clusters receive:

- Site deployments (Ignition gateways)
- Promoted through Kargo pipelines
- OIDC configured against mgmt Keycloak
