# Available Models for Inference Solution

This document lists the models tested and confirmed working with our AWS EC2 Inference Solution. When selecting a model, ensure your EC2 instance has sufficient GPU memory for the model size.

## Recommended Instance Types

| AWS Instance | GPU | VRAM | Suitable For |
|--------------|-----|------|-------------|
| g6.xlarge    | 1x NVIDIA L4 | 24GB | 8B-13B models, quantized models |
| g6.2xlarge   | 1x NVIDIA L4 | 24GB | Same as g6.xlarge but with twice the CPU/RAM |
| g6.4xlarge   | 1x NVIDIA L4 | 24GB | Same as g6.2xlarge but with twice the CPU/RAM and faster network |
| g6.12xlarge  | 4x NVIDIA L4 | 96GB (4x24GB) | 32B+ models, long context models |
| g6.48xlarge  | 8x NVIDIA L4 | 192GB (8x24GB) | Multiple large models, highest throughput |

## Supported Models

### Hermes 3 Llama (8B AWQ)
**Model ID:** `solidrust/Hermes-3-Llama-3.1-8B-AWQ`
- **GPU Requirements:** 12GB VRAM minimum
- **Recommended Instance:** g6.xlarge
- **Context Length:** 14,992 tokens
- **Quantization:** AWQ (Activation-aware Weight Quantization)
- **Description:** Optimized custom model based on Llama 3.1 with AWQ quantization for efficient inference
- **Use Cases:** General purpose assistant, content generation, summarization
- **Performance Notes:** Excellent performance-to-resource ratio due to quantization

### Llama 3.1 Instruct (8B)
**Model ID:** `meta-llama/Llama-3.1-8B-Instruct`
- **GPU Requirements:** 24GB VRAM
- **Recommended Instance:** g6.xlarge
- **Context Length:** 8,192 tokens
- **Quantization:** None (full precision)
- **Description:** Meta's instruction-tuned model for general-purpose use with industry-leading performance in its size class
- **Use Cases:** Chatbots, instruction following, creative writing
- **Performance Notes:** Good balance of capabilities and resource requirements

### Qwen QwQ (32B)
**Model ID:** `Qwen/QwQ-32B`
- **GPU Requirements:** 48GB VRAM minimum (tensor parallelism recommended)
- **Recommended Instance:** g6.12xlarge
- **Context Length:** 131,072 tokens (128K)
- **Quantization:** None (full precision)
- **Description:** High-capacity reasoning model with extended context window from Alibaba Cloud
- **Use Cases:** Complex reasoning, long document analysis, specialized knowledge tasks
- **Performance Notes:** 
  - Requires multi-GPU setup for optimal performance
  - With g6.12xlarge (4x24GB GPUs), use tensor parallelism across all 4 GPUs
  - Set `gpu_memory_utilization` to 0.8-0.9 for stability

## Configuration Examples

Here are examples of terraform.tfvars configurations for different models:

### For Hermes 3 Llama (8B AWQ)
```hcl
# EC2 instance settings
use_gpu_instance  = true
gpu_instance_type = "g6.xlarge"

# vLLM Configuration
model_id               = "solidrust/Hermes-3-Llama-3.1-8B-AWQ"
max_model_len          = 14992
gpu_memory_utilization = 0.98
```

### For Llama 3.1 Instruct (8B)
```hcl
# EC2 instance settings
use_gpu_instance  = true
gpu_instance_type = "g6.xlarge"

# vLLM Configuration
model_id               = "meta-llama/Llama-3.1-8B-Instruct"
max_model_len          = 8192
gpu_memory_utilization = 0.95
```

### For Qwen QwQ (32B)
```hcl
# EC2 instance settings
use_gpu_instance  = true
gpu_instance_type = "g6.12xlarge"  # Provides 4x24GB GPUs

# vLLM Configuration
model_id               = "Qwen/QwQ-32B"
max_model_len          = 40960  # Can use full 128K context
gpu_memory_utilization = 0.85
```

## Adding New Models

To add a new model:

1. Verify the model is compatible with vLLM by checking the [vLLM supported models list](https://vllm.readthedocs.io/en/latest/models/supported_models.html)
2. Ensure your HuggingFace token has access to the model (if it's gated)
3. Update `terraform.tfvars` with the appropriate model_id and parameters
4. If needed, adjust the instance type to match GPU requirements
5. Increment the `ec2_instance_version` to force a redeployment
6. Run `terraform apply` to deploy the changes

## Troubleshooting

If you encounter issues when deploying a new model:

1. Check the vLLM logs on the EC2 instance: `docker logs vllm-service`
2. Verify your HuggingFace token is valid: `/usr/local/bin/get-hf-token.sh`
3. For large models, try reducing `gpu_memory_utilization` to 0.8 or lower
4. If the model fails to load, ensure the instance has sufficient GPU memory
5. For models requiring multiple GPUs, verify tensor parallelism is working correctly
