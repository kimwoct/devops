# OrbStack + kind Map

This project uses OrbStack as the local Docker engine and kind as the Kubernetes cluster for the weather stack.

## OrbStack Usage Reminder

- Use OrbStack as the local Docker backend for containers and kind nodes.
- Use OrbStack's `Machines` only when you need a full Linux VM.
- Do not create a Linux machine just to run Kubernetes workloads; kind already gives you the Kubernetes layer.
- Use `kubectl --context kind-devops-lite` for this project, not the `orbstack` Kubernetes context.
- Use `kubectl --context orbstack` only if you intentionally want OrbStack's own built-in Kubernetes cluster.
- For local app hosting, prefer:
  - `kind` pods and services
  - `kubectl port-forward`
  - `./scripts/start-weather-service.sh`
  - `./scripts/smoke-linux.sh`
- Use `./scripts/run-aspire.sh` when you want the Aspire dashboard path instead of the Kubernetes path.

## Simple Map

```text
macOS
  |
  | docker / kubectl / kind CLI
  v
+--------------------------------------------------+
| OrbStack                                         |
| - lightweight Linux VM                           |
| - Docker Engine backend                          |
| - optional built-in Kubernetes context: orbstack |
+-------------------------+------------------------+
                          |
                          | Docker container created by kind
                          v
              +-----------------------------+
              | kind cluster: devops-lite   |
              | kubectl context:            |
              | kind-devops-lite            |
              +--------------+--------------+
                             |
              +--------------+--------------+
              | Kubernetes workloads         |
              | - linux-smoke                |
              | - weather-nginx              |
              | - weather-live-stream        |
              | - redis                      |
              | - redpanda                   |
              | - otel-collector             |
              | - prometheus / grafana       |
              +--------------+--------------+
                             |
                             | kubectl port-forward
                             v
                   http://127.0.0.1:5035
```

## Why OrbStack UI Looked Empty

- OrbStack has its own Kubernetes context named `orbstack`.
- The weather app is deployed to the kind context named `kind-devops-lite`.
- The OrbStack Kubernetes UI shows resources from OrbStack's built-in Kubernetes cluster, not the kind cluster.
- `kubectl --context orbstack get pods -A` only shows OrbStack's built-in system pods.
- `kubectl --context kind-devops-lite get pods -A` shows the real dev stack: Redis, Redpanda, Prometheus, Grafana, and kind system pods.
- The weather app deployments currently exist but are scaled to `0`, so there are no weather pods until you run `./scripts/start-weather-service.sh`.
- Aspire can also use local ports through DCP. If Aspire owns `5035`, the Kubernetes script falls back to `5037`.

## Step 1 - Understand The Roles

- OrbStack replaces Docker Desktop for this setup.
- Docker images and kind node containers run inside OrbStack.
- kind creates a Kubernetes cluster inside Docker.
- `kubectl` talks to whichever Kubernetes context is selected.
- The weather app is not deployed to OrbStack's built-in Kubernetes context; it is deployed to kind.
- Aspire is not the Kubernetes cluster. It is a local AppHost and dashboard workflow for developer-time orchestration.

## Why Use Kubernetes For Development

Kubernetes is useful locally when the production system will also be containerized and service-based. The goal is not to make the Mac behave like production; the goal is to practice the same deployment shape before paying for cloud infrastructure.

```text
Local development problem         Kubernetes practice
-------------------------         -------------------
Run many services                 Deployments + Services
Expose one entry point            Nginx / Ingress / port-forward
Restart failed processes          liveness + readiness probes
Change config safely              ConfigMaps + Secrets
Test app startup behavior         rollout status + logs
Observe service health            OpenTelemetry + Prometheus + Grafana
Replace local dependencies        Redis + Redpanda in cluster
Clean everything quickly          delete namespace / delete cluster
```

For this project:

