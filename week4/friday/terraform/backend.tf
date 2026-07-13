terraform {
  backend "s3" {
    bucket       = "kijanikiosk-terraform-state-oz"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
