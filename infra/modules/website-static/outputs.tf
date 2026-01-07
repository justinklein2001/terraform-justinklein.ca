output "bucket_name" {
  value = aws_s3_bucket.site.id
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.site.domain_name
}

output "site_domain" {
  value = var.site_domain
}

output "github_role_arn" {
  value = aws_iam_role.github_deploy_role.arn
}