- `weather-nginx` teaches reverse proxy and edge routing.
- `linux-smoke` teaches the smallest Linux container/pod/service pattern.
- `weather-live-stream` teaches app deployment, probes, and service discovery.
- `redis` teaches cache/state projection.
- `redpanda` teaches Kafka-compatible event streaming.
- `otel-collector` teaches vendor-neutral trace shipping.
- `prometheus` and `grafana` teach service monitoring.

## Practical Production Usage: Serving 1M Users

Kubernetes does not automatically make an app handle 1M users. It gives you the control plane to run, scale, replace, observe, and isolate services. The app, database, cache, and messaging design still decide whether the system can handle the traffic.

```text
1M users
  |
  v
CDN / WAF / DNS
  |
  v
Cloud Load Balancer
  |
  v
Kubernetes Ingress / Nginx
  |
  v
API pods: weather-live-stream replicas
  |
  +--> Redis cache for hot reads
  |
  +--> Kafka / Redpanda for async events
  |
  +--> Database read replicas / primary DB
  |
  v
OpenTelemetry + Prometheus + Grafana + alerts
```

Practical production patterns:

- Run multiple app replicas across multiple nodes.
- Use readiness probes so bad pods do not receive traffic.
- Use horizontal autoscaling based on CPU, memory, request rate, or queue lag.
- Put Nginx or cloud ingress in front of app services.
- Use Redis for repeated hot reads, sessions, rate limits, and short-lived projections.
- Use Kafka or Redpanda for async work so user requests do not wait on slow side effects.
- Use OpenTelemetry traces to follow one request across services.
- Use Prometheus metrics to track latency, errors, saturation, and throughput.
- Use rolling deployments and quick rollback for safer releases.
In this repo, `linux-smoke` is the smallest container example. It uses `busybox:1.36`, runs a tiny HTTP server, and proves the minimum pod/service path without a custom image.

## Practical Data Usage: Handling 1M DB Queries

Kubernetes can scale app pods, but it does not fix inefficient database access. A million database queries can mean very different things:

- `1M queries per day` is moderate for many systems.
- `1M queries per hour` needs careful caching and read scaling.
- `1M queries per minute` needs serious data architecture.
- `1M queries per second` is a specialized distributed systems problem.

For this weather service, a scalable read path should look like this:

```text
Client request
  |
  v
Nginx
  |
  v
ASP.NET Core API
  |
  +--> Redis first for latest weather snapshot
  |
  +--> Database only for cache miss or history query
  |
  +--> Kafka event for async analytics / downstream processing
```

Data management checklist:

- Use Redis to avoid hitting the database for every repeated request.
- Add TTLs so cached weather data expires predictably.
- Keep read models small and query-friendly.
- Use database indexes for every high-volume lookup path.
- Use connection pooling so app replicas do not overload the database.
- Split reads and writes when volume grows: primary DB for writes, replicas for reads.
- Use Kafka for event history, analytics, and background processing.
- Track query latency, cache hit ratio, DB connections, and slow queries.
- Add rate limiting so one client cannot exhaust app or database capacity.

For a real 1M-user production design, the local kind stack is only the practice environment. The production version needs managed Kubernetes, managed database, managed Redis, durable Kafka or Redpanda, real load balancers, DNS, TLS, backups, disaster recovery, and alerting.

## CI/CD Design: GitHub Actions + Argo CD

Use GitHub Actions for CI and Argo CD for Kubernetes CD.

```text
developer
  |
  | git push
  v
GitHub repository
  |
  v
GitHub Actions CI
  - restore .NET
  - test .NET
  - build Docker image
  - push image to GHCR
  |
  v
GitOps manifests in this repo
  - desired image tag
  - weather app deployment
  - Nginx reverse proxy
  |
  v
Argo CD inside kind-devops-lite
  - watches Git
  - compares Git vs cluster
  - syncs Kubernetes resources
  |
  v
OrbStack Docker backend + kind Kubernetes
  |
  v
localhost:5035 via kubectl port-forward
```

### Observability In The Delivery Loop

