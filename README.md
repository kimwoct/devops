# macOS Local DevOps Essentials

CLI-only local DevOps setup for a low-disk macOS machine using OrbStack as the Docker backend and kind as the local Kubernetes cluster.

This guide is tuned for this Mac's current disk pressure: about 29 GiB free on `/`. It prioritizes quick local API and exporter development, not production parity.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Container runtime | OrbStack + Docker CLI | Lightweight Docker Desktop replacement with the `docker` client needed by kind. |
| Kubernetes | kind | Disposable local Kubernetes clusters running in Docker containers. |
| Observability | OpenTelemetry + kube-prometheus-stack | OpenTelemetry emits traces and metrics; Prometheus stores metrics; Grafana visualizes them. |
| Cache | Redis via Bitnami Helm chart | Single-node Redis for local development. |
| Kafka-compatible streaming | Redpanda | Kafka API-compatible broker without ZooKeeper or JVM. |

## Local vs Managed

| Tooling Mode | Local: OrbStack + kind | Managed: Civo / DigitalOcean |
| --- | --- | --- |
| Persistence | Fast, but data stays on your SSD. | Uses real cloud block storage. |
| Latency | Near zero, useful for API dev. | Includes real-world network jitter. |
| Ingress | localhost and `kubectl port-forward`. | Real LoadBalancers and DNS. |
| Best use | Developing logic, dashboards, exporters, and CLI workflows. | Testing scale, reliability, storage behavior, and managed ingress. |

## 0. Disk Guardrails

Run these checks before installing anything.

```sh
df -h /
du -sh ~/.orbstack ~/.docker ~/Library/Containers/com.docker.docker 2>/dev/null || true
```

Recommended minimum for this README:

- Stop if `/` has less than 25 GiB available.
- Prefer deleting and recreating the kind cluster over keeping long-lived state.
- Keep Prometheus retention short.
- Do not enable persistent volumes unless you need to debug storage behavior.
- Avoid full Kafka distributions locally; use Redpanda for Kafka API development.

Optional cleanup before starting:

```sh
brew cleanup -s
rm -rf ~/Library/Caches/Homebrew/*
```

## 1. Install CLI Essentials

Install Homebrew first if it is missing:

```sh
command -v brew
```

If the command fails, install Homebrew from <https://brew.sh/> and reopen the terminal.

Install only the essentials:

```sh
brew install --cask orbstack
brew install docker kubectl kind helm
```

Start OrbStack from the command line:

```sh
orb start
```

If `orb` is not available immediately after installation, open OrbStack once so it installs its command-line tools, then rerun:

```sh
orb start
docker version
docker info
```

Verify the CLIs:

```sh
kubectl version --client
kind version
helm version
docker version
```

## 2. Create a Small kind Cluster

Create a single-node cluster. This is intentionally smaller than a production-like Kafka or Kubernetes topology.

```sh
cat > kind-devops.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: devops-lite
nodes:
  - role: control-plane
EOF

kind create cluster --name devops-lite --config kind-devops.yaml
kubectl cluster-info --context kind-devops-lite
kubectl get nodes -o wide
```

Disk check after cluster creation:

```sh
df -h /
docker system df
```

## 3. Add Helm Repositories

```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add redpanda https://charts.redpanda.com/
helm repo update
```

Redis uses Bitnami's OCI chart directly, so no Bitnami Helm repository is required.

## 4. Install Prometheus and Grafana

Use short retention and no persistent volumes. This keeps the stack disposable and disk-light.

```sh
cat > values-prometheus-lite.yaml <<'EOF'
alertmanager:
  enabled: false
grafana:
  enabled: true
  persistence:
    enabled: false
  adminPassword: admin
prometheus:
  prometheusSpec:
    retention: 2h
    retentionSize: 512MB
    storageSpec: {}
nodeExporter:
  enabled: false
kube-state-metrics:
  enabled: true
EOF

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values values-prometheus-lite.yaml

kubectl -n monitoring rollout status deploy/monitoring-grafana --timeout=5m
kubectl -n monitoring get pods
kubectl -n monitoring get svc
```

CLI verification:

```sh
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 >/tmp/prometheus-port-forward.log 2>&1 &
PF_PID=$!
sleep 5
curl -fsS http://127.0.0.1:9090/-/ready
kill "$PF_PID"
```

