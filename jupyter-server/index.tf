# AWS Provider configuration is assumed to be defined elsewhere

# Security Group for Jupyter Server
resource "aws_security_group" "jupyter_sg" {
  name        = "jupyter-server-sg"
  description = "Security group for Jupyter server"

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

# EC2 Instance
resource "aws_instance" "jupyter_server" {
  ami           = "ami-0453ec754f44f9a4a" # Amazon Linux 2023 AMI - update as needed
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.jupyter_sg.id]
  key_name              = "jupyter-key-name" # Replace with your key pair name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y python3-pip python3-devel
              
              # Install Jupyter and essential packages
              pip3 install jupyter numpy pandas matplotlib scikit-learn

              # Create jupyter config
              mkdir -p /root/.jupyter
              jupyter notebook --generate-config
              
              # Generate random port and password
              JUPYTER_PORT=$(shuf -i 10000-65000 -n 1)
              JUPYTER_PASSWORD=$(openssl rand -hex 32)
              
              # Configure Jupyter
              cat > /root/.jupyter/jupyter_notebook_config.py << EOL
              c.NotebookApp.ip = '0.0.0.0'
              c.NotebookApp.port = $JUPYTER_PORT
              c.NotebookApp.password = '$JUPYTER_PASSWORD'
              c.NotebookApp.allow_root = True
              c.NotebookApp.open_browser = False
              EOL
              
              # Create systemd service
              cat > /etc/systemd/system/jupyter.service << EOL
              [Unit]
              Description=Jupyter Notebook Server

              [Service]
              Type=simple
              ExecStart=/usr/local/bin/jupyter notebook --config=/root/.jupyter/jupyter_notebook_config.py
              WorkingDirectory=/root
              User=root

              [Install]
              WantedBy=multi-user.target
              EOL

              # Setup SSH tunnel
              echo "GatewayPorts yes" >> /etc/ssh/sshd_config
              systemctl restart sshd

              # Start Jupyter service
              systemctl daemon-reload
              systemctl enable jupyter
              systemctl start jupyter

              # Save credentials for retrieval
              echo "Jupyter Port: $JUPYTER_PORT" > /root/jupyter_credentials.txt
              echo "Jupyter Password: $JUPYTER_PASSWORD" >> /root/jupyter_credentials.txt
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
    1. SSH into the instance:
       ssh -i <your-key-pair.pem> ec2-user@${aws_instance.jupyter_server.public_ip}
    
    2. Get Jupyter credentials:
       sudo cat /root/jupyter_credentials.txt
    
    3. Create SSH tunnel:
       ssh -i <your-key-pair.pem> -L 8888:<JUPYTER_PORT> ec2-user@${aws_instance.jupyter_server.public_ip}
    
    4. Access Jupyter in your browser:
       http://localhost:8888
EOT
}