```text
request
  |
  v
weather-live-stream
  |
  +--> /metrics -----------------> Prometheus ----------> Grafana
  |
  +--> OTLP traces --------------> OpenTelemetry Collector
                                      |
                                      +--> local debug logs now
                                      +--> Tempo / Jaeger / Sentry later
```

- CI says whether code passed tests.
- Argo CD says whether Kubernetes matches Git.
- OpenTelemetry says what one request did.
- Prometheus says whether the service trend is healthy.
- Grafana makes those trends visible.
- Sentry is optional for release-linked exception triage when you need error grouping and user impact.

### Aspire vs kind Runtime Paths

```text
Aspire path
  ./scripts/run-aspire.sh
    -> WeatherLiveStream.AppHost
    -> Aspire dashboard / DCP
    -> local app endpoint, usually localhost:5038 or an Aspire-assigned endpoint

Kubernetes path
  ./scripts/start-weather-service.sh
    -> Docker build
    -> kind load image
    -> weather-live-stream pod
    -> weather-nginx service
    -> localhost:5035, or 5037 when Aspire owns 5035
```

- Use Aspire when you want local service orchestration, dashboard, logs, metrics, traces, and quick app iteration.
- Use kind when you want to validate the container image, Kubernetes YAML, probes, Services, Nginx proxy, OpenTelemetry Collector, Prometheus, and Argo CD GitOps path.
- Do not expect the OrbStack Kubernetes UI to show kind workloads; use `kubectl --context kind-devops-lite`.

### Dashboard And Error Trace Runbook

Use this runbook when you want to prove the observability path from shell commands, not just read the architecture.

#### 1. Check Which Runtime Owns The App

```sh
cd /Users/kingwong/Downloads/devops
kubectl config current-context
lsof -nP -iTCP:5035 -sTCP:LISTEN || true
lsof -nP -iTCP:5037 -sTCP:LISTEN || true
lsof -nP -iTCP:5038 -sTCP:LISTEN || true
```

What the ports mean:

- `5035`: preferred Kubernetes Nginx port-forward.
- `5037`: Kubernetes fallback when Aspire DCP owns `5035`.
- `5038`: direct local app launch profile used by Aspire or `dotnet run`.

If `5035` is owned by `dcp`, Aspire is using that port. Start Kubernetes anyway; the script will fall back to `5037`.

#### 2. Start The Kubernetes Weather Stack

```sh
cd /Users/kingwong/Downloads/devops
./scripts/start-weather-service.sh
```

What this script does:

- starts OrbStack if needed
- builds `weather-live-stream:local`
- loads the image into kind
- applies `k8s/otel-collector.yaml`
- applies `k8s/weather-live-stream.yaml`
- applies `k8s/weather-nginx.yaml`
- applies `k8s/weather-servicemonitor.yaml` only when Prometheus CRDs exist
- opens a local port-forward on `5035`, or `5037` if Aspire owns `5035`

If you want to choose the Kubernetes port yourself:

```sh
LOCAL_PORT=5037 ./scripts/start-weather-service.sh
```

#### 3. Confirm Pods, Services, And Monitoring

```sh
kubectl --context kind-devops-lite get pods -A
kubectl --context kind-devops-lite get svc -A
kubectl --context kind-devops-lite get deploy -A
kubectl --context kind-devops-lite get servicemonitor -A 2>/dev/null || true
```

Expected important resources:

- `default/deployment/weather-live-stream`
- `default/deployment/weather-nginx`
- `observability/deployment/otel-collector`
- `monitoring/deployment/monitoring-grafana`
- `monitoring/prometheus/monitoring-kube-prometheus-prometheus`

#### 4. Watch OpenTelemetry Trace Output

Open one terminal for trace logs:

```sh
kubectl --context kind-devops-lite logs -n observability deploy/otel-collector -f
```

What this shows:

- traces received by the OpenTelemetry Collector
- one or more spans for app requests
- basic proof that the app is exporting OTLP telemetry

Current local collector behavior:

- It uses the `debug` exporter.
- It prints trace batch summaries to logs.
- It does not provide a trace search UI yet.

#### 5. Generate Normal And Error Traffic

