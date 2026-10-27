'use strict';
const express = require('express');

const app = express();
app.disable('x-powered-by');

const startedAt = Date.now();

// Read at request time so the value can be set by Docker/CI (APP_VERSION = git commit SHA).
const getVersion = () => process.env.APP_VERSION || 'dev';

app.get('/', (req, res) => {
  const version = getVersion();
  res.type('html').send(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>CI/CD Pipeline Demo</title>
  <style>
    body { font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0;
           display: grid; place-items: center; min-height: 100vh; margin: 0; }
    main { text-align: center; padding: 2rem; }
    code { background: #1e293b; padding: .2rem .5rem; border-radius: 6px; }
    .ok { color: #4ade80; }
    a { color: #38bdf8; }
  </style>
</head>
<body>
  <main>
    <h1>CI/CD Pipeline Demo</h1>
    <p class="ok">Deployed automatically by GitHub Actions</p>
    <p>Version: <code>${version}</code></p>
    <p><a href="/health">/health</a> &middot; <a href="/api/info">/api/info</a></p>
  </main>
</body>
</html>`);
});

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    version: getVersion(),
    uptime_seconds: Math.round((Date.now() - startedAt) / 1000),
  });
});

app.get('/api/info', (req, res) => {
  res.json({
    name: 'cicd-pipeline-demo',
    version: getVersion(),
    node: process.version,
    environment: process.env.NODE_ENV || 'development',
  });
});

app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

module.exports = app;
