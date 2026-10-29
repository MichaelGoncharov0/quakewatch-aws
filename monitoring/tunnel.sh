#!/bin/bash
# Opens Grafana and Prometheus on YOUR LAPTOP through SSH - no extra ports in the security group.
# Run it ON YOUR LAPTOP:  ./tunnel.sh <instance_public_ip>
# Then browse to http://localhost:3000 (Grafana) and http://localhost:9090 (Prometheus).
# Press Ctrl+C to close the tunnel.
set -euo pipefail

IP="${1:?Usage: ./tunnel.sh <instance_public_ip>}"

echo "Grafana:    http://localhost:3000"
echo "Prometheus: http://localhost:9090"
echo "Press Ctrl+C to stop."

ssh -L 3000:localhost:3000 -L 9090:localhost:9090 "ubuntu@$IP" '
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80 &
  kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
'
