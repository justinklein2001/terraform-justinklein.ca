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