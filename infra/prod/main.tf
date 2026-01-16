terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ------------------------------------------------------------------
# 1. GLOBAL DATA & LOCALS
# ------------------------------------------------------------------

# Get the current Account ID dynamically
data "aws_caller_identity" "current" {}

# Define the ARN using the Account ID
locals {
  github_oidc_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

# Lookup the existing Zone
data "aws_route53_zone" "main" {
  name = "justinklein.ca"
}

# Lookup the existing Wildcard Certificate
data "aws_acm_certificate" "wildcard" {
  domain      = "justinklein.ca" 
  most_recent = true
  statuses    = ["ISSUED"]
}

# ------------------------------------------------------------------
# 2. SHARED STORAGE (The "Brain")
# ------------------------------------------------------------------

# The Knowledge Base Bucket (Stores the Vectors)
resource "aws_s3_bucket" "knowledge_base" {
  bucket = "knowledge-base-justinklein-ca"
}

# Block public access for the Knowledge Base Bucket
resource "aws_s3_bucket_public_access_block" "kb_block" {
  bucket = aws_s3_bucket.knowledge_base.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# [DRIFT PROTECTION] Reserve these keys so Terraform doesn't fight GitHub Actions
resource "aws_s3_object" "resume_placeholder" {
  bucket = aws_s3_bucket.knowledge_base.id
  key    = "raw/private/resume.pdf"
  lifecycle { ignore_changes = [source, content, etag, version_id] }
}

resource "aws_s3_object" "leetcode_placeholder" {
  bucket = aws_s3_bucket.knowledge_base.id
  key    = "raw/private/leetcode.json"
  lifecycle { ignore_changes = [source, content, etag, version_id] }
}

# ------------------------------------------------------------------
# 3. WEB MODULES (Static Sites)
# ------------------------------------------------------------------

module "site_root" {
  source              = "../modules/website-static"
  site_domain         = "justinklein.ca"
  zone_id             = data.aws_route53_zone.main.zone_id
  acm_certificate_arn = data.aws_acm_certificate.wildcard.arn
  github_repo         = "justinklein2001/justinklein.ca" 
  github_oidc_arn     = local.github_oidc_arn
}

module "site_get_smart" {
  source              = "../modules/website-static"
  site_domain         = "get-smart.justinklein.ca"
  zone_id             = data.aws_route53_zone.main.zone_id
  acm_certificate_arn = data.aws_acm_certificate.wildcard.arn
  github_repo         = "justinklein2001/my-tech-notes" 
  github_oidc_arn     = local.github_oidc_arn
  
  # Grants this specific GitHub Repo permission to WRITE to this bucket
  kb_bucket_name      = aws_s3_bucket.knowledge_base.bucket
}

module "site_get_quizzed" {
  source              = "../modules/website-static"
  site_domain         = "get-quizzed.justinklein.ca"
  zone_id             = data.aws_route53_zone.main.zone_id
  acm_certificate_arn = data.aws_acm_certificate.wildcard.arn
  github_repo         = "justinklein2001/get-quizzed" 
  github_oidc_arn     = local.github_oidc_arn
}

# ------------------------------------------------------------------
# 4. APP MODULES (Serverless Backend)
# ------------------------------------------------------------------

module "quiz_backend" {
  source            = "../modules/serverless-api" 
  app_name          = "quiz-app"
  # only URL to allow requests from:
  cors_domain       = "https://get-quizzed.justinklein.ca"
  lambda_source_dir = "${path.module}/lambda"
  
  # Pass permissions so the Lambda can READ from the bucket
  kb_bucket_arn     = aws_s3_bucket.knowledge_base.arn
  kb_bucket_id      = aws_s3_bucket.knowledge_base.id
}

# ------------------------------------------------------------------
# 5. COST SAFETY (The "Panic Button")
# ------------------------------------------------------------------
resource "aws_budgets_budget" "cost_alert" {
  name              = "monthly-cost-limit"
  budget_type       = "COST"
  limit_amount      = "10.00"   # Alert if spend goes over $5
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  # Alert me when ACTUAL spend hits 80% ($8.00)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["justinkleindev@gmail.com"]
  }

  # Alert me when FORECASTED spend hits 100% ($10.00)
  # (AWS predicts you will go over based on current usage)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["justinkleindev@gmail.com"]
  }
}