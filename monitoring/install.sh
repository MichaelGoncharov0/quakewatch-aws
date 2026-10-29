#!/bin/bash
# Installs Prometheus + Grafana on the k3s cluster.
# Run it ON THE EC2 SERVER:  bash ~/quakewatch-aws/monitoring/install.sh
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
CHART_VERSION="92.15.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version "$CHART_VERSION" \
  --namespace monitoring --create-namespace \
  -f "$SCRIPT_DIR/values.yaml" \
  --wait --timeout 10m

echo
kubectl get pods -n monitoring
echo
echo "Grafana user:     admin"
echo "Grafana password: $(kubectl get secret -n monitoring monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
