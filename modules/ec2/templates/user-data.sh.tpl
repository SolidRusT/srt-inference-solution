#!/bin/bash

# Script generated at ${timestamp}
# Instance version: ${instance_version}

# Log everything to a file for debugging
set -x  # Enable command echo for better debugging
exec > >(tee /var/log/user-data.log) 2>&1
echo "Starting user-data script execution at $(date)"

# Update and install required packages
echo "===== Installing base packages ====="
apt-get update
apt-get upgrade -y
apt-get install -y apt-transport-https ca-certificates curl software-properties-common awscli jq unzip

# Install Docker
echo "===== Installing Docker ====="
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Setup directories and scripts before other operations
mkdir -p /usr/local/bin
mkdir -p /etc/ssl/private
mkdir -p /etc/ssl/certs

# Create the Docker login script
echo "===== Creating utility scripts ====="
cat > /usr/local/bin/docker-login-ecr.sh << 'EOF'
#!/bin/bash

# Get the ECR login token and use it to authenticate Docker
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query 'Account' --output text).dkr.ecr.${aws_region}.amazonaws.com
EOF
chmod +x /usr/local/bin/docker-login-ecr.sh

# Create script to get HF token from SSM Parameter Store
cat > /usr/local/bin/get-hf-token.sh << 'EOF'
#!/bin/bash

# Get the HuggingFace token from SSM Parameter Store
echo "Retrieving HuggingFace token from SSM parameter: ${hf_token_parameter_name}"
HF_TOKEN=$(aws ssm get-parameter --name ${hf_token_parameter_name} --with-decryption --region ${aws_region} --query "Parameter.Value" --output text)
if [ -z "$HF_TOKEN" ]; then
  echo "WARNING: Empty HuggingFace token retrieved! Using fallback value."
  HF_TOKEN="hf_fallback_token_for_testing"
else
  echo "Successfully retrieved HuggingFace token (first 3 chars): $${HF_TOKEN:0:3}..."
fi
echo "$HF_TOKEN"
EOF
chmod +x /usr/local/bin/get-hf-token.sh

# Test the token retrieval script
echo "Testing HuggingFace token retrieval..."
/usr/local/bin/get-hf-token.sh || echo "WARNING: Error retrieving HuggingFace token, but continuing anyway"

# Create script to test vLLM
cat > /usr/local/bin/test-vllm.sh << 'EOL'
#!/bin/bash

echo "==== vLLM Test Script ===="
echo "Checking for HuggingFace token..."
HF_TOKEN=$(/usr/local/bin/get-hf-token.sh)
if [ -z "$HF_TOKEN" ]; then
  echo "ERROR: No HuggingFace token available!"
else
  echo "HuggingFace token found. First few characters: $${HF_TOKEN:0:4}..."
fi

echo "Checking vLLM service status..."
systemctl status vllm

echo "Checking container status..."
docker ps | grep vllm-service

echo "Testing vLLM API..."
curl -s http://localhost:${vllm_port}/health || echo "vLLM API not responding"

echo "Docker logs for vLLM:"
docker logs vllm-service --tail 50

echo "==== End of vLLM Test ===="
EOL
chmod +x /usr/local/bin/test-vllm.sh

# Create a health check script
cat > /usr/local/bin/health-check.sh << 'EOL'
#!/bin/bash
# Check if both services are running
vllm_status=$(systemctl is-active vllm)
api_status=$(systemctl is-active inference-app)

if [ "$vllm_status" = "active" ] && [ "$api_status" = "active" ]; then
  # Now check if the API is responding
  curl -s http://localhost:${app_port}/health || exit 1
  exit 0
else
  echo "Services not running: vLLM=$vllm_status, API=$api_status"
  exit 1
fi
EOL
chmod +x /usr/local/bin/health-check.sh

# Create update script
cat > /usr/local/bin/update-inference-app.sh << 'EOL'
#!/bin/bash

# Login to ECR
/usr/local/bin/docker-login-ecr.sh

# Pull the latest image
docker pull ${ecr_repository_url}:latest

# Restart the service to use the new image
systemctl restart inference-app
EOL
chmod +x /usr/local/bin/update-inference-app.sh

# Install NVIDIA drivers and Docker runtime if using GPU
if [ "${use_gpu}" = "true" ]; then
  echo "===== Setting up GPU environment ====="
  
  # Install NVIDIA drivers (newer version)
  apt-get install -y linux-headers-$(uname -r)
  apt-get install -y software-properties-common
  add-apt-repository -y ppa:graphics-drivers/ppa
  apt-get update
  apt-get install -y nvidia-driver-525 # Using a specific version for stability
  
  # Add NVIDIA repository for Docker runtime
  distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
  curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
  curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
  apt-get update
  
  # Install NVIDIA Docker runtime
  apt-get install -y nvidia-docker2
  
  # Configure Docker to use NVIDIA runtime
  cat > /etc/docker/daemon.json << 'EOJ'
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOJ
  
  # Restart Docker to apply changes
  systemctl restart docker
  
  # Verify NVIDIA setup
  nvidia-smi || echo "NVIDIA drivers not loaded correctly. Check installation."
fi

# Create service files
echo "===== Creating systemd services ====="

