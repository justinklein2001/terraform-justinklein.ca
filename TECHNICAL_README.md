# Terraform Infrastructure Technical Overview
**Author: Justin Klein**  
**Last Updated: December 12th, 2025**

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
TFC_AWS_RUN_ROLE_ARN = arn:aws:iam::{ACCOUNT}:role/{ROLE}  
```

### GitHub Actions Considerations
The repository's **secrets** need to have a **Terraform Cloud API Key** since all workspaces are **CLI-Driven**. This key must be **manually rotated** periodically to ensure best security practices.

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
The **assumed** role is tied to this provider.

Provider: **app.terraform.io** 

Audience: **aws.workload.identity**



## 2. IAM Roles 
Each **deployable** site has its own Terraform role.

### Assumed Role

This role is only assumed when Terraform Cloud performs a `plan/apply` for the **each** workspace.

#### Trust Policy
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::{ACCOUNT}:oidc-provider/app.terraform.io"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "app.terraform.io:aud": "aws.workload.identity"
                },
                "StringLike": {
                    "app.terraform.io:sub": [
                        "organization:{ORG}:project:{PROJECT}:workspace:{WORKSPACE}:run_phase:*"
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
 
### Assumed Role Permissions

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "FullAccessToSiteBucket",
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::{BUCKET_NAME}",
                "arn:aws:s3:::{BUCKET_NAME}/*"
            ]
        },
        {
            "Sid": "S3ListAllBuckets",
            "Effect": "Allow",
            "Action": [
                "s3:ListAllMyBuckets",
                "s3:GetBucketLocation"
            ],
            "Resource": "*"
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
                "cloudfront:CreateInvalidation",
                "cloudfront:CreateOriginAccessControl",
                "cloudfront:UpdateOriginAccessControl",
                "cloudfront:GetOriginAccessControl",
                "cloudfront:ListOriginAccessControls"
            ],
            "Resource": "*"
        },
        {
            "Sid": "Route53LimitedAccess",
            "Effect": "Allow",
            "Action": "route53:*",
            "Resource": [
                "arn:aws:route53:::hostedzone/{ZONE_ID}"
            ]
        },
        {
            "Sid": "Route53Reads",
            "Effect": "Allow",
            "Action": [
                "route53:ListHostedZones",
                "route53:ListHostedZonesByName",
                "route53:GetHostedZone",
                "route53:ListResourceRecordSets",
                "route53:ListTagsForResource",
                "route53:ListTagsForResources",
                "route53:ListHealthChecks",
                "route53:GetHealthCheck",
                "route53:GetHealthCheckStatus",
                "route53:ListTrafficPolicies",
                "route53:GetTrafficPolicy",
                "route53:GetTrafficPolicyInstance",
                "route53:ListTrafficPolicyInstances",
                "route53:ListQueryLoggingConfigs",
                "route53:GetQueryLoggingConfig",
                "route53:GetChange"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ACMFullAccess",
            "Effect": "Allow",
            "Action": "acm:*",
            "Resource": "*"
        }
    ]
}
```

# Sources

[Terraform Cloud → AWS OIDC documentation](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/aws-configuration#configure-hcp-terraform
)  

