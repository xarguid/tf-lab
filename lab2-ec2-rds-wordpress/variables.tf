variable "ssh_public_key_path" {
  description = "Path to local SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "allowed_ssh_cidr" {
  description = "Your public IP in CIDR notation, e.g. 203.0.113.10/32"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "wp-mariadb-lab"
}

variable "instance_type" {
  description = "EC2 instance type (Free Plan eligible in eu-north-1)"
  type        = string
  default     = "t3.micro"
}


variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Initial MariaDB database name"
  type        = string
  default     = "wordpress"
}

variable "db_username" {
  description = "Master username for MariaDB"
  type        = string
  default     = "wpuser"
}

variable "db_password" {
  description = "Master password for MariaDB (min 8 chars, no @, /, or quotes)"
  type        = string
  sensitive   = true
}

variable "allowed_http_cidr" {
  description = "CIDR allowed to reach HTTP port 80 (restrict to your IP/32 for tighter security)"
  type        = string
  default     = "0.0.0.0/0"
}