#!/bin/bash
# Opens the Argo CD UI on YOUR LAPTOP through SSH - no extra ports in the security group.
# Run it ON YOUR LAPTOP:  ./tunnel.sh <instance_public_ip>
# Then browse to http://localhost:8080
# Press Ctrl+C to close the tunnel.
set -euo pipefail

IP="${1:?Usage: ./tunnel.sh <instance_public_ip>}"

echo "Argo CD: http://localhost:8080"
echo "Press Ctrl+C to stop."

ssh -L 8080:localhost:8080 "ubuntu@$IP" '
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  kubectl port-forward -n argocd svc/argocd-server 8080:80
'
