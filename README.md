# QuakeWatch on AWS

QuakeWatch is a small website that shows recent earthquakes around the world, using live data
from the [USGS Earthquake API](https://earthquake.usgs.gov/fdsnws/event/1/).

This repo runs it on AWS:

1. You make **your own copy** of this repo on GitHub, and **your own Docker Hub repo** for the
   app's image. GitHub Actions builds the image and pushes it there.
2. **Terraform** creates a network and one server (EC2) in AWS.
3. The server **sets itself up** on first boot: it installs Kubernetes ([k3s](https://k3s.io/)),
   Helm and git, and downloads your repo.
4. You **install Argo CD** on the server with one script.
5. **Argo CD deploys QuakeWatch** from your GitHub repo, using the image from your Docker Hub,
   and keeps it up to date.
6. You open `http://<server-ip>` and see the site.

It takes about 20 minutes and costs about **$1 a day** while the server is running.

---

## Contents

- [How it works](#how-it-works)
- [What's in this repo](#whats-in-this-repo)
- [Before you start](#before-you-start)
- [Step 1 – Make your own copy of the repo](#step-1--make-your-own-copy-of-the-repo)
- [Step 2 – Create the server](#step-2--create-the-server)
- [Step 3 – Connect to the server](#step-3--connect-to-the-server)
- [Step 4 – Install Argo CD](#step-4--install-argo-cd)
- [Step 5 – Open the site](#step-5--open-the-site)
- [Step 6 – Open the Argo CD dashboard](#step-6--open-the-argo-cd-dashboard)
- [Making changes](#making-changes)
- [Monitoring (optional)](#monitoring-optional)
- [Clean up](#clean-up-dont-skip-this)
- [Troubleshooting](#troubleshooting)

---

## How it works

```
   You ──► YOUR GitHub repo ──► GitHub Actions builds the image ──► YOUR Docker Hub repo
                 ▲                                                          │
                 │ Argo CD checks it every 3 minutes                        │ k3s downloads
                 │                                                          │ the image
                 │                                        ┌─────────────────┘
                 │                                        ▼
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
| **Argo CD** | Watches the Helm chart in your GitHub repo. When the chart changes, Argo CD updates the cluster to match. You don't deploy by hand. |
| **GitHub Actions** | Checks every pull request (CI). When app code changes, builds a new Docker image and pushes it to your Docker Hub (CD). |
| **Docker Hub** | Stores the app's Docker image. The server downloads it from your Docker Hub repo. |

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

You need:

| What | Check it works |
|---|---|
| A [GitHub](https://github.com/) account and [git](https://git-scm.com/downloads) | `git --version` |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (Mac: `brew install awscli`) | `aws --version` |
| [Terraform](https://developer.hashicorp.com/terraform/install) 1.5 or newer | `terraform version` |
| An SSH key at `~/.ssh/id_ed25519.pub` | `ls ~/.ssh/id_ed25519.pub` – missing? Run `ssh-keygen -t ed25519` |
| A [Docker Hub](https://hub.docker.com/) account (the free plan is enough) | You can log in at hub.docker.com |

### Get an AWS access key

Terraform needs an AWS access key. Use an **IAM user**, not the root account, and give
each person their own key.

1. In the [AWS Console](https://console.aws.amazon.com/iam/) go to **IAM → Users → Create user**.
   Give it a name (e.g. `dana-terraform`) and leave console access unticked.
2. On the permissions page choose **Attach policies directly** and pick **`AmazonEC2FullAccess`**.
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

## Step 1 – Make your own copy of the repo

> **Don't push to the original repo or the original Docker Hub image.** You'll use your own
> GitHub repo (for the code) and your own Docker Hub repo (for the app image). The server and
> Argo CD pull from **yours**, so every change you make is under your control.

**1. Create an empty repo on GitHub**

On GitHub click **+ → New repository**. Name it `quakewatch-aws`, make it **Public**, and
**don't** tick "Add a README" – it must be empty.

> It needs to be public because the server and Argo CD download it without a password.

**2. Create a repo on Docker Hub**

On [Docker Hub](https://hub.docker.com/) go to **Repositories → Create a repository**.
Name it `quakewatch` and set it to **Public**.

> Public for the same reason – the server downloads the image without a password.

**3. Create a Docker Hub access token**

In Docker Hub go to **Account settings → Personal access tokens → Generate new token**.
Give it **Read & Write** access and **copy the token** – it's shown only once.

**4. Give GitHub your Docker Hub login**

In **your** GitHub repo go to **Settings → Secrets and variables → Actions → New repository secret**
and add these two:

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | The token from the step above (not your password) |

The CD pipeline uses them to push images to your Docker Hub.

**5. Download this project and point it at your repo**

Replace `<your-github-user>` with your GitHub username:

```bash
git clone https://github.com/MichaelGoncharov0/quakewatch-aws.git
cd quakewatch-aws
git remote set-url origin https://github.com/<your-github-user>/quakewatch-aws.git
```

The last line changes where `git push` goes – from now on it goes to **your** repo.
Check it with `git remote -v`.

**6. Tell the project to use your repos**

Open these four files and change the names to yours:

| File | Line to change | Replace with | What it's for |
|---|---|---|---|
| [`terraform/variables.tf`](terraform/variables.tf) | `default = "https://github.com/MichaelGoncharov0/quakewatch-aws.git"` (under `repo_url`) | Your **GitHub** username | The repo the server downloads |
| [`argocd/quakewatch-app.yaml`](argocd/quakewatch-app.yaml) | `repoURL: https://github.com/MichaelGoncharov0/quakewatch-aws.git` | Your **GitHub** username | The repo Argo CD deploys from |
| [`.github/workflows/quakewatch-cd.yaml`](.github/workflows/quakewatch-cd.yaml) | `images: michaelgoncharov0/quakewatch` | Your **Docker Hub** username | Where CD pushes the image |
| [`quakewatch-chart/values.yaml`](quakewatch-chart/values.yaml) | `repository: michaelgoncharov0/quakewatch` | Your **Docker Hub** username | Where the server downloads the image from |

**7. Push it to your repo**

```bash
git add .
git commit -m "Use my own GitHub and Docker Hub repos"
git push -u origin main
```

This push also starts the **CD** pipeline (because you changed its file). It builds the app
image and pushes it to your Docker Hub:

1. In your GitHub repo open the **Actions** tab and wait for **QuakeWatch CD** to turn green (2–3 minutes).
2. In Docker Hub open your `quakewatch` repo – you should see a `latest` tag.

**Wait for the `latest` tag before Step 2** – without it the server has no image to run.

---

## Step 2 – Create the server

On your computer, from the `quakewatch-aws` folder:

```bash
cd terraform

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

## Step 3 – Connect to the server

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

## Step 4 – Install Argo CD

Still on the server, run:

```bash
bash ~/quakewatch-aws/argocd/install.sh
```

This script:

1. Installs **Argo CD** with Helm (takes 2–3 minutes).
2. Applies [`argocd/quakewatch-app.yaml`](argocd/quakewatch-app.yaml), which tells Argo CD:
   *"deploy the chart in `quakewatch-chart/` from the `main` branch of your repo, into the
   `quakewatch` namespace, and keep it that way."*
3. Prints the Argo CD login at the end:

```
Argo CD user:     admin
Argo CD password: <random password>
```

**Copy the password** – you'll need it in Step 6.

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

## Step 5 – Open the site

In your browser (use `http://`, not `https://`):

```
http://<instance_public_ip>
```

You should see the QuakeWatch dashboard. 🎉

---

## Step 6 – Open the Argo CD dashboard

The Argo CD dashboard is **not** open to the internet. You reach it through SSH.

On your computer:

```bash
cd quakewatch-aws/argocd
./tunnel.sh <instance_public_ip>
```

Keep that terminal open and go to **http://localhost:8080**.
Log in as `admin` with the password from Step 4.

You'll see the **quakewatch** app. It should show:

- **Healthy** (green heart) – all the app's parts are running
- **Synced** (green tick) – the cluster matches what's in your GitHub repo

Click it to see every part of the app (pods, service, autoscaler…) as a tree.
Press `Ctrl+C` in the terminal to close the tunnel.

**Lost the password?** On the server:

```bash
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

---

## Making changes

All changes go to **your own repo**. Argo CD keeps the cluster the same as your repo, so if
you change something by hand in the cluster (e.g. `kubectl edit` or `kubectl scale`), Argo CD
will put it back.

### Changing the Helm chart (anything in `quakewatch-chart/`)

1. Change the file, commit, and push to your repo (or open a pull request in your repo and merge it).
2. Argo CD picks up the change **within about 3 minutes**.
   In a hurry? Click **Refresh** on the app in the Argo CD dashboard.

### Changing the app code (anything in `QuakeWatch-app/`)

1. Change the code, commit, and push to `main` in your repo (or open a pull request and merge it).
2. **CD** builds a new image and pushes it to your Docker Hub as `<your-dockerhub-user>/quakewatch:latest`.
   Watch it in the **Actions** tab.
3. The image name didn't change, so Argo CD doesn't see anything new. Restart the app to
   pull the new image – on the server:
   ```bash
   kubectl rollout restart deployment quakewatch -n quakewatch
   ```
   Or in the Argo CD dashboard: open the app → click the **quakewatch** deployment → **⋮** → **Restart**.

### CI/CD pipelines

These run in **your** GitHub repo, under the **Actions** tab.

| Pipeline | Runs when | What it does |
|---|---|---|
| **CI** – [`quakewatch-ci.yaml`](.github/workflows/quakewatch-ci.yaml) | Every pull request | Checks the Python code (pylint), checks the chart (`helm lint`), test-builds the Docker image |
| **CD** – [`quakewatch-cd.yaml`](.github/workflows/quakewatch-cd.yaml) | App code pushed to `main` | Builds the image and pushes it to your Docker Hub |

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

This deletes everything Terraform created. Your GitHub repo is not touched. Want the server
back? Run `terraform apply` again and repeat Steps 3–4 (you'll get a **new** IP).

---

## Troubleshooting

| Problem | Fix |
|---|---|
| **Site or SSH suddenly stopped working** | Your home IP probably changed (router restart, VPN, new Wi-Fi). Run `terraform apply` again – it updates the firewall with your new IP. |
| **`git push` says "Permission denied" or "403"** | You're pushing to the original repo. Run `git remote -v` – it should show **your** username. Fix it with `git remote set-url origin https://github.com/<your-github-user>/quakewatch-aws.git`. |
| **My changes don't show up on the server** | Check that `repo_url` in `terraform/variables.tf` and `repoURL` in `argocd/quakewatch-app.yaml` point to **your** repo, and that you pushed. |
| **Pods show `ImagePullBackOff` or `ErrImagePull`** | The server can't download the image. Check that CD finished (green in **Actions**), your Docker Hub repo has a `latest` tag and is **Public**, and `repository:` in `quakewatch-chart/values.yaml` has **your** Docker Hub username. |
| **`kubectl get nodes` says "connection refused"** | The server is still setting up. Wait a minute. To watch progress: `sudo tail -f /var/log/cloud-init-output.log` (it ends with `Bootstrap complete`). |
| **`helm` says "Kubernetes cluster unreachable"** | Run `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` and try again. |
| **Argo CD app shows *OutOfSync*** | Click **Sync** in the dashboard. If it keeps coming back, someone changed the cluster by hand – change the repo instead. |
| **Argo CD app shows *Degraded* or pods are not `Running`** | Run `kubectl describe pod -n quakewatch <pod-name>` – the **Events** at the bottom say what's wrong. |
| **CD fails with "unauthorized" or "denied"** | The Docker Hub secrets are missing or wrong in your GitHub repo, the token doesn't have **Write** access, or `images:` in `quakewatch-cd.yaml` still says `michaelgoncharov0`. See [Step 1](#step-1--make-your-own-copy-of-the-repo). |
| **`tunnel.sh` says "Address already in use"** | An old tunnel is still open. Close that terminal, or find it with `lsof -i :8080`. |
| **`terraform apply` fails with `error asking for approval: EOF`** | Run it in a normal terminal so you can type `yes`. |
