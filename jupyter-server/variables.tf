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
  #default     = "c6gn.xlarge"
  #default     = "im4gn.large"
}

variable "tf_state_dir" {}
variable "public_key" { type = string }
variable "ami" {}
variable "git_user_pub_key" {}
variable "git_user_private_key" {}
variable "bw_session" {}
variable "jupyter_hash" { }