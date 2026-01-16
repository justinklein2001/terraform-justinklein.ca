# ------------------------------------------------------------------------------
# 1. AUTHENTICATION (Cognito)
# ------------------------------------------------------------------------------
resource "aws_cognito_user_pool" "pool" {
  name = "${var.app_name}-users"
  
  auto_verified_attributes = ["email"]

  # SECURITY: Prevent strangers from creating accounts
  admin_create_user_config {
    allow_admin_create_user_only = true
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name = "${var.app_name}-client"
  user_pool_id = aws_cognito_user_pool.pool.id
  
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH", 
    "ALLOW_REFRESH_TOKEN_AUTH", 
    "ALLOW_USER_SRP_AUTH"
  ]
}

# ------------------------------------------------------------------------------
# 2. COMPUTE (Lambda)
# ------------------------------------------------------------------------------

# A. Create a "Dummy" Zip (The Placeholder)
data "archive_file" "dummy" {
  type        = "zip"
  output_path = "${path.module}/dummy.zip"
  
  source {
    content  = "exports.handler = async () => ({ statusCode: 200, body: 'Placeholder' });"
    filename = "index.mjs"
  }
}

# B. IAM Role (The Brain's Identity)
resource "aws_iam_role" "lambda_role" {
  name = "${var.app_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# C. IAM Permissions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.app_name}-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "AllowLogging"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid      = "AllowKBRead"
        Action   = ["s3:GetObject", "s3:ListBucket"],
        Effect   = "Allow",
        Resource = [var.kb_bucket_arn, "${var.kb_bucket_arn}/*"]
      },
      {
        Sid      = "AllowBedrockAI"
        Action   = "bedrock:InvokeModel",
        Effect   = "Allow",
        Resource = [
          "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-sonnet-20240620-v1:0",
          "arn:aws:bedrock:us-east-1::foundation-model/amazon.titan-embed-text-v2:0"
        ]
      }
    ]
  })
}

# D. The Function
resource "aws_lambda_function" "fn" {
  function_name    = "${var.app_name}-fn"
  role             = aws_iam_role.lambda_role.arn
  runtime          = "nodejs24.x"
  handler          = "index.handler"
  timeout          = 30
  memory_size      = 512
  
  # INITIAL DEPLOYMENT: Use the dummy zip
  filename         = data.archive_file.dummy.output_path
  source_code_hash = data.archive_file.dummy.output_base64sha256

  environment {
    variables = {
      KB_BUCKET_NAME = var.kb_bucket_id
    }
  }

  # CRITICAL: Ignore future code changes (handled by GitHub Actions)
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
      last_modified
    ]
  }
}

# ------------------------------------------------------------------------------
# 3. API GATEWAY (HTTP API)
# ------------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "api" {
  name          = "${var.app_name}-gateway"
  protocol_type = "HTTP"
  
  cors_configuration {
    allow_origins = [var.cors_domain, "http://localhost:3000"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
  
  default_route_settings {
    throttling_burst_limit = 5
    throttling_rate_limit  = 1
  }
}

resource "aws_apigatewayv2_authorizer" "auth" {
  api_id           = aws_apigatewayv2_api.api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.client.id]
    issuer   = "https://${aws_cognito_user_pool.pool.endpoint}"
  }
}

resource "aws_apigatewayv2_integration" "lambda_int" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.fn.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "route" {
  api_id             = aws_apigatewayv2_api.api.id
  route_key          = "POST /generate"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_int.id}"
  authorizer_id      = aws_apigatewayv2_authorizer.auth.id
  authorization_type = "JWT"
}

resource "aws_lambda_permission" "gw_perm" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# ------------------------------------------------------------------------------
# 4. CI/CD DEPLOYMENT ROLE (For GitHub Actions)
# ------------------------------------------------------------------------------

# A. The Trust Policy (The "Bouncer")
# Allows YOUR specific GitHub repo to assume this role
data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    
    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
    
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "deployer" {
  name               = "${var.app_name}-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

# B. The Permissions (What it can do)
# Strictly limited to updating THIS specific Lambda function
resource "aws_iam_role_policy" "deployer_policy" {
  name = "lambda-update-policy"
  role = aws_iam_role.deployer.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "UpdateLambdaCode",
        Effect   = "Allow",
        Action   = [
          "lambda:UpdateFunctionCode",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration"
        ],
        Resource = aws_lambda_function.fn.arn
      }
    ]
  })
}