Optional Grafana port-forward:

```sh
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Use <http://127.0.0.1:3000> only if you want to inspect Grafana in a browser. The CLI workflow does not require it. Log in with `admin` / `admin`, then stop the port-forward with `Ctrl+C`.

### OpenTelemetry, Prometheus, And Grafana Tutorial

Use this when you want to understand what each tool does, not just start it.

#### Why These Tools Matter

- `OpenTelemetry` is the instrumentation standard. The app uses it to create traces and metrics without locking into one vendor.
- `Prometheus` stores metrics such as request rate, error rate, latency, CPU, memory, and pod health.
- `Grafana` turns those metrics into dashboards that a human can read quickly.
- `OpenTelemetry Collector` receives traces from the app and can forward them to Jaeger, Grafana Tempo, Aspire, Sentry, or another backend.
- `Sentry` is useful for error tracking and release-aware debugging. Use it when you need exception grouping, stack traces, affected users, and deploy regression tracking.

For this low-disk local stack, OpenTelemetry is enabled by default and the collector prints traces to logs. Sentry is documented as an optional production-style backend because self-hosting Sentry locally is much heavier than this kind cluster needs.

#### Step 1 - Install The Monitoring Stack

- `helm` installs the whole monitoring bundle from the chart.
- `kube-prometheus-stack` gives you Prometheus, Grafana, kube-state-metrics, and the operator wiring in one package.
- Short retention keeps the stack small on this Mac.

You already installed it with:

```sh
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values values-prometheus-lite.yaml
```

#### Step 2 - Start The Weather App With OpenTelemetry

- The weather app uses OpenTelemetry instrumentation for ASP.NET Core, outgoing HTTP calls, runtime metrics, and Prometheus metrics.
- `/metrics` exposes Prometheus-format metrics.
- `OTEL_EXPORTER_OTLP_ENDPOINT` sends traces to the collector inside Kubernetes.
- The local collector currently uses a `debug` exporter, so traces appear in collector logs.

Start the app stack:

```sh
./scripts/start-weather-service.sh
```

Verify the collector:

```sh
kubectl --context kind-devops-lite get pods -n observability
kubectl --context kind-devops-lite logs -n observability deploy/otel-collector --tail=50
```

Generate traffic so traces and metrics exist:

```sh
curl -i http://127.0.0.1:5035/
curl -i http://127.0.0.1:5035/weather/local
kubectl --context kind-devops-lite logs -n observability deploy/otel-collector --tail=80
```

What to look for:

- `otel-collector` pod should be `Running`.
- Collector logs should show trace export output after app traffic.
- The app should still respond through Nginx at `http://127.0.0.1:5035`.

#### Step 3 - Start With Prometheus

- `kubectl port-forward` exposes Prometheus locally without adding an Ingress or LoadBalancer.
- Prometheus is the collector. It asks targets for `/metrics`, stores time-series samples, and lets you query them.
- In this repo, it is the place to confirm that the weather app, Kubernetes, and any exporters are alive.

Open the Prometheus UI or use curl:

```sh
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Then open:

- `http://127.0.0.1:9090`

Useful checks in Prometheus:

- Status > Targets to see which pods are being scraped.
- Graph to run a query like `up`.
- Graph to run `process_cpu_seconds_total` for process-level behavior.

Why this matters:

- If a target is missing here, Grafana will not be able to graph it.
- If Prometheus cannot scrape the target, the issue is usually service discovery, labels, or the app not exposing `/metrics`.

#### Step 4 - Check The Weather App Metrics

- The weather app exports metrics on `/metrics`.
- Prometheus scrapes those metrics and turns them into queryable samples.
- This is how you prove the app is observable before you even open Grafana.

From the cluster, check the service first:

```sh
kubectl --context kind-devops-lite get svc weather-live-stream
kubectl --context kind-devops-lite port-forward svc/weather-live-stream 5036:80 --address 127.0.0.1
curl -i http://127.0.0.1:5036/metrics
```

What to look for:

- `200 OK` means the app is exposing metrics.
- A text payload means Prometheus can usually scrape it.
- If `/metrics` fails, fix the app before debugging Grafana.

#### Step 5 - Open Grafana

- `Grafana` is the visualization layer.
- It does not collect metrics itself.
- It reads from Prometheus and turns time-series data into dashboards.

Start the UI:

