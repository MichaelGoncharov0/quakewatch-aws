#!/bin/bash
# EC2 user data: runs once as root on first boot.
# Rendered by Terraform templatefile(), so shell variables are written without braces.
# Progress log on the instance: /var/log/cloud-init-output.log
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# Base packages
apt-get update -y
apt-get install -y git curl openssl

# 2 GB swap file: a free safety net for the system itself (k3s, containerd) so a short
# memory spike slows things down instead of killing them. k3s runs fine with swap on;
# pods themselves don't use it. Kept on after reboots via /etc/fstab.
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# k3s: Traefik is disabled so the built-in ServiceLB can bind the QuakeWatch
# LoadBalancer service directly to port 80. Kubeconfig is readable by the ubuntu user.
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -

# Helm (handy for looking around: `helm list -A`)
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Helm reads ~/.kube/config by default, so point it at the k3s kubeconfig
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /home/ubuntu/.bashrc

# Pull the repository that contains the Argo CD manifests and the QuakeWatch Helm chart
REPO=/home/ubuntu/quakewatch-aws
git clone "${repo_url}" "$REPO"
chown -R ubuntu:ubuntu "$REPO"

# Wait until the node is Ready
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  sleep 5
done

# Grafana admin password: random, created here so it is never stored in Git
kubectl create namespace monitoring
kubectl create secret generic grafana-admin -n monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -hex 16)"

# k3s installs anything placed in its auto-deploy folder - here, the Argo CD Helm chart
MANIFESTS=/var/lib/rancher/k3s/server/manifests
cp "$REPO/argocd/argocd.yaml" "$MANIFESTS/argocd.yaml"

# Once Argo CD is installed, hand it the "app of apps".
# From here Argo CD deploys everything in argocd/apps/ (QuakeWatch and monitoring) from Git.
until kubectl get crd applications.argoproj.io >/dev/null 2>&1; do
  sleep 5
done
cp "$REPO/argocd/root-app.yaml" "$MANIFESTS/root-app.yaml"

echo "Bootstrap complete"
