variable "site_domain" {
  description = "The subdomain used for this site, e.g., get-smart.justinklein.ca"
  type        = string
}

variable "root_domain" {
  description = "Base domain for cert lookup, e.g., justinklein.ca"
  type        = string
}

variable "create_dns_record" {
  description = "Whether to create an A/AAAA record"
  type        = bool
  default     = true
}

variable "acm_certificate_arn" {
  description = "ARN of manually created ACM certificate in us-east-1"
  type        = string
}
