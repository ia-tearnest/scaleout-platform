# Developer Setup Guide

This guide covers setting up your local environment to work with the example platform.

## Prerequisites

- kubectl
- helm
- helmfile
- AWS CLI v2
- direnv (recommended)

## AWS SSO Configuration

Add the Discovery Day SSO profile to your AWS config:

```ini
# ~/.aws/config

[sso-session ia]
sso_start_url = https://d-xxxxxxxxxx.awsapps.com/start/#
sso_region = us-west-2
sso_registration_scopes = sso:account:access

[profile example]
region = us-west-2
output = json
sso_session = ia
sso_account_id = 123456789012
sso_role_name = AWSPowerUserAccess
```

### Logging In

```bash
# Login to SSO (opens browser)
aws sso login --profile example

# Verify access
aws sts get-caller-identity --profile example
```

The `.envrc` in this repository sets `AWS_PROFILE=example` automatically when you enter the directory.

## Cluster Context Configuration

We use a consistent naming convention for kubectl contexts: `{project}:{cluster}`

| Cluster | Context Name |
|---------|--------------|
| Development | `example:example-eks-dev` |
| Staging | `example:example-eks-stg` |
| Production | `example:example-eks-prd` |
| Management | `example:example-eks-mgmt` |

### Setting Up Contexts

Get credentials for each cluster, then rename contexts to match our convention:

```bash
# Get credentials for all clusters
aws eks update-kubeconfig --region us-west-2 --name example-eks-mgmt
aws eks update-kubeconfig --region us-west-2 --name example-eks-dev
aws eks update-kubeconfig --region us-west-2 --name example-eks-stg
aws eks update-kubeconfig --region us-west-2 --name example-eks-prd

# Rename contexts to our convention
kubectl config rename-context arn:aws:eks:us-west-2:123456789012:cluster/example-eks-mgmt example:example-eks-mgmt
kubectl config rename-context arn:aws:eks:us-west-2:123456789012:cluster/example-eks-dev example:example-eks-dev
kubectl config rename-context arn:aws:eks:us-west-2:123456789012:cluster/example-eks-stg example:example-eks-stg
kubectl config rename-context arn:aws:eks:us-west-2:123456789012:cluster/example-eks-prd example:example-eks-prd
```

### Switching Contexts

```bash
# Switch to management cluster
kubectl config use-context example:example-eks-mgmt

# Verify
kubectl config current-context
```

## Environment Variables with direnv

The `.envrc` file is gitignored, so you'll need to create your own. direnv automatically loads environment variables when you enter the project directory.

### Installing direnv

```bash
# macOS
brew install direnv

# Add to your shell (bash)
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc

# Add to your shell (zsh)
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
```

### Creating Your .envrc

Create a `.envrc` file in the repository root:

```bash
# .envrc

# AWS
export AWS_REGION="us-west-2"
export AWS_PROFILE="example"
```

Then allow it:

```bash
direnv allow
```

## Makefile Helpers

Common operations are available via `make`. Run `make help` to see all available commands.

```bash
# AWS
make login              # SSO login
make whoami             # Check current identity

# Applications
make apps               # List all ArgoCD applications
make apps-dev           # List dev applications only

# Site operations
make status ENV=stg SITE=site1      # Show app and pod status
make decommission ENV=stg SITE=site2  # Cleanup after config removal
```

### Decommissioning a Site

To fully decommission a site:

1. Revert/remove the site config files (e.g., `values/site2/stg/`)
2. Run `make decommission ENV=stg SITE=site2` to clean up resources
