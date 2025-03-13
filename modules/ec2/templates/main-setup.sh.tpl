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

# Create a cron job to check for updates every hour and monitor vLLM if GPU is enabled
if [ "$USE_GPU" = "true" ]; then
  cat > /etc/cron.d/inference-maintenance << 'EOCRON'
# Update inference app image hourly
0 * * * * root /usr/local/bin/update-inference-app.sh > /dev/null 2>&1

# Check vLLM health every 5 minutes and restart if needed
*/5 * * * * root /usr/local/bin/monitor-vllm.sh > /tmp/vllm-status.json 2>&1 && if grep -q '"api_status": "unavailable"' /tmp/vllm-status.json; then /usr/local/bin/restart-vllm.sh; fi
EOCRON
else
  cat > /etc/cron.d/inference-maintenance << 'EOCRON'
# Update inference app image hourly
0 * * * * root /usr/local/bin/update-inference-app.sh > /dev/null 2>&1
EOCRON
fi

# Set proper permissions
chmod 0644 /etc/cron.d/inference-maintenance

# Enable and start the services with more robust error handling
echo "===== Starting services ====="
systemctl daemon-reload

# Enable services (but don't start yet)
echo "Enabling vLLM service..."
systemctl enable vllm
echo "Enabling inference-app service..."
systemctl enable inference-app

# Start inference app independently
echo "Starting inference-app service..."
if ! systemctl start inference-app; then
  echo "Failed to start inference-app service, checking logs:"
  journalctl -u inference-app --no-pager -n 50
  docker logs inference-app || echo "No inference-app container logs available"
  echo "Will try again after a short wait..."
  sleep 10
  systemctl restart inference-app || echo "Second attempt to start inference-app failed"
fi

# Start vLLM service only if using GPU
if [ "$USE_GPU" = "true" ]; then
  echo "Starting vLLM service..."
  if ! systemctl start vllm; then
    echo "Failed to start vLLM service, checking logs:"
    journalctl -u vllm --no-pager -n 50
    echo "Will try again after a short wait..."
    sleep 10
    systemctl restart vllm || echo "Second attempt to start vLLM failed"
  fi
else
  echo "GPU is disabled, not starting vLLM service"
  # Disable the vLLM service to prevent auto-start attempts
  systemctl disable vllm
  echo "vLLM service disabled - it will not be available in non-GPU mode"
fi

# Run vLLM test script to check status only if GPU is enabled
if [ "$USE_GPU" = "true" ]; then
  echo "===== Running vLLM test script ====="
  /usr/local/bin/test-vllm.sh
else
  echo "===== Skipping vLLM test - GPU disabled ====="
  echo "vLLM will not be available in non-GPU mode"
fi

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

# Source the configuration if available
GPU_ENABLED=false
if [ -f /opt/inference/config.env ]; then
  source /opt/inference/config.env
  if [ "$USE_GPU" = "true" ]; then
    GPU_ENABLED=true
  fi
fi

echo "=== Service Status Check at $(date) ==="

echo "\n=== System Information ==="
uptime
free -m
df -h /

echo "\n=== Service Status ==="
echo "Inference app: $(systemctl is-active inference-app) ($(systemctl is-enabled inference-app))"
echo "Docker status: $(systemctl is-active docker) ($(systemctl is-enabled docker))"

if [ "$GPU_ENABLED" = "true" ]; then
  echo "vLLM service: $(systemctl is-active vllm) ($(systemctl is-enabled vllm))"
  echo "\n=== NVIDIA Status ==="
  nvidia-smi || echo "NVIDIA drivers not available or not loaded"
else
  echo "vLLM service: disabled (GPU support not enabled)"
  echo "\n=== NVIDIA Status ==="
  echo "GPU support not enabled"
fi

echo "\n=== Network Status ==="
netstat -tulpn | grep -E "(8080|8000|443)" || echo "No services listening on API ports"

