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
    --tensor-parallel-size ${tensor_parallel_size} \\
    --pipeline-parallel-size ${pipeline_parallel_size} \\
    --tool-call-parser ${tool_call_parser}'

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
    -e DEFAULT_TIMEOUT_MS="60000" \\
    -e MAX_TIMEOUT_MS="300000" \\
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