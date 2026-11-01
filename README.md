# QuakeWatch on AWS

QuakeWatch is a small website that shows recent earthquakes around the world, using live data
from the [USGS Earthquake API](https://earthquake.usgs.gov/fdsnws/event/1/).

This repo runs it on AWS:

1. You make **your own copy** of this repo on GitHub, and **your own Docker Hub repo** for the
   app's image. GitHub Actions builds the image and pushes it there.
2. You run **`terraform apply`**. It creates a network and one server (EC2) in AWS.
3. The server **sets everything up by itself** on first boot: Kubernetes ([k3s](https://k3s.io/)),
   then **Argo CD**, and Argo CD then deploys **QuakeWatch** and **Prometheus + Alertmanager +
   Grafana** from your GitHub repo.
4. You open `http://<server-ip>` and see the site.

There's nothing to install by hand on the server. It takes about 20 minutes and costs about
**$0.75 a day** while the server is running (a cheap "Spot" server – see [Cost](#cost-and-spot-servers)).

---

## Contents

- [How it works](#how-it-works)
- [What's in this repo](#whats-in-this-repo)
- [Before you start](#before-you-start)
- [Step 1 – Make your own copy of the repo](#step-1--make-your-own-copy-of-the-repo)
- [Step 2 – Create the server](#step-2--create-the-server)
- [Step 3 – Wait for the setup to finish](#step-3--wait-for-the-setup-to-finish)
- [Step 4 – Open the site](#step-4--open-the-site)
- [Step 5 – Open the dashboards](#step-5--open-the-dashboards)
- [Alerts (Alertmanager)](#alerts-alertmanager)
- [Making changes](#making-changes)
- [Getting the latest changes from the original repo](#getting-the-latest-changes-from-the-original-repo)
- [Cost and Spot servers](#cost-and-spot-servers)
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
   ┌───────────── AWS ────────────────────────────────────────────┐
   │  EC2 server (Ubuntu, t3a.large Spot: 2 vCPU, 8 GB RAM)       │
   │    └── k3s (Kubernetes)                                      │
   │          ├── Argo CD      – deploys the apps below from Git  │
   │          ├── QuakeWatch   – the website, on port 80          │
   │          └── Monitoring   – Prometheus, Alertmanager, Grafana │
   └──────────────────────────────────────────────────────────────┘
                     ▲
     Firewall: only YOUR IP can reach ports 80 (web) and 22 (SSH)
```

**What happens when the server boots** (see [`terraform/user_data.sh`](terraform/user_data.sh)):

1. It installs **k3s** and downloads your GitHub repo.
2. It copies [`argocd/argocd.yaml`](argocd/argocd.yaml) into k3s's **auto-deploy folder**.
   k3s applies anything placed in that folder by itself, so it installs Argo CD.
3. Once Argo CD is running, it hands Argo CD [`argocd/root-app.yaml`](argocd/root-app.yaml).
   This is the **"app of apps"**: it tells Argo CD *"deploy every app in the `argocd/apps/` folder."*
4. Argo CD deploys the two apps in that folder, **QuakeWatch** and **monitoring**, and keeps
   them matching your GitHub repo from then on.

| Part | What it does |
|---|---|
| **Terraform** | Creates everything in AWS: a network (VPC), a firewall (security group), your SSH key and the server. |
| **k3s** | A small Kubernetes that runs on one server. It can serve the site on port 80 without an AWS load balancer. |
| **Argo CD** | Watches your GitHub repo. When something changes there, Argo CD updates the cluster to match. You never deploy by hand. |
| **Helm chart** | The recipe for running QuakeWatch in Kubernetes (pods, service, autoscaling…). Lives in `quakewatch-chart/`. |
| **Prometheus + Alertmanager + Grafana** | Prometheus collects numbers like CPU and memory and fires alerts when something looks wrong. Alertmanager collects those alerts (and can send them to Slack/email). Grafana draws graphs. |
| **GitHub Actions** | Checks every pull request (CI). When app code changes, builds a new Docker image and pushes it to your Docker Hub (CD). |
| **Docker Hub** | Stores the app's Docker image. The server downloads it from your Docker Hub repo. |

---

## What's in this repo

```
quakewatch-aws/
├── terraform/              Creates the AWS network and server (user_data.sh = what the server does on boot)
├── argocd/
│   ├── argocd.yaml         Installs Argo CD (k3s applies it on boot)
│   ├── root-app.yaml       The "app of apps" – deploys everything in apps/
│   └── apps/
│       ├── quakewatch.yaml The QuakeWatch website (from quakewatch-chart/)
│       └── monitoring.yaml Prometheus + Alertmanager + Grafana, and their settings
├── quakewatch-chart/       Helm chart for QuakeWatch
├── QuakeWatch-app/         The Python (Flask) app and its Dockerfile
├── tunnel.sh               Opens the Argo CD, Grafana, Prometheus and Alertmanager dashboards on your laptop
└── .github/workflows/      CI and CD pipelines
```

---

## Before you start

You need:

| What | Check it works |
|---|---|
| A [GitHub](https://github.com/) account and [git](https://git-scm.com/downloads) | `git --version` |
| A [Docker Hub](https://hub.docker.com/) account (the free plan is enough) | You can log in at hub.docker.com |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (Mac: `brew install awscli`) | `aws --version` |
| [Terraform](https://developer.hashicorp.com/terraform/install) 1.5 or newer | `terraform version` |
| An SSH key at `~/.ssh/id_ed25519.pub` | `ls ~/.ssh/id_ed25519.pub` – missing? Run `ssh-keygen -t ed25519` |

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

Open these five files and change the names to yours:

| File | Line to change | Replace with | What it's for |
|---|---|---|---|
| [`terraform/variables.tf`](terraform/variables.tf) | `default = "https://github.com/MichaelGoncharov0/quakewatch-aws.git"` (under `repo_url`) | Your **GitHub** username | The repo the server downloads |
| [`argocd/root-app.yaml`](argocd/root-app.yaml) | `repoURL: https://github.com/MichaelGoncharov0/quakewatch-aws.git` | Your **GitHub** username | Where Argo CD finds the list of apps |
| [`argocd/apps/quakewatch.yaml`](argocd/apps/quakewatch.yaml) | `repoURL: https://github.com/MichaelGoncharov0/quakewatch-aws.git` | Your **GitHub** username | Where Argo CD finds the QuakeWatch chart |
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

**Write down the `instance_public_ip`** – you'll use it in the steps below.
Forgot it? Run `terraform output`.

> Terraform finds your public IP by itself and only lets that IP through the firewall.
> To change the region, see [`terraform/variables.tf`](terraform/variables.tf). The server is a
> **`t3a.large` Spot** instance (8 GB RAM). Don't go smaller than 8 GB – on 4 GB (`t3.medium`)
> Grafana and Argo CD keep getting restarted. Want a normal (non-Spot) server? See
> [Cost and Spot servers](#cost-and-spot-servers).

---

## Step 3 – Wait for the setup to finish

The server now installs everything by itself. This takes about **5–8 minutes**.
You don't need to do anything – but if you want to watch, connect to the server:

```bash
ssh ubuntu@<instance_public_ip>
sudo tail -f /var/log/cloud-init-output.log    # Ctrl+C to stop watching
```

When the last line says **`Bootstrap complete`**, Argo CD is running and deploying the apps.
After another 2–3 minutes, check:

```bash
kubectl get applications -n argocd
```

```
NAME         SYNC STATUS   HEALTH STATUS
monitoring   Synced        Healthy
quakewatch   Synced        Healthy
root         Synced        Healthy
```

All three **Synced** and **Healthy** means everything is deployed. Type `exit` to leave the server.

---

## Step 4 – Open the site

In your browser (use `http://`, not `https://`):

```
http://<instance_public_ip>
```

You should see the QuakeWatch dashboard. 🎉

---

## Step 5 – Open the dashboards

Argo CD, Grafana, Prometheus and Alertmanager are **not** open to the internet. You reach them
through SSH with one script.

**1. Get the passwords – on the server:**

```bash
ssh ubuntu@<instance_public_ip>

# Argo CD
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

# Grafana
kubectl get secret -n monitoring grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo

exit
```

> The passwords are created randomly on the server, so they're never in Git or in any log.

**2. Open the tunnel – on your computer:**

```bash
cd quakewatch-aws
./tunnel.sh <instance_public_ip>
```

Keep that terminal open and browse to:

| Dashboard | Address | Login |
|---|---|---|
| **Argo CD** | http://localhost:8080 | `admin` + Argo CD password |
| **Grafana** | http://localhost:3000 | `admin` + Grafana password |
| **Prometheus** | http://localhost:9090 | no login |
| **Alertmanager** | http://localhost:9093 | no login |

Press `Ctrl+C` to close the tunnel. It also stops the port-forwards on the server, and if a
dashboard restarts while the tunnel is open, the tunnel reconnects to it by itself after a few seconds.

> **Grafana right after setup:** on first start Grafana loads ~30 dashboards, which can take a
> few minutes. If `localhost:3000` doesn't answer yet, wait 2–3 minutes and reload.

**What to look at:**

- **Argo CD:** the `root`, `quakewatch` and `monitoring` apps should all be **Healthy** (green heart)
  and **Synced** (green tick). Click one to see all its parts as a tree.
- **Grafana → Dashboards:**
  - **Node Exporter / Nodes** – the server's CPU, memory, disk and network
  - **Kubernetes / Compute Resources / Namespace (Pods)** – pick `quakewatch` to see the app's pods
- **Prometheus → Status → Target health:** every target should be green **UP**.
- **Prometheus → Alerts:** the alert rules and which ones are firing right now.
- **Alertmanager:** the alerts that are firing, grouped. See [Alerts](#alerts-alertmanager).

> Graphs start from zero if Prometheus restarts – history isn't saved to disk.

---

## Alerts (Alertmanager)

Prometheus checks ~100 ready-made alert rules from the
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
chart every 30 seconds – for example *a pod keeps crash-looping*, *the server is almost out of
memory or disk*, *a Prometheus target is down*. When a rule fires, Prometheus sends the alert to
**Alertmanager**, which groups it and shows it at **http://localhost:9093** (through `tunnel.sh`).

**Two alerts are always firing – that's normal:**

| Alert | Why |
|---|---|
| `Watchdog` | A "heartbeat" alert that's always on, to prove the alert pipeline works. |
| `InfoInhibitor` | Used internally to hide low-importance alerts. |

**Getting notified on Slack or email.** Out of the box nothing is sent anywhere. To get a Slack
message, add this under `alertmanager:` in [`argocd/apps/monitoring.yaml`](argocd/apps/monitoring.yaml),
then commit and push:

```yaml
        alertmanager:
          enabled: true
          config:
            route:
              receiver: slack
              group_by: [alertname, namespace]
              routes:
                - receiver: "null"
                  matchers: [alertname = "Watchdog"]
            receivers:
              - name: "null"
              - name: slack
                slack_configs:
                  - api_url: https://hooks.slack.com/services/XXX/YYY/ZZZ   # your Slack webhook
                    channel: "#alerts"
                    send_resolved: true
```

> A Slack webhook URL is a secret – anyone who has it can post to your channel. Only put it in
> Git if the repo is private, or keep it in a Kubernetes Secret instead.

---

## Making changes

All changes go to **your own repo**. Argo CD keeps the cluster the same as your repo, so if
you change something by hand in the cluster (e.g. `kubectl edit` or `kubectl scale`), Argo CD
will put it back.

### Changing the Helm chart or the monitoring settings

Edit anything in `quakewatch-chart/` or `argocd/apps/`, then commit and push to your repo
(or open a pull request in your repo and merge it).

Argo CD picks up the change **within about 3 minutes**. In a hurry? Click **Refresh** on the
app in the Argo CD dashboard.

**Don't want monitoring?** Delete `argocd/apps/monitoring.yaml` and push. Argo CD uninstalls it.

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

## Getting the latest changes from the original repo

Already made your copy and want the newest version of this project? Pull it from the original
repo into yours. Run this in your `quakewatch-aws` folder on your computer:

```bash
# Once: remember the original repo under the name "upstream"
git remote add upstream https://github.com/MichaelGoncharov0/quakewatch-aws.git

# Every time you want the latest changes
git checkout main
git pull upstream main
```

**Keep your own names.** The original repo has *its* GitHub and Docker Hub names in the five
files from [Step 1 – part 6](#step-1--make-your-own-copy-of-the-repo). If git reports a
**conflict** in any of them, keep **your** line – your GitHub / Docker Hub username – and delete
the other. Then check nothing slipped through. This should print **nothing**:

```bash
grep -rn -i "michaelgoncharov0" --exclude=README.md --exclude-dir=.git .
```

If it prints a line, change that name to yours (see the table in Step 1 – part 6). These are
all the places with a name in them:

| File | What to check |
|---|---|
| `terraform/variables.tf` | `repo_url` → **your GitHub** repo |
| `argocd/root-app.yaml` | `repoURL` → **your GitHub** repo |
| `argocd/apps/quakewatch.yaml` | `repoURL` → **your GitHub** repo |
| `.github/workflows/quakewatch-cd.yaml` | `images:` → **your Docker Hub** user |
| `quakewatch-chart/values.yaml` | `repository:` → **your Docker Hub** user |

Then push to your repo, so Argo CD sees the changes:

```bash
git push origin main
```

**After this update you also need to rebuild the server**, because the server type changed
(`t3.medium` → `t3a.large` Spot) and so did what it does on first boot (it now adds swap):

```bash
cd terraform
terraform apply      # type "yes"
```

Terraform deletes the old server and creates a new one. Everything is reinstalled by itself,
but you get a **new IP** and **new Argo CD and Grafana passwords** – get them again as in
[Step 5](#step-5--open-the-dashboards). Also pull the latest `tunnel.sh` (it now opens
Alertmanager on port 9093 and cleans up after itself).

**What changed in this update:**

| Change | Files | Do you need to edit anything? |
|---|---|---|
| Bigger, cheaper server: `t3a.large` Spot (8 GB) instead of `t3.medium` (4 GB) | `terraform/variables.tf`, `terraform/main.tf` | No – just `terraform apply` |
| 2 GB swap file on the server | `terraform/user_data.sh` | No |
| Alertmanager turned on | `argocd/apps/monitoring.yaml` | No (optional: add Slack, see [Alerts](#alerts-alertmanager)) |
| Grafana given more memory and more time to start | `argocd/apps/monitoring.yaml` | No |
| `tunnel.sh` cleans up old port-forwards, reconnects by itself, adds Alertmanager | `tunnel.sh` | No |

---

## Cost and Spot servers

The server is a **`t3a.large`** (2 vCPU, 8 GB RAM) bought as a **Spot instance**. Spot is
AWS's spare capacity, sold much cheaper than normal ("on-demand") servers.

| Server | Memory | About per day (us-east-1) |
|---|---|---|
| `t3.medium` on-demand (the old default) | 4 GB – too small | $1.00 |
| `t3a.large` on-demand | 8 GB | $1.80 |
| **`t3a.large` Spot (the default)** | **8 GB** | **$0.65–0.75** |

Plus about **$0.05 a day** for the 20 GB disk. Spot prices change a little over time; you never
pay more than the on-demand price.

**The catch:** when AWS needs the capacity back, it can stop a Spot server with 2 minutes'
warning. It's rare for this size, but it can happen. The server is **stopped, not deleted** –
AWS starts it again when capacity is back, and everything comes back by itself, but it gets a
**new public IP**. Run `terraform refresh` and then `terraform output` to see it.

**Want a normal server that's never interrupted?** In
[`terraform/variables.tf`](terraform/variables.tf) set `use_spot` to `false` and run
`terraform apply` (it builds a new server). It costs about $1.80 a day.

**Save more:** run `terraform destroy` whenever you're not using the server – you pay nothing
while it's gone, and `terraform apply` brings it all back in ~15 minutes.

---

## Clean up (don't skip this!)

The server costs about **$0.75 a day**. When you're done, on your computer:

```bash
cd quakewatch-aws/terraform
terraform destroy    # type "yes"
```

This deletes everything Terraform created. Your GitHub and Docker Hub repos are not touched.
Want the server back? Run `terraform apply` again and wait for the setup (you'll get a **new** IP).

---

## Troubleshooting

| Problem | Fix |
|---|---|
| **Site or SSH suddenly stopped working** | Your home IP probably changed (router restart, VPN, new Wi-Fi). Run `terraform apply` again – it updates the firewall with your new IP. |
| **`git push` says "Permission denied" or "403"** | You're pushing to the original repo. Run `git remote -v` – it should show **your** username. Fix it with `git remote set-url origin https://github.com/<your-github-user>/quakewatch-aws.git`. |
| **Setup never says `Bootstrap complete`** | Read `sudo cat /var/log/cloud-init-output.log` on the server and look at the last command before the error. |
| **`kubectl get applications` shows nothing** | Argo CD is still installing. Wait a few minutes. To see its progress: `kubectl get pods -n argocd`. |
| **My changes don't show up on the server** | Check that `repo_url` in `terraform/variables.tf` and `repoURL` in `argocd/root-app.yaml` and `argocd/apps/quakewatch.yaml` point to **your** repo, and that you pushed. |
| **Pods show `ImagePullBackOff` or `ErrImagePull`** | The server can't download the image. Check that CD finished (green in **Actions**), your Docker Hub repo has a `latest` tag and is **Public**, and `repository:` in `quakewatch-chart/values.yaml` has **your** Docker Hub username. |
| **An Argo CD app shows *OutOfSync*** | Click **Sync** in the dashboard. If it keeps coming back, someone changed the cluster by hand – change the repo instead. |
| **An Argo CD app shows *Degraded*** | Click the app and look for the red part. For pods, run `kubectl describe pod -n <namespace> <pod-name>` – the **Events** at the bottom say what's wrong. |
| **CD fails with "unauthorized" or "denied"** | The Docker Hub secrets are missing or wrong in your GitHub repo, the token doesn't have **Write** access, or `images:` in `quakewatch-cd.yaml` still says `michaelgoncharov0`. See [Step 1](#step-1--make-your-own-copy-of-the-repo). |
| **`tunnel.sh` stops with "Address already in use" or "remote port forwarding failed"** | An old tunnel is still open **on your computer**. Close that terminal, or find it with `lsof -i :8080` and `kill <PID>`. (Old port-forwards left **on the server** are cleaned up by the script itself.) |
| **Grafana (`localhost:3000`) doesn't load, the others do** | Grafana is still starting – it can take a few minutes after setup. Check on the server: `kubectl get pods -n monitoring` – wait for `monitoring-grafana-…` to show `3/3 Running`. |
| **The server's IP changed by itself** | It's a Spot server and AWS stopped and restarted it (see [Cost](#cost-and-spot-servers)). Run `terraform refresh` and `terraform output` for the new IP. |
| **`terraform apply` fails with `InsufficientInstanceCapacity`, `MaxSpotInstanceCountExceeded` or `SpotMaxPriceTooLow`** | AWS has no Spot capacity for you right now. Try again in a few minutes, or set `use_spot = false` in `terraform/variables.tf`. |
| **I changed `user_data.sh` or `argocd/argocd.yaml` but nothing happened** | These are only used when the server first boots. Run `terraform apply` – a change to `user_data.sh` builds a new server. For `argocd.yaml`, run `terraform destroy` then `terraform apply`. |
| **`terraform apply` fails with `error asking for approval: EOF`** | Run it in a normal terminal so you can type `yes`. |
