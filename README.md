# Terraform/AWS Infrastructure Overview
**Author: Justin Klein**  
**Last Updated: December 12th, 2025**

### What's this repo do?
This repo contains a small, **production-ready AWS** infrastructure managed with **Terraform**.
It deploys static websites and backend API using an efficient, low-cost **serverless** stack:

- **S3 + CloudFront** — global CDN for the static site  
- **API Gateway + Lambda** — backend API with minimal operational overhead  
- **Route 53** — DNS for the custom domain  
- **ACM** — automatic SSL certificates  
- **IAM** — secure role-based access for Terraform Cloud

### How does it work?
All infrastructure is provisioned automatically through **Terraform Cloud**, using a dedicated **IAM role** that Terraform assumes during each run. This ensures **consistent**, **repeatable** deployments and **avoids long-lived** **AWS** **credentials**.

The setup is intentionally **lightweight**, **inexpensive**, and **easy to extend** as the project grows.
#### High-Level Diagram:
![Terraform CI/CD Workflow](./assets/terraform-diagram.png)


If you're looking for an **in-depth technical breakdown**, read [this](./TECHNICAL_README.md).
