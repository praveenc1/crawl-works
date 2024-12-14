#!/bin/bash

# Format and mount instance store
if [ -b /dev/nvme1n1 ]; then
  DEVICE=/dev/nvme1n1
elif [ -b /dev/xvdb ]; then
  DEVICE=/dev/xvdb
else
  DEVICE=/dev/sdb
fi

# Format the instance store if it's not already formatted
if ! blkid $DEVICE; then
  mkfs -t xfs $DEVICE
fi

# Create mount point and mount
mkdir -p /jupyter-data
mount $DEVICE /jupyter-data

# Create jupyter user
useradd -m jupyter
mkdir -p /home/jupyter/.jupyter
mkdir -p /home/jupyter/.ssh
chown -R jupyter:jupyter /jupyter-data

# Copy SSH key
echo "${ssh_public_key}" > /home/jupyter/.ssh/authorized_keys

# Set proper permissions
chmod 700 /home/jupyter/.ssh
chmod 600 /home/jupyter/.ssh/authorized_keys
chown -R jupyter:jupyter /home/jupyter/.ssh
chown -R jupyter:jupyter /home/jupyter/.jupyter

echo "${git_user_pub_key}" > /home/jupyter/.ssh/id_ed25519.pub
echo "${git_user_private_key}" > /home/jupyter/.ssh/id_ed25519
chmod 600 /home/jupyter/.ssh/id_ed25519.pub
chmod 600 /home/jupyter/.ssh/id_ed25519
chown jupyter:jupyter /home/jupyter/.ssh/id_ed25519.pub
chown jupyter:jupyter /home/jupyter/.ssh/id_ed25519

# Update SSH configuration to listen on port 8022
sed -i 's/#Port 22/Port 8022/' /etc/ssh/sshd_config
systemctl restart sshd

yum update -y;
yum install -y python python3-pip python3-devel gcc unzip aws-cli vim git

# Install Jupyter and essential packages
sudo su jupyter -c "{
  pip install --user jupyter numpy pandas matplotlib scikit-learn boto3 duckdb;
  
  mkdir -p /jupyter-data/projects
  cd /jupyter-data/projects
  git clone https://github.com/praveenc1/crawl-works.git
  }"

echo "jupyter ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
echo "ec2-user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# bw login your-email@example.com
# bw sync 
# export BW_SESSION=$(bw unlock --raw)

# Hash the jupyter_password variable
#pass_hash=$(python -c "from jupyter_server.auth import passwd; print(passwd('{jupyter_password}'))")
pass_hash=$(echo "${jupyter_hash_base64}" | base64 --decode)
#echo "pass hash: $pass_hash"

# Configure Jupyter
cat > /home/jupyter/.jupyter/jupyter_server_config.py << EOL
c.ServerApp.ip = '127.0.0.1'
c.ServerApp.port = 8888
c.ServerApp.password = '$pass_hash'
c.ServerApp.allow_remote_access = False
c.ServerApp.allow_origin = '*'
c.ServerApp.root_dir = '/jupyter-data'
EOL

unset jupyter_password

cat > /home/jupyter/.bashrc << EOL
# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific aliases and functions
alias ll='ls -l'
alias la='ls -a'
alias jn='jupyter notebook'

# Set PATH
export PATH=\$PATH:/home/jupyter/.local/bin

# Set EDITOR
export EDITOR=vim

# Set HISTSIZE
export HISTSIZE=1000

# Set HISTFILESIZE
export HISTFILESIZE=1000

# Set HISTTIMEFORMAT
export HISTTIMEFORMAT="%F %T "

# Set PS1
export PS1='[\u@\h \W]\$ '

# Enable vi mode
set -o vi
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
chmod 700 /home/jupyter/.jupyter

# Enable and start Jupyter service
systemctl daemon-reload
systemctl enable jupyter
systemctl start jupyter 