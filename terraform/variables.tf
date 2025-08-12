variable "aws_region" {
  default = "ap-south-1"
}

variable "vpc_name" {
  type        = string
  description = "Name of the VPC"
  default     = "main"
}

variable "vpc_tags" {
  type    = map(string)
  default = {}
}

variable "public_Subnet_tags" {
  type    = map(string)
  default = {}
}

variable "public_route_table_tags" {
  type    = map(string)
  default = {}
}

variable "ami_id" {
  default = "ami-0f918f7e67a3323f0" # Ubuntu 22.04 LTS for ap-south-1 (Mumbai)
}

variable "instance_type" {
  default = "t2.medium"
}

variable "jenkins_instance_type" {
  default = "t2.medium"
}

variable "jenkins_instance_tags" {
  type = map(string)
  default = {
    Name = ""
  }

}

