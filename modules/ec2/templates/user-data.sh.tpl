#!/bin/bash
set -e

# Update and install required packages
apt-get update
apt-get upgrade -y
apt-get install -y apt-transport-https ca-certificates curl software-properties-common awscli jq

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Create the Docker login script
cat > /usr/local/bin/docker-login-ecr.sh << 'EOF'
#!/bin/bash
set -e

# Get the ECR login token and use it to authenticate Docker
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query 'Account' --output text).dkr.ecr.${aws_region}.amazonaws.com
EOF
chmod +x /usr/local/bin/docker-login-ecr.sh

# Create a service file for the inference app
cat > /etc/systemd/system/inference-app.service << 'EOT'
[Unit]
Description=Inference API Application
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop inference-app
ExecStartPre=-/usr/bin/docker rm inference-app
ExecStartPre=/usr/local/bin/docker-login-ecr.sh
ExecStartPre=/usr/bin/docker pull ${ecr_repository_url}:latest
ExecStart=/usr/bin/docker run --rm --name inference-app -p ${app_port}:${app_port} -e PORT=${app_port} -e AWS_REGION=${aws_region} ${ecr_repository_url}:latest

[Install]
WantedBy=multi-user.target
EOT

# Create a script to pull and run the latest image
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

# Enable and start the service
systemctl daemon-reload
systemctl enable inference-app
systemctl start inference-app

# Simple health check endpoint
cat > /usr/local/bin/health-check.sh << 'EOL'
#!/bin/bash
curl -s http://localhost:${app_port}/health || exit 1
EOL
chmod +x /usr/local/bin/health-check.sh

# Install CloudWatch agent for monitoring (optional)
curl -O https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

echo "Instance setup complete!"