In another terminal, use the active Kubernetes URL.

If the script used `5035`:

```sh
curl -i http://127.0.0.1:5035/
curl -i http://127.0.0.1:5035/weather/local
curl -i http://127.0.0.1:5035/not-existing-route
```

If Aspire owns `5035` and the script fell back to `5037`:

```sh
curl -i http://127.0.0.1:5037/
curl -i http://127.0.0.1:5037/weather/local
curl -i http://127.0.0.1:5037/not-existing-route
```

What these requests prove:

- `/` proves the Razor dashboard route works.
- `/weather/local` proves the app API route works.
- `/not-existing-route` creates a `404` HTTP error-style trace.

Important distinction:

- A `404` is an HTTP error trace.
- A real exception trace requires an app endpoint or code path that throws an exception.
- If you need exception grouping and release correlation, add Sentry or a trace backend such as Tempo/Jaeger plus structured error handling.

#### 6. Read The Trace Logs

After generating traffic, inspect the collector logs:

```sh
kubectl --context kind-devops-lite logs -n observability deploy/otel-collector --tail=200
```

Filter for useful trace words:

```sh
kubectl --context kind-devops-lite logs -n observability deploy/otel-collector --tail=500 \
  | grep -Ei "traces|traceid|spanid|status|error|weather-live-stream|404"
```

Common output with the current debug exporter:

```text
Traces {"kind":"exporter","data_type":"traces","name":"debug","resource spans":1,"spans":1}
```

How to interpret it:

- `Traces` means the collector received trace data.
- `resource spans` means one service resource emitted spans.
- `spans` means individual request operations were exported.
- If no new trace lines appear after `curl`, check the app env var `OTEL_EXPORTER_OTLP_ENDPOINT`.

#### 7. Open Prometheus

Prometheus stores metrics, not detailed traces.

```sh
kubectl --context kind-devops-lite -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Open:

```text
http://127.0.0.1:9090
```

Useful checks:

- Status > Targets
- query: `up`
- query: `http_server_request_duration_seconds_count`
- query: `rate(http_server_request_duration_seconds_count[5m])`

If the weather service target is missing:

```sh
kubectl --context kind-devops-lite get servicemonitor -A
kubectl --context kind-devops-lite get svc weather-live-stream -o yaml
curl -i http://127.0.0.1:5035/metrics
```

Use `5037` in the curl command if the Kubernetes stack is using the fallback port.

#### 8. Open Grafana

Grafana visualizes Prometheus metrics.

```sh
kubectl --context kind-devops-lite -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Open:

```text
http://127.0.0.1:3000
```

Login:

```text
username: admin
password: admin
```

Use Grafana Explore with the Prometheus data source and try:

```text
up
rate(http_server_request_duration_seconds_count[5m])
process_cpu_seconds_total
```

What Grafana tells you:

- whether the service is up
- request rate over time
- process/runtime behavior
- cluster-level workload health through existing dashboards

What Grafana does not show yet:

- full trace waterfall
- exception grouping
- release regression tracking

For those, add Grafana Tempo, Jaeger, or Sentry.

#### 9. Open Aspire Dashboard

Use Aspire when you want local developer-time resource views instead of the Kubernetes path.

```sh
cd /Users/kingwong/Downloads/devops
./scripts/run-aspire.sh
```

The script prints the Aspire dashboard URL. You can also inspect Aspire state:

```sh
aspire describe --apphost WeatherLiveStream.AppHost/WeatherLiveStream.AppHost.csproj
```

Aspire is best for:

- local AppHost resource view
- developer logs
- local traces and metrics when the app runs under Aspire
- quick iteration without rebuilding a container image

kind is best for:

- testing Kubernetes YAML
- testing container images
- testing Nginx proxy behavior
- testing OpenTelemetry Collector and Prometheus wiring
- testing Argo CD GitOps behavior

#### 10. Stop The Stack

Stop the Kubernetes weather app and its port-forward:

```sh
./scripts/stop-weather-service.sh
```

The stop script handles:

