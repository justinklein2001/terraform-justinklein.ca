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
  description = "Robust permissions for TFC to manage the Portfolio Stack"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # --------------------------------------------------------
      # 1. STORAGE & CONTENT DELIVERY (S3 + CloudFront)
      # --------------------------------------------------------
      {
        Sid      = "S3FullAccessToPortfolio"
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
        Sid      = "S3ListAll"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
        Resource = "*"
      },
      {
        Sid      = "CloudFrontFullAccess"
        Effect   = "Allow"
        Action   = [
          "cloudfront:*" 
          # CloudFront is safe to wildcard here because it's hard to scope by resource ARN
        ]
        Resource = "*"
      },

      # --------------------------------------------------------
      # 2. NETWORKING (Route53 + ACM)
      # --------------------------------------------------------
      {
        Sid      = "Route53ZoneAccess"
        Effect   = "Allow"
        Action   = "route53:*"
        Resource = ["arn:aws:route53:::hostedzone/Z000438022EYGSL687R91"]
      },
      {
        Sid      = "Route53GlobalReads"
        Effect   = "Allow"
        Action   = ["route53:List*", "route53:Get*"]
        Resource = "*"
      },
      {
        Sid      = "ACMReadOnly"
        Effect   = "Allow"
        Action   = ["acm:List*", "acm:Describe*", "acm:Get*"]
        Resource = "*"
      },

      # --------------------------------------------------------
      # 3. SERVERLESS COMPUTE (The Fix for Whack-a-Mole)
      # --------------------------------------------------------
      
      # LAMBDA: Allow ALL Reads/Lists, strict Writes
      {
        Sid      = "LambdaReadList"
        Effect   = "Allow"
        Action   = ["lambda:Get*", "lambda:List*"]
        Resource = "*"
      },
      {
        Sid      = "LambdaWrite"
        Effect   = "Allow"
        Action   = [
          "lambda:CreateFunction", "lambda:DeleteFunction",
          "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
          "lambda:TagResource", "lambda:UntagResource", 
          "lambda:AddPermission", "lambda:RemovePermission",
          "lambda:PutFunctionConcurrency"
        ]
        Resource = "*"
      },

      # COGNITO: Broad access needed for User Pool configuration
      {
        Sid      = "CognitoFullAccess"
        Effect   = "Allow"
        Action   = ["cognito-idp:*"]
        Resource = "*"
      },

      # API GATEWAY: Broad access needed for V2 APIs
      {
        Sid      = "APIGatewayFullAccess"
        Effect   = "Allow"
        Action   = ["apigateway:*"]
        Resource = "*"
      },

      # BUDGETS: Just give full access (Low security risk)
      {
        Sid      = "BudgetsFullAccess"
        Effect   = "Allow"
        Action   = ["budgets:*"]
        Resource = "*"
      },

      # DYNAMODB: Allow table creation for History/State
      {
        Sid      = "DynamoDBFullAccess"
        Effect   = "Allow"
        Action   = ["dynamodb:*"]
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