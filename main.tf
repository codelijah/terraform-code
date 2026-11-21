terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket = "elijah-tfstate-2026"
    key    = "docker-site/terraform.tfstate"
    region = "eu-north-1"
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "eu-north-1"
}

variable "alert_email" {
  type = string
}

variable "cpu_threshold" {
  type    = number
  default = 80
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "code" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.code_sg.id]
  key_name               = aws_key_pair.docker_site.key_name


  user_data = <<-EOF
    #!/bin/bash
    dnf install -y docker git
    systemctl enable --now docker
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjkAP9SujALIwL0IqmwYJ1nnSV5i+/+6QUPLcLVVXvf docker-site-key-deploy" >> /home/ec2-user/.ssh/authorized_keys  
    git clone https://github.com/codelijah/docker-site.git /home/ec2-user/docker-site
    cd /home/ec2-user/docker-site
    docker build -t docker-site .
    docker run -d -p 80:80 --name docker-site-container docker-site
  EOF

  tags = {
    Name = "terraform-code-server"
  }
}

resource "aws_security_group" "code_sg" {
  name        = "terraform-code-sg"
  description = "Firewall for the Terraform web Server"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "server_ip" {
  value = aws_eip.code_ip.public_ip
}

resource "aws_eip" "code_ip" {
  instance = aws_instance.code.id
  domain   = "vpc"
}

resource "aws_key_pair" "docker_site" {
  key_name   = "docker-site-key"
  public_key = file("~/.ssh/docker-site-key.pub")
}

resource "aws_sns_topic" "alert" {
  name = "docker-site-alert"
}

module "monitoring" {
  source        = "./modules/monitoring"
  instance_id   = aws_instance.code.id
  alert_email   = var.alert_email
  cpu_threshold = var.cpu_threshold
}

output "alert_topic_arn" {
  value = module.monitoring.topic_arn
}
