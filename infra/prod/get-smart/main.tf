provider "aws" {
  region = "us-east-1"
}

module "smart" {
  source      = "../../modules/website-static"
  site_domain = "get-smart.justinklein.ca"
  root_domain = "justinklein.ca"
  acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abcd1234-ab12-cd34-ef56-abcdef123456"
}
