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

# The Knowledge Base Bucket (Stores the Vectors)
resource "aws_s3_bucket" "knowledge_base" {
  bucket = "knowledge-base-justinklein-ca" # Must be globally unique
}

# Block public access for the Knowledge Base Bucket
resource "aws_s3_bucket_public_access_block" "kb_block" {
  bucket = aws_s3_bucket.knowledge_base.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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
  kb_bucket_arn       = aws_s3_bucket.knowledge_base.arn
}
