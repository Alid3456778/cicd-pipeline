'use strict';
const request = require('supertest');
const app = require('../src/app');

describe('CI/CD demo app', () => {
  afterEach(() => {
    delete process.env.APP_VERSION;
  });

  test('GET /health returns ok and the current version', async () => {
    process.env.APP_VERSION = 'abc123';
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.version).toBe('abc123');
    expect(typeof res.body.uptime_seconds).toBe('number');
  });

  test('GET /health falls back to "dev" when APP_VERSION is not set', async () => {
    const res = await request(app).get('/health');
    expect(res.body.version).toBe('dev');
  });

  test('GET / returns the HTML status page', async () => {
    process.env.APP_VERSION = 'abc123';
    const res = await request(app).get('/');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/html/);
    expect(res.text).toContain('abc123');
  });

  test('GET /api/info returns service info', async () => {
    const res = await request(app).get('/api/info');
    expect(res.status).toBe(200);
    expect(res.body.name).toBe('cicd-pipeline-demo');
    expect(res.body.node).toBe(process.version);
  });

  test('unknown routes return a JSON 404', async () => {
    const res = await request(app).get('/does-not-exist');
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: 'Not found' });
  });
});
