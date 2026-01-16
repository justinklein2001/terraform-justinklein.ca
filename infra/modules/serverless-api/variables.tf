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