# Create vLLM service
cat > /etc/systemd/system/vllm.service << EOT
[Unit]
Description=vLLM Inference Service
After=docker.service
Requires=docker.service
Before=inference-app.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop vllm-service
ExecStartPre=-/usr/bin/docker rm vllm-service
ExecStartPre=/usr/bin/docker pull vllm/vllm-openai:${vllm_image_tag}
ExecStart=/bin/bash -c 'HF_TOKEN=\$(/usr/local/bin/get-hf-token.sh) && \\
    /usr/bin/docker run --rm --name vllm-service \\
EOT

# Add GPU flag if needed
if [ "${use_gpu}" = "true" ]; then
  echo "    --runtime nvidia --gpus all \\" >> /etc/systemd/system/vllm.service
fi

# Continue the service file
cat >> /etc/systemd/system/vllm.service << EOT
    -v ~/.cache/huggingface:/root/.cache/huggingface \\
    --env "VLLM_LOGGING_LEVEL=DEBUG" \\
    --env "HUGGING_FACE_HUB_TOKEN=$${HF_TOKEN}" \\
    -p ${vllm_port}:8000 \\
    --ipc=host \\
    --network=host \\
    vllm/vllm-openai:${vllm_image_tag} \\
    --model ${model_id} \\
    --tokenizer ${model_id} \\
    --trust-remote-code \\
    --dtype auto \\
    --device auto \\
    --max-model-len ${max_model_len} \\
    --gpu-memory-utilization ${gpu_memory_utilization} \\
    --tool-call-parser hermes'

[Install]
WantedBy=multi-user.target
EOT

# Create the API service
cat > /etc/systemd/system/inference-app.service << EOT
[Unit]
Description=Inference API Proxy
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop inference-app
ExecStartPre=-/usr/bin/docker rm inference-app
ExecStartPre=/usr/local/bin/docker-login-ecr.sh
ExecStartPre=/usr/bin/docker pull ${ecr_repository_url}:latest
ExecStart=/usr/bin/docker run --rm --name inference-app \\
    -p ${app_port}:${app_port} \\
EOT

# Add HTTPS port if enabled
if [ "${enable_https}" = "true" ]; then
  echo "    -p 443:443 \\" >> /etc/systemd/system/inference-app.service
fi

# Continue the service file
cat >> /etc/systemd/system/inference-app.service << EOT
    -e PORT=${app_port} \\
    -e VLLM_PORT=${vllm_port} \\
    -e VLLM_HOST=localhost \\
    -e MODEL_ID="${model_id}" \\
    -e USE_HTTPS="${enable_https}" \\
EOT

# Add volume mount if HTTPS is enabled
if [ "${enable_https}" = "true" ]; then
  echo "    -v /etc/ssl:/etc/ssl \\" >> /etc/systemd/system/inference-app.service
fi

# Finish the service file
cat >> /etc/systemd/system/inference-app.service << EOT
    -e AWS_REGION=${aws_region} \\
    --network=host \\
    ${ecr_repository_url}:latest

[Install]
WantedBy=multi-user.target
EOT

# If HTTPS is enabled, set up certificates
if [ "${enable_https}" = "true" ]; then
  echo "===== Setting up TLS certificate ====="
  
  # Install Certbot and dependencies
  apt-get install -y nginx certbot python3-certbot-nginx
  
  # Setup a simple self-signed certificate initially
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/server.key \
    -out /etc/ssl/certs/server.crt \
    -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,DNS:infer.${domain_name}" || true
  
  chmod 600 /etc/ssl/private/server.key
  
  # Create basic NGINX config for Certbot
  cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80;
    server_name infer.${domain_name};
    location / {
        proxy_pass http://localhost:${app_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
  
  # Enable the site
  ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  
  # Restart NGINX
  systemctl restart nginx || true
  
  # Request Let's Encrypt certificate
  # Don't fail the script if this fails, we'll fall back to self-signed
  certbot --nginx -d infer.${domain_name} --non-interactive --agree-tos -m ${admin_email} --redirect || true
  
  # Setup renewal cron job
  echo "0 3 * * * certbot renew --quiet" > /etc/cron.d/certbot-renew
  
  # Use Let's Encrypt certificates for our API if available
  if [ -d "/etc/letsencrypt/live/infer.${domain_name}" ]; then
    ln -sf /etc/letsencrypt/live/infer.${domain_name}/privkey.pem /etc/ssl/private/server.key
    ln -sf /etc/letsencrypt/live/infer.${domain_name}/fullchain.pem /etc/ssl/certs/server.crt
  fi
fi

# Run the Docker login script
/usr/local/bin/docker-login-ecr.sh || true

# Create a cron job to check for updates every hour
echo "0 * * * * /usr/local/bin/update-inference-app.sh" | crontab -

# Enable and start the services
echo "===== Starting services ====="
systemctl daemon-reload
systemctl enable vllm
systemctl start vllm || echo "Failed to start vLLM service, check logs"
systemctl enable inference-app
systemctl start inference-app || echo "Failed to start inference-app service, check logs"

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

# Reboot after NVIDIA driver installation if GPU is enabled
# This ensures drivers are properly loaded
if [ "${use_gpu}" = "true" ]; then
  echo "===== Scheduling reboot to complete GPU setup ====="
  # Create a startup script to handle post-reboot tasks
  cat > /var/lib/cloud/scripts/per-boot/post-reboot-setup.sh << 'EOB'
#!/bin/bash
# Check if NVIDIA drivers are loaded
if ! nvidia-smi > /dev/null 2>&1; then
  echo "NVIDIA drivers not loaded after reboot, trying to reload"
  # Additional recovery steps could be added here
fi

# Make sure services are running
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

echo "===== User-data script completed at $(date) ====="
