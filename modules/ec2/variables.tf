variable "name" {
  description = "Name for the EC2 instance and related resources"
  type        = string
  default     = "inference"
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet to deploy the instance into"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "Type of instance to deploy"
  type        = string
  default     = "t3.small"
}

variable "use_gpu" {
  description = "Whether to use a GPU instance for inference"
  type        = bool
  default     = false
}

variable "gpu_instance_type" {
  description = "EC2 instance type for GPU inference"
  type        = string
  default     = "g4dn.xlarge"
}

variable "key_name" {
  description = "Name of the key pair to use for SSH access"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 30
}

variable "app_port" {
  description = "Port on which the API will run"
  type        = number
  default     = 8080
}

variable "vllm_port" {
  description = "Port on which the vLLM service will run"
  type        = number
  default     = 8000
}

variable "model_id" {
  description = "HuggingFace model ID to use for inference"
  type        = string
  default     = "solidrust/Hermes-3-Llama-3.1-8B-AWQ"
}

variable "max_model_len" {
  description = "Maximum model context length"
  type        = number
  default     = 14992
}

variable "gpu_memory_utilization" {
  description = "GPU memory utilization for vLLM (0.0-1.0)"
  type        = number
  default     = 0.98
}

variable "vllm_image_tag" {
  description = "Docker image tag for vLLM"
  type        = string
  default     = "latest"
}

variable "hf_token_parameter_name" {
  description = "Name of the SSM parameter containing the HuggingFace token"
  type        = string
  default     = "/inference/hf_token"
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "ecr_repository_url" {
  description = "URL of the ECR repository for the app"
  type        = string
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
