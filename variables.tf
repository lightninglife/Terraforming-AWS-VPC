variable "aws_region" {
  description = "AWS Region"
}

variable "vpc_cidr_block" {
  description = "Main VPC CIDR Block"
}

variable "availability_zones" {
  type        = "list"
  description = "AWS Region Availability Zones"
}

variable "public_subnet_cidr_block" {
  type        = "list"
  description = "Public Subnet CIDR Block"
}

variable "private_subnet_cidr_block" {
  type        = "list"
  description = "Private Subnet CIDR Block"
}

variable "database_subnet_cidr_block" {
  type        = "list"
  description = "Database Subnet CIDR Block"
}

variable "bastion_host_public_key" {
  description = "Bastion host public key"
}
