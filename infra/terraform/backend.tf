terraform {
  backend "s3" {
    bucket         = "phoenix-chantel-tfstate"
    key            = "capstone-phoenix/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}