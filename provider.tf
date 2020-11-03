terraform {
  backend "s3" {
    bucket  = "sample_bucket"
    key    = "sample.tfstate"
    region  = "ap-northeast-1"
    encrypt = true
  }
}

# default
provider "aws" {
  region  = "ap-northeast-1"
  version = "~> 3.11.0"
  profile = "default"
}

# For Certificate on Cloudfront
provider "aws" {
  alias  = "virginia"
  version = "~> 3.11.0"
  region = "us-east-1"
  profile = "default"
}
