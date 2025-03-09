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
      res.status(200).json({ status: 'ok', message: 'API and vLLM service are healthy' });
    } else {
      res.status(503).json({ status: 'error', message: 'vLLM service is not healthy' });
    }
  });

  vllmReq.on('error', (e) => {
    console.error(`vLLM health check failed: ${e.message}`);
    res.status(503).json({ 
      status: 'error', 
      message: 'vLLM service unavailable',
      error: e.message
    });
  });

  vllmReq.on('timeout', () => {
    vllmReq.destroy();
    res.status(503).json({ 
      status: 'error', 
      message: 'vLLM service timeout'
    });
  });

  vllmReq.end();
});

// Root endpoint
app.get('/', (req, res) => {
  res.status(200).json({ 
    message: 'vLLM Inference API',
    timestamp: new Date().toISOString(),
    version: '1.0.0',
    modelInfo: process.env.MODEL_ID || 'Not specified'
  });
});

// vLLM models endpoint - pass through to vLLM
app.get('/v1/models', async (req, res) => {
  try {
    const options = {
      hostname: vllmHost,
      port: vllmPort,
      path: '/v1/models',
      method: 'GET'
    };

    const vllmReq = http.request(options, (vllmRes) => {
      let data = '';
      
      vllmRes.on('data', (chunk) => {
        data += chunk;
      });
      
      vllmRes.on('end', () => {
        try {
          const responseData = JSON.parse(data);
          res.status(vllmRes.statusCode).json(responseData);
        } catch (error) {
          console.error('Error parsing vLLM response:', error);
          res.status(500).json({ error: 'Failed to parse vLLM response' });
        }
      });
    });

    vllmReq.on('error', (error) => {
      console.error('Error calling vLLM service:', error);
      res.status(503).json({ error: 'vLLM service unavailable', details: error.message });
    });

    vllmReq.end();
  } catch (error) {
    console.error('Error in models endpoint:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Inference endpoint - proxy to vLLM
app.post('/v1/chat/completions', (req, res) => {
  try {
    const postData = JSON.stringify(req.body);
    
    const options = {
      hostname: vllmHost,
      port: vllmPort,
      path: '/v1/chat/completions',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const vllmReq = http.request(options, (vllmRes) => {
      let data = '';
      
      // Set headers from vLLM response
      Object.keys(vllmRes.headers).forEach(key => {
        res.setHeader(key, vllmRes.headers[key]);
      });
      
      vllmRes.on('data', (chunk) => {
        data += chunk;
        // For streaming responses, send each chunk immediately
        if (req.body.stream) {
          res.write(chunk);
        }
      });
      
      vllmRes.on('end', () => {
        if (!req.body.stream) {
          try {
            const responseData = JSON.parse(data);
            res.status(vllmRes.statusCode).json(responseData);
          } catch (error) {
            console.error('Error parsing vLLM response:', error);
            res.status(500).json({ error: 'Failed to parse vLLM response' });
          }
        } else {
          res.end();
        }
      });
    });

    vllmReq.on('error', (error) => {
      console.error('Error calling vLLM service:', error);
      res.status(503).json({ error: 'vLLM service unavailable', details: error.message });
    });

    vllmReq.write(postData);
    vllmReq.end();
  } catch (error) {
    console.error('Error in inference endpoint:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Compatibility with old API route
app.post('/api/infer', (req, res) => {
  // Transform the request to match OpenAI format
  const transformedBody = {
    model: process.env.MODEL_ID || "default",
    messages: [
      {
        role: "user",
        content: req.body.data || "Hello, world!"
      }
    ],
    max_tokens: parseInt(process.env.MAX_TOKENS || "1024", 10)
  };

  // Forward to vLLM
  const postData = JSON.stringify(transformedBody);
  
  const options = {
    hostname: vllmHost,
    port: vllmPort,
    path: '/v1/chat/completions',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(postData)
    }
  };

  const vllmReq = http.request(options, (vllmRes) => {
    let data = '';
    
    vllmRes.on('data', (chunk) => {
      data += chunk;
    });
    
    vllmRes.on('end', () => {
      try {
        const vllmResponse = JSON.parse(data);
        
        // Extract the model's response and format for compatibility
        const responseText = vllmResponse.choices && 
                            vllmResponse.choices[0] && 
                            vllmResponse.choices[0].message && 
                            vllmResponse.choices[0].message.content || 
                            "No response generated";
        
        // Return in the old format for backward compatibility
        res.status(200).json({
          input: req.body,
          result: responseText,
          timestamp: new Date().toISOString(),
          model: vllmResponse.model || process.env.MODEL_ID || "unknown"
        });
      } catch (error) {
        console.error('Error parsing vLLM response:', error);
        res.status(500).json({ error: 'Failed to parse vLLM response' });
      }
    });
  });

  vllmReq.on('error', (error) => {
    console.error('Error calling vLLM service:', error);
    res.status(503).json({ error: 'vLLM service unavailable', details: error.message });
  });

  vllmReq.write(postData);
  vllmReq.end();
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
      console.log(`vLLM Inference API proxy running on HTTPS port ${httpsPort}`);
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
      console.log(`vLLM Inference API proxy running on HTTP port ${port}`);
      console.log(`Forwarding requests to vLLM at ${vllmHost}:${vllmPort}`);
    });
  }
} else {
  // HTTP only mode
  app.listen(port, () => {
    console.log(`vLLM Inference API proxy running on HTTP port ${port}`);
    console.log(`Forwarding requests to vLLM at ${vllmHost}:${vllmPort}`);
  });
}
