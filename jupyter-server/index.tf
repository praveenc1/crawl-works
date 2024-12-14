# AWS Provider configuration is assumed to be defined elsewhere

terraform {
  backend "local" {
    path = var.tf_state_dir
  }
}


# Create a default VPC
resource "aws_default_vpc" "default" {
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Default VPC"
  }
}

# Create default subnets in each AZ
resource "aws_default_subnet" "default_az1" {
  availability_zone = "us-east-1a"
  
  depends_on = [aws_default_vpc.default]  # Add explicit dependency

  tags = {
    Name = "Default subnet for us-east-1a"
  }
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = "us-east-1b"
  
  depends_on = [aws_default_vpc.default]  # Add explicit dependency

  tags = {
    Name = "Default subnet for us-east-1b"
  }
}

# Security Group for Jupyter Server
resource "aws_security_group" "jupyter_sg" {
  name        = "jupyter-server-sg"
  description = "Security group for Jupyter server"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    from_port   = 8022
    to_port     = 8022
    protocol    = "tcp"
    cidr_blocks = [for ip in var.allowed_ip : "${ip}/32"]
    description = "SSH access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jupyter-server-sg"
  }
}

# Add your SSH key
resource "aws_key_pair" "jupyter_key" {
  key_name   = "jupyter-key"
  public_key = var.public_key
}

# Create IAM role for EC2
resource "aws_iam_role" "jupyter_role" {
  name = "jupyter_server_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "jupyter-server-role"
  }
}

# Create IAM policy for Common Crawl access
resource "aws_iam_role_policy" "commoncrawl_access" {
  name = "commoncrawl_access"
  role = aws_iam_role.jupyter_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:*"
        ]
        Resource = [
          "arn:aws:s3:::commoncrawl",
          "arn:aws:s3:::commoncrawl/*",
          "arn:aws:s3:::crawler-works",
          "arn:aws:s3:::crawler-works/*"
        ]
      }
    ]
  })
}

# Create instance profile
resource "aws_iam_instance_profile" "jupyter_profile" {
  name = "jupyter_server_profile"
  role = aws_iam_role.jupyter_role.name
}

# EC2 Instance
resource "aws_instance" "jupyter_server" {
  ami           = var.ami
  instance_type = var.instance_type
  subnet_id     = aws_default_subnet.default_az1.id

  vpc_security_group_ids = [aws_security_group.jupyter_sg.id]
  key_name              = aws_key_pair.jupyter_key.key_name
  iam_instance_profile  = aws_iam_instance_profile.jupyter_profile.name

  root_block_device {
    encrypted   = true
    volume_size = 20
  }

  # Request ephemeral storage
  ephemeral_block_device {
    device_name  = "/dev/sdb"
    virtual_name = "ephemeral0"
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    jupyter_hash_base64 = base64encode(var.jupyter_hash),
    ssh_public_key  = var.public_key,
    git_user_private_key = var.git_user_private_key,
    git_user_pub_key = var.git_user_pub_key
  })

  tags = {
    Name = "jupyter-server"
  }
}

# Get the IP from the fixed-ip configuration output
data "aws_eip" "fixed_ip" {
  #public_ip = ["bash", "-c", "cd ../fixed-ip && tofu output -json | jq -r '.public_ip.value'"]
  #id = ["bash", "-c", "cd ../fixed-ip && tofu output -json | jq -r '.allocation_id.value'"]
  public_ip = "3.218.16.212"
  id        = "eipalloc-08a4d99cd8d8f99ef"
}
# Associate EIP with EC2 instance
resource "aws_eip_association" "jupyter_eip_assoc" {
  instance_id   = aws_instance.jupyter_server.id
  allocation_id = data.aws_eip.fixed_ip.id
}

resource "null_resource" "set_jupyter_password" {
  depends_on = [aws_instance.jupyter_server]

  provisioner "local-exec" {
    command = <<EOT
    bw_jupyter_password=$(bw get password jupyter --session "${var.bw_session}") && \
    ssh jupyter-aws "echo 'jupyter:$bw_jupyter_password' | sudo chpasswd"
    EOT
  }
}

# Update the connection instructions
output "connection_instructions" {
  value = <<EOT
    1. Create SSH tunnel:
       ssh -N -L 8888:localhost:8888 jupyter-aws

    2. Access Jupyter in your browser:
       http://localhost:8888
       
    3. Use the token above to log in

    Direct SSH access:
       ssh jupyter-aws         # for ec2-user
       ssh jupyter-aws-user    # for jupyter user
EOT
}
