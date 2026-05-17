# OrbStack + kind Map

This project uses OrbStack as the local Docker engine and kind as the Kubernetes cluster for the weather stack.

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
              | - weather-nginx              |
              | - weather-live-stream        |
              | - redis                      |
              | - redpanda                   |
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

## Step 1 - Understand The Roles

- OrbStack replaces Docker Desktop for this setup.
- Docker images and kind node containers run inside OrbStack.
- kind creates a Kubernetes cluster inside Docker.
- `kubectl` talks to whichever Kubernetes context is selected.
- The weather app is not deployed to OrbStack's built-in Kubernetes context; it is deployed to kind.

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
Observe service health            Prometheus + Grafana
Replace local dependencies        Redis + Redpanda in cluster
Clean everything quickly          delete namespace / delete cluster
```

For this project:

- `weather-nginx` teaches reverse proxy and edge routing.
- `weather-live-stream` teaches app deployment, probes, and service discovery.
- `redis` teaches cache/state projection.
- `redpanda` teaches Kafka-compatible event streaming.
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
Prometheus + Grafana + alerts
```

Practical production patterns:

- Run multiple app replicas across multiple nodes.
- Use readiness probes so bad pods do not receive traffic.
- Use horizontal autoscaling based on CPU, memory, request rate, or queue lag.
- Put Nginx or cloud ingress in front of app services.
- Use Redis for repeated hot reads, sessions, rate limits, and short-lived projections.
- Use Kafka or Redpanda for async work so user requests do not wait on slow side effects.
- Use Prometheus metrics to track latency, errors, saturation, and throughput.
- Use rolling deployments and quick rollback for safer releases.

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