```sh
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Then open:

- `http://127.0.0.1:3000`

Log in with `admin` / `admin`.

In Grafana:

- Use Explore to test a Prometheus query.
- Open the default dashboard or build your own panel.
- Add a panel for request rate, latency, or pod health.

#### Step 6 - Build A Useful Query

Prometheus is most useful when you query real signals.

Good starter queries:

- `up`
- `rate(http_server_request_duration_seconds_count[5m])`
- `rate(process_cpu_seconds_total[5m])`
- `sum by (job) (up)`

How to think about them:

- `up` tells you whether a scrape target is reachable.
- `rate(...)` tells you how fast a counter is changing.
- `sum by (job)` groups related targets together.

#### Step 7 - Where Sentry Fits

Sentry and OpenTelemetry solve overlapping but different problems.

| Tool | Best for | Local role | Production role |
| --- | --- | --- | --- |
| OpenTelemetry | Vendor-neutral traces, metrics, and logs pipeline | Instrument app once and send traces to local collector logs | Send telemetry to Tempo, Jaeger, Sentry, Datadog, New Relic, Azure Monitor, or another backend |
| Prometheus | Metrics storage and PromQL queries | Store short-lived local metrics | Alert on SLOs, saturation, error rate, and latency |
| Grafana | Dashboards and visual exploration | Inspect app and cluster behavior | Operations dashboards and incident views |
| Sentry | Exceptions, stack traces, releases, user impact | Optional cloud or remote DSN only | Error triage, release regression detection, frontend and backend exception grouping |

Do not self-host Sentry on this low-disk Mac unless you specifically need to learn Sentry operations. For this project, the practical path is:

1. Keep OpenTelemetry in the app.
2. Send local traces to the lightweight collector.
3. In production, point the collector or Sentry SDK at the real backend.
4. Add release tags in CI/CD so errors connect back to GitHub commits and image tags.

#### Step 8 - Why Observability Helps CI/CD

CI tells you whether the code built and tests passed. Observability tells you whether the deployed system is healthy after release.

In this project:

- GitHub Actions proves restore, build, test, and image publishing.
- Argo CD proves Kubernetes desired state is synced.
- OpenTelemetry proves requests create traces.
- Prometheus proves metrics are being scraped.
- Grafana proves humans can inspect app and cluster behavior.
- Sentry, when enabled, proves new releases are not creating new exception groups.

This is the practical DevOps loop:

```text
git push
  -> GitHub Actions build/test/image
  -> Argo CD sync
  -> Kubernetes rollout
  -> OpenTelemetry traces
  -> Prometheus metrics
  -> Grafana/Sentry release verification
```

#### Step 9 - Use The Tools Together

Use this order when debugging:

1. `kubectl get pods` to see whether the workload is running.
2. `kubectl get svc` to see whether the Service exists.
3. `curl /metrics` through a port-forward to check the app endpoint.
4. Prometheus Targets to check scrape status.
5. Grafana Explore to visualize the query.

That sequence keeps the diagnosis simple:

- `kubectl` tells you whether Kubernetes is healthy.
- `curl` tells you whether the app is exposing metrics.
- `Prometheus` tells you whether scraping works.
- `Grafana` tells you whether the data is readable by humans.
- `OpenTelemetry Collector` tells you whether request traces are leaving the app.
- `Sentry` tells you which errors are tied to a release, commit, or user impact when you enable it.

## 5. Install Redis

Install one Redis pod with auth and persistence disabled for local development.

```sh
helm upgrade --install redis oci://registry-1.docker.io/bitnamicharts/redis \
  --namespace data \
  --create-namespace \
  --set architecture=standalone \
  --set auth.enabled=false \
  --set master.persistence.enabled=false \
  --set replica.replicaCount=0

kubectl -n data rollout status statefulset/redis-master --timeout=5m
kubectl -n data get pods
kubectl -n data get svc
```

CLI verification:

```sh
kubectl -n data run redis-client --rm -i --restart=Never \
  --image=redis:8-alpine \
  -- redis-cli -h redis-master.data.svc.cluster.local ping
```

Expected output:

```text
PONG
```

## 6. Install Lightweight Kafka-Compatible Streaming

Use Redpanda as the default Kafka-compatible local broker. This is lighter than running a full Apache Kafka stack with ZooKeeper or multiple brokers.

