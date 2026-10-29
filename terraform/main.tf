# ---------- My public IP (used to restrict the security group) ----------

data "http" "myip" {
  url = "https://ipv4.icanhazip.com"
}

locals {
  # The response ends with a newline, so chomp it before building the CIDR
  my_ip_cidr = "${chomp(data.http.myip.response_body)}/32"
}

# ---------- VPC (community module from the Terraform Registry) ----------

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs            = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets = [cidrsubnet(var.vpc_cidr, 8, 1), cidrsubnet(var.vpc_cidr, 8, 2)]

  # Public subnets only: no private subnets, so no (paid) NAT gateway
  enable_nat_gateway      = false
  map_public_ip_on_launch = true

  enable_dns_hostnames = true
  enable_dns_support   = true
}

# ---------- Security group: HTTP + SSH from my IP only ----------

resource "aws_security_group" "k3s" {
  name        = "${var.project_name}-k3s-sg"
  description = "Allow HTTP and SSH from my public IP"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from my IP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  egress {
    description = "All outbound (k3s install, GitHub, Docker Hub)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-k3s-sg"
  }
}

# ---------- EC2 instance running k3s ----------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.public_key_path))
}

resource "aws_instance" "k3s" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh", {
    repo_url = var.repo_url
  })
  # Recreate the instance when the bootstrap script changes (user data only runs on first boot)
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-k3s"
  }
}
