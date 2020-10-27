provider "aws" {
  region = var.region
}

# AMIs
data "aws_ami" "amzn-ami-minimal-hvm-ebs" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-minimal-hvm-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

data "aws_ami" "arch-ami-hvm-ebs" {
  most_recent = true
  owners      = ["093273469852"]

  filter {
    name   = "name"
    values = ["arch-linux-hvm-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# Instance types
data "aws_ec2_instance_type_offering" "nano" {
  filter {
    name   = "instance-type"
    values = ["t3a.nano", "t3.nano"]
  }

  preferred_instance_types = ["t3a.nano", "t3.nano"]
}

data "aws_ec2_instance_type_offering" "dev" {
  filter {
    name   = "instance-type"
    values = var.dev-instance-types
  }

  preferred_instance_types = var.dev-instance-types
}

# Network topology
data "external" "local_public_ip" {
  program = [
    "bash",
    "-c", 
    "echo {\\\"local_public_ip\\\":\\\"$(curl https://checkip.amazonaws.com/)\\\"}"]
}

resource "aws_vpc" "dev" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_subnet" "subnet-zero" {
  cidr_block        = cidrsubnet(aws_vpc.dev.cidr_block, 3, 0)
  vpc_id            = aws_vpc.dev.id
}

resource "aws_eip" "ip-bastion" {
  instance = aws_spot_instance_request.bastion-nodes[0].spot_instance_id
  vpc      = true
}

resource "aws_internet_gateway" "dev-gw" {
  vpc_id = aws_vpc.dev.id
}

resource "aws_route_table" "route-table-dev" {
  vpc_id = aws_vpc.dev.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dev-gw.id
  }
}

resource "aws_route_table_association" "subnet-association" {
  subnet_id      = aws_subnet.subnet-zero.id
  route_table_id = aws_route_table.route-table-dev.id
}

resource "aws_security_group" "ingress-ssh" {
  name   = "allow-ssh-sg"
  vpc_id = aws_vpc.dev.id

  ingress {
    cidr_blocks = [
      "${data.external.local_public_ip.result.local_public_ip}/32"
    ]

    from_port = 22
    to_port   = 22
    protocol  = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "internal" {
  name   = "allow-internal-sg"
  vpc_id = aws_vpc.dev.id

  ingress {
    cidr_blocks = [
      aws_vpc.dev.cidr_block
    ]

    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      aws_vpc.dev.cidr_block
    ]
  }
}

# SSH key
resource "aws_key_pair" "spot_key" {
  key_name   = "spot_key"
  public_key = file(var.ssh-pub-key)
}

# Spot instance(s)
resource "aws_spot_instance_request" "bastion-nodes" {
  count = 1
  ami           = data.aws_ami.amzn-ami-minimal-hvm-ebs.id
  instance_type = data.aws_ec2_instance_type_offering.nano.instance_type

  spot_price = "0.005"

  spot_type = "one-time"
  key_name  = "spot_key"

  wait_for_fulfillment = true

  security_groups = [aws_security_group.ingress-ssh.id, aws_security_group.internal.id]
  subnet_id = aws_subnet.subnet-zero.id
}

resource "aws_spot_instance_request" "dev-nodes" {
  count = 1
  ami           = data.aws_ami.arch-ami-hvm-ebs.id
  instance_type = data.aws_ec2_instance_type_offering.dev.instance_type

  spot_price = var.dev-instance-spot-price

  spot_type = "one-time"
  key_name  = "spot_key"

  wait_for_fulfillment = true

  security_groups = [aws_security_group.internal.id]
  subnet_id = aws_subnet.subnet-zero.id
}

# Ansible hosts file
resource "local_file" "hosts_cfg" {
  content = templatefile("${path.module}/ansible-hosts.tpl",
    {
      bastions = aws_spot_instance_request.bastion-nodes.*.public_ip
      dev_instances = aws_spot_instance_request.dev-nodes.*.private_ip
      first_bastion = aws_spot_instance_request.bastion-nodes.0.public_ip
      ssh_pub_key = var.ssh-pub-key
    }
  )
  filename = "../ansible/hosts.cfg"
}