This configuration keeps Redpanda single-node, reduces CPU, avoids persistent storage, and disables Console because the requirement is CLI-only.

The current Redpanda chart uses its own `resources.memory` fields to generate `rpk` startup flags. Keep the broker at 1 CPU and 1.5 GiB memory; lower memory settings fail Redpanda's startup check.

```sh
cat > values-redpanda-lite.yaml <<'EOF'
statefulset:
  replicas: 1
  additionalRedpandaCmdFlags:
    - --overprovisioned
resources:
  cpu:
    cores: 1
  memory:
    container:
      max: 1536Mi
    redpanda:
      memory: 1100Mi
      reserveMemory: 0Mi
storage:
  persistentVolume:
    enabled: false
console:
  enabled: false
tls:
  enabled: false
external:
  enabled: false
EOF

helm upgrade --install redpanda redpanda/redpanda \
  --namespace streaming \
  --create-namespace \
  --values values-redpanda-lite.yaml

kubectl -n streaming rollout status statefulset/redpanda --timeout=8m
kubectl -n streaming get pods
kubectl -n streaming get svc
```

CLI verification with Redpanda's bundled `rpk`:

```sh
kubectl -n streaming exec -it redpanda-0 -c redpanda -- \
  rpk topic create devops-test

printf 'hello from kind\n' | kubectl -n streaming exec -i redpanda-0 -c redpanda -- \
  rpk topic produce devops-test

kubectl -n streaming exec -it redpanda-0 -c redpanda -- \
  rpk topic consume devops-test --num 1
```

## 7. Daily CLI Checks

```sh
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
helm list -A
docker system df
df -h /
```

## 8. Start the Weather Microservice Through Nginx

Use the helper script to build the .NET 10 app in Docker, load it into the OrbStack-backed kind cluster, apply the app and Nginx Kubernetes manifests, wait for both rollouts, and expose Nginx on localhost:

```sh
./scripts/start-weather-service.sh
```

The default local endpoint is:

```text
http://127.0.0.1:5035/
```

If Aspire is already running, port `5035` can be owned by Aspire DCP. In that case the start script automatically falls back to:

```text
http://127.0.0.1:5037/
```

The default path is:

```text
browser/curl -> 127.0.0.1:5035 -> kubectl port-forward -> svc/weather-nginx -> svc/weather-live-stream
```

Check the dashboard and API through Nginx:

```sh
curl -i http://127.0.0.1:5035/
curl -i http://127.0.0.1:5035/weather/local
```

Kubernetes services:

```text
weather-nginx.default.svc.cluster.local:80
weather-live-stream.default.svc.cluster.local:80
```

Useful overrides:

```sh
LOCAL_PORT=8080 ./scripts/start-weather-service.sh
FALLBACK_LOCAL_PORT=5039 ./scripts/start-weather-service.sh
CLUSTER_NAME=devops-lite IMAGE_NAME=weather-live-stream:local ./scripts/start-weather-service.sh
```

The script does not require the host .NET SDK to match the app target framework because the build happens inside the .NET 10 SDK container image.

For direct app debugging without Nginx, run a temporary port-forward in another shell:

```sh
kubectl --context kind-devops-lite port-forward svc/weather-live-stream 5036:80 --address 127.0.0.1
curl -i http://127.0.0.1:5036/weather/local
```

If Prometheus is installed, the script also applies `k8s/weather-servicemonitor.yaml` so Prometheus can discover the app's `/metrics` endpoint. If the `ServiceMonitor` CRD is missing, the script skips that optional manifest and the app still starts.

Stop only the weather microservice and its localhost port-forward without deleting the kind cluster:

```sh
./scripts/stop-weather-service.sh
```

The stop script scales `deployment/weather-nginx` and `deployment/weather-live-stream` to `0` replicas and only terminates a `kubectl port-forward` process when it is forwarding the configured weather service on the configured `LOCAL_PORT`.

To remove the weather manifests completely and recover a little cluster state:

```sh
kubectl delete -f k8s/weather-nginx.yaml --ignore-not-found
kubectl delete -f k8s/weather-live-stream.yaml --ignore-not-found
```

### Aspire Monitoring Remarks

