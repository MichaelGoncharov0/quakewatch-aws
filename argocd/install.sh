#!/bin/bash
# Installs Argo CD on the k3s cluster and tells it to deploy QuakeWatch.
# Run it ON THE EC2 SERVER:  bash ~/quakewatch-aws/argocd/install.sh
set -euo pipefail

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
CHART_VERSION="10.10.3"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --version "$CHART_VERSION" \
  --namespace argocd --create-namespace \
  -f "$SCRIPT_DIR/values.yaml" \
  --wait --timeout 10m

kubectl apply -f "$SCRIPT_DIR/quakewatch-app.yaml"

echo
kubectl get pods -n argocd
echo
echo "Argo CD user:     admin"
echo "Argo CD password: $(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
