data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_security_group" "k3s_sg" {
  name        = "greencity-k3s-sg"
  description = "Security group for k3s cluster and GreenCity services"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "k3s supervisor / Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "greencity-k3s-sg"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "greencity-k3s-key"
  public_key = file("~/.ssh/greencity_key.pub")
}

resource "aws_instance" "k3s_node" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.k3s_sg.id]
  key_name                    = aws_key_pair.deployer.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 25 
    volume_type           = "gp3"
    delete_on_termination = true
  }

user_data = <<-EOF
              #!/bin/bash
              fallocate -l 4G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              curl -sfL https://get.k3s.io | sh -
              sleep 10
              chmod 644 /etc/rancher/k3s/k3s.yaml
              EOF

  tags = {
    Name = "greencity-k3s-node"
  }
}

output "k3s_public_ip" {
  description = "Public IP of k3s instance"
  value       = aws_instance.k3s_node.public_ip
}