- .NET Aspire is useful for local developer observability when the app is run through an Aspire AppHost; it can show logs, traces, metrics, resources, and service dependencies in the Aspire dashboard.
- The current Kubernetes script deploys the weather service directly to kind. To monitor this exact kind deployment, use Kubernetes checks (`kubectl get pods`, `kubectl logs`) and the optional Prometheus/Grafana stack from this guide.
- Aspire is already wired through `WeatherLiveStream.AppHost`. Use it when you want the local Aspire dashboard and app resource view.
- The app's direct local launch profile uses `http://localhost:5038` so it does not collide with the Kubernetes Nginx port-forward on `5035`.
- Keep Aspire and kind as separate run paths: Aspire is the local developer dashboard path; kind is the Kubernetes deployment path.

Start Aspire:

```sh
./scripts/run-aspire.sh
```

Check Aspire state:

```sh
aspire describe --apphost WeatherLiveStream.AppHost/WeatherLiveStream.AppHost.csproj
```

If Aspire is running and you still need the Kubernetes stack, use either the automatic fallback port or set one explicitly:

```sh
LOCAL_PORT=5037 ./scripts/start-weather-service.sh
```

### Public Demo With ngrok

Use ngrok to expose only the weather Nginx port-forward for a short public demo. Do not point ngrok at local port `80`; on this Mac that can expose Apache instead of the weather service.

Keep credentials in a local env file that is ignored by Git:

```sh
cp .env.example .env.local
$EDITOR .env.local
```

Set `NGROK_AUTHTOKEN` only in `.env.local`, then save it into the local ngrok config:

```sh
./scripts/configure-ngrok.sh
```

If an ngrok token is leaked in chat, markdown, shell history, or a screenshot:

1. Open the ngrok dashboard and revoke or rotate the exposed authtoken.
2. Replace `NGROK_AUTHTOKEN` in `.env.local` with the new token.
3. Re-run local ngrok configuration:

```sh
./scripts/configure-ngrok.sh
```

4. Check local shell history and remove any command that contains the old token.

Start or confirm the Kubernetes weather port:

```sh
./scripts/start-weather-service.sh
curl -i http://127.0.0.1:5035/weather/local
```

If Aspire owns `5035`, use the verified fallback:

```sh
kubectl --context kind-devops-lite port-forward svc/weather-nginx 5037:80 --address 127.0.0.1
curl -i http://127.0.0.1:5037/weather/local
```

Expose the working local port:

```sh
NGROK_LOCAL_URL=http://127.0.0.1:5035 ./scripts/start-ngrok-demo.sh
```

Or, for the fallback port:

```sh
NGROK_LOCAL_URL=http://127.0.0.1:5037 ./scripts/start-ngrok-demo.sh
```

Then test the public URL:

```sh
curl -i https://YOUR-NGROK-URL.ngrok-free.dev/weather/local
```

Troubleshooting:

```sh
curl -fsS http://127.0.0.1:4040/api/tunnels
lsof -nP -iTCP:80 -sTCP:LISTEN || true
lsof -nP -iTCP:5035 -sTCP:LISTEN || true
lsof -nP -iTCP:5037 -sTCP:LISTEN || true
```

Correct ngrok target:

```text
http://127.0.0.1:5035
http://127.0.0.1:5037
```

Wrong target for the weather demo:

```text
http://localhost:80
```

## 9. Stop and Start

Stop local workload pods without deleting the cluster:

```sh
kubectl scale statefulset redis-master -n data --replicas=0
kubectl scale statefulset redpanda -n streaming --replicas=0
kubectl scale deployment monitoring-grafana -n monitoring --replicas=0
kubectl -n monitoring patch prometheus monitoring-kube-prometheus-prometheus \
  --type merge \
  -p '{"spec":{"replicas":0}}'
```

Start them again:

```sh
kubectl scale statefulset redis-master -n data --replicas=1
kubectl scale statefulset redpanda -n streaming --replicas=1
kubectl scale deployment monitoring-grafana -n monitoring --replicas=1
kubectl -n monitoring patch prometheus monitoring-kube-prometheus-prometheus \
  --type merge \
  -p '{"spec":{"replicas":1}}'
```

Stop OrbStack when you are not using containers:

```sh
orb stop
```

## 10. Uninstall Workloads

Remove Helm releases:

```sh
helm uninstall redpanda -n streaming || true
helm uninstall redis -n data || true
helm uninstall monitoring -n monitoring || true
```

Remove namespaces:

