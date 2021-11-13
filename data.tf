data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_ami" "ami_id" {
  owners      = ["self"]
  most_recent = true

  filter {
    name   = "name"
    values = ["ecs*"]
  }

  filter {
    name   = "tag:packer/created"
    values = ["yes"]
  }
}

data "aws_iam_instance_profile" "ecs_container_instance_role" {
  name = "ecs-container-instance"
}

data "aws_vpc" "vpc" {
  tags = {
    env   = var.environment
    owner = "engineering"
  }
}

data "aws_subnet_ids" "worker_subnet_ids" {
  vpc_id = data.aws_vpc.vpc.id
  tags = {
    public  = "yes"
    has_igw = "yes"
    usage   = "any"
  }
}