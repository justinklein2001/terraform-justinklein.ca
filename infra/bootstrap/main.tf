provider "aws" {
  region = var.region
  # Uses local AWS CLI credentials
}

# ------------------------------------------------------------------------------
# Terraform OIDC Provider (Connects AWS to Terraform Cloud)
# ------------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "tfc_provider" {
  url             = "https://app.terraform.io"
  client_id_list  = ["aws.workload.identity"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
}

# ------------------------------------------------------------------------------
# GitHub OIDC Provider (Global)
# ------------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github_provider" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # GitHub's thumbprint (This is the standard one)
  thumbprint_list = ["1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

# ------------------------------------------------------------------------------
# IAM Role (The Identity TFC Assumes)
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

resource "aws_iam_policy" "tfc_least_privilege" {
  name        = "TFC-LeastPrivilege-Policy"
  description = "Permissions for TFC to manage S3, CloudFront, Cognito, Lambda, and API Gateway"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # --------------------------------------------------------
      # 1. STORAGE & CONTENT DELIVERY
      # --------------------------------------------------------
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
        Action   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
        Resource = "*"
      },
      {
        Sid      = "CloudFrontManagement"
        Effect   = "Allow"
        Action   = [
          "cloudfront:CreateDistribution", "cloudfront:UpdateDistribution",
          "cloudfront:GetDistribution", "cloudfront:DeleteDistribution",
          "cloudfront:TagResource", "cloudfront:UntagResource",
          "cloudfront:ListTagsForResource", "cloudfront:CreateInvalidation",
          "cloudfront:CreateOriginAccessControl", "cloudfront:UpdateOriginAccessControl",
          "cloudfront:GetOriginAccessControl", "cloudfront:DeleteOriginAccessControl",
          "cloudfront:ListOriginAccessControls",
          "cloudfront:CreateFunction", "cloudfront:DescribeFunction",
          "cloudfront:GetFunction", "cloudfront:UpdateFunction",
          "cloudfront:DeleteFunction", "cloudfront:PublishFunction", "cloudfront:TestFunction"
        ]
        Resource = "*"
      },

      # --------------------------------------------------------
      # 2. NETWORKING & DNS
      # --------------------------------------------------------
      {
        Sid      = "Route53LimitedAccess"
        Effect   = "Allow"
        Action   = "route53:*"
        Resource = ["arn:aws:route53:::hostedzone/Z000438022EYGSL687R91"]
      },
      {
        Sid      = "Route53Reads"
        Effect   = "Allow"
        Action   = [
          "route53:ListHostedZones", "route53:ListHostedZonesByName",
          "route53:GetHostedZone", "route53:ListResourceRecordSets",
          "route53:ListTagsForResource", "route53:ListTagsForResources",
          "route53:ListHealthChecks", "route53:GetHealthCheck",
          "route53:GetHealthCheckStatus", "route53:ListTrafficPolicies",
          "route53:GetTrafficPolicy", "route53:GetTrafficPolicyInstance",
          "route53:ListTrafficPolicyInstances", "route53:ListQueryLoggingConfigs",
          "route53:GetQueryLoggingConfig", "route53:GetChange"
        ]
        Resource = "*"
      },
      {
        Sid      = "ACMReadOnly"
        Effect   = "Allow"
        Action   = ["acm:ListCertificates", "acm:DescribeCertificate", "acm:GetCertificate", "acm:ListTagsForCertificate"]
        Resource = "*"
      },

      # --------------------------------------------------------
      # 3. SERVERLESS COMPUTE & AUTH (Updated)
      # --------------------------------------------------------
      
      # COGNITO
      {
        Sid      = "ManageCognito"
        Effect   = "Allow"
        Action   = ["cognito-idp:*"] 
        Resource = "*"
      },

      # LAMBDA: Added 'lambda:ListVersionsByFunction'
      {
        Sid      = "ManageLambda"
        Effect   = "Allow"
        Action   = [
          "lambda:CreateFunction", "lambda:DeleteFunction",
          "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunction", "lambda:ListTags", "lambda:TagResource", 
          "lambda:UntagResource", "lambda:AddPermission", "lambda:RemovePermission",
          "lambda:ListVersionsByFunction", "lambda:ListAliases"
        ]
        Resource = "*"
      },

      # API GATEWAY
      {
        Sid      = "ManageAPIGateway"
        Effect   = "Allow"
        Action   = ["apigateway:*"] 
        Resource = "*"
      },

      # BUDGETS: Added Tagging Permissions
      {
        Sid      = "ManageBudgets"
        Effect   = "Allow"
        Action   = [
          "budgets:ViewBudget", 
          "budgets:ModifyBudget",
          "budgets:ListTagsForResource",
          "budgets:TagResource",
          "budgets:UntagResource"
        ]
        Resource = "*"
      },

      # --------------------------------------------------------
      # 4. IAM ROLE MANAGEMENT
      # --------------------------------------------------------
      {
        Sid    = "AllowTFCToCreateRoles",
        Effect = "Allow",
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
          "iam:UpdateRole", "iam:TagRole", "iam:UntagRole",
          "iam:PassRole", "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies", "iam:GetRolePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy"
        ],
        Resource = [
          "arn:aws:iam::${var.aws_account_id}:role/*-github-deploy-role",
          "arn:aws:iam::${var.aws_account_id}:role/*-role"
        ]
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