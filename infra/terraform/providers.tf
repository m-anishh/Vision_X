terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state for now. Once this is running for real, move to an S3 backend
  # (with DynamoDB locking) so state isn't just on one machine.
}

provider "aws" {
  region = var.aws_region
}
