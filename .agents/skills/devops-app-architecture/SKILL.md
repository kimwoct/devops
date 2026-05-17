---
name: devops-app-architecture
description: Use when building a frontend, backend, fullstack app, or microservice on this repo's OrbStack + kind + Nginx + Aspire + GitHub Actions + Argo CD stack. Use it to choose the right local run path, start the correct smoke or service script, wire Kubernetes manifests, and keep CI/CD aligned with GitOps.
---

# DevOps App Architecture

Use this skill when the work needs to fit the repo's local development architecture instead of inventing a new one.

## What this stack is for

- OrbStack provides the local Docker engine on macOS.
- kind provides the local Kubernetes cluster.
- Nginx is the local reverse proxy for the weather app.
- Aspire is the local developer dashboard path for the app host.
- GitHub Actions is CI.
- Argo CD is Kubernetes CD through GitOps.

## When to use this skill

- Starting a new frontend, backend, fullstack app, or microservice in this repo
- Adding a small service that should run in kind
- Wiring a service behind Nginx and `kubectl port-forward`
- Adding CI in GitHub Actions and CD through Argo CD
- Creating a tiny smoke pod for Linux/container verification

## First check

Verify the repo and current tools:

```sh
git status --short
kubectl config current-context
kind get clusters
```

## Choose the right path

- **Frontend only**: use the app service plus local port-forward or Aspire if the app host exists.
- **Backend or microservice**: use `k8s/*.yaml`, `scripts/start-weather-service.sh`, and the kind cluster.
- **Fullstack**: model the app in Aspire for local developer flow, then deploy the containerized app to kind.
- **Smoke test / smallest container**: use `k8s/linux-smoke.yaml` and `scripts/smoke-linux.sh`.

## Standard local flow

1. Build or update the app code.
2. Start the local stack:
   - `./scripts/start-weather-service.sh` for the weather service
   - `./scripts/smoke-linux.sh` for the tiny Linux pod
   - `./scripts/run-aspire.sh` for Aspire
3. Verify with `kubectl get pods`, `kubectl get svc`, and `curl`.
4. Stop with the matching script.

## Public demo flow

- Use ngrok only in front of the active weather Nginx port-forward.
- Keep ngrok tokens and public-demo passwords in `.env.local`; never write real credentials into markdown, Git commits, or shell-history examples.
- Correct local targets:
  - `http://127.0.0.1:5035` when the Kubernetes weather port-forward owns `5035`
  - `http://127.0.0.1:5037` when Aspire DCP owns `5035` and the Kubernetes fallback port is used
- Do not use `ngrok http 80` for the weather demo; on this Mac that exposes local Apache, so `/` can return `200 OK` while `/weather/local` returns Apache `404`.
- Before starting ngrok, prove the local API:

```sh
curl -i http://127.0.0.1:5035/weather/local
curl -i http://127.0.0.1:5037/weather/local
```

- Start ngrok against the working local port:

```sh
NGROK_LOCAL_URL=http://127.0.0.1:5037 ./scripts/start-ngrok-demo.sh
```

- Check ngrok's active target when troubleshooting:

```sh
curl -fsS http://127.0.0.1:4040/api/tunnels
```

## Kubernetes rules

- Keep container images small.
- Keep YAML declarative.
- Put procedures in scripts, not in manifests.
- Use `Deployment`, `Service`, `ConfigMap`, `Ingress` or Nginx, and `Application` as needed.
- Use `kubectl port-forward` for localhost access.

## CI/CD rules

- GitHub Actions builds, tests, and publishes the image to GHCR.
- Argo CD syncs GitOps manifests into `kind-devops-lite`.
- Do not let GitHub Actions deploy directly to the Mac-local cluster.
- Keep the GitOps source of truth in this repo unless the user asks for a separate repo.

## Safe defaults

- Prefer `ubuntu-latest` in GitHub Actions.
- Prefer `busybox` or `alpine` for tiny smoke or proxy containers.
- Prefer one service per manifest file or per logical bundle.
- Prefer `screen`-backed port-forward scripts for long-running local access.

## Do not do this without explicit approval

- Do not change the root `.NET SDK` pin.
- Do not move the app off kind unless the user asks.
- Do not add production-only infrastructure to local manifests.
- Do not replace YAML with shell logic.
- Do not hardcode GitHub repo URLs in Argo CD manifests without using a placeholder or parameter.

## Good command examples

```sh
./scripts/start-weather-service.sh
kubectl apply -f k8s/linux-smoke.yaml
./scripts/install-argocd.sh
```
