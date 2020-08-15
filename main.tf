#-------------------------------
# AWS Provider
#-------------------------------
provider "aws" {
  region = "${var.aws_region}"
}

#-------------------------------
# VPC resource
#-------------------------------
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name        = "my-terraform-aws-vpc-${terraform.workspace}"
    Environment = "${terraform.workspace}"
  }
}

#-------------------------------
# S3 Bucket Creation
#-------------------------------
resource "aws_s3_bucket" "my-bucket" {
  bucket = "my-terraform-bucket-with-unique-name"
  acl    = "private"
  versioning {
    enabled = true
  }

  tags = {
    Name = "my-terraform-bucket-with-unique-name"
  }
}

#-------------------------------
# S3 Remote State
#-------------------------------
terraform {
  backend "s3" {
    bucket = "my-terraform-bucket-with-unique-name"
    key    = "vpc.tfstate"
    region = "ap-southeast-2"
  }
}

resource "aws_subnet" "public_subnet" {
  count = "${length(var.public_subnet_cidr_block)}"

  vpc_id     = "${aws_vpc.main.id}"
  cidr_block = "${element(var.public_subnet_cidr_block, count.index)}"

  availability_zone = "${element(var.availability_zones, count.index)}"

  tags = {
    Name = "public_subnet_${count.index}"
  }
}

resource "aws_subnet" "private_subnet" {
  count = "${length(var.private_subnet_cidr_block)}"

  vpc_id     = "${aws_vpc.main.id}"
  cidr_block = "${element(var.private_subnet_cidr_block, count.index)}"

  availability_zone = "${element(var.availability_zones, count.index)}"

  tags = {
    Name = "private_subnet_${count.index}"
  }
}

resource "aws_subnet" "database_subnet" {
  count = "${length(var.database_subnet_cidr_block)}"

  vpc_id     = "${aws_vpc.main.id}"
  cidr_block = "${element(var.database_subnet_cidr_block, count.index)}"

  availability_zone = "${element(var.availability_zones, count.index)}"

  tags = {
    Name = "database_subnet_${count.index}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.main.id}"
}

# EIP and NAT Gateway
resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "natgw" {
  allocation_id = "${aws_eip.nat_eip.id}"
  subnet_id     = "${element(aws_subnet.public_subnet.*.id, 1)}"

  depends_on = ["aws_internet_gateway.igw"]
}

# Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }
}

resource "aws_route_table_association" "public_rt_association" {
  count = "${length(aws_subnet.public_subnet.*.id)}"

  subnet_id      = "${element(aws_subnet.public_subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.public_route_table.id}"
}

# Private Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.natgw.id}"
  }
}

resource "aws_route_table_association" "private_rt_association" {
  count = "${length(aws_subnet.private_subnet.*.id)}"

  subnet_id      = "${element(aws_subnet.private_subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.private_route_table.id}"
}

# Database Route Table
resource "aws_route_table" "database_route_table" {
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.natgw.id}"
  }
}

resource "aws_route_table_association" "database_rt_association" {
  count = "${length(aws_subnet.database_subnet.*.id)}"

  subnet_id      = "${element(aws_subnet.database_subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.database_route_table.id}"
}

# Keypair
resource "aws_key_pair" "bastion_host_key" {
  key_name   = "bastion_host_key"
  public_key = "${file(var.bastion_host_public_key)}"
}

# Bastion Host AMI
data "aws_ami" "ubuntu_ami" {
  most_recent = true

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  owners = ["099720109477"] # ubuntu
}

# Bastion Host Security Group
resource "aws_security_group" "bastion_host" {
  vpc_id = "${aws_vpc.main.id}"

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    // replace with your IP address, or CIDR block
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
  
  cidr_blocks = concat(aws_subnet.public_subnet.*.cidr_block, aws_subnet.private_subnet.*.cidr_block, aws_subnet.database_subnet.*.cidr_block)
 #   cidr_blocks = [
 #     "${aws_subnet.public_subnet.*.cidr_block}",
 #     "${aws_subnet.private_subnet.*.cidr_block}",
 #     "${aws_subnet.database_subnet.*.cidr_block}",
 #   ]
  }
}

# Bastion host EC2 instance
resource "aws_instance" "bastion_host" {
  ami           = "${data.aws_ami.ubuntu_ami.id}"
  instance_type = "t2.micro"
  key_name      = "${aws_key_pair.bastion_host_key.key_name}"

  vpc_security_group_ids      = ["${aws_security_group.bastion_host.id}"]
  subnet_id                   = "${element(aws_subnet.public_subnet.*.id, 1)}"
  associate_public_ip_address = true
}
