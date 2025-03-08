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

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform 1.7.0 or later
- Docker (for local testing, optional)
- An existing Route53 hosted zone (if DNS records are needed)

## Deployment

### Quick Start

1. Clone this repository
2. Update `terraform.tfvars` with your desired configuration
3. Deploy with Terraform:

```bash
terraform init
terraform apply
```

4. Access your API using the outputs provided by Terraform

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

- Check CloudWatch logs for application issues
- SSH to the instance using the provided connection string
- Use the AWS SSM Session Manager for secure console access

## License

See the LICENSE file for details.
