terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Get the current Account ID dynamically
data "aws_caller_identity" "current" {}

# Define the ARN using the Account ID
locals {
  github_oidc_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

# Lookup the existing Zone (Manually created to avoid infinite hang)
data "aws_route53_zone" "main" {
  name = "justinklein.ca"
}

# Lookup the existing Wildcard Certificate (*.justinklein.ca)
data "aws_acm_certificate" "wildcard" {
  domain      = "justinklein.ca" 
  most_recent = true
  statuses    = ["ISSUED"]
}

# Deploy the Sites
module "site_root" {
  source          = "../modules/website-static"
  site_domain     = "justinklein.ca"
  zone_id         = data.aws_route53_zone.main.zone_id
  acm_certificate_arn = data.aws_acm_certificate.wildcard.arn
  github_repo         = "justinklein2001/justinklein.ca" 
  github_oidc_arn     = local.github_oidc_arn
}

module "site_get_smart" {
  source          = "../modules/website-static"
  site_domain     = "get-smart.justinklein.ca"
  zone_id         = data.aws_route53_zone.main.zone_id
  acm_certificate_arn = data.aws_acm_certificate.wildcard.arn
  github_repo         = "justinklein2001/my-tech-notes" 
  github_oidc_arn     = local.github_oidc_arn
}
