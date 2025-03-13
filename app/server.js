const express = require('express');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const app = express();
const port = process.env.PORT || 8080;
const httpsPort = process.env.HTTPS_PORT || 443;
const vllmPort = process.env.VLLM_PORT || 8000;
const vllmHost = process.env.VLLM_HOST || 'localhost';
const useHttps = process.env.USE_HTTPS === 'true';
const appVersion = '1.1.0';

// Security headers middleware
app.use((req, res, next) => {
  // Add security headers
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-XSS-Protection', '1; mode=block');
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  res.setHeader('Content-Security-Policy', "default-src 'self'");
  next();
});

// Middleware to parse JSON
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Utility function for proxying requests to vLLM
function proxyToVLLM(path, req, res, transformResponse = null) {
  try {
    // Determine if this is a GET or POST request
    const isGet = !req.body || Object.keys(req.body).length === 0;
    const method = isGet ? 'GET' : 'POST';
    
    // Set up the options for the request
    const options = {
      hostname: vllmHost,
      port: vllmPort,
      path: path,
      method: method,
      headers: {
        'Accept': 'application/json'
      }
    };

    let postData = null;
    if (!isGet) {
      postData = JSON.stringify(req.body);
      options.headers['Content-Type'] = 'application/json';
      options.headers['Content-Length'] = Buffer.byteLength(postData);
    }

    // Handle streaming responses
    const isStreaming = !isGet && req.body && req.body.stream === true;

    // Create the request to vLLM
    const vllmReq = http.request(options, (vllmRes) => {
      let data = '';
      
      // Set headers from vLLM response
      Object.keys(vllmRes.headers).forEach(key => {
        res.setHeader(key, vllmRes.headers[key]);
      });
      
      vllmRes.on('data', (chunk) => {
        // For streaming responses, send each chunk immediately
        if (isStreaming) {
          res.write(chunk);
        } else {
          data += chunk;
        }
      });
      
      vllmRes.on('end', () => {
        if (!isStreaming) {
          try {
            if (data) {
              const responseData = JSON.parse(data);
              if (transformResponse) {
                // Apply custom transformation if provided
                const transformedData = transformResponse(responseData);
                res.status(vllmRes.statusCode).json(transformedData);
              } else {
                res.status(vllmRes.statusCode).json(responseData);
              }
            } else {
              res.status(vllmRes.statusCode).end();
            }
          } catch (error) {
            console.error(`Error parsing vLLM response: ${error}`);
            res.status(500).json({ 
              error: 'Failed to parse vLLM response',
              details: error.message
            });
          }
        } else {
          res.end();
        }
      });
    });

    vllmReq.on('error', (error) => {
      console.error(`Error calling vLLM service at ${path}: ${error}`);
      res.status(503).json({ 
        error: 'vLLM service unavailable', 
        details: error.message,
        path: path
      });
    });

    vllmReq.on('timeout', () => {
      vllmReq.destroy();
      res.status(504).json({ 
        error: 'vLLM service timeout', 
        path: path
      });
    });

    if (postData) {
      vllmReq.write(postData);
    }
    
    vllmReq.end();
  } catch (error) {
    console.error(`Error in proxy to vLLM: ${error}`);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
}

// Health check endpoint
app.get('/health', (req, res) => {
  // Check if vLLM is running by making a request to its health endpoint
  const options = {
    hostname: vllmHost,
    port: vllmPort,
    path: '/health',
    method: 'GET',
    timeout: 5000
  };

  const vllmReq = http.request(options, (vllmRes) => {
    if (vllmRes.statusCode === 200) {
      res.status(200).json({ 
        status: 'ok', 
        message: 'API and vLLM service are healthy',
        version: appVersion
      });
    } else {
      res.status(503).json({ 
        status: 'error', 
        message: 'vLLM service is not healthy',
        version: appVersion
      });
    }
  });

  vllmReq.on('error', (e) => {
    console.error(`vLLM health check failed: ${e.message}`);
    res.status(503).json({ 
      status: 'error', 
      message: 'vLLM service unavailable',
      error: e.message,
      version: appVersion
    });
  });

  vllmReq.on('timeout', () => {
    vllmReq.destroy();
    res.status(503).json({ 
      status: 'error', 
      message: 'vLLM service timeout',
      version: appVersion
    });
  });

  vllmReq.end();
});

// Root endpoint
app.get('/', (req, res) => {
  res.status(200).json({ 
    message: 'vLLM Inference API',
    timestamp: new Date().toISOString(),
    version: appVersion,
    modelInfo: process.env.MODEL_ID || 'Not specified'
  });
});

// vLLM models endpoint
app.get('/v1/models', (req, res) => {
  proxyToVLLM('/v1/models', req, res);
});

// Chat completions endpoint (OpenAI compatible)
app.post('/v1/chat/completions', (req, res) => {
  proxyToVLLM('/v1/chat/completions', req, res);
});

// Text completions endpoint (OpenAI compatible)
app.post('/v1/completions', (req, res) => {
  proxyToVLLM('/v1/completions', req, res);
});

// Tokenize endpoint
app.post('/tokenize', (req, res) => {
  proxyToVLLM('/tokenize', req, res);
});

// Detokenize endpoint
app.post('/detokenize', (req, res) => {
  proxyToVLLM('/detokenize', req, res);
});

// Version endpoint
app.get('/version', (req, res) => {
  proxyToVLLM('/version', req, res, (responseData) => {
    // Add proxy version to response
    return {
      ...responseData,
      proxy_version: appVersion
    };
  });
});

// Embeddings endpoint (OpenAI compatible)
app.post('/v1/embeddings', (req, res) => {
  proxyToVLLM('/v1/embeddings', req, res);
});

// Rerank endpoint
app.post('/rerank', (req, res) => {
  proxyToVLLM('/rerank', req, res);
});

// Rerank v1 endpoint
app.post('/v1/rerank', (req, res) => {
  proxyToVLLM('/v1/rerank', req, res);
});

// Rerank v2 endpoint
app.post('/v2/rerank', (req, res) => {
  proxyToVLLM('/v2/rerank', req, res);
});

// Score endpoint
app.post('/score', (req, res) => {
  proxyToVLLM('/score', req, res);
});

// Score v1 endpoint
app.post('/v1/score', (req, res) => {
  proxyToVLLM('/v1/score', req, res);
});

// SageMaker compatible endpoint
app.post('/invocations', (req, res) => {
  proxyToVLLM('/invocations', req, res);
});

// Start the server
if (useHttps) {
  try {
    // Check for certificate and key files
    const privateKey = fs.readFileSync('/etc/ssl/private/server.key', 'utf8');
    const certificate = fs.readFileSync('/etc/ssl/certs/server.crt', 'utf8');
    const credentials = { key: privateKey, cert: certificate };
    
    // Create HTTPS server
    const httpsServer = https.createServer(credentials, app);
    
    httpsServer.listen(httpsPort, () => {
      console.log(`vLLM Inference API proxy v${appVersion} running on HTTPS port ${httpsPort}`);
      console.log(`Also listening on HTTP port ${port} for health checks`);
      console.log(`Forwarding requests to vLLM at ${vllmHost}:${vllmPort}`);
    });
    
    // Also start HTTP server for health checks and redirect
    http.createServer((req, res) => {
      // Redirect HTTP to HTTPS except for health check endpoint
      if (req.url === '/health') {
        // Handle health check on HTTP
        app(req, res);
      } else {
        res.writeHead(301, { "Location": `https://${req.headers.host}${req.url}` });
        res.end();
      }
    }).listen(port, () => {
      console.log(`HTTP to HTTPS redirect running on port ${port}`);
    });
  } catch (error) {
    console.error('Failed to start HTTPS server:', error);
    console.log('Falling back to HTTP only mode');
    
    // Fall back to HTTP if HTTPS setup fails
    app.listen(port, () => {
      console.log(`vLLM Inference API proxy v${appVersion} running on HTTP port ${port}`);
      console.log(`Forwarding requests to vLLM at ${vllmHost}:${vllmPort}`);
    });
  }
} else {
  // HTTP only mode
  app.listen(port, () => {
    console.log(`vLLM Inference API proxy v${appVersion} running on HTTP port ${port}`);
    console.log(`Forwarding requests to vLLM at ${vllmHost}:${vllmPort}`);
  });
}
