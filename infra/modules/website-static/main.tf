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
# ACM Certificate (wildcard for entire domain)
# Must be in us-east-1
# ------------------------------------------------------------------

resource "aws_acm_certificate" "wildcard" {
  provider          = aws.us_east_1
  domain_name       = "*.${var.root_domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "wildcard_validation" {
  zone_id = data.aws_route53_zone.root.zone_id

  name    = aws_acm_certificate.wildcard.domain_validation_options[0].resource_record_name
  type    = aws_acm_certificate.wildcard.domain_validation_options[0].resource_record_type
  ttl     = 60

  records = [
    aws_acm_certificate.wildcard.domain_validation_options[0].resource_record_value
  ]
}

resource "aws_acm_certificate_validation" "wildcard" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [aws_route53_record.wildcard_validation.fqdn]
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
    acm_certificate_arn      = aws_acm_certificate_validation.wildcard.certificate_arn
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

data "aws_route53_zone" "root" {
  name         = "${var.root_domain}."
  private_zone = false
}

resource "aws_route53_record" "a_record" {
  count = var.create_dns_record ? 1 : 0

  zone_id = data.aws_route53_zone.root.zone_id
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

  zone_id = data.aws_route53_zone.root.zone_id
  name    = var.site_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}