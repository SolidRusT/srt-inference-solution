# AWS EC2 Inference Solution

This Terraform solution deploys a fully automated inference solution on AWS EC2 with Docker and a "Hello World" API.

## Architecture

The solution includes the following components:

- **VPC**: Secure network environment with public and private subnets
- **EC2 Instance**: Running the latest Ubuntu AMI with Docker pre-installed
- **ECR Repository**: For storing the inference application Docker images
- **Route53 DNS**: Optional DNS record configuration for easy access
- **IAM Roles**: Properly scoped permissions for the EC2 instance
- **Security Groups**: Configured for secure access to the application

## Documentation

Detailed documentation is available in the `docs/` directory:

- [Architecture Document](./docs/ARCHITECTURE.md): System design and components
- [Operations Guide](./docs/OPERATIONS.md): Deployment and maintenance instructions
- [Development Roadmap](./docs/DEVELOPMENT_ROADMAP.md): Current status and future plans
- [API Reference](./docs/API_REFERENCE.md): API endpoints documentation
- [Customization Guide](./docs/CUSTOMIZATION.md): How to customize the solution

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform 1.7.0 or later
- Docker (for local testing, optional)
- An existing Route53 hosted zone (if DNS records are needed)

## Deployment

### Step 1: Create the S3 Bucket for Terraform State

Before initializing Terraform, create an S3 bucket to store the Terraform state:

```bash
aws s3api create-bucket \
    --bucket ob-lq-live-inference-solution-terraform-state-us-west-2 \
    --region us-west-2 \
    --create-bucket-configuration LocationConstraint=us-west-2

# Enable S3 bucket versioning for state recovery
aws s3api put-bucket-versioning \
    --bucket ob-lq-live-inference-solution-terraform-state-us-west-2 \
    --versioning-configuration Status=Enabled

# Enable S3 bucket encryption for security
aws s3api put-bucket-encryption \
    --bucket ob-lq-live-inference-solution-terraform-state-us-west-2 \
    --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
```

### Step 2: Quick Start

1. Clone this repository
2. Update `terraform.tfvars` with your desired configuration
3. Make sure the S3 bucket name in `backend.tf` matches the bucket you created
4. Deploy with Terraform:

```bash
terraform init
terraform apply
```

5. Access your API using the outputs provided by Terraform

### Configuration Options

Edit `terraform.tfvars` to customize:

- AWS region
- Environment name (production, staging, etc.)
- Domain name for DNS records
- Admin IPs allowed to access management endpoints
- Instance type and other EC2 parameters

## Customizing the API

The sample "Hello World" API is located in the `app/` directory. To customize:

1. Modify `app/server.js` with your inference logic
2. Run `terraform apply` to rebuild and redeploy

## Outputs

After deployment, Terraform provides detailed outputs including:

- API endpoint URLs (IP-based and domain-based)
- SSH connection string
- ECR repository URL
- Detailed resource IDs and information

## Maintenance

### Updating the API

1. Modify the application code in the `app/` directory
2. Run `terraform apply` to rebuild and redeploy
3. The EC2 instance will automatically pull the latest image

### Cleaning Up

To remove all resources:

```bash
terraform destroy
```

## Security Considerations

- The EC2 instance uses IMDSv2 for enhanced security
- The security group restricts access to configured IP ranges
- All data volumes are encrypted

## Troubleshooting

For detailed troubleshooting steps, refer to the [Operations Guide](./docs/OPERATIONS.md#troubleshooting).

Common issues:
- Check CloudWatch logs for application issues
- SSH to the instance using the provided connection string
- Use the AWS SSM Session Manager for secure console access
- If you encounter Terraform state issues:
  - Verify the S3 bucket exists and is accessible
  - Check the bucket name in `backend.tf` matches the created bucket
  - Ensure you have proper permissions to read/write to the bucket
  - For state lock issues, you may need to manually release locks in S3 using the AWS console

## Project Status

This project is actively maintained. See the [Development Roadmap](./docs/DEVELOPMENT_ROADMAP.md) for information about current status, planned features, and technical debt.

## License

See the LICENSE file for details.
