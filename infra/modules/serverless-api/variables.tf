variable "app_name" {
  description = "Unique name for the app (e.g. quiz-backend)"
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to the folder containing the lambda index.mjs"
  type        = string
}

variable "cors_domain" {
  description = "The frontend domain allowed to call this API"
  type        = string
}

variable "kb_bucket_arn" {
  description = "ARN of the Knowledge Base bucket (for IAM permissions)"
  type        = string
}

variable "kb_bucket_id" {
  description = "ID of the Knowledge Base bucket (for Env Vars)"
  type        = string
}

variable "github_repo" {
  description = "The GitHub repo allowed to deploy this function (e.g., 'justinklein2001/monorepo')"
  type        = string
}

variable "github_oidc_arn" {
  description = "The ARN of the GitHub OIDC Provider (passed from root)"
  type        = string
}