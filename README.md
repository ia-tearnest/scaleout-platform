# Solar Discovery Day 2026 Conference Demo

Platform supporting the Solar Discovery Day 2026 demo application.

## Quick Links

| Documentation | Description |
|---------------|-------------|
| [Bootstrapping Guide](docs/BOOTSTRAPPING.md) | Bootstrap clusters with ArgoCD and ApplicationSets |
| [Developer Setup](docs/SETUP.md) | Local environment setup, kubectl contexts, direnv |

## External Resources

- [Project Documentation](<link-to-project-docs>)
- [Project Tracker](<link-to-project-tracker>)
- [Demo App Repository](https://github.com/example-org/app)

## Repository Structure

```text
├── appsets/          # ArgoCD ApplicationSets per environment
├── bootstrapping/    # Helmfile for initial cluster bootstrap
├── charts/           # Helm charts (argocd, keycloak, kargo, pgo, site)
├── values/           # Helm values by component and environment
└── docs/             # Documentation
```

## Getting Started

1. **New to the project?** Start with the [Developer Setup](docs/SETUP.md) guide
2. **Bootstrapping a cluster?** See the [Bootstrapping Guide](docs/BOOTSTRAPPING.md)
