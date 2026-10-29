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
- [Step 5 – Clean up](#step-5--clean-up-dont-skip-this)
- [Monitoring (optional)](#monitoring-optional)
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
├── monitoring/            Optional Prometheus + Grafana (has its own README)
└── .github/workflows/     CI and CD pipelines
```

---

## Before you start

You need these once:

| What | Why | Check it |
|---|---|---|
| **AWS account + IAM user** with the `AmazonEC2FullAccess` policy | Terraform uses it to create things. Please don't use the root account. | – |
| **AWS CLI** set up with that user's keys | Terraform reads the same credentials | `aws sts get-caller-identity` → should show your IAM user, not `root` |
| **Terraform** 1.5 or newer | Builds the infrastructure | `terraform version` |
| **An SSH key** at `~/.ssh/id_ed25519.pub` | To log in to the server | `ls ~/.ssh/id_ed25519.pub` – if it's missing, run `ssh-keygen -t ed25519` |

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

## Step 5 – Clean up (don't skip this!)

The server costs about **$1 a day** while it's running. When you're done, from the `terraform` folder:

```bash
terraform destroy    # type "yes"
```

Everything Terraform created is removed – server, firewall, SSH key and network.
Want it back later? Just run `terraform apply` again (you'll get a **new** public IP).

---

## Monitoring (optional)

The [`monitoring/`](monitoring/) folder adds **Prometheus and Grafana**, so you can see graphs of
the server's CPU, memory and disk, and of everything running in k3s.
It's two commands – one on the server, one on your laptop. See [monitoring/README.md](monitoring/README.md).

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
