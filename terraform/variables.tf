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
  description = "EC2 instance type for the k3s node"
  type        = string
  default     = "t3.medium"
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
