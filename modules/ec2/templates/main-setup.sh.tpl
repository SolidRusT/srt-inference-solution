#!/bin/bash

# Main setup script that orchestrates the deployment
# Instance version: ${instance_version}

# Exit on error, enable command echo
set -ex

# Create working directories
mkdir -p /opt/inference/scripts

# Set up environment variables
echo "Setting up environment variables..."
cat > /opt/inference/config.env << EOF
export AWS_REGION="${aws_region}"
export SCRIPTS_BUCKET="${scripts_bucket}"
export USE_GPU="${use_gpu}"
export ENABLE_HTTPS="${enable_https}"
export INSTANCE_VERSION="${instance_version}"
EOF

# Source the environment
source /opt/inference/config.env

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker
    systemctl start docker
fi

# Download utility scripts from S3
echo "Downloading setup scripts from S3..."
aws s3 cp s3://$SCRIPTS_BUCKET/scripts/utility-scripts.sh /opt/inference/scripts/
aws s3 cp s3://$SCRIPTS_BUCKET/scripts/services-setup.sh /opt/inference/scripts/

# Download conditional scripts
if [ "$USE_GPU" = "true" ]; then
  aws s3 cp s3://$SCRIPTS_BUCKET/scripts/gpu-setup.sh /opt/inference/scripts/
fi

if [ "$ENABLE_HTTPS" = "true" ]; then
  aws s3 cp s3://$SCRIPTS_BUCKET/scripts/nginx-setup.sh /opt/inference/scripts/
fi

# Make scripts executable
chmod +x /opt/inference/scripts/*.sh

# Execute the scripts in order
echo "Running utility scripts..."
/opt/inference/scripts/utility-scripts.sh

if [ "$USE_GPU" = "true" ]; then
  echo "Running GPU setup..."
  /opt/inference/scripts/gpu-setup.sh
fi

echo "Setting up services..."
/opt/inference/scripts/services-setup.sh

if [ "$ENABLE_HTTPS" = "true" ]; then
  echo "Setting up NGINX and HTTPS..."
  /opt/inference/scripts/nginx-setup.sh
fi

# Run the Docker login script
echo "Logging into ECR..."
/usr/local/bin/docker-login-ecr.sh || echo "Docker login failed but continuing..."

# Pull the images before service startup
echo "Pulling Docker images..."
docker pull vllm/vllm-openai:latest || echo "Failed to pull vLLM image but continuing..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query 'Account' --output text).dkr.ecr.$AWS_REGION.amazonaws.com
docker pull $(aws sts get-caller-identity --query 'Account' --output text).dkr.ecr.$AWS_REGION.amazonaws.com/inference-app-production:latest || echo "Failed to pull inference app image but continuing..."

# Create a cron job to check for updates every hour
echo "0 * * * * /usr/local/bin/update-inference-app.sh" | crontab -

# Enable and start the services with more robust error handling
echo "===== Starting services ====="
systemctl daemon-reload

# Enable and start vLLM with detailed error reporting
echo "Enabling vLLM service..."
systemctl enable vllm
echo "Starting vLLM service..."
if ! systemctl start vllm; then
  echo "Failed to start vLLM service, checking logs:"
  journalctl -u vllm --no-pager -n 50
  echo "Will try to continue with inference app service..."
fi

# Enable and start inference app with detailed error reporting
echo "Enabling inference-app service..."
systemctl enable inference-app
echo "Starting inference-app service..."
if ! systemctl start inference-app; then
  echo "Failed to start inference-app service, checking logs:"
  journalctl -u inference-app --no-pager -n 50
  echo "Will try to continue with monitoring setup..."
fi

# Run vLLM test script to check status
echo "===== Running vLLM test script ====="
/usr/local/bin/test-vllm.sh

# Install CloudWatch agent for monitoring
echo "===== Installing monitoring agents ====="
curl -O https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Install SSM agent for management
mkdir -p /tmp/ssm
cd /tmp/ssm
wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
dpkg -i amazon-ssm-agent.deb
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Create a service status script for easy checking
cat > /usr/local/bin/check-services.sh << 'EOCS'
#!/bin/bash
echo "=== Service Status ==="
echo "vLLM service: $(systemctl is-active vllm) ($(systemctl is-enabled vllm))"
echo "Inference app: $(systemctl is-active inference-app) ($(systemctl is-enabled inference-app))"
echo "Docker status: $(systemctl is-active docker) ($(systemctl is-enabled docker))"
echo "=== Docker Containers ==="
docker ps -a
echo "=== NVIDIA Status ==="
nvidia-smi || echo "NVIDIA drivers not available"
echo "=== Service Logs ==="
echo "--- Last 10 lines of vLLM logs ---"
journalctl -u vllm --no-pager -n 10
echo "--- Last 10 lines of inference-app logs ---"
journalctl -u inference-app --no-pager -n 10
EOCS
chmod +x /usr/local/bin/check-services.sh

# Reboot after NVIDIA driver installation if GPU is enabled
if [ "$USE_GPU" = "true" ]; then
  echo "===== Scheduling reboot to complete GPU setup ====="
  # Create a startup script to handle post-reboot tasks
  mkdir -p /var/lib/cloud/scripts/per-boot
  cat > /var/lib/cloud/scripts/per-boot/post-reboot-setup.sh << 'EOB'
#!/bin/bash
# Check if NVIDIA drivers are loaded
if ! nvidia-smi > /dev/null 2>&1; then
  echo "NVIDIA drivers not loaded after reboot, trying to reload"
fi

# Make sure services are running
echo "Making sure services are running after reboot..."
systemctl restart vllm
systemctl restart inference-app

# Run the test script to verify everything
echo "Running post-reboot vLLM test..."
/usr/local/bin/test-vllm.sh > /var/log/post-reboot-vllm-test.log 2>&1
EOB
  chmod +x /var/lib/cloud/scripts/per-boot/post-reboot-setup.sh

  # Schedule a reboot in 1 minute to give cloud-init time to finish
  echo "Scheduling reboot in 1 minute..."
  shutdown -r +1 "Rebooting to complete NVIDIA driver installation"
fi

echo "===== Setup completed at $(date) ====="