# AWS Configuration
region = "us-west-2"

# Environment name
environment = "production"

# Domain Configuration - IMPORTANT: Change this for your deployment
domain_name            = "live.ca.obenv.net"
create_route53_records = true

# Admin settings
allowed_admin_ips = ["24.86.211.228/32"]
email_address     = "admin@live.ca.obenv.net"

# EC2 instance settings
instance_type     = "t3.small"
key_name          = null  # Set to your key name if SSH access is needed
app_port          = 8080