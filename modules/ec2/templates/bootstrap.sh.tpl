#!/bin/bash

# Minimal bootstrap script to download and run the main setup
# Instance version: ${instance_version}
# Generated at: $(date)

# Log everything to a file for debugging
set -e
exec > >(tee /var/log/user-data.log) 2>&1
echo "Starting bootstrap script at $(date)"

# Install minimal dependencies
apt-get update
apt-get install -y awscli curl

# Set up AWS region
export AWS_DEFAULT_REGION="${aws_region}"

# Create directories
mkdir -p /opt/inference
mkdir -p /var/lib/cloud/scripts/per-boot

# Create service check script to run at every boot
cat > /var/lib/cloud/scripts/per-boot/ensure-services.sh << 'EOSVC'
#!/bin/bash
# This script runs at every boot to ensure services are running

LOG_FILE="/var/log/ensure-services.log"
exec > >(tee $LOG_FILE) 2>&1

echo "Running service check at $(date)"

# Check if services are enabled
if ! systemctl is-enabled vllm >/dev/null 2>&1; then
  echo "vLLM service not enabled, enabling..."
  systemctl enable vllm
fi

if ! systemctl is-enabled inference-app >/dev/null 2>&1; then
  echo "Inference app service not enabled, enabling..."
  systemctl enable inference-app
fi

# Check if services are running
if ! systemctl is-active vllm >/dev/null 2>&1; then
  echo "vLLM service not running, starting..."
  systemctl start vllm
fi

if ! systemctl is-active inference-app >/dev/null 2>&1; then
  echo "Inference app service not running, starting..."
  systemctl start inference-app
fi

# Check NVIDIA if GPU is used
if command -v nvidia-smi >/dev/null 2>&1; then
  echo "NVIDIA drivers status:"
  nvidia-smi || echo "NVIDIA drivers not loaded"
fi

echo "Service check completed at $(date)"
EOSVC
chmod +x /var/lib/cloud/scripts/per-boot/ensure-services.sh

# Download the main setup script from S3
echo "Downloading main setup script from S3..."
aws s3 cp s3://${scripts_bucket}/${main_setup_key} /opt/inference/main-setup.sh

# Make script executable
chmod +x /opt/inference/main-setup.sh

# Execute the main setup script
echo "Executing main setup script..."
/opt/inference/main-setup.sh

# Run the service check immediately after setup
echo "Running service check..."
/var/lib/cloud/scripts/per-boot/ensure-services.sh

echo "Bootstrap completed at $(date)"