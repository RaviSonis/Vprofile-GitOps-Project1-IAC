terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.25.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.4"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3.2"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23.0"
    }
  }

  backend "s3" {
    bucket = "gitopsbucket90"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }

  # allows all 1.x versions from 1.6.3 up to (but not including) 2.0
  required_version = ">= 1.6.3, < 2.0.0"
  # or (also allows 1.13.1)
  required_version = "~> 1.6"

}
##
##
##
