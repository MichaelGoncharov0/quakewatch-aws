# QuakeWatch on AWS

QuakeWatch is a small web dashboard that shows recent earthquakes around the world,
using live data from the [USGS Earthquake API](https://earthquake.usgs.gov/fdsnws/event/1/).

In the earlier phases of this project it ran on a local Kubernetes cluster (Docker Desktop)
and was deployed by Argo CD. This repo is the next step: the same app and Helm chart,
now running on AWS. Terraform builds the infrastructure, and the app runs on a
lightweight Kubernetes cluster ([k3s](https://k3s.io/)) on a single EC2 instance.

## What's in here

```
quakewatch-aws/
├── QuakeWatch-app/        # Flask app + Dockerfile
├── quakewatch-chart/      # Helm chart (values.yaml is set up for k3s on EC2)
├── terraform/             # VPC, security group and EC2 instance with k3s
│   └── README.md          #   👉 step-by-step guide to deploy everything
└── .github/workflows/     # CI and CD pipelines
```

## How it fits together

```text
  Code change ──► Pull request ──► CI (lint + build) ──► Merge to main
                                                             │
                                                             ▼
                                   CD builds the image and pushes it to Docker Hub
                                                             │
                                                             ▼
   terraform apply ──► EC2 boots, installs k3s, clones this repo ──► helm install ──► http://<EC2 public IP>
```

- **CI** (`.github/workflows/quakewatch-ci.yaml`) runs on every pull request: pylint on the
  Python code, `helm lint` on the chart, and a test Docker build.
- **CD** (`.github/workflows/quakewatch-cd.yaml`) runs when app code is merged to `main`.
  It builds the image and pushes it to Docker Hub as
  [`michaelgoncharov0/quakewatch`](https://hub.docker.com/r/michaelgoncharov0/quakewatch).
  The k3s cluster pulls the image from there.
- **Terraform** (`terraform/`) creates the network and the server. The server sets itself up
  on first boot (k3s, Helm, git clone of this repo).

## Getting started

Everything you need – prerequisites, Terraform commands, deploying the chart, checking
the site and cleaning up – is in **[terraform/README.md](terraform/README.md)**.

The short version:

```bash
cd terraform
terraform init
terraform apply

ssh ubuntu@<instance_public_ip>
cd ~/quakewatch-aws
helm install quakewatch ./quakewatch-chart -n quakewatch --create-namespace
```

Then open `http://<instance_public_ip>` in your browser.

When you're done, don't forget `terraform destroy` – the server costs about $1 a day.

## Repository secrets

The CD pipeline needs these secrets in **Settings → Secrets and variables → Actions**:

| Secret               | What it is                                  |
|----------------------|---------------------------------------------|
| `DOCKERHUB_USERNAME` | Your Docker Hub username                    |
| `DOCKERHUB_TOKEN`    | A Docker Hub access token (not your password) |
