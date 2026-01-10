# Terraform Infrastructure Technical Overview
## Author: Justin Klein
## Last Updated: January 10th, 2026

This repository utilizes a **Split-State Architecture** to manage AWS infrastructure securely.
- **`infra/bootstrap`**: Manages Identity & Access (IAM). Executed locally by an Admin.
- **`infra/prod`**: Manages Workloads (S3/CloudFront/DNS). Executed by Terraform Cloud via VCS.

---

# Layer 1: The Bootstrap (Identity)
**Directory:** `infra/bootstrap`  
**Execution:** Local CLI (`terraform apply`)  

This layer solves the "secure introduction" problem. It creates the **OIDC Provider** and the **IAM Role** that Terraform Cloud will assume.

### Why split this out?
1.  **Security:** We do not want Terraform Cloud to have permissions to change its own permissions (No Privilege Escalation).
2.  **Safety:** If the TFC workspace is compromised, it cannot delete the IAM Role that governs it.

### Usage
To update the trust policy or IAM permissions:
1.  Export your personal AWS CLI credentials (`aws configure`).
2.  Create a `terraform.tfvars` file (gitignored) with your `aws_account_id`.
3.  Run `terraform apply` locally.
4.  Copy the output `role_arn` to the TFC Workspace Variable `TFC_AWS_RUN_ROLE_ARN`.

---

# Layer 2: The Monolith (Workload)
**Directory:** `infra/prod`  
**Execution:** Terraform Cloud (VCS-Driven)

This is the "Root Module" that manages the active infrastructure. It utilizes a **Dependency Injection** pattern to manage multiple sites efficiently.

### Architecture
Instead of independent workspaces for each site, a single workspace (`prod-main`) manages the entire portfolio.
1.  **Root (`main.tf`):** Lookups the Shared Route53 Zone and Wildcard Certificate **once**.
2.  **Modules:** The Zone ID and Cert ARN are passed into the `website-static` module.
3.  **Result:** Faster plans and no "racing" conditions for DNS validation.

### Adding a New Site
To deploy a new subdomain (e.g., `blog.justinklein.ca`), simply add a module block to `infra/prod/main.tf`:

```hcl
module "site_blog" {
  source              = "../modules/website-static"
  site_domain         = "blog.justinklein.ca"
  zone_id             = data.aws_route53_zone.main.zone_id
  acm_certificate_arn = data.aws_acm_certificate.wildcard.arn
}
```

---

# Security & IAM
**Authentication Method:** OIDC (OpenID Connect)  
**Provider:** `app.terraform.io`  

### Trust Policy (The Guardrail)
The IAM Role trusts **Terraform Cloud** only if the request comes from the `justinklein` organization.

```json
{
  "StringLike": {
    "app.terraform.io:sub": "organization:justinklein:project:*:workspace:*:run_phase:*"
  }
}
```

### Least Privilege Permissions
The workload role does **NOT** have AdministratorAccess. It is scoped strictly to the resources it needs to manage.

1.  **S3:** Full access only to buckets matching `*-justinklein-ca` or `justinlein-ca`.
2.  **CloudFront:** Full management of Distributions and OACs.
3.  **Route53:** Full access only to the specific Zone ID.
4.  **ACM:** **Read-Only**. Terraform can find certificates, but cannot delete or revoke them.

#### Policy Snippet
```json
{
    "Sid": "ManagePortfolioBuckets",
    "Effect": "Allow",
    "Action": "s3:*",
    "Resource": [
        "arn:aws:s3:::*-justinklein-ca",
        "arn:aws:s3:::*-justinklein-ca/*",
        "arn:aws:s3:::justinklein-ca",
        "arn:aws:s3:::justinklein-ca/*"
    ]
}
```

---

# Sources & Reference
* [Terraform Cloud OIDC Configuration](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/aws-configuration)
* [AWS IAM Least Privilege Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)