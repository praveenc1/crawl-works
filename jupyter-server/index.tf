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

  tags = {
    Name = "Default subnet for us-east-1a"
  }
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = "us-east-1b"

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
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

# EC2 Instance
resource "aws_instance" "jupyter_server" {
  ami           = "ami-0453ec754f44f9a4a" # Amazon Linux 2023 AMI - update as needed
  instance_type = "t2.micro"
  subnet_id     = aws_default_subnet.default_az1.id  # Using first AZ subnet

  vpc_security_group_ids = [aws_security_group.jupyter_sg.id]
  key_name              = aws_key_pair.jupyter_key.key_name  # Reference the key we just created

  user_data = <<-EOF
              #!/bin/bash
              # Update SSH configuration to listen on port 8022
              sed -i 's/#Port 22/Port 8022/' /etc/ssh/sshd_config
              systemctl restart sshd

              yum update -y
              yum install -y python3-pip python3-devel
              
              # Install Jupyter and essential packages
              pip3 install jupyter numpy pandas matplotlib scikit-learn

              # Create jupyter config
              mkdir -p /root/.jupyter

              # Generate and configure Jupyter
              cat > /root/.jupyter/jupyter_server_config.py << EOL
              c.ServerApp.ip = '127.0.0.1'  # Only accept localhost connections
              c.ServerApp.port = 8888
              c.ServerApp.password = ''  # Use token authentication
              c.ServerApp.allow_remote_access = False
              c.ServerApp.allow_origin = '*'
              EOL

              # Create startup script
              cat > /root/start_jupyter.sh << EOL
              #!/bin/bash
              cd /root
              jupyter notebook --no-browser
              EOL

              # Make startup script executable
              chmod +x /root/start_jupyter.sh

              # Create systemd service
              cat > /etc/systemd/system/jupyter.service << EOL
              [Unit]
              Description=Jupyter Notebook Server
              After=network.target

              [Service]
              Type=simple
              User=root
              ExecStart=/root/start_jupyter.sh
              WorkingDirectory=/root
              Restart=always

              [Install]
              WantedBy=multi-user.target
              EOL

              # Enable and start Jupyter service
              systemctl daemon-reload
              systemctl enable jupyter
              systemctl start jupyter

              # Save initial token for retrieval
              jupyter server list > /root/jupyter_token.txt
              EOF

  tags = {
    Name = "jupyter-server"
  }
}

# Output the instance public IP
output "jupyter_server_ip" {
  value = aws_instance.jupyter_server.public_ip
}

# Output connection instructions
output "connection_instructions" {
  value = <<EOT
    1. SSH into the instance to get the Jupyter token:
       ssh -p 8022 ec2-user@${aws_instance.jupyter_server.public_ip}
       sudo cat /root/jupyter_token.txt

    2. Create SSH tunnel:
       ssh -p 8022 -N -L 8888:localhost:8888 ec2-user@${aws_instance.jupyter_server.public_ip}

    3. Access Jupyter in your browser:
       http://localhost:8888
       Use the token from step 1 to log in

    Tip: Add this to your ~/.ssh/config for easier access:
    
    Host jupyter-aws
        HostName ${aws_instance.jupyter_server.public_ip}
        User ec2-user
        Port 8022
        IdentityFile ~/.ssh/id_ed25519
EOT
}
