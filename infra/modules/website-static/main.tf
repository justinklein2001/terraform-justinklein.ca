# ------------------------------------------------------------------
# Locals
# ------------------------------------------------------------------

locals {
  bucket_name = replace(var.site_domain, ".", "-")
}

# ------------------------------------------------------------------
# S3 Bucket (private — ONLY CloudFront can read it)
# ------------------------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------
# CloudFront Origin Access Control (OAC)
# ------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.site_domain}-oac"
  description                       = "Access control for ${var.site_domain}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ------------------------------------------------------------------
# CloudFront Distribution
# ------------------------------------------------------------------

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = var.site_domain
  default_root_object = "index.html"

  aliases = [var.site_domain]

  origin {
    domain_name               = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                 = "s3-origin"
    origin_access_control_id  = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    compress = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# ------------------------------------------------------------------
# Bucket policy: allow CloudFront only
# ------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "site_policy" {
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.site.arn
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------
# Route53 DNS
# ------------------------------------------------------------------

resource "aws_route53_record" "a_record" {
  count = var.create_dns_record ? 1 : 0

  zone_id = var.zone_id
  name    = var.site_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "aaaa_record" {
  count = var.create_dns_record ? 1 : 0

  zone_id = var.zone_id
  name    = var.site_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

# ------------------------------------------------------------------
# GitHub Actions Deployment Role
# ------------------------------------------------------------------

resource "aws_iam_role" "github_deploy_role" {
  # Enforcing the naming convention set in Bootstrap permissions
  name = "${var.site_domain}-github-deploy-role" 

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.github_oidc_arn
        }
        Condition = {
          StringLike = {
            # Only allow the specific repo (main branch)
            "token.actions.githubusercontent.com:sub": "repo:${var.github_repo}:ref:refs/heads/main"
          },
          StringEquals = {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_deploy_policy" {
  name = "s3-deploy-policy"
  role = aws_iam_role.github_deploy_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SyncToS3",
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ],
        Resource = [
          aws_s3_bucket.site.arn,
          "${aws_s3_bucket.site.arn}/*"
        ]
      },
      {
        Sid    = "InvalidateCloudFront",
        Effect = "Allow",
        Action = "cloudfront:CreateInvalidation",
        Resource = aws_cloudfront_distribution.site.arn
      }
    ]
  })
}