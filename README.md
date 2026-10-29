# QuakeWatch on AWS

QuakeWatch is a small web dashboard that shows recent earthquakes around the world,
using live data from the [USGS Earthquake API](https://earthquake.usgs.gov/fdsnws/event/1/).

In the earlier phases of this project it ran on my laptop (Docker Desktop's Kubernetes)
and Argo CD deployed it. In this phase I moved it to AWS:

1. **Terraform** builds a network and one EC2 server.
2. The server **sets itself up** when it boots – it installs a small Kubernetes
   cluster ([k3s](https://k3s.io/)), Helm and git, and clones this repo.
3. I **SSH in and install the Helm chart**.
4. I open `http://<server-public-ip>` and see the dashboard.

The whole thing takes about 10 minutes and costs around **$1 a day** while it's running.

---

## Contents

- [What gets built](#what-gets-built)
- [What's in this repo](#whats-in-this-repo)
- [Before you start](#before-you-start)
- [Step 1 – Build the infrastructure](#step-1--build-the-infrastructure)
- [Step 2 – Connect to the server](#step-2--connect-to-the-server)
- [Step 3 – Deploy QuakeWatch](#step-3--deploy-quakewatch)
- [Step 4 – Open the site](#step-4--open-the-site)
- [Monitoring (optional)](#monitoring-optional)
- [Step 5 – Clean up](#step-5--clean-up-dont-skip-this)
- [Updating the app](#updating-the-app)
- [CI/CD](#cicd)
- [Troubleshooting](#troubleshooting)

---

## What gets built

```
                    Internet
                        │
          only YOUR IP, ports 80 and 22
                        │
   ┌──────────────── VPC 10.0.0.0/16 ────────────────┐
   │                                                 │
   │   Public subnet 10.0.1.0/24                     │
   │   ┌─────────────────────────────────────────┐   │
   │   │  EC2 – Ubuntu 24.04, t3.medium          │   │
   │   │    └── k3s (one-node Kubernetes)        │   │
   │   │          └── QuakeWatch pods ◄── :80    │   │
   │   └─────────────────────────────────────────┘   │
   │                                                 │
   └─────────────────────────────────────────────────┘
```

| Piece | What it is |
|---|---|
| **VPC** | A private network in AWS, built with the community module [`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws). Two public subnets and an internet gateway. No NAT gateway – we don't need it and it costs money. |
| **Security group** | The server's firewall. It lets in HTTP (80) and SSH (22) **only from your own public IP**. Terraform looks your IP up by itself (from `https://ipv4.icanhazip.com`), so nothing is hardcoded. |
| **EC2 instance** | The server. On first boot it runs [`terraform/user_data.sh`](terraform/user_data.sh), which installs git, k3s and Helm, then clones this repo. |
| **k3s** | A lightweight Kubernetes. It comes with a tiny built-in load balancer, so our `LoadBalancer` service is served straight from port 80 on the server – no AWS load balancer needed. |

---

## What's in this repo

```
quakewatch-aws/
├── README.md              ← you are here
├── QuakeWatch-app/        The Flask app and its Dockerfile
├── quakewatch-chart/      Helm chart – values.yaml is already set up for this server
├── terraform/
│   ├── providers.tf       Terraform/provider versions, AWS region, default tags
│   ├── variables.tf       Settings you might want to change
│   ├── main.tf            VPC, security group, SSH key, EC2 instance
│   ├── user_data.sh       Script the server runs on its first boot
│   └── outputs.tf         Prints the server IP, site URL and SSH command
├── monitoring/            Optional Prometheus + Grafana (values.yaml, install.sh, tunnel.sh)
└── .github/workflows/     CI and CD pipelines
```

---

## Before you start

You need these once:

| What | Why | Check it |
|---|---|---|
| **AWS account + IAM user** with the `AmazonEC2FullAccess` policy | Terraform uses it to create things. Please don't use the root account. | See [Getting AWS access](#getting-aws-access-iam-user) below |
| **AWS CLI** set up with that user's keys | Terraform reads the same credentials | `aws sts get-caller-identity` → should show your IAM user, not `root` |
| **Terraform** 1.5 or newer | Builds the infrastructure | `terraform version` |
| **An SSH key** at `~/.ssh/id_ed25519.pub` | To log in to the server | `ls ~/.ssh/id_ed25519.pub` – if it's missing, run `ssh-keygen -t ed25519` |

### Getting AWS access (IAM user)

Terraform talks to AWS using an **access key** that belongs to an **IAM user**. Think of the
IAM user as an employee account and the access key as their badge – Terraform shows the badge,
and AWS checks what that user is allowed to do.

**Everyone gets their own IAM user and their own key.** Never share one key between people –
if it leaks you can't tell who used it, and you'd have to change it for everybody.

#### Part A – Create the user (done once per person, by whoever manages the AWS account)

In the [AWS Console](https://console.aws.amazon.com/iam/):

1. **Create a group** (only the first time):
   **IAM → User groups → Create group**. Name it `terraform-users` and attach the
   **`AmazonEC2FullAccess`** policy. That's everything this project needs – the VPC, firewall,
   SSH key and server are all part of EC2.
2. **Create the user:**
   **IAM → Users → Create user**. Give it a name, e.g. `dana-terraform`.
   Leave *"Provide user access to the AWS Management Console"* unticked – Terraform only needs a key.
   On the next page choose **Add user to group** → `terraform-users` → **Create user**.
3. **Create the access key:**
   Open the new user → **Security credentials** tab → **Create access key** →
   choose **Command Line Interface (CLI)** → tick the confirmation → **Create access key**.
4. **Save it now.** You get an **Access key ID** (`AKIA…`) and a **Secret access key**.
   The secret is shown **only once** – click **Download .csv file**.
5. **Hand it over safely** – through a password manager or another secure channel.
   Not over Slack, email or in a git repo.

<details>
<summary>Prefer the command line? Same thing with the AWS CLI (needs an admin user)</summary>

```bash
# first time only: the group and its permissions
aws iam create-group --group-name terraform-users
aws iam attach-group-policy --group-name terraform-users \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

# for each person
aws iam create-user --user-name dana-terraform
aws iam add-user-to-group --user-name dana-terraform --group-name terraform-users
aws iam create-access-key --user-name dana-terraform    # prints the key ID and secret - save them
```
</details>

#### Part B – Put the key on the person's computer (done by them)

1. **Install the AWS CLI:**
   - Mac: `brew install awscli`
   - Windows / Linux: follow the [official installer guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
2. **Save the key:**
   ```bash
   aws configure
   ```
   It asks four questions:
   ```
   AWS Access Key ID [None]: AKIA................
   AWS Secret Access Key [None]: ........................................
   Default region name [None]: us-east-1
   Default output format [None]: json
   ```
   This writes the key to `~/.aws/credentials` (on Windows: `C:\Users\<you>\.aws\credentials`).
   Terraform finds it there automatically – there's nothing to add to the Terraform files.
3. **Check it works:**
   ```bash
   aws sts get-caller-identity
   ```
   You should see your own user at the end, e.g. `arn:aws:iam::123456789012:user/dana-terraform`.

**Already using AWS for something else on that computer?** Save this key under its own name
so it doesn't replace the other one:

```bash
aws configure --profile quakewatch
export AWS_PROFILE=quakewatch    # tell the AWS CLI and Terraform to use it in this terminal
```

#### Keeping keys safe

- The `~/.aws/credentials` file **is** your AWS access – never commit it, paste it or screenshot it.
- When someone leaves the project, **delete their access key** (IAM → Users → the user →
  Security credentials) or the whole user.
- Think a key leaked? Deactivate it in IAM right away and create a new one.
- Two people can use the same AWS account, but **not run this project at the same time** –
  the SSH key and firewall have fixed names and would clash.

### Settings you can change

They're all in [`terraform/variables.tf`](terraform/variables.tf). The defaults work as they are.

| Variable | Default | What it is |
|---|---|---|
| `region` | `us-east-1` | AWS region |
| `instance_type` | `t3.medium` | Server size (2 CPUs, 4 GB RAM) |
| `public_key_path` | `~/.ssh/id_ed25519.pub` | Your SSH public key |
| `repo_url` | this repo | Repo the server clones |

You can also change one without editing the file: `terraform apply -var region=eu-central-1`

---

## Step 1 – Build the infrastructure

```bash
git clone https://github.com/MichaelGoncharov0/quakewatch-aws.git
cd quakewatch-aws/terraform

terraform init     # downloads the AWS provider and the VPC module (first time only)
terraform plan     # shows what will be created – worth a quick read
terraform apply    # type "yes" to confirm
```

After 1–2 minutes you'll see something like:

```
Apply complete! Resources: 14 added, 0 changed, 0 destroyed.

instance_public_ip = "18.207.104.139"
my_ip_cidr         = "89.139.80.84/32"
quakewatch_url     = "http://18.207.104.139"
ssh_command        = "ssh ubuntu@18.207.104.139"
vpc_id             = "vpc-0c17b808796e578de"
```

You'll need the **public IP** in the next steps. Forgot it? Run `terraform output`.

> Running `apply` a second time is safe. If nothing changed, Terraform says
> **"No changes"** and leaves everything alone.

---

## Step 2 – Connect to the server

The server needs about **1–3 minutes** after `apply` to finish setting itself up.

```bash
ssh ubuntu@<instance_public_ip>
```

Check that the setup finished – the last line should say `Bootstrap complete`:

```bash
sudo tail -f /var/log/cloud-init-output.log     # Ctrl+C to stop watching
```

Then check that Kubernetes is up:

```bash
kubectl get nodes
```

```
NAME            STATUS   ROLES           AGE   VERSION
ip-10-0-1-106   Ready    control-plane   2m    v1.36.5+k3s1
```

---

## Step 3 – Deploy QuakeWatch

Still on the server:

```bash
cd ~/quakewatch-aws
helm install quakewatch ./quakewatch-chart --namespace quakewatch --create-namespace
```

Check that it's running:

```bash
kubectl get pods,svc,hpa -n quakewatch
```

You're looking for:

- pods showing **`Running`** and **`1/1`** (the first start can take a minute while the image downloads)
- the service showing **`LoadBalancer`** and port **`80`**

```
NAME                             READY   STATUS    RESTARTS   AGE
pod/quakewatch-6599bbd957-gxns8  1/1     Running   0          1m
pod/quakewatch-6599bbd957-hf6kq  1/1     Running   0          1m
pod/quakewatch-6599bbd957-rcjr2  1/1     Running   0          1m

NAME                         TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)
service/quakewatch-service   LoadBalancer   10.43.9.198   10.0.1.106    80:32664/TCP
```

The `EXTERNAL-IP` is the server's *private* address inside AWS – that's normal for k3s.
You'll use the *public* IP from Terraform to open the site.

<details>
<summary>Prefer plain <code>kubectl</code> instead of <code>helm install</code>?</summary>

```bash
kubectl create namespace quakewatch
helm template quakewatch ./quakewatch-chart --namespace quakewatch | kubectl apply -n quakewatch -f -
```

Helm only turns the chart into plain Kubernetes YAML here, and `kubectl` applies it.
</details>

---

## Step 4 – Open the site

Open this in your browser (use `http://`, not `https://`):

```
http://<instance_public_ip>
```

You should see the QuakeWatch dashboard. 🎉

**Testing from your phone:** connect it to the **same Wi-Fi** as your computer. Every device on
your home Wi-Fi uses the same public IP, so the security group lets it in.
Now switch the phone to **mobile data** – the site should *not* load. That proves the firewall
only lets your IP in.

> **On a work laptop and getting "Gateway Timeout"?** Your company probably sends browser
> traffic through a proxy, which reaches AWS from a different IP – so the security group blocks it.
> Check from the terminal with `curl -I http://<instance_public_ip>`, use your phone on home Wi-Fi,
> or open an SSH tunnel: `ssh -L 8080:localhost:80 ubuntu@<instance_public_ip>` and browse to
> http://localhost:8080.

---

## Monitoring (optional)

Want to see how the server and the cluster are doing? The [`monitoring/`](monitoring/) folder
adds **Prometheus** and **Grafana** with ready-made dashboards. Do this *before* Step 5,
while the server is still running.

### What's what

| Part | What it does |
|---|---|
| **Prometheus** | A database for numbers over time. Every 30 seconds it collects ("scrapes") metrics from the parts below and stores them. |
| **Grafana** | The website you look at. It reads from Prometheus and draws graphs and dashboards. |
| **node-exporter** | Runs on the server and reports the **EC2 machine's** CPU, memory, disk and network. |
| **kube-state-metrics** | Reports what **Kubernetes** knows – pods, restarts, deployments, the HPA. |
| **kubelet / cAdvisor** | Built into k3s. Report how much CPU and memory each **container** uses. |

```
  EC2 server  ──► node-exporter ────────┐
  containers  ──► kubelet / cAdvisor ───┼──► Prometheus ──► Grafana ──► your browser
  Kubernetes  ──► kube-state-metrics ───┘    (stores)       (shows)     (through SSH)
```

It's all installed from one popular Helm chart,
[kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).
[`monitoring/values.yaml`](monitoring/values.yaml) trims it down for our one small server:
no Alertmanager, 2 days of history, limited memory, and the k3s parts that can't be scraped are switched off.

### 1. Install it – on the server

```bash
ssh ubuntu@<instance_public_ip>
bash ~/quakewatch-aws/monitoring/install.sh
```

It takes 2–3 minutes and ends by printing the pods and the Grafana login:

```
Grafana user:     admin
Grafana password: <random password>
```

Copy the password, then type `exit`. Lost it? On the server:
`kubectl get secret -n monitoring monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo`

### 2. Open it – on your laptop

```bash
cd quakewatch-aws/monitoring
./tunnel.sh <instance_public_ip>
```

Keep that terminal open and browse to:

- **Grafana** → http://localhost:3000 (user `admin`, password from step 1)
- **Prometheus** → http://localhost:9090

Press `Ctrl+C` to close the tunnel.

> **Why a tunnel?** The firewall only opens ports 80 and 22, and we don't want Grafana open to
> the internet. `tunnel.sh` connects over SSH (already allowed) and carries Grafana and
> Prometheus to your laptop's `localhost`. Nothing new is opened in AWS.

### 3. Look around

In Grafana, open **Dashboards**:

| Dashboard | Shows |
|---|---|
| **Node Exporter / Nodes** | The EC2 server – CPU, memory, disk, network |
| **Kubernetes / Compute Resources / Cluster** | CPU and memory used by the whole cluster |
| **Kubernetes / Compute Resources / Namespace (Pods)** | Pick `quakewatch` to see the app's pods |

In Prometheus, **Status → Target health** should show every target as green **UP**.

### Good to know

- **History isn't saved to disk** – if Prometheus restarts or you rebuild the server, graphs start from zero.
- **The app has no `/metrics` endpoint**, so you see its CPU, memory and restarts, but not things like requests per second.
- **Remove it** with `helm uninstall monitoring -n monitoring` on the server – or just `terraform destroy`.
- **`tunnel.sh` says "Address already in use"?** Something on your laptop already uses port 3000 or 9090 – probably an old tunnel. Find it with `lsof -i :3000`.

---

## Step 5 – Clean up (don't skip this!)

The server costs about **$1 a day** while it's running. When you're done, from the `terraform` folder:

```bash
terraform destroy    # type "yes"
```

Everything Terraform created is removed – server, firewall, SSH key and network.
Want it back later? Just run `terraform apply` again (you'll get a **new** public IP).

---

## Updating the app

If you changed the chart on GitHub, pull it on the server and upgrade:

```bash
cd ~/quakewatch-aws && git pull
helm upgrade quakewatch ./quakewatch-chart -n quakewatch
```

---

## CI/CD

```text
  Code change ──► Pull request ──► CI checks it ──► Merge to main
                                                        │
                                                        ▼
                              CD builds the image and pushes it to Docker Hub
                                                        │
                                                        ▼
                                   k3s pulls the image when the pods start
```

- **CI** ([`quakewatch-ci.yaml`](.github/workflows/quakewatch-ci.yaml)) runs on every pull request:
  pylint on the Python code, `helm lint` on the chart, and a test Docker build.
- **CD** ([`quakewatch-cd.yaml`](.github/workflows/quakewatch-cd.yaml)) runs when app code is merged
  to `main`. It builds the image and pushes it to Docker Hub as
  [`michaelgoncharov0/quakewatch`](https://hub.docker.com/r/michaelgoncharov0/quakewatch).

CD needs two secrets in **Settings → Secrets and variables → Actions**:

| Secret | What it is |
|---|---|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | A Docker Hub access token (not your password) |

---

## Troubleshooting

**The site or SSH suddenly stopped working**
Your home IP probably changed (router restart, new Wi-Fi, VPN). Run `terraform apply` again –
it looks up your IP and updates the firewall.

**`terraform apply` fails with `error asking for approval: EOF`**
It's waiting for you to type `yes`, but it's running somewhere it can't read your keyboard.
Run it in a normal terminal, or use `terraform apply -auto-approve` once you've checked the plan.

**`kubectl get nodes` says "connection refused"**
k3s is still starting. Wait a minute and check `sudo tail /var/log/cloud-init-output.log`.

**`helm` says "Kubernetes cluster unreachable"**
Helm can't find the k3s config. Run `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml` and try again.

**Pods are stuck in `Pending` or `ImagePullBackOff`**
Run `kubectl describe pod -n quakewatch <pod-name>` – the `Events` at the bottom usually say exactly what's wrong.

**I changed `user_data.sh` but nothing happened**
That script only runs on the server's first boot. Terraform is set to build a *new* server when the
script changes, so just run `terraform apply`.

**Something failed during the server setup**
Everything the setup script did is in `sudo cat /var/log/cloud-init-output.log`. Look at the last
command before the error.
