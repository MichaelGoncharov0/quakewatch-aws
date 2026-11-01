# QuakeWatch on AWS

QuakeWatch is a small website that shows recent earthquakes around the world, using live data
from the [USGS Earthquake API](https://earthquake.usgs.gov/fdsnws/event/1/).

This repo runs it on AWS in five steps:

1. **Terraform** creates a network and one server (EC2) in AWS.
2. The server **sets itself up** on first boot: it installs Kubernetes ([k3s](https://k3s.io/)),
   Helm and git, and downloads this repo.
3. You **install Argo CD** on the server with one script.
4. **Argo CD deploys QuakeWatch** from this GitHub repo and keeps it up to date.
5. You open `http://<server-ip>` and see the site.

It takes about 10 minutes and costs about **$1 a day** while the server is running.

---

## Contents

- [How it works](#how-it-works)
- [What's in this repo](#whats-in-this-repo)
- [Before you start](#before-you-start)
- [Step 1 – Create the server](#step-1--create-the-server)
- [Step 2 – Connect to the server](#step-2--connect-to-the-server)
- [Step 3 – Install Argo CD](#step-3--install-argo-cd)
- [Step 4 – Open the site](#step-4--open-the-site)
- [Step 5 – Open the Argo CD dashboard](#step-5--open-the-argo-cd-dashboard)
- [Making changes](#making-changes)
- [Monitoring (optional)](#monitoring-optional)
- [Clean up](#clean-up-dont-skip-this)
- [Troubleshooting](#troubleshooting)

---

## How it works

```
   You ──► GitHub repo ◄────────── Argo CD checks it every 3 minutes
                                          │
                                          ▼
   ┌───────────── AWS ──────────────────────────────────────┐
   │  EC2 server (Ubuntu, t3.medium)                        │
   │    └── k3s (Kubernetes)                                │
   │          ├── Argo CD     – deploys the app from GitHub │
   │          └── QuakeWatch  – the website, on port 80     │
   └────────────────────────────────────────────────────────┘
                     ▲
     Firewall: only YOUR IP can reach ports 80 (web) and 22 (SSH)
```

| Part | What it does |
|---|---|
| **Terraform** | Creates everything in AWS: a network (VPC), a firewall (security group), your SSH key and the server. |
| **k3s** | A small Kubernetes that runs on one server. It can serve the site on port 80 without an AWS load balancer. |
| **Helm chart** | The recipe for running QuakeWatch in Kubernetes (pods, service, autoscaling…). Lives in `quakewatch-chart/`. |
| **Argo CD** | Watches the Helm chart in GitHub. When the chart changes, Argo CD updates the cluster to match. You don't deploy by hand. |
| **GitHub Actions** | Checks every pull request (CI) and builds a new Docker image when app code is merged (CD). |

---

## What's in this repo

```
quakewatch-aws/
├── terraform/         Creates the AWS network and server
├── argocd/            Argo CD install script, settings, and the QuakeWatch "Application"
├── quakewatch-chart/  Helm chart for QuakeWatch
├── QuakeWatch-app/    The Python (Flask) app and its Dockerfile
├── monitoring/        Optional Prometheus + Grafana
└── .github/workflows/ CI and CD pipelines
```

---

## Before you start

Install these on your computer:

| What | Check it works |
|---|---|
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (Mac: `brew install awscli`) | `aws --version` |
| [Terraform](https://developer.hashicorp.com/terraform/install) 1.5 or newer | `terraform version` |
| An SSH key at `~/.ssh/id_ed25519.pub` | `ls ~/.ssh/id_ed25519.pub` – missing? Run `ssh-keygen -t ed25519` |

### Get an AWS access key

Terraform needs an AWS access key. Use an **IAM user**, not the root account, and give
each person their own key.

1. In the [AWS Console](https://console.aws.amazon.com/iam/) go to **IAM → Users → Create user**.
   Give it a name (e.g. `dana-terraform`) and leave console access unticked.
2. On the permissions page choose **Attach policies directly** and pick **`AmazonEC2FullAccess`**.
   That's all this project needs.
3. Open the new user → **Security credentials** → **Create access key** → **Command Line Interface (CLI)**.
4. **Download the .csv file.** The secret is shown only once.

Then save the key on your computer:

```bash
aws configure
```

```
AWS Access Key ID [None]: AKIA................
AWS Secret Access Key [None]: ........................................
Default region name [None]: us-east-1
Default output format [None]: json
```

Check it:

```bash
aws sts get-caller-identity    # should end with  user/dana-terraform  (not root)
```

> **Keep the key secret.** Never commit it, paste it in chat, or share it. If it leaks,
> deactivate it in IAM right away and create a new one.

---

## Step 1 – Create the server

On your computer:

```bash
git clone https://github.com/MichaelGoncharov0/quakewatch-aws.git
cd quakewatch-aws/terraform

terraform init     # first time only – downloads what Terraform needs
terraform apply    # shows the plan – type "yes" to create it
```

After 1–2 minutes you'll see:

```
Apply complete! Resources: 14 added, 0 changed, 0 destroyed.

instance_public_ip = "18.207.104.139"
quakewatch_url     = "http://18.207.104.139"
ssh_command        = "ssh ubuntu@18.207.104.139"
```

**Write down the `instance_public_ip`** – you'll use it in every step below.
Forgot it? Run `terraform output`.

> Terraform finds your public IP by itself and only lets that IP through the firewall.
> To change the region or server size, see [`terraform/variables.tf`](terraform/variables.tf).

---

## Step 2 – Connect to the server

Wait **2–3 minutes** for the server to finish setting itself up, then:

```bash
ssh ubuntu@<instance_public_ip>
```

Check that Kubernetes is ready:

```bash
kubectl get nodes
```

```
NAME            STATUS   ROLES           AGE   VERSION
ip-10-0-1-106   Ready    control-plane   2m    v1.36.5+k3s1
```

If it says `Ready`, go on. If not, wait a minute and try again.

---

## Step 3 – Install Argo CD

Still on the server, run:

```bash
bash ~/quakewatch-aws/argocd/install.sh
```

This script:

1. Installs **Argo CD** with Helm (takes 2–3 minutes).
2. Applies [`argocd/quakewatch-app.yaml`](argocd/quakewatch-app.yaml), which tells Argo CD:
   *"deploy the chart in `quakewatch-chart/` from the `main` branch of this repo, into the
   `quakewatch` namespace, and keep it that way."*
3. Prints the Argo CD login at the end:

```
Argo CD user:     admin
Argo CD password: <random password>
```

**Copy the password** – you'll need it in Step 5.

Argo CD now deploys QuakeWatch by itself. After about a minute, check:

```bash
kubectl get pods -n quakewatch
```

```
NAME                          READY   STATUS    RESTARTS   AGE
quakewatch-6599bbd957-gxns8   1/1     Running   0          1m
quakewatch-6599bbd957-hf6kq   1/1     Running   0          1m
quakewatch-6599bbd957-rcjr2   1/1     Running   0          1m
```

When the pods show **`Running`** and **`1/1`**, type `exit` to leave the server.

---

## Step 4 – Open the site

In your browser (use `http://`, not `https://`):

```
http://<instance_public_ip>
```

You should see the QuakeWatch dashboard. 🎉

> **Site won't load on a work laptop?** Company networks often send web traffic through a proxy
> with a different IP, so the firewall blocks it. Try your phone on your home Wi-Fi, or run
> `ssh -L 8081:localhost:80 ubuntu@<instance_public_ip>` and open http://localhost:8081.

---

## Step 5 – Open the Argo CD dashboard

The Argo CD dashboard is **not** open to the internet. You reach it through SSH.

On your computer:

```bash
cd quakewatch-aws/argocd
./tunnel.sh <instance_public_ip>
```

Keep that terminal open and go to **http://localhost:8080**.
Log in as `admin` with the password from Step 3.

You'll see the **quakewatch** app. It should show:

- **Healthy** (green heart) – all the app's parts are running
- **Synced** (green tick) – the cluster matches what's in GitHub

Click it to see every part of the app (pods, service, autoscaler…) as a tree.
Press `Ctrl+C` in the terminal to close the tunnel.

**Lost the password?** On the server:

```bash
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

---

## Making changes

**Always change the repo, not the cluster.** Argo CD keeps the cluster the same as GitHub,
so if you change something by hand (e.g. `kubectl edit` or `kubectl scale`), Argo CD will
put it back.

### Changing the Helm chart (anything in `quakewatch-chart/`)

1. Change the file and open a pull request.
2. Wait for the **CI** check to pass, then merge to `main`.
3. Argo CD picks up the change **within about 3 minutes**.
   In a hurry? Click **Refresh** on the app in the Argo CD dashboard.

### Changing the app code (anything in `QuakeWatch-app/`)

1. Change the code, open a pull request, wait for **CI**, then merge to `main`.
2. **CD** builds a new Docker image and pushes it to Docker Hub as
   [`michaelgoncharov0/quakewatch:latest`](https://hub.docker.com/r/michaelgoncharov0/quakewatch).
3. The image name didn't change, so Argo CD doesn't see anything new. Restart the app to
   pull the new image – on the server:
   ```bash
   kubectl rollout restart deployment quakewatch -n quakewatch
   ```
   Or in the Argo CD dashboard: open the app → click the **quakewatch** deployment → **⋮** → **Restart**.

### CI/CD pipelines

| Pipeline | Runs when | What it does |
|---|---|---|
| **CI** – [`quakewatch-ci.yaml`](.github/workflows/quakewatch-ci.yaml) | Every pull request | Checks the Python code (pylint), checks the chart (`helm lint`), test-builds the Docker image |
| **CD** – [`quakewatch-cd.yaml`](.github/workflows/quakewatch-cd.yaml) | App code merged to `main` | Builds the image and pushes it to Docker Hub |

CD needs two secrets in GitHub → **Settings → Secrets and variables → Actions**:
`DOCKERHUB_USERNAME` (your Docker Hub username) and `DOCKERHUB_TOKEN` (a Docker Hub access token, not your password).

---

## Monitoring (optional)

Adds **Prometheus** (collects numbers like CPU and memory) and **Grafana** (draws graphs
of them) with ready-made dashboards.

**1. Install it – on the server:**

```bash
ssh ubuntu@<instance_public_ip>
bash ~/quakewatch-aws/monitoring/install.sh
```

It takes 2–3 minutes and prints the Grafana password at the end. Copy it, then `exit`.

**2. Open it – on your computer:**

```bash
cd quakewatch-aws/monitoring
./tunnel.sh <instance_public_ip>
```

- **Grafana** → http://localhost:3000 (user `admin`, password from step 1)
- **Prometheus** → http://localhost:9090

**3. Dashboards worth opening in Grafana:**

| Dashboard | Shows |
|---|---|
| **Node Exporter / Nodes** | The server's CPU, memory, disk and network |
| **Kubernetes / Compute Resources / Namespace (Pods)** | Pick `quakewatch` to see the app's pods |

> Graphs start from zero if Prometheus restarts – history isn't saved to disk.

---

## Clean up (don't skip this!)

The server costs about **$1 a day**. When you're done, on your computer:

```bash
cd quakewatch-aws/terraform
terraform destroy    # type "yes"
```

This deletes everything Terraform created. Want it back? Run `terraform apply` again and
repeat Steps 2–3 (you'll get a **new** IP).

---

## Troubleshooting

| Problem | Fix |
|---|---|
| **Site or SSH suddenly stopped working** | Your home IP probably changed (router restart, VPN, new Wi-Fi). Run `terraform apply` again – it updates the firewall with your new IP. |
| **`kubectl get nodes` says "connection refused"** | The server is still setting up. Wait a minute. To watch progress: `sudo tail -f /var/log/cloud-init-output.log` (it ends with `Bootstrap complete`). |
| **`helm` says "Kubernetes cluster unreachable"** | Run `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` and try again. |
| **Argo CD app shows *OutOfSync*** | Click **Sync** in the dashboard. If it keeps coming back, someone changed the cluster by hand – change the repo instead. |
| **Argo CD app shows *Degraded* or pods are not `Running`** | Run `kubectl describe pod -n quakewatch <pod-name>` – the **Events** at the bottom say what's wrong. |
| **`tunnel.sh` says "Address already in use"** | An old tunnel is still open. Close that terminal, or find it with `lsof -i :8080`. |
| **`terraform apply` fails with `error asking for approval: EOF`** | Run it in a normal terminal so you can type `yes`. |
