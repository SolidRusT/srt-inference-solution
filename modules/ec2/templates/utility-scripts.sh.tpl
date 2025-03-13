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