echo "\n=== API Status ==="
echo "Inference API Health Check:"
curl -s http://localhost:8080/health || echo "Inference API not responding"

if [ "$GPU_ENABLED" = "true" ]; then
  echo "\nvLLM Health Check:"
  curl -s http://localhost:8000/health || echo "vLLM API not responding"
fi

echo "\n=== Container Logs ==="
echo "--- Last 15 lines of inference-app container logs ---"
docker logs inference-app --tail 15 2>&1 || echo "No inference-app container logs available"

if [ "$GPU_ENABLED" = "true" ]; then
  echo "\n--- Last 15 lines of vLLM container logs ---"
  docker logs vllm-service --tail 15 2>&1 || echo "No vLLM container logs available"
fi

echo "\n=== Service Logs ==="
echo "--- Last 15 lines of inference-app service logs ---"
journalctl -u inference-app --no-pager -n 15

if [ "$GPU_ENABLED" = "true" ]; then
  echo "\n--- Last 15 lines of vLLM service logs ---"
  journalctl -u vllm --no-pager -n 15
fi

echo "\n=== Startup Scripts ==="
ls -la /var/lib/cloud/scripts/per-boot/

echo "\n=== Recent Boot Log ==="
tail -n 20 /var/log/post-reboot-setup.log 2>/dev/null || echo "No post-reboot log available"

echo "\n=== Service Status Check Completed ==="
EOCS
chmod +x /usr/local/bin/check-services.sh

# Reboot after NVIDIA driver installation if GPU is enabled
if [ "$USE_GPU" = "true" ]; then
  echo "===== Scheduling reboot to complete GPU setup ====="
  # Create a startup script to handle post-reboot tasks
mkdir -p /var/lib/cloud/scripts/per-boot
cat > /var/lib/cloud/scripts/per-boot/post-reboot-setup.sh << 'EOB'
#!/bin/bash

# Log outputs to a file for debugging
exec > >(tee /var/log/post-reboot-setup.log) 2>&1
echo "Running post-reboot setup at $$(date)"

# Check if NVIDIA drivers are loaded
if ! nvidia-smi > /dev/null 2>&1; then
  echo "NVIDIA drivers not loaded after reboot, trying to reload"
  # Add actions to reload NVIDIA if needed
fi

# Stop any potentially running services
systemctl stop inference-app
systemctl stop vllm

# Clean up any old containers
docker rm -f vllm-service inference-app || echo "No containers to remove"

# Wait to ensure everything is stopped
sleep 5

# Start API first for immediate availability
echo "Starting inference-app service after reboot..."
systemctl start inference-app

# Start vLLM only if GPU is enabled
if [ -f /opt/inference/config.env ]; then
  source /opt/inference/config.env
  if [ "$USE_GPU" = "true" ]; then
    echo "Starting vLLM service after reboot..."
    systemctl start vllm
    
    # Wait a bit more
    sleep 10
    
    # Run the test script to verify everything
    echo "Running post-reboot vLLM test..."
    /usr/local/bin/test-vllm.sh > /var/log/post-reboot-vllm-test.log 2>&1
  else
    echo "GPU is disabled, not starting vLLM service after reboot"
    # Ensure vLLM is disabled
    systemctl disable vllm
  fi
else
  echo "Config file not found, falling back to no vLLM"
  systemctl disable vllm
fi

# Check final status
echo "Final service status after reboot:"
systemctl status vllm --no-pager
systemctl status inference-app --no-pager
docker ps

echo "Post-reboot setup completed at $$(date)"
EOB
chmod +x /var/lib/cloud/scripts/per-boot/post-reboot-setup.sh

  # Schedule a reboot in 1 minute to give cloud-init time to finish
  echo "Scheduling reboot in 1 minute..."
  shutdown -r +1 "Rebooting to complete NVIDIA driver installation"
fi

echo "===== Setup completed at $(date) ====="