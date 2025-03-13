# HTTPS Configuration
enable_https = true
# AWS Configuration
region = "us-west-2"

# Environment name
environment = "production"

# Domain Configuration - IMPORTANT: Change this for your deployment
domain_name            = "live.ca.obenv.net"
create_route53_records = true
# Fixed Route53 zone ID to prevent recreation
route53_zone_id        = "Z01814691UALOFO3WZ9I2"

# Admin settings
allowed_admin_ips = ["24.86.211.228/32"]
email_address     = "admin@live.ca.obenv.net"

# EC2 instance settings
instance_type     = "t3.small"
use_gpu_instance  = true
gpu_instance_type = "g6.xlarge"
key_name          = "ob-live-open-inference-oregon"
app_port          = 8080

# Deployment version - increment to force replacement of EC2 instance
ec2_instance_version = 1

# vLLM Configuration
vllm_port              = 8000
model_id               = "solidrust/Hermes-3-Llama-3.1-8B-AWQ"
max_model_len          = 14992
gpu_memory_utilization = 0.98
vllm_image_tag         = "latest"
hf_token_parameter_name = "/inference/hf_token"
