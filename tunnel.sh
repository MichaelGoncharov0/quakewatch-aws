#!/bin/bash
# Opens the Argo CD, Grafana and Prometheus dashboards on YOUR LAPTOP through SSH -
# no extra ports in the security group.
# Run it ON YOUR LAPTOP:  ./tunnel.sh <instance_public_ip>
# Press Ctrl+C to close the tunnel (this also stops the port-forwards on the server).
set -euo pipefail

IP="${1:?Usage: ./tunnel.sh <instance_public_ip>}"

echo "Argo CD:    http://localhost:8080"
echo "Grafana:    http://localhost:3000"
echo "Prometheus: http://localhost:9090"
echo "Press Ctrl+C to stop."

# -t: allocate a TTY so Ctrl+C / disconnect hangs up the remote side too.
# ExitOnForwardFailure: fail fast if a local port is already taken.
ssh -t -o ExitOnForwardFailure=yes \
  -L 8080:localhost:8080 -L 3000:localhost:3000 -L 9090:localhost:9090 "ubuntu@$IP" '
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  # Clear port-forwards left over from earlier runs, which would hold the ports.
  pkill -f "kubectl port-forward" || true
  # Stop every forward started below when this session ends.
  trap "kill 0" EXIT INT TERM HUP
  # Restart a forward when it drops (e.g. after a pod restart).
  pf() { while true; do kubectl port-forward "$@"; sleep 2; done; }
  pf -n argocd svc/argocd-server 8080:80 &
  pf -n monitoring svc/monitoring-grafana 3000:80 &
  pf -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090 &
  wait
'
