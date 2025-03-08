# AWS EC2 Inference Solution - Operational Guide

## Overview

This operational guide provides detailed instructions for deploying, maintaining, and troubleshooting the AWS EC2 Inference Solution. The solution is designed to be fully automated through Terraform, requiring minimal manual intervention during normal operation.

## Prerequisites

Before deploying the solution, ensure you have:

- AWS CLI installed and configured with appropriate credentials
- Terraform 1.7.0 or newer installed
- Docker installed (for local testing or development)
- Git installed (for version control)
- An existing Route53 hosted zone (if DNS functionality is required)

## Initial Deployment

### Step 1: Create S3 Bucket for Terraform State

```bash
# Create the S3 bucket in the specified region
aws s3api create-bucket \
    --bucket ob-lq-live-inference-solution-terraform-state-us-west-2 \
    --region us-west-2 \
    --create-bucket-configuration LocationConstraint=us-west-2

# Enable versioning for state file recovery
aws s3api put-bucket-versioning \
    --bucket ob-lq-live-inference-solution-terraform-state-us-west-2 \
    --versioning-configuration Status=Enabled

# Enable server-side encryption
aws s3api put-bucket-encryption \
    --bucket ob-lq-live-inference-solution-terraform-state-us-west-2 \
    --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
```

### Step 2: Store HuggingFace Token in SSM Parameter Store

The vLLM service requires a HuggingFace token to access models.

Validate your token locally:

```bash
export HF_TOKEN=<your_actual_token>
curl https://huggingface.co/api/whoami-v2 -H "Authorization: Bearer ${HF_TOKEN}"
```

Store your token securely in SSM Parameter Store:

```bash
export HF_TOKEN=<your_actual_token>
aws ssm put-parameter \
    --name "/inference/hf_token" \
    --value "${HF_TOKEN}" \
    --type SecureString \
    --region us-west-2
```

If you need to update the token later:

```bash
export HF_TOKEN=<your_new_token>
aws ssm put-parameter \
    --name "/inference/hf_token" \
    --value "${HF_TOKEN}" \
    --type SecureString \
    --region us-west-2 \
    --overwrite
```



### Step 3: Clone the Repository

```bash
git clone <repository-url>
cd inference-solution
```

### Step 3: Configure Variables

Edit `terraform.tfvars` to customize the deployment:

```hcl
# AWS Configuration
region = "us-west-2"

# Environment name
environment = "production"

# Domain Configuration
domain_name = "your-domain.com"
create_route53_records = true

# Admin settings
allowed_admin_ips = ["your-ip/32"]
email_address = "admin@your-domain.com"

# EC2 instance settings
instance_type = "t3.small"
key_name = "your-ssh-key"  # Set to null if not needed
app_port = 8080
```

### Step 4: Deploy the Solution

```bash
# Initialize Terraform
terraform init

# Validate the configuration
terraform validate

# Preview changes
terraform plan

# Apply changes
terraform apply
```

### Step 5: Verify Deployment

After deployment completes, Terraform will display various outputs, including:

- API endpoint URL
- SSH connection string
- ECR repository URL
- DNS records (if enabled)

Verify that the application is running by accessing the API endpoint URL.

## Routine Operations

### Updating the Application

To deploy a new version of the application:

1. Make changes to the application code in the `app/` directory
2. Run `terraform apply` to trigger a rebuild and redeploy
3. The EC2 instance will automatically pull the new image

### Connecting to the EC2 Instance

Use AWS Systems Manager Session Manager for secure shell access:

```bash
aws ssm start-session --target <instance-id>
```

Where `<instance-id>` is the value from `terraform output instance_id`.

Alternatively, if you configured an SSH key:

```bash
ssh ubuntu@<instance-public-ip>
```

Where `<instance-public-ip>` is the value from `terraform output instance_public_ip`.

### Viewing Application Logs

To view application logs on the EC2 instance:

```bash
# View Docker container logs
docker logs inference-app

# View systemd service logs
journalctl -u inference-app.service
```

### Manually Updating the Container

If you need to manually trigger a container update:

```bash
sudo /usr/local/bin/update-inference-app.sh
```

## Scaling and Modifications

### Changing Instance Type

To change the EC2 instance type:

1. Update the `instance_type` variable in `terraform.tfvars`
2. Run `terraform apply`

This will replace the EC2 instance while maintaining all configuration.

### Adding Custom Domain Names

To add additional domain names:

1. Modify the Route53 module in `modules/route53/main.tf`
2. Add new record resources for each domain
3. Run `terraform apply`

## Monitoring and Health Checks

### Health Check Endpoint

The application provides a health check endpoint at `/health`. Use this to verify the API is functioning correctly:

```bash
curl http://<instance-public-ip>:8080/health
```

A successful response will be:

```json
{"status":"ok"}
```

