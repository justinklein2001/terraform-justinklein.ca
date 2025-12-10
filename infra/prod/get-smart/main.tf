provider "aws" {
  region = "us-east-1"
}

module "smart" {
  source      = "../../modules/website-static"
  site_domain = "get-smart.justinklein.ca"
  root_domain = "justinklein.ca"
}
