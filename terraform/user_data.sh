#!/bin/bash
# EC2 user data: runs once as root on first boot.
# Rendered by Terraform templatefile(), so shell variables are written without braces.
# Progress log on the instance: /var/log/cloud-init-output.log
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

# Base packages
apt-get update -y
apt-get install -y git curl

# k3s: Traefik is disabled so the built-in ServiceLB can bind the QuakeWatch
# LoadBalancer service directly to port 80. Kubeconfig is readable by the ubuntu user.
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" sh -

# Helm (kubectl can't install a chart by itself; also used for `helm template | kubectl apply`)
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Helm reads ~/.kube/config by default, so point it at the k3s kubeconfig
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /home/ubuntu/.bashrc

# Pull the repository that contains the QuakeWatch Helm chart
git clone "${repo_url}" /home/ubuntu/quakewatch-aws
chown -R ubuntu:ubuntu /home/ubuntu/quakewatch-aws

# Wait until the node is Ready
until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
  sleep 5
done

echo "Bootstrap complete"