- normal `5035` Kubernetes port-forward
- fallback `5037` Kubernetes port-forward
- `weather-nginx`
- `weather-live-stream`
- `otel-collector`

Stop Aspire with `Ctrl+C` in the terminal running `./scripts/run-aspire.sh`.

### Public Demo With ngrok

Use ngrok only for a short public demo of the weather UI/API. Keep Kubernetes private and expose only the local Nginx port-forward.

```text
Public browser
  |
  v
ngrok HTTPS URL
  |
  v
127.0.0.1:5035 or 127.0.0.1:5037
  |
  v
kubectl port-forward
  |
  v
svc/weather-nginx
  |
  v
svc/weather-live-stream
```

Do not expose these services with ngrok for a casual demo:

- Prometheus
- Grafana
- Argo CD
- Redis
- Redpanda
- Kubernetes API server
- OpenTelemetry Collector OTLP ports

What ngrok is for:

- sharing a temporary HTTPS URL with a reviewer
- demoing the dashboard and `/weather/local` endpoint
- testing an external webhook callback against a local service
- avoiding router port-forward rules on your home network

What ngrok is not for:

- production ingress
- long-lived public hosting
- exposing cluster admin tools
- exposing observability backends to the internet

#### 1. Install And Authenticate ngrok

Install the ngrok agent on macOS:

```sh
brew install ngrok
```

Add your ngrok authtoken from the ngrok dashboard:

```sh
cp .env.example .env.local
$EDITOR .env.local
./scripts/configure-ngrok.sh
```

Put the real token only in `.env.local` as `NGROK_AUTHTOKEN=...`. Do not paste a real ngrok token into markdown, Git commits, shell history snippets, screenshots, or chat. If a token is exposed, revoke or rotate it in the ngrok dashboard before using ngrok again.

If an ngrok token is exposed:

1. Go to the ngrok dashboard.
2. Revoke or rotate the exposed authtoken.
3. Put the new token in `.env.local`.
4. Reconfigure the local agent:

```sh
./scripts/configure-ngrok.sh
```

5. Search shell history for the old token and remove any matching entry.
6. Re-run the repository credential scan before committing. Keep the pattern split so the documentation line does not match itself:

```sh
TOKEN_SCAN='ngrok config add-authtoken [A-Za-z0-9_\-]+|[A-Za-z0-9]{20,}_[A-Za-z0-9]{20,}|NGROK_'\
'AUTHTOKEN=[^[:space:]<>.]+'
rg -n --hidden --glob '!/.git/**' --glob '!**/bin/**' --glob '!**/obj/**' "$TOKEN_SCAN" .
```

Verify:

```sh
ngrok version
ngrok config check
```

Official ngrok CLI patterns used here:

- `ngrok config add-authtoken` saves the token in the ngrok config file.
- `ngrok http 8080` forwards a local HTTP service.
- `ngrok http 8080 --traffic-policy-file tp.yml` adds auth or routing policy.
- `ngrok http 8080 --url https://example.ngrok.app` chooses the public URL when your plan supports it.

Official references:

- ngrok macOS install: <https://ngrok.com/downloads/mac-os>
- ngrok agent CLI: <https://ngrok.com/docs/agent/cli>

#### 2. Start The Weather Stack Locally

```sh
cd /Users/kingwong/Downloads/devops
./scripts/start-weather-service.sh
```

The normal local URL is:

```text
http://127.0.0.1:5035/
```

If Aspire owns `5035`, the script falls back to:

```text
http://127.0.0.1:5037/
```

Find the active port:

```sh
lsof -nP -iTCP:5035 -sTCP:LISTEN || true
lsof -nP -iTCP:5037 -sTCP:LISTEN || true
```

Test local access before making it public:

```sh
curl -i http://127.0.0.1:5035/
curl -i http://127.0.0.1:5035/weather/local
```

Use `5037` in those URLs if the start script selected the fallback port.

Known working fallback from local troubleshooting:

