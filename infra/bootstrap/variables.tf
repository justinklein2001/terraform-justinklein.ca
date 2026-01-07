variable "aws_account_id" {
  description = "The AWS Account ID where the OIDC provider exists. Kept local for privacy."
  type        = string
  sensitive   = true 
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}