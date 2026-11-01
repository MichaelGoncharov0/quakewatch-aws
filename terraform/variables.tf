variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "quakewatch"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  # t3a.large = 2 vCPU, 8 GB RAM (AMD). Same CPU count as t3.medium but twice the memory,
  # which Argo CD + Prometheus + Grafana + Alertmanager need. t3a is ~10% cheaper than t3.
  description = "EC2 instance type for the k3s node"
  type        = string
  default     = "t3a.large"
}

variable "use_spot" {
  # Spot = AWS's spare capacity, ~60% cheaper than normal (on-demand) pricing.
  # The catch: AWS can take the server back with 2 minutes' warning when it needs the
  # capacity. The server is then STOPPED (not deleted) and started again automatically when
  # capacity returns - everything on its disk is kept, but it gets a new public IP.
  # Set to false for a normal on-demand server that is never interrupted.
  description = "Run the k3s node as a Spot instance (much cheaper, can be interrupted)"
  type        = bool
  default     = true
}

variable "public_key_path" {
  description = "Path to the local SSH public key used to log in to the instance"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "repo_url" {
  description = "Git repository containing the QuakeWatch Helm chart"
  type        = string
  default     = "https://github.com/MichaelGoncharov0/quakewatch-aws.git"
}
