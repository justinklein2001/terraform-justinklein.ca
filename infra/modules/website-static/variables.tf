variable "site_domain" {
  description = "The full domain used for this site, e.g., get-smart.justinklein.ca"
  type        = string
}

variable "zone_id" {
  description = "The Hosted Zone ID where DNS records will be created"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ARN of the existing ACM certificate in us-east-1"
  type        = string
}

variable "create_dns_record" {
  description = "Whether to create an A/AAAA record"
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "The GitHub repo allowed to deploy (e.g., justinklein/get-smart)"
  type        = string
}

variable "github_oidc_arn" {
  description = "ARN of the GitHub OIDC Provider"
  type        = string
}

variable "kb_bucket_arn" {
  description = "Optional: ARN of the S3 Bucket used for Vector Knowledge Base"
  type        = string
  default     = "" # Defaults to empty if not provided (like for your root site)
}