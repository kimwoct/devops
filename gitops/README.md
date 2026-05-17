# GitOps

This folder is the desired state that Argo CD syncs into `kind-devops-lite`.

The Argo CD bootstrap script replaces the `REPO_URL` placeholder in `gitops/argocd/application.yaml`.

The weather app image currently points at:

```text
ghcr.io/kimwoct/weather-live-stream:latest
```

GitHub Actions publishes this image after CI succeeds on `main`.
