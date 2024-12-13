variable "allowed_ip" {
  description = "List of IP addresses allowed to access the Jupyter server"
  type        = list(string)
  default     = []  # Empty list as default
}

variable "jupyter_password" {
  description = "Password for Jupyter notebook"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}