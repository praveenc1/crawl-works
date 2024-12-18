# Create Elastic IP without instance association
terraform {
  backend "local" {
    path = "/Users/praveen/.tf/jupyter-aws-fixed-ip"
  }
}

resource "aws_eip" "fixed_ip" {
  domain = "vpc"

  tags = {
    Name = "jupyter-server-fixed-ip"
  }
}

# Output the allocated IP
output "public_ip" {
  value = aws_eip.fixed_ip.public_ip
  description = "The allocated fixed public IP address"
}

output "allocation_id" {
  value = aws_eip.fixed_ip.allocation_id 
  description = "The allocation ID of the Elastic IP"
}