### CloudWatch Metrics

The solution collects standard EC2 metrics in CloudWatch. Key metrics to monitor:

- CPU Utilization
- Memory Utilization
- Disk Space
- Network Traffic

## Troubleshooting

### Testing the API

Examples of testing the API with cURL:

Health check:
```bash
curl http://<instance-public-ip>:8080/health
```

Root endpoint:
```bash
curl http://<instance-public-ip>:8080/
```

List available models:
```bash
curl http://<instance-public-ip>:8080/v1/models
```

Chat completions (OpenAI-compatible API):
```bash
curl -X POST \
  http://<instance-public-ip>:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "solidrust/Hermes-3-Llama-3.1-8B-AWQ",
    "messages": [
      {"role": "user", "content": "Explain what AWS EC2 is in one paragraph."}
    ],
    "max_tokens": 100
  }'
```

Legacy inference endpoint:
```bash
curl -X POST \
  http://<instance-public-ip>:8080/api/infer \
  -H 'Content-Type: application/json' \
  -d '{"data": "Explain what AWS EC2 is in one paragraph."}'
```

### Common Issues and Resolutions

#### Docker Image Build Fails

**Symptoms**: `terraform apply` fails during the build step.

**Resolution**:
1. Check the build script output
2. Verify AWS credentials have ECR permissions
3. Run the build script manually to see detailed errors:

```bash
cd modules/build/scripts
bash build_and_push.sh <ecr-repo-url> <aws-region> <app-path>
```

#### EC2 Instance Not Running the Container

**Symptoms**: EC2 instance is running but the API is not accessible.

**Resolution**:
1. Connect to the instance using Session Manager
2. Check service status: `sudo systemctl status inference-app`
3. View service logs: `journalctl -u inference-app`
4. Verify Docker is running: `sudo systemctl status docker`
5. Check container status: `docker ps -a`

#### vLLM Service Not Starting

**Symptoms**: API proxy is running but requests to vLLM endpoints fail with 503 errors.

**Resolution**:
1. Check vLLM service status: `sudo systemctl status vllm`
2. View service logs: `journalctl -u vllm -n 100`
3. Check if NVIDIA drivers are installed (if using GPU): `nvidia-smi`
4. Verify the HuggingFace token is accessible: `sudo /usr/local/bin/get-hf-token.sh`
5. Check if the model is available for download: Browse to the model page on HuggingFace
6. For GPU instances, verify Docker NVIDIA runtime: `docker info | grep -A 10 Runtimes`

#### Out of Memory Errors with vLLM

**Symptoms**: vLLM service crashes or fails to start with out of memory errors.

**Resolution**:
1. Reduce `gpu_memory_utilization` in terraform.tfvars (e.g., from 0.98 to 0.8)
2. Switch to a smaller model or a quantized version
3. For GPU instances, consider using a larger instance type with more GPU memory
4. Check for other processes consuming GPU memory: `nvidia-smi`
5. Restart the vLLM service: `sudo systemctl restart vllm`

#### DNS Records Not Resolving

**Symptoms**: The domain name does not resolve to the EC2 instance.

**Resolution**:
1. Verify Route53 records in AWS console
2. Check DNS propagation: `dig infer.<domain-name>`
3. Ensure the correct domain name is specified in `terraform.tfvars`
4. Verify the zone exists in Route53

#### Terraform State Issues

**Symptoms**: Terraform operations fail with state-related errors.

**Resolution**:
1. Verify the S3 bucket exists and is accessible
2. Check that the bucket name in `backend.tf` is correct
3. Ensure AWS credentials have S3 permissions
4. If needed, release state locks in S3

## Backup and Disaster Recovery

### State Backup

The Terraform state is stored in S3 with versioning enabled. To recover a previous state:

1. View state file versions in the S3 console
2. Download the desired version
3. Use `terraform state push` to restore it

### Application Backup

The application code and configuration are version-controlled. To recover:

1. Revert to a previous commit if needed
2. Run `terraform apply` to redeploy

## Security Considerations

### Rotating IAM Credentials

Regularly rotate AWS access keys:

1. Create new access keys in IAM
2. Update AWS CLI configuration
3. Verify functionality
4. Delete old access keys

### Updating Docker Images

Keep base images up to date:

1. Update the `FROM` line in the Dockerfile
2. Run `terraform apply` to rebuild and redeploy

### Patching the EC2 Instance

The EC2 instance uses Ubuntu, which can be updated with:

```bash
sudo apt update
sudo apt upgrade -y
sudo reboot
```

## Complete Removal

To completely remove all resources:

```bash
terraform destroy
```

This will:
1. Terminate the EC2 instance
2. Delete the ECR repository and images
3. Remove DNS records
4. Delete all associated resources

The S3 bucket for Terraform state must be manually deleted if no longer needed.
