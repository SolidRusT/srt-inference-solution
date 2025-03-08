data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group for EC2 instance
resource "aws_security_group" "inference_instance" {
  name        = "${var.name}-sg"
  description = "Security group for inference instance"
  vpc_id      = var.vpc_id

  # Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTP"
  }

  # Allow HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTPS"
  }

  # Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "SSH"
  }

  # Allow API port
  ingress {
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "API port"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, { Name = "${var.name}-sg" })
}

# IAM role for EC2 instance
resource "aws_iam_role" "inference_instance" {
  name = "${var.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for ECR access
resource "aws_iam_policy" "ecr_access" {
  name        = "${var.name}-ecr-access"
  description = "Policy for ECR access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# IAM policy for SSM Parameter access (for HF token)
resource "aws_iam_policy" "ssm_parameter_access" {
  name        = "${var.name}-ssm-parameter-access"
  description = "Policy for SSM Parameter access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:ssm:${var.region}:*:parameter${var.hf_token_parameter_name}"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "ecr_access_attach" {
  role       = aws_iam_role.inference_instance.name
  policy_arn = aws_iam_policy.ecr_access.arn
}

# Attach SSM parameter access policy
resource "aws_iam_role_policy_attachment" "ssm_parameter_access_attach" {
  role       = aws_iam_role.inference_instance.name
  policy_arn = aws_iam_policy.ssm_parameter_access.arn
}

# Attach SSM policy for easier management
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.inference_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile
resource "aws_iam_instance_profile" "inference_instance" {
  name = "${var.name}-profile"
  role = aws_iam_role.inference_instance.name
}

# Create user-data content
locals {
  user_data = templatefile("${path.module}/templates/user-data.sh.tpl", {
    app_port                = var.app_port
    vllm_port               = var.vllm_port
    aws_region              = var.region
    ecr_repository_url      = var.ecr_repository_url
    use_gpu                 = var.use_gpu
    model_id                = var.model_id
    max_model_len           = var.max_model_len
    gpu_memory_utilization  = var.gpu_memory_utilization
    vllm_image_tag          = var.vllm_image_tag
    hf_token_parameter_name = var.hf_token_parameter_name
  })
}

# EC2 instance
resource "aws_instance" "inference" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.use_gpu ? var.gpu_instance_type : var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.inference_instance.id]
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.inference_instance.name
  user_data              = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2
  }

  tags = merge(var.tags, { Name = var.name })

  # Connect to session manager instead of direct SSH
  provisioner "local-exec" {
    command = "echo 'Instance ${self.id} has been created. Connect using AWS SSM Session Manager.'"
  }
}

# Elastic IP for the instance
resource "aws_eip" "inference" {
  domain   = "vpc"
  instance = aws_instance.inference.id
  tags     = merge(var.tags, { Name = "${var.name}-eip" })
}
