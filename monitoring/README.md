# Monitoring – Prometheus + Grafana on k3s

This folder adds simple monitoring to the QuakeWatch server. Once it's installed you can
open dashboards that show how the **EC2 instance** (CPU, memory, disk, network) and the
**k3s cluster** (nodes, pods, restarts, resource usage) are doing.

## What is it?

- **Prometheus** is a database for metrics. Every 30 seconds it goes out and collects
  ("scrapes") numbers from different places and stores them with a timestamp.
- **Grafana** is the website you look at. It reads the data from Prometheus and draws it
  as graphs and dashboards.
- **node-exporter** runs on the server and reports the EC2 machine's own stats – CPU,
  RAM, disk space, network traffic.
- **kube-state-metrics** reports what Kubernetes knows – how many pods are running,
  which ones restarted, what the HPA is doing, and so on.
- **kubelet / cAdvisor** (built into k3s) report how much CPU and memory each container uses.

All of this comes from one well-known Helm chart:
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).
It also ships with ready-made Grafana dashboards, so there's nothing to build yourself.

```
  EC2 instance ──► node-exporter ───────┐
  k3s / pods   ──► kubelet, cAdvisor ───┼──► Prometheus ──► Grafana ──► your browser
  Kubernetes   ──► kube-state-metrics ──┘    (stores)      (shows)     (via SSH tunnel)
```

## Files

| File          | What it does                                                        | Where you run it |
|---------------|---------------------------------------------------------------------|------------------|
| `values.yaml` | Settings for the chart, trimmed down for one small server           | –                |
| `install.sh`  | Installs Prometheus + Grafana and prints the Grafana password       | On the EC2 server |
| `tunnel.sh`   | Opens Grafana and Prometheus on your laptop through SSH              | On your laptop   |

What I changed from the chart defaults (all in `values.yaml`):

- **Alertmanager is off** – it sends alert notifications, which we don't need here.
- **Metrics are kept for 2 days** and memory is limited, so it fits next to the app on a `t3.medium`.
- **Scheduler, controller-manager, kube-proxy and etcd monitoring are off** – in k3s these
  all live inside one k3s process instead of separate pods, so Prometheus can't reach them the
  normal way. Leaving them on just gives you red "down" targets that aren't real problems.

## How to use it

You need the server running first (see the [main README](../README.md)).
The repo is already cloned on the server, so this folder is there too.

### 1. Install it (on the server)

```bash
ssh ubuntu@<instance_public_ip>
bash ~/quakewatch-aws/monitoring/install.sh
```

It takes 2–3 minutes. At the end you'll see the pods and the Grafana login:

```
NAME                                                     READY   STATUS    RESTARTS   AGE
monitoring-grafana-xxxxx                                 3/3     Running   0          2m
monitoring-kube-prometheus-operator-xxxxx                1/1     Running   0          2m
monitoring-kube-state-metrics-xxxxx                      1/1     Running   0          2m
monitoring-prometheus-node-exporter-xxxxx                1/1     Running   0          2m
prometheus-monitoring-kube-prometheus-prometheus-0       2/2     Running   0          2m

Grafana user:     admin
Grafana password: <random password>
```

Copy the password. You can always get it again with:

```bash
kubectl get secret -n monitoring monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Type `exit` to leave the server.

### 2. Open the dashboards (on your laptop)

Our security group only opens ports 80 and 22, and that's on purpose – we don't want
Grafana open to the internet. Instead we reach it **through SSH**, which is already allowed.

```bash
cd quakewatch-aws/monitoring
./tunnel.sh <instance_public_ip>
```

Leave that terminal open and browse to:

- **Grafana:** http://localhost:3000 – log in with `admin` and the password from step 1
- **Prometheus:** http://localhost:9090

Press `Ctrl+C` in the tunnel terminal when you're done.

> How the tunnel works: on the server, `kubectl port-forward` makes Grafana and Prometheus
> available on the server's own `localhost`. SSH then carries those two ports over to your
> laptop's `localhost`. Nothing new is opened in AWS.

### 3. Dashboards worth looking at

In Grafana go to **Dashboards** – they're already there:

| Dashboard                                         | Shows                                          |
|---------------------------------------------------|------------------------------------------------|
| **Node Exporter / Nodes**                         | The EC2 instance: CPU, memory, disk, network   |
| **Kubernetes / Compute Resources / Cluster**      | Overall CPU and memory used by the cluster     |
| **Kubernetes / Compute Resources / Namespace (Pods)** | Pick namespace `quakewatch` to see the app's pods |
| **Kubernetes / Kubelet**                          | Health of k3s on the node                      |

### 4. Check that Prometheus collects everything

Open http://localhost:9090 → **Status → Target health**. Every target should be green (**UP**):
apiserver, kubelet, node-exporter, kube-state-metrics, coredns, grafana, prometheus and the operator.

You can also try a query in the Prometheus search box, for example:

```
# CPU usage of the EC2 instance, in %
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory used by each QuakeWatch pod
sum by (pod) (container_memory_working_set_bytes{namespace="quakewatch", container!=""})
```

## Removing it

On the server:

```bash
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring
```

Or just run `terraform destroy` – everything goes away with the server.

## Good to know

- **Metrics are not saved to disk.** If the Prometheus pod restarts, or you rebuild the server,
  the history starts from zero. That's fine for a demo; for real use you'd add a persistent volume.
- **The QuakeWatch app itself doesn't expose metrics** (there's no `/metrics` endpoint), so
  we see its CPU, memory and restarts from Kubernetes, but not app-level numbers like requests per second.
- **Memory:** the whole stack uses roughly 600–800 MB, which fits on a `t3.medium` (4 GB)
  next to QuakeWatch. On a smaller instance it may get tight.

## Troubleshooting

**`tunnel.sh` says `bind: Address already in use`**
Something on your laptop already uses port 3000 or 9090 (maybe an old tunnel). Close it, or
find it with `lsof -i :3000`.

**Grafana page doesn't load**
Make sure the tunnel terminal is still open and the pods are `Running`:
`kubectl get pods -n monitoring` (on the server).

**A pod is stuck in `Pending`**
Usually not enough memory. Check with `kubectl describe pod -n monitoring <pod-name>` and look
at the `Events` at the bottom.
