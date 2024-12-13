# AWS Provider configuration is assumed to be defined elsewhere

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
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICrU8V8KXdc+jkKlWDvK+zKcm7L9EkBLq3eOpaRvi6yt praveen@WonderOfTheSeas.local"
}

# Create EBS volume
resource "aws_ebs_volume" "jupyter_data" {
  availability_zone = "us-east-1a"  # Same AZ as the EC2 instance
  size             = 1024  # 1TB in GiB
  type             = "gp3"

  tags = {
    Name = "jupyter-data"
  }
}

# Attach EBS volume to EC2 instance
resource "aws_volume_attachment" "jupyter_data_attachment" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.jupyter_data.id
  instance_id = aws_instance.jupyter_server.id
}

# EC2 Instance
resource "aws_instance" "jupyter_server" {
  ami           = "ami-0453ec754f44f9a4a"
  instance_type = var.instance_type
  subnet_id     = aws_default_subnet.default_az1.id

  vpc_security_group_ids = [aws_security_group.jupyter_sg.id]
  key_name              = aws_key_pair.jupyter_key.key_name

  root_block_device {
    encrypted   = true
    volume_size = 20
  }

  user_data = <<-EOF
              #!/bin/bash
              # Wait for EBS volume to be attached
              while [ ! -e /dev/nvme1n1 ]; do sleep 1; done

              # Format the volume if it's not already formatted
              if ! blkid /dev/nvme1n1; then
                mkfs -t xfs /dev/nvme1n1
              fi

              # Create mount point and add to fstab
              mkdir -p /jupyter-data
              echo "/dev/nvme1n1 /jupyter-data xfs defaults,nofail 0 2" >> /etc/fstab
              mount -a

              # Set permissions
              chown -R ec2-user:ec2-user /jupyter-data

              # Update SSH configuration to listen on port 8022
              sed -i 's/#Port 22/Port 8022/' /etc/ssh/sshd_config
              systemctl restart sshd

              yum update -y
              yum install -y python3-pip python3-devel gcc

              # Create jupyter user
              useradd -m jupyter
              mkdir -p /home/jupyter/.jupyter
              chown -R jupyter:jupyter /home/jupyter

              # Install Jupyter and essential packages
              sudo -u jupyter pip3 install --user jupyter numpy pandas matplotlib scikit-learn

              # Generate Jupyter config with password
              JUPYTER_HASH=$(python3 -c "from jupyter_server.auth import passwd; print(passwd('${var.jupyter_password}'))")

              # Configure Jupyter
              cat > /home/jupyter/.jupyter/jupyter_server_config.py << EOL
              c.ServerApp.ip = '127.0.0.1'
              c.ServerApp.port = 8888
              c.ServerApp.password = '$JUPYTER_HASH'
              c.ServerApp.allow_remote_access = False
              c.ServerApp.allow_origin = '*'
              c.ServerApp.root_dir = '/jupyter-data'
              EOL

              # Create systemd service
              cat > /etc/systemd/system/jupyter.service << EOL
              [Unit]
              Description=Jupyter Notebook Server
              After=network.target

              [Service]
              Type=simple
              User=jupyter
              Environment="PATH=/home/jupyter/.local/bin:/usr/local/bin:/usr/bin"
              ExecStart=/home/jupyter/.local/bin/jupyter notebook --config=/home/jupyter/.jupyter/jupyter_server_config.py
              WorkingDirectory=/jupyter-data
              Restart=always

              [Install]
              WantedBy=multi-user.target
              EOL

              # Set proper permissions
              chown -R jupyter:jupyter /jupyter-data
              chmod 700 /home/jupyter/.jupyter

              # Update SSH configuration to listen on port 8022
              sed -i 's/#Port 22/Port 8022/' /etc/ssh/sshd_config
              systemctl restart sshd

              # Enable and start Jupyter service
              systemctl daemon-reload
              systemctl enable jupyter
              systemctl start jupyter

              # Wait for Jupyter to start and save token
              sleep 10
              sudo journalctl -u jupyter.service | grep token | tail -n 1 > /home/jupyter/token.txt
              chown jupyter:jupyter /home/jupyter/token.txt
              EOF

  tags = {
    Name = "jupyter-server"
  }
}

# Get Jupyter token
resource "null_resource" "get_jupyter_token" {
  depends_on = [
    aws_instance.jupyter_server,
    aws_volume_attachment.jupyter_data_attachment
  ]

  provisioner "local-exec" {
    command = <<-EOF
      while ! nc -z ${aws_instance.jupyter_server.public_ip} 8022; do
        echo "Waiting for SSH to become available..."
        sleep 5
      done
      
      sleep 30
      
      ssh -o StrictHostKeyChecking=no \
          -o ConnectTimeout=60 \
          -i ~/.ssh/id_jup_nb \
          -p 8022 \
          ec2-user@${aws_instance.jupyter_server.public_ip} \
          'sudo journalctl -u jupyter.service | grep token | tail -n 1 | cut -d= -f2 | tr -d " "' \
          > jupyter_token.txt
    EOF
  }
}

# Update SSH config
resource "null_resource" "update_ssh_config" {
  depends_on = [aws_instance.jupyter_server]

  provisioner "local-exec" {
    command = <<-EOF
      # Create backup of existing config
      cp ~/.ssh/config ~/.ssh/config.bak 2>/dev/null || true
      
      # Remove existing jupyter-aws section if it exists
      sed -i.bak '/^Host jupyter-aws/,/^$/d' ~/.ssh/config || true
      
      # Append new configuration
      cat >> ~/.ssh/config << SSHCONFIG

Host jupyter-aws
    HostName ${aws_instance.jupyter_server.public_ip}
    User ec2-user
    Port 8022
    IdentityFile ~/.ssh/id_jup_nb
    StrictHostKeyChecking no

SSHCONFIG
    EOF
  }

  triggers = {
    instance_ip = aws_instance.jupyter_server.public_ip
  }
}

# Read the token file
data "local_file" "jupyter_token" {
  depends_on = [null_resource.get_jupyter_token]
  filename   = "jupyter_token.txt"
}

# Clean output for just the token
output "jupyter_token" {
  value = chomp(data.local_file.jupyter_token.content)
  description = "Jupyter notebook access token"
}

# Update the connection instructions
output "connection_instructions" {
  value = <<EOT
    Jupyter Token: ${chomp(data.local_file.jupyter_token.content)}

    Your SSH config has been updated. You can now:

    1. Create SSH tunnel:
       ssh -N -L 8888:localhost:8888 jupyter-aws

    2. Access Jupyter in your browser:
       http://localhost:8888
       
    3. Use the token above to log in

    Direct SSH access:
       ssh jupyter-aws
EOT
}