```sh
kubectl --context kind-devops-lite port-forward svc/weather-nginx 5037:80 --address 127.0.0.1
curl -i http://127.0.0.1:5037/weather/local
```

Expected API result:

```text
HTTP/1.1 200 OK
content-type: application/json
```

If `curl http://127.0.0.1:80/weather/local` returns `404` from `Apache`, ngrok is pointing at the wrong local service. Local port `80` is not the weather service on this Mac.

#### 3. Start A Public ngrok Tunnel

For a quick demo on port `5035`:

```sh
NGROK_LOCAL_URL=http://127.0.0.1:5035 ./scripts/start-ngrok-demo.sh
```

For the Aspire-safe fallback port:

```sh
NGROK_LOCAL_URL=http://127.0.0.1:5037 ./scripts/start-ngrok-demo.sh
```

This is the verified command when `5035` is owned by Aspire DCP:

```sh
NGROK_LOCAL_URL=http://127.0.0.1:5037 ./scripts/start-ngrok-demo.sh
```

Do not use this for the weather demo:

```sh
ngrok http 80
```

On this Mac, `ngrok http 80` exposed local Apache. It made `/` return `200 OK`, but `/weather/local` returned `404` because Apache does not know the weather API route.

If you prefer to choose the public URL and your ngrok account supports it:

```sh
NGROK_LOCAL_URL=http://127.0.0.1:5035 \
NGROK_URL=https://weather-demo.example.ngrok.app \
  ./scripts/start-ngrok-demo.sh
```

Use the same pattern with `5037` if Aspire owns `5035`.

ngrok prints a public HTTPS URL like:

```text
https://random-name.ngrok-free.app
```

Share only that HTTPS URL for the demo.

Demo URLs:

```text
https://random-name.ngrok-free.app/
https://random-name.ngrok-free.app/weather/local
```

Verify the public weather API:

```sh
curl -i https://random-name.ngrok-free.app/weather/local
```

Expected public API result:

```text
HTTP/2 200
content-type: application/json
```

ngrok also provides a traffic inspector in the dashboard. Use it to see incoming request paths and status codes during the demo without changing the app.

If `/` works but `/weather/local` does not, check what ngrok is forwarding to:

```sh
curl -fsS http://127.0.0.1:4040/api/tunnels
```

Good target:

```text
http://127.0.0.1:5035
http://127.0.0.1:5037
```

Wrong target for this app:

```text
http://localhost:80
```

#### 4. Safer Demo With Basic Auth

A public ngrok URL is reachable from the internet. For anything beyond a quick screen-share demo, enable basic auth through `.env.local`:

```sh
NGROK_BASIC_AUTH_ENABLED=true
NGROK_BASIC_AUTH_USER=demo
NGROK_BASIC_AUTH_PASSWORD=<choose-a-password>
```

Start ngrok through the helper. The helper creates a temporary Traffic Policy file from local env values and deletes it when ngrok exits.

```sh
NGROK_LOCAL_URL=http://127.0.0.1:5035 ./scripts/start-ngrok-demo.sh
```

Use `5037` if the Kubernetes stack is running on the fallback port:

```sh
NGROK_LOCAL_URL=http://127.0.0.1:5037 ./scripts/start-ngrok-demo.sh
```

Demo login:

```text
username: demo
password: value from NGROK_BASIC_AUTH_PASSWORD in .env.local
```

If your plan supports a fixed public URL, combine it with the policy:

```sh
NGROK_LOCAL_URL=http://127.0.0.1:5035 \
NGROK_URL=https://weather-demo.example.ngrok.app \
  ./scripts/start-ngrok-demo.sh
```

#### 5. Observe Demo Traffic

While the public demo is running, watch Kubernetes logs:

```sh
kubectl --context kind-devops-lite logs deploy/weather-live-stream -f
```

Watch Nginx logs:

```sh
kubectl --context kind-devops-lite logs deploy/weather-nginx -f
```

Watch OpenTelemetry trace batches:

```sh
kubectl --context kind-devops-lite logs -n observability deploy/otel-collector -f
```

Generate a public request:

