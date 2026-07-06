terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {}

data "aws_region" "current" {}
data "aws_availability_zones" "available" { state = "available" }
data "aws_caller_identity" "current" {}
