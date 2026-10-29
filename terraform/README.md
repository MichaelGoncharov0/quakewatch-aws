# Phase 4 – Running QuakeWatch on AWS with Terraform and k3s

In the previous phases QuakeWatch ran on my laptop (Docker Desktop's Kubernetes).
In this phase I moved it to AWS. Terraform builds the network and a single EC2
server, the server installs a small Kubernetes cluster (k3s) on its own when it
boots, and then I deploy the QuakeWatch Helm chart on it.

The end result: you open `http://<server-public-ip>` in your browser and see the
QuakeWatch dashboard.

## What gets created

```
                Internet
                    |
        (only your IP, ports 80 + 22)
                    |
   +----------------VPC 10.0.0.0/16----------------+
   |                                               |
   |   Public subnet 10.0.1.0/24                   |
   |   +---------------------------------------+   |
   |   |  EC2 (Ubuntu 24.04, t3.medium)        |   |
   |   |    k3s (single-node Kubernetes)       |   |
   |   |      QuakeWatch pods  <-- port 80     |   |
   |   +---------------------------------------+   |
   |                                               |
   +-----------------------------------------------+
```

- **VPC** – built with the community module
  [`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws).
  Two public subnets, an internet gateway, no NAT gateway (it's not needed and it costs money).
- **Security group** – allows HTTP (80) and SSH (22) **only from your own public IP**.
  Terraform finds your IP by itself using `https://ipv4.icanhazip.com`, so nothing is hardcoded.
- **EC2 instance** – Ubuntu 24.04 with a public IP. On first boot it runs `user_data.sh`, which:
  1. installs `git` and `curl`
  2. installs k3s (with Traefik turned off so our app can use port 80)
  3. installs Helm
  4. clones this repo ([quakewatch-aws](https://github.com/MichaelGoncharov0/quakewatch-aws)) so the Helm chart is ready on the server

## Files

```
quakewatch-aws/
├── QuakeWatch-app/      # the Flask app + Dockerfile
├── quakewatch-chart/    # Helm chart (values.yaml is set up for this server)
└── terraform/
    ├── README.md        # you are here
    ├── providers.tf     # Terraform + provider versions, AWS region and default tags
    ├── variables.tf     # things you might want to change (region, instance size, ...)
    ├── main.tf          # VPC, security group, key pair, EC2 instance
    ├── user_data.sh     # script the EC2 instance runs on first boot
    └── outputs.tf       # prints the public IP, site URL and SSH command
```

## Before you start

You'll need:

- An **AWS account** and an **IAM user** with EC2 permissions
  (the `AmazonEC2FullAccess` policy is enough). Please don't use the root account.
- **AWS CLI** configured with that user's access keys. Check it with:
  ```bash
  aws sts get-caller-identity
  ```
  You should see your IAM user in the output, not `root`.
- **Terraform** 1.5 or newer (`terraform version`)
- An **SSH key** at `~/.ssh/id_ed25519.pub`. If you don't have one:
  ```bash
  ssh-keygen -t ed25519
  ```

### Settings you might want to change

All of these live in `variables.tf`:

| Variable          | Default                       | What it is                          |
|-------------------|-------------------------------|-------------------------------------|
| `region`          | `us-east-1`                   | AWS region                          |
| `instance_type`   | `t3.medium`                   | EC2 size (2 vCPU, 4 GB RAM)         |
| `public_key_path` | `~/.ssh/id_ed25519.pub`       | Your SSH public key                 |
| `repo_url`        | this repo on GitHub           | Repo the server clones the chart from |

You can also override them on the command line without editing the file, e.g.
`terraform apply -var region=eu-central-1`.

## Step 1 – Build the infrastructure

```bash
cd quakewatch-aws/terraform

terraform init      # downloads the AWS provider and the VPC module (only needed once)
terraform plan      # shows what will be created - read it before applying!
terraform apply     # type "yes" to confirm
```

It takes about 1–2 minutes. When it's done you'll see something like this:

```
instance_public_ip = "3.85.12.34"
my_ip_cidr         = "89.139.80.84/32"
quakewatch_url     = "http://3.85.12.34"
ssh_command        = "ssh ubuntu@3.85.12.34"
vpc_id             = "vpc-0abc123..."
```

You can print these again at any time with `terraform output`.

## Step 2 – Connect to the server and wait for the setup to finish

The server needs another **2–3 minutes** after `apply` to install k3s, Helm and clone the repo.

```bash
ssh ubuntu@<instance_public_ip>
```

Watch the setup log until you see `Bootstrap complete`:

```bash
sudo tail -f /var/log/cloud-init-output.log
```

Press `Ctrl+C` to stop watching, then make sure the cluster is up:

```bash
kubectl get nodes
```

```
NAME              STATUS   ROLES                  AGE   VERSION
ip-10-0-1-xx      Ready    control-plane,master   2m    v1.xx.x+k3s1
```

The repo with the chart is already there:

```bash
ls ~/quakewatch-aws/quakewatch-chart
```

## Step 3 – Deploy QuakeWatch

Still on the server:

```bash
cd ~/quakewatch-aws
helm install quakewatch ./quakewatch-chart \
  --namespace quakewatch --create-namespace
```

The chart's service is a `LoadBalancer` on port 80. k3s has a tiny built-in load
balancer (ServiceLB) that binds it straight to port 80 on the server – no AWS load
balancer is created, so there's nothing extra to pay for.

> Prefer plain kubectl? This does the same thing:
> ```bash
> helm template quakewatch ./quakewatch-chart \
>   --namespace quakewatch \
>   | kubectl apply -n quakewatch -f -
> ```
> (create the namespace first with `kubectl create namespace quakewatch`)

Check that everything is running:

```bash
kubectl get pods,svc,hpa -n quakewatch
```

You want the pods to be `Running` / `1/1` and the service to show an `EXTERNAL-IP`
with port `80`. The first start can take a minute while the image is pulled from Docker Hub.

## Step 4 – Open the site

On your laptop, open the `quakewatch_url` from the Terraform output:

```
http://<instance_public_ip>
```

You should see the QuakeWatch dashboard. 🎉

You can also test it from the terminal:

```bash
curl -I http://<instance_public_ip>
```

**Bonus check:** try opening the same URL from your phone on mobile data (Wi-Fi off).
It should **not** load – that proves the security group only lets your IP in.

## Updating the app

If you changed the chart in GitHub, pull the changes on the server and upgrade:

```bash
cd ~/quakewatch-aws && git pull
helm upgrade quakewatch ./quakewatch-chart -n quakewatch
```

## Clean up (don't skip this!)

The server costs roughly **$1 per day** while it's running. When you're done:

```bash
cd quakewatch-aws/terraform
terraform destroy   # type "yes"
```

This removes everything Terraform created – the instance, security group, key pair and VPC.

## Troubleshooting

**The site doesn't open / SSH hangs**
Your public IP probably changed (new Wi-Fi, VPN, router restart). Just run
`terraform apply` again – it re-checks your IP and updates the security group.

**`kubectl get nodes` says connection refused**
k3s is still starting. Wait a minute and check `/var/log/cloud-init-output.log`.

**`helm` says "Kubernetes cluster unreachable"**
Helm doesn't know where the k3s config is. The setup script adds it to `.bashrc`,
but if you opened the shell before setup finished, run:
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

**Pods are stuck in `Pending` or `ImagePullBackOff`**
```bash
kubectl describe pod -n quakewatch <pod-name>
```
The `Events` section at the bottom usually tells you exactly what's wrong.

**I changed `user_data.sh` but nothing happened**
User data only runs on the first boot. Terraform is set to replace the instance when
the script changes, so run `terraform apply` and it will build a fresh server.

**Something failed during setup**
Everything the setup script does is printed to:
```bash
sudo cat /var/log/cloud-init-output.log
```
Look for the last command before the error.
