# AWS EC2 Inference Solution - API Reference

## Overview

This document provides details about the REST API endpoints exposed by the inference application. The sample application is built using Node.js and Express, and includes basic endpoints for health checking and a mock inference service.

## Base URLs

- **Development**: `http://localhost:8080`
- **Production**: 
  - IP-based: `http://<ec2-instance-ip>:8080`
  - Domain-based: `https://infer.<your-domain>:8080` (when DNS records are enabled)

## Authentication

The API currently does not implement authentication. Future versions will include:
- API key authentication
- JWT token-based authentication
- AWS IAM-based authentication

## Endpoints

### Health Check

Verify the API service is running properly.

```
GET /health
```

#### Response

```json
{
  "status": "ok"
}
```

#### Status Codes

- `200 OK`: Service is healthy

### Root Endpoint

Get basic information about the API service.

```
GET /
```

#### Response

```json
{
  "message": "Hello from the Inference API!",
  "timestamp": "2025-03-08T12:34:56.789Z",
  "version": "1.0.0"
}
```

#### Status Codes

- `200 OK`: Request successful

### Inference Endpoint

Submit data for inference processing.

```
POST /api/infer
```

#### Request Body

```json
{
  "data": "Your input data here"
}
```

#### Response

```json
{
  "input": {
    "data": "Your input data here"
  },
  "result": "This is a sample inference result",
  "timestamp": "2025-03-08T12:34:56.789Z"
}
```

#### Status Codes

- `200 OK`: Inference successful
- `400 Bad Request`: Invalid input data
- `500 Internal Server Error`: Processing error

## Error Handling

All error responses follow this format:

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message"
  }
}
```

## Rate Limiting

Currently, the API does not implement rate limiting. Future versions will include rate limiting based on:
- IP address
- API key
- User/Client ID

## Versioning

The API follows semantic versioning (MAJOR.MINOR.PATCH). The current version can be found in the response from the root endpoint.

## Development and Testing

### Local Development

To run the API locally:

1. Navigate to the app directory:
   ```bash
   cd app
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Start the server:
   ```bash
   npm start
   ```

4. The server will be available at `http://localhost:8080`

### Docker Development

To build and run the API using Docker:

1. Build the image:
   ```bash
   docker build -t inference-app .
   ```

2. Run the container:
   ```bash
   docker run -p 8080:8080 inference-app
   ```

3. The server will be available at `http://localhost:8080`

### Testing with cURL

Examples of testing the API with cURL:

Health check:
```bash
curl http://localhost:8080/health
```

Root endpoint:
```bash
curl http://localhost:8080/
```

Inference endpoint:
```bash
curl -X POST \
  http://localhost:8080/api/infer \
  -H 'Content-Type: application/json' \
  -d '{"data": "Test inference data"}'
```

## Future Enhancements

The API will be enhanced with the following features in future releases:

1. **Authentication and Authorization**:
   - API key management
   - OAuth 2.0 / OpenID Connect integration
   - Role-based access control

2. **Enhanced Inference Capabilities**:
   - Support for multiple model types
   - Batched inference requests
   - Asynchronous inference processing

3. **Performance Features**:
   - Response caching
   - Request queuing
   - Throttling controls

4. **Monitoring and Logging**:
   - Detailed request/response logging
   - Performance metrics
   - Tracing support

5. **Documentation**:
   - OpenAPI (Swagger) specification
   - Interactive documentation
