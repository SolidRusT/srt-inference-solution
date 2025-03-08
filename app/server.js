const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

// Middleware to parse JSON
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Root endpoint
app.get('/', (req, res) => {
  res.status(200).json({ 
    message: 'Hello from the Inference API!',
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

// Sample inference endpoint
app.post('/api/infer', (req, res) => {
  const data = req.body;
  
  // This is where you would normally run your model
  // For this example, we just echo back the request with a timestamp
  
  res.status(200).json({
    input: data,
    result: "This is a sample inference result",
    timestamp: new Date().toISOString()
  });
});

// Start the server
app.listen(port, () => {
  console.log(`Inference API server running on port ${port}`);
});
