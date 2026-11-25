output "wordpress_url" {
  description = "Public URL to open WordPress setup"
  value       = "http://${aws_instance.app_server.public_ip}"
}

output "ec2_public_ip" {
  description = "Public IP of the Nginx + WordPress EC2 instance"
  value       = aws_instance.app_server.public_ip
}

output "rds_mariadb_endpoint" {
  description = "Private RDS MariaDB endpoint"
  value       = aws_db_instance.mariadb.endpoint
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 instance"
  value       = "ssh -i ~/.ssh/id_ed25519 ubuntu@${aws_instance.app_server.public_ip}"
}