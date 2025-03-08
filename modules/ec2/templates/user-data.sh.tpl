#!/bin/bash
set -e

# Update and install required packages
apt-get update
apt-get upgrade -y
apt-get install -y apt-transport-https ca-certificates curl software-properties-common awscli jq unzip

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Install NVIDIA drivers and Docker runtime if using GPU
if [ "${use_gpu}" = "true" ]; then
  echo "Setting up GPU environment..."
  
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

# Create the Docker login script
cat > /usr/local/bin/docker-login-ecr.sh << 'EOF'
#!/bin/bash
set -e

# Get the ECR login token and use it to authenticate Docker
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query 'Account' --output text).dkr.ecr.${aws_region}.amazonaws.com
EOF
chmod +x /usr/local/bin/docker-login-ecr.sh

# Create script to get HF token from SSM Parameter Store
cat > /usr/local/bin/get-hf-token.sh << 'EOF'
#!/bin/bash
set -e

# Get the HuggingFace token from SSM Parameter Store
HF_TOKEN=$(aws ssm get-parameter --name ${hf_token_parameter_name} --with-decryption --region ${aws_region} --query "Parameter.Value" --output text)
echo $HF_TOKEN
EOF
chmod +x /usr/local/bin/get-hf-token.sh

# Create a systemd service file for our API proxy
cat > /etc/systemd/system/inference-app.service << 'EOT'
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
ExecStart=/usr/bin/docker run --rm --name inference-app \
    -p ${app_port}:${app_port} \
    -e PORT=${app_port} \
    -e VLLM_PORT=${vllm_port} \
    -e VLLM_HOST=localhost \
    -e MODEL_ID="${model_id}" \
    -e AWS_REGION=${aws_region} \
    --network=host \
    ${ecr_repository_url}:latest

[Install]
WantedBy=multi-user.target
EOT

# Create a systemd service file for vLLM
cat > /etc/systemd/system/vllm.service << 'EOT'
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
ExecStart=/bin/bash -c 'HF_TOKEN=$(/usr/local/bin/get-hf-token.sh) && \
    /usr/bin/docker run --rm --name vllm-service \
    %GPU_FLAG% \
    -v ~/.cache/huggingface:/root/.cache/huggingface \
    --env "VLLM_LOGGING_LEVEL=DEBUG" \
    --env "HUGGING_FACE_HUB_TOKEN=$${HF_TOKEN}" \
    -p ${vllm_port}:8000 \
    --ipc=host \
    --network=host \
    vllm/vllm-openai:${vllm_image_tag} \
    --model ${model_id} \
    --tokenizer ${model_id} \
    --trust-remote-code \
    --dtype auto \
    --device auto \
    --max-model-len ${max_model_len} \
    --gpu-memory-utilization ${gpu_memory_utilization} \
    --tool-call-parser hermes'

[Install]
WantedBy=multi-user.target
EOT

# Update the GPU flag based on whether we're using GPU
if [ "${use_gpu}" = "true" ]; then
  sed -i 's/%GPU_FLAG%/--runtime nvidia --gpus all/g' /etc/systemd/system/vllm.service
else
  sed -i 's/%GPU_FLAG%//g' /etc/systemd/system/vllm.service
fi

# Create a script to pull and run the latest API proxy image
cat > /usr/local/bin/update-inference-app.sh << 'EOL'
#!/bin/bash
set -e

# Login to ECR
/usr/local/bin/docker-login-ecr.sh

# Pull the latest image
docker pull ${ecr_repository_url}:latest

# Restart the service to use the new image
systemctl restart inference-app
EOL
chmod +x /usr/local/bin/update-inference-app.sh

# Run the Docker login and pull script
/usr/local/bin/docker-login-ecr.sh

# Create a cron job to check for updates every hour
echo "0 * * * * /usr/local/bin/update-inference-app.sh" | crontab -

# Enable and start the services
systemctl daemon-reload
systemctl enable vllm
systemctl start vllm
systemctl enable inference-app
systemctl start inference-app

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

# Install CloudWatch agent for monitoring (optional)
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

echo "Instance setup complete!"
