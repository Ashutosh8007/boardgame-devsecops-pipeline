# SSH key pair - Terraform uploads your public key to AWS so it can be
# injected into the instance at launch (no manual key-copying needed)
resource "aws_key_pair" "boardgame_key" {
  key_name   = "boardgame-ec2-key"
  public_key = file("~/.ssh/boardgame-ec2.pub")
}

# Security group: acts as the instance's firewall. Deliberately scoped -
# only the ports we actually need are opened, not a wide-open default.
resource "aws_security_group" "boardgame_sg" {
  name        = "boardgame-sg"
  description = "Security group for Boardgame K3s node"

  # SSH - restricted to your current IP only, not 0.0.0.0/0 (the whole
  # internet). This matters: leaving SSH open to everyone is one of the
  # most common real-world causes of compromised EC2 instances.
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"]
  }

  # HTTP - the app itself, via Ingress, needs to be reachable publicly
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # K3s API server port - needed so kubectl on your WSL machine can
  # talk to the cluster's control plane remotely
  ingress {
    description = "K3s API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_ip.response_body)}/32"]
  }

  # NodePort - exposes the Boardgame app externally. Open to the internet
  # (not IP-restricted like SSH/K3s API) since this is the actual
  # application traffic, meant to be publicly reachable.
  ingress {
    description = "Boardgame NodePort"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "boardgame-sg"
  }
}

# Fetches your current public IP at apply-time, so the SSH/K3s-API rules
# above lock down to just you, rather than hardcoding an IP that could
# go stale (e.g. if your home IP changes) or, worse, defaulting to
# 0.0.0.0/0 out of laziness.
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

# The actual EC2 instance
resource "aws_instance" "boardgame_node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.boardgame_key.key_name
  vpc_security_group_ids = [aws_security_group.boardgame_sg.id]

  tags = {
    Name = "boardgame-k3s-node"
  }
}

# Elastic IP: a static public IP that persists across instance stop/start
# cycles. Without this, AWS assigns a new public IP every time the
# instance restarts, breaking SSH, kubectl's TLS cert (which has the
# old IP baked into its tls-san list), and the app's public URL.
resource "aws_eip" "boardgame_eip" {
  instance = aws_instance.boardgame_node.id
  domain   = "vpc"

  tags = {
    Name = "boardgame-eip"
  }
}

# Always looks up the latest official Ubuntu 22.04 AMI for the region,
# rather than hardcoding an AMI ID - AMI IDs are region-specific and
# get replaced periodically as Canonical patches the base image, so
# hardcoding one is a common source of "works on my machine" Terraform
# configs that silently break for someone in a different region or a
# few months later.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