```sh
kubectl delete namespace streaming data monitoring --ignore-not-found
```

Delete the whole local cluster:

```sh
kind delete cluster --name devops-lite
```

Recover Docker and OrbStack disk:

```sh
docker system prune -af --volumes
orb stop
```

Final disk check:

```sh
docker system df
df -h /
du -sh ~/.orbstack ~/.docker 2>/dev/null || true
```

## 11. Troubleshooting

If `docker version` fails:

```sh
orb start
docker context ls
docker context use orbstack
docker version
```

If `kubectl` points at the wrong cluster:

```sh
kubectl config get-contexts
kubectl config use-context kind-devops-lite
```

If pods are pending:

```sh
kubectl describe pod -A | less
kubectl get events -A --sort-by='.lastTimestamp' | tail -50
df -h /
docker system df
```

If disk is too low:

```sh
kind delete cluster --name devops-lite
docker system prune -af --volumes
brew cleanup -s
rm -rf ~/Library/Caches/Homebrew/*
df -h /
```

## 12. CI/CD With GitHub Actions And Argo CD

This repo uses GitHub Actions for CI and Argo CD for Kubernetes delivery.

### What GitHub Actions Does

- restores, tests, and builds the .NET app
- builds the Docker image
- pushes the image to GHCR

### What Argo CD Does

- runs inside `kind-devops-lite`
- watches this repository's GitOps path
- syncs the app and Nginx manifests into Kubernetes

### Practical Local Flow

1. Push code to GitHub.
2. GitHub Actions runs CI and publishes the image.
3. Update the GitOps image tag in the repo.
4. Argo CD syncs the cluster to the Git state.
5. Use `kubectl port-forward` for local access through Nginx.

### Install Argo CD Locally

```sh
cp .env.example .env.local
$EDITOR .env.local
./scripts/install-argocd.sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

### Current Repo Paths

- GitHub Actions workflow: `.github/workflows/ci.yml`
- Argo CD bootstrap: `scripts/install-argocd.sh`
- GitOps manifests: `gitops/`
- CI/CD map: `docs/orbstack-kind-map.md`

## 13. Terraform Usage

Terraform is not required for the local OrbStack + kind stack. Keep local kind disposable and script-driven so it stays lightweight on this low-disk Mac.

Use Terraform when you move from local practice to a managed environment such as Civo, DigitalOcean, AWS, Azure, or GCP.

Terraform should manage platform infrastructure:

- managed Kubernetes cluster
- cloud load balancer and DNS
- managed database
- managed Redis
- managed Kafka or Redpanda
- object storage, backups, and IAM
- Argo CD installation or bootstrap inputs

Argo CD should continue to manage Kubernetes app desired state:

- weather app Deployment and Service
- Nginx reverse proxy
- OpenTelemetry Collector
- ServiceMonitor and app Kubernetes config

Recommended future layout:

```text
infra/
  terraform/
    README.md
    digitalocean/
    civo/
    github/
```

Do not commit Terraform state or real variable files. This repo ignores `.terraform/`, `*.tfstate`, and `*.tfvars`; commit only examples such as `terraform.tfvars.example`.

## 14. Smallest Linux Pod Example

If you want the smallest practical Linux container in this stack, use the BusyBox smoke pod:

```sh
./scripts/smoke-linux.sh
curl http://127.0.0.1:5050/
```

That pod is intentionally tiny:

- image: `busybox:1.36`
- memory request: `16Mi`
- CPU request: `5m`
- one static page served over HTTP

Remove it when done:

```sh
screen -S linux-smoke-port-forward -X quit >/dev/null 2>&1 || true
kubectl delete -f k8s/linux-smoke.yaml
```

## References

- OrbStack: <https://orbstack.dev/>
- kind quick start: <https://kind.sigs.k8s.io/docs/user/quick-start/>
- kubectl on macOS: <https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/>
- Helm install guide: <https://helm.sh/docs/intro/install/>
- Prometheus community Helm charts: <https://github.com/prometheus-community/helm-charts>
- Bitnami Redis Helm chart: <https://bitnami.com/stack/redis/helm>
- Redpanda local Kubernetes guide: <https://docs.redpanda.com/current/deploy/deployment-option/self-hosted/kubernetes/local-guide/>
- Redpanda Helm chart specification: <https://docs.redpanda.com/current/reference/k-redpanda-helm-spec/>
