variable "instance_name" {
  description = "Name of the EC2 instance."
  type        = string
  default     = "learn-terraform"
}

variable "instance_type" {
  description = "The EC2 instance's type."
  type        = string
  default     = "t3.micro"
}
