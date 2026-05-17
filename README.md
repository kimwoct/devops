# macOS Local DevOps Essentials

CLI-only local DevOps setup for a low-disk macOS machine using OrbStack as the Docker backend and kind as the local Kubernetes cluster.

This guide is tuned for this Mac's current disk pressure: about 29 GiB free on `/`. It prioritizes quick local API and exporter development, not production parity.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Container runtime | OrbStack + Docker CLI | Lightweight Docker Desktop replacement with the `docker` client needed by kind. |
| Kubernetes | kind | Disposable local Kubernetes clusters running in Docker containers. |
| Observability | kube-prometheus-stack | Prometheus Operator, Prometheus, Grafana, kube-state-metrics. |
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
CLUSTER_NAME=devops-lite IMAGE_NAME=weather-live-stream:local ./scripts/start-weather-service.sh
```

The script does not require the host .NET SDK to match the app target framework because the build happens inside the .NET 10 SDK container image.

For direct app debugging without Nginx, run a temporary port-forward in another shell:

```sh
kubectl --context kind-devops-lite port-forward svc/weather-live-stream 5036:80 --address 127.0.0.1
curl -i http://127.0.0.1:5036/weather/local
```

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
- To use Aspire for the weather service, add an Aspire AppHost project and register `WeatherLiveStream.App` there. Run the AppHost locally when you want the Aspire dashboard experience, and keep the kind script for validating the containerized Kubernetes path.
- If the weather service should appear with richer telemetry in Aspire, wire the app to OpenTelemetry/Aspire service defaults so it exports logs, metrics, and traces to the dashboard instead of only serving HTTP traffic.

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
REPO_URL="https://github.com/OWNER/REPO.git" ./scripts/install-argocd.sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

### Current Repo Paths

- GitHub Actions workflow: `.github/workflows/ci.yml`
- Argo CD bootstrap: `scripts/install-argocd.sh`
- GitOps manifests: `gitops/`
- CI/CD map: `docs/orbstack-kind-map.md`
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
