output "my_ip_cidr" {
  description = "Your public IP that the security group allows"
  value       = local.my_ip_cidr
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "instance_public_ip" {
  description = "Public IP of the k3s EC2 instance"
  value       = aws_instance.k3s.public_ip
}

output "quakewatch_url" {
  description = "QuakeWatch site URL (after the chart is deployed)"
  value       = "http://${aws_instance.k3s.public_ip}"
}

output "ssh_command" {
  description = "Command to connect to the instance"
  value       = "ssh ubuntu@${aws_instance.k3s.public_ip}"
}
