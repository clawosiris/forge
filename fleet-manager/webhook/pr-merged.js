#!/usr/bin/env node

const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const path = require('path');
const { spawn } = require('child_process');

const PORT = Number(process.env.WEBHOOK_PORT || 9000);
const SECRET = process.env.WEBHOOK_SECRET || '';
const FLOWS_DIR = process.env.FLOWS_DIR || '/app/flows/active';
const FLOW_CLI = process.env.FLOW_CLI || '/app/flow/flow.js';

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, { 'content-type': 'application/json' });
  res.end(JSON.stringify(payload));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function isValidSignature(rawBody, signatureHeader) {
  if (!SECRET || !signatureHeader || !signatureHeader.startsWith('sha256=')) {
    return false;
  }

  const expected = `sha256=${crypto
    .createHmac('sha256', SECRET)
    .update(rawBody)
    .digest('hex')}`;
  const actual = signatureHeader;

  const expectedBuffer = Buffer.from(expected, 'utf8');
  const actualBuffer = Buffer.from(actual, 'utf8');
  if (expectedBuffer.length !== actualBuffer.length) {
    return false;
  }
  return crypto.timingSafeEqual(expectedBuffer, actualBuffer);
}

function listFlowFiles() {
  if (!fs.existsSync(FLOWS_DIR)) {
    return [];
  }
  return fs
    .readdirSync(FLOWS_DIR)
    .filter((file) => file.endsWith('.json'))
    .map((file) => path.join(FLOWS_DIR, file));
}

function readFlow(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    console.error(`failed to parse flow file ${filePath}: ${error.message}`);
    return null;
  }
}

function resumeFlow(flowId, step, prUrl, matchField) {
  console.log(`resuming flow ${flowId} to ${step} for ${matchField}=${prUrl}`);
  const child = spawn(
    'node',
    [FLOW_CLI, 'resume', flowId, '--step', step],
    {
      env: process.env,
      stdio: 'ignore',
      detached: true,
    },
  );
  child.unref();
}

function handleMergedPullRequest(payload) {
  const pr = payload && payload.pull_request;
  if (!pr || payload.action !== 'closed' || pr.merged !== true) {
    return;
  }

  const prUrl = pr.html_url;
  if (!prUrl) {
    return;
  }

  listFlowFiles().forEach((filePath) => {
    const flow = readFlow(filePath);
    if (!flow) {
      return;
    }

    const outputs = flow.outputs || {};
    if (outputs.spec_pr_url === prUrl) {
      resumeFlow(flow.flowId, 'implement', prUrl, 'spec_pr_url');
      return;
    }

    if (outputs.impl_pr_url === prUrl) {
      resumeFlow(flow.flowId, 'review', prUrl, 'impl_pr_url');
    }
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method !== 'POST' || req.url !== '/webhook/github') {
    sendJson(res, 404, { ok: false });
    return;
  }

  let rawBody;
  try {
    rawBody = await readBody(req);
  } catch (error) {
    console.error(`failed to read request body: ${error.message}`);
    sendJson(res, 500, { ok: false });
    return;
  }

  if (!isValidSignature(rawBody, req.headers['x-hub-signature-256'])) {
    sendJson(res, 401, { ok: false, error: 'invalid signature' });
    return;
  }

  let payload;
  try {
    payload = JSON.parse(rawBody.toString('utf8'));
  } catch (error) {
    sendJson(res, 400, { ok: false, error: 'invalid json' });
    return;
  }

  try {
    if (req.headers['x-github-event'] === 'pull_request') {
      handleMergedPullRequest(payload);
    }
    sendJson(res, 200, { ok: true });
  } catch (error) {
    console.error(`failed to process webhook: ${error.message}`);
    sendJson(res, 500, { ok: false });
  }
});

server.listen(PORT, () => {
  console.log(`GitHub PR merge webhook listening on ${PORT}`);
});
