provider "aws" {
  region = "us-west-2"
}


terraform {
  required_version = "~> 1.0.0"

  required_providers {
    aws = {
      version = "~> 3.0"
      source  = "hashicorp/aws"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.2.0"
    }
  }
}