```sh
curl -i https://random-name.ngrok-free.app/weather/local
```

Then check trace output:

```sh
kubectl --context kind-devops-lite logs -n observability deploy/otel-collector --tail=200 \
  | grep -Ei "traces|span|status|weather-live-stream"
```

#### 6. Stop The Public Demo

Stop ngrok with `Ctrl+C` in the terminal running `ngrok http`.

Stop the Kubernetes weather stack:

```sh
./scripts/stop-weather-service.sh
```

The ngrok helper removes its temporary auth policy automatically.

#### 7. Public Demo Rules

- Use ngrok for short demos, webhook testing, or stakeholder review.
- Do not put secrets, admin dashboards, or production data behind a random public URL.
- Prefer basic auth or OAuth when anyone outside your machine can access the URL.
- Keep the app behind Nginx; do not expose the app pod directly unless debugging.
- Stop ngrok when the demo is over.
- For real production access, use managed Kubernetes ingress, DNS, TLS, WAF/rate limits, observability, and authentication instead of ngrok.
- If you need a stable team-facing demo endpoint, use cloud ingress or a managed environment rather than ngrok.

### Why Not Let GitHub Actions Deploy Directly To OrbStack

- GitHub-hosted runners cannot reach the kind cluster running on this Mac.
- A self-hosted runner on this Mac can reach OrbStack, but it gives GitHub workflow jobs direct access to local Docker and Kubernetes.
- Argo CD is safer for Kubernetes delivery because it pulls desired state from Git while running inside the cluster.
- GitHub Actions should build and publish artifacts; Argo CD should reconcile the cluster.

### Cost Notes For GitHub Actions

- Public repositories normally get GitHub-hosted CI without Actions minute charges.
- Private repositories get included minutes based on the GitHub plan, then pay beyond that.
- Linux runners are the cheapest hosted option and are enough for this .NET container build.
- Self-hosted runners do not consume GitHub-hosted runner minutes, but your Mac supplies the CPU, disk, and network.
- Keep this workflow on `ubuntu-latest`; do not use hosted macOS runners unless the job really needs macOS.

### Argo CD vs GitHub Actions CD

```text
GitHub Actions CD
  push model: workflow runs kubectl apply
  runner needs cluster credentials
  useful for simple remote clusters

Argo CD
  pull model: controller watches Git
  cluster reconciles itself to Git
  better fit for Kubernetes GitOps
```

## Step 2 - Check Which Kubernetes Cluster You Are Viewing

```sh
kubectl config get-contexts
kubectl config current-context
```

Expected project context:

```text
kind-devops-lite
```

Useful checks:

```sh
kubectl --context orbstack get pods -A
kubectl --context kind-devops-lite get pods -A
```

## Step 3 - Start The Weather Stack

```sh
cd /Users/kingwong/Downloads/devops
./scripts/start-weather-service.sh
```

This does four things:

- builds `weather-live-stream:local`
- loads the image into the kind cluster
- applies `weather-live-stream` and `weather-nginx`
- exposes Nginx at `http://127.0.0.1:5035`

Check it:

```sh
curl -i http://127.0.0.1:5035/
curl -i http://127.0.0.1:5035/weather/local
```

## Step 4 - Inspect And Stop

Inspect the kind cluster:

```sh
kubectl --context kind-devops-lite get pods -A
kubectl --context kind-devops-lite get svc -A
kubectl --context kind-devops-lite get deploy -A
```

Stop only the weather app:

```sh
./scripts/stop-weather-service.sh
```

Delete the whole kind cluster when disk is tight:

```sh
kind delete cluster --name devops-lite
```

## User Manual Notes

- Use `docker` for containers and images; OrbStack provides the Docker backend.
- Use `orb` or `orbctl` for OrbStack machines and OrbStack management.
- Use `kubectl` for Kubernetes resources.
- Use `kind` to create or delete the disposable local Kubernetes cluster.
- Do not rely on the OrbStack Kubernetes UI for kind resources; use `kubectl --context kind-devops-lite`.
