# Terraform Infrastructure Technical Overview
**Author: Justin Klein**  
**Last Updated: December 10th, 2025**

This repository contains a monolithic Terraform setup for deploying multiple static sites using **S3 + CloudFront**. All **state** is stored in **Terraform Cloud** and **AWS** access uses **dynamic provider credentials (OIDC)**, avoiding long-lived IAM keys completely.

Each subfolder under `infra/prod/` represents a **deployable** environment/site.

# Terraform Cloud Configuration
Each deployable site has its **own** **workspace** and **AWS Assumed Role**.

**Organization:** justinklein  

**Workspaces:**
1.  [prod-get-smart](https://app.terraform.io/app/justinklein/workspaces/prod-get-smart)


### Required Environment Variables (set in each workspace):

```bash
TFC_AWS_PROVIDER_AUTH = true  
TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::{ACCOUNT_ID_HERE}:role/{APP_NAME_HERE}-TerraformCloudRole  
```

# Dynamic AWS Credentials (OIDC)

This repo uses Terraform Cloud → AWS OIDC federation.  
No long-lived AWS access keys exist.

### How it Works

1. A Terraform run starts.  
2. Terraform Cloud generates an OIDC workload identity token.  
3. AWS verifies the token using the Terraform Cloud OIDC provider.  
4. AWS issues temporary credentials for the run.  
5. Terraform uses those credentials to apply infrastructure.  
6. Credentials expire after the run.


# AWS Configuration

## 1. OIDC Provider (`app.terraform.io`)
All **Assumed** roles are tied to this provider.

Provider: **app.terraform.io** 

Audience: **aws.workload.identity**



## 2. IAM Roles 
Each **deployable** site has its own Terraform role.

### 2a. GetSmartApp-TerraformCloudRole

This role is only assumed when Terraform Cloud performs an `apply` for the `prod-get-smart` workspace.

#### Trust Policy
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::966433002166:oidc-provider/app.terraform.io"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "app.terraform.io:aud": "aws.workload.identity"
                },
                "StringLike": {
                    "app.terraform.io:sub": [
                        "organization:justinklein:project:Study-Project:workspace:prod-get-smart:run_phase:*"
                    ]
                }
            }
        }
    ]
}
```


## 3. IAM Policy

These policies grant Terraform Cloud just enough permissions to manage:

- S3 bucket for static site  
- CloudFront distribution  
- ACM certificate lookup  
- Route53 DNS records  
- CloudWatch logs (CloudFront)
 
### 3a. GetSmartApp-TerraformCloudPermissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3ManagementForStaticSites",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:PutBucketPolicy",
        "s3:PutEncryptionConfiguration",
        "s3:GetBucketPolicy",
        "s3:DeleteBucket",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::*"
    },
    {
      "Sid": "CloudFrontManagement",
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateDistribution",
        "cloudfront:UpdateDistribution",
        "cloudfront:GetDistribution",
        "cloudfront:DeleteDistribution",
        "cloudfront:TagResource",
        "cloudfront:CreateInvalidation"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Route53Management",
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:GetHostedZone",
        "route53:ListHostedZonesByName"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ACMReadOnly",
      "Effect": "Allow",
      "Action": [
        "acm:ListCertificates",
        "acm:DescribeCertificate"
      ],
      "Resource": "*"
    }
  ]
}
```

# Sources

[Terraform Cloud → AWS OIDC documentation](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/aws-configuration#configure-hcp-terraform
)  

