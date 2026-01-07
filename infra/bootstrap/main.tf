provider "aws" {
  region = var.region
  # Uses local AWS CLI credentials
}

# ------------------------------------------------------------------------------
# 1. OIDC Provider (Connects AWS to Terraform Cloud)
# ------------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "tfc_provider" {
  url             = "https://app.terraform.io"
  client_id_list  = ["aws.workload.identity"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
}

# ------------------------------------------------------------------------------
# 2. IAM Role (The Identity TFC Assumes)
# ------------------------------------------------------------------------------
resource "aws_iam_role" "tfc_admin_role" {
  name = "tfc-admin-role" 

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${var.aws_account_id}:oidc-provider/app.terraform.io"
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "app.terraform.io:aud" = "aws.workload.identity"
          },
          # Wildcard allowing any workspace in project
          StringLike = {
            "app.terraform.io:sub" = "organization:justinklein:project:*:workspace:*:run_phase:*"
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# 3. Custom Least Privilege Policy
# ------------------------------------------------------------------------------
resource "aws_iam_policy" "tfc_least_privilege" {
  name        = "TFC-LeastPrivilege-Policy"
  description = "Permissions for TFC to manage S3/CloudFront/Route53 for justinklein.ca"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # S3 Management (Scoped to root domain naming convention)
      {
        Sid      = "ManagePortfolioBuckets"
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = [
          "arn:aws:s3:::*-justinklein-ca",
          "arn:aws:s3:::*-justinklein-ca/*",
          "arn:aws:s3:::justinklein-ca",
          "arn:aws:s3:::justinklein-ca/*"
        ]
      },
      {
        Sid      = "S3ListAllBuckets"
        Effect   = "Allow"
        Action   = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      },
      # CloudFront Management
      {
        Sid      = "CloudFrontManagement"
        Effect   = "Allow"
        Action   = [
          "cloudfront:CreateDistribution",
          "cloudfront:UpdateDistribution",
          "cloudfront:GetDistribution",
          "cloudfront:DeleteDistribution",
          "cloudfront:TagResource",
          "cloudfront:UntagResource",
          "cloudfront:ListTagsForResource",
          "cloudfront:CreateInvalidation",
          "cloudfront:CreateOriginAccessControl",
          "cloudfront:UpdateOriginAccessControl",
          "cloudfront:GetOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl",
          "cloudfront:ListOriginAccessControls"
        ]
        Resource = "*"
      },
      # Route53 Management (Specific Zone)
      {
        Sid      = "Route53LimitedAccess"
        Effect   = "Allow"
        Action   = "route53:*"
        Resource = [
          "arn:aws:route53:::hostedzone/Z000438022EYGSL687R91"
        ]
      },
      # Route53 Read-Only (Global)
      {
        Sid      = "Route53Reads"
        Effect   = "Allow"
        Action   = [
          "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource",
          "route53:ListTagsForResources",
          "route53:ListHealthChecks",
          "route53:GetHealthCheck",
          "route53:GetHealthCheckStatus",
          "route53:ListTrafficPolicies",
          "route53:GetTrafficPolicy",
          "route53:GetTrafficPolicyInstance",
          "route53:ListTrafficPolicyInstances",
          "route53:ListQueryLoggingConfigs",
          "route53:GetQueryLoggingConfig",
          "route53:GetChange"
        ]
        Resource = "*"
      },
      # ACM Read-Only (Safe)
      {
        Sid      = "ACMReadOnly"
        Effect   = "Allow"
        Action   = [
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "acm:GetCertificate",
          "acm:ListTagsForCertificate"
        ]
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# 4. Attach Policy to Role
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "attach_least_privilege" {
  role       = aws_iam_role.tfc_admin_role.name
  policy_arn = aws_iam_policy.tfc_least_privilege.arn
}