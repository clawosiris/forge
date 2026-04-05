#!/usr/bin/env node

const fs = require('fs');
const { spawnSync } = require('child_process');

const FLOW_CLI = process.env.FLOW_CLI || '/app/flow/flow.js';

function die(message) {
  console.error(message);
  process.exit(1);
}

function readJsonStdin() {
  const input = fs.readFileSync(0, 'utf8').trim();
  if (!input) {
    die('stdin JSON is required');
  }
  return JSON.parse(input);
}

function runFlow(args) {
  const result = spawnSync('node', [FLOW_CLI, ...args], {
    stdio: ['ignore', 'pipe', 'inherit'],
    encoding: 'utf8',
    env: process.env,
  });

  if (result.status !== 0) {
    process.exit(result.status || 1);
  }

  process.stdout.write(result.stdout);
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    die(`${name} is required`);
  }
  return value;
}

function createFlow() {
  const repo = requireEnv('FORGE_REPO');
  const branch = requireEnv('FORGE_BRANCH');
  const feature =
    process.env.FORGE_FEATURE ||
    `Implement ${repo}#${process.env.FORGE_ISSUE || 'unknown'}`;
  const issueNumber = process.env.FORGE_ISSUE ? Number(process.env.FORGE_ISSUE) : null;
  const meta = JSON.stringify({
    issue_number: Number.isNaN(issueNumber) ? process.env.FORGE_ISSUE : issueNumber,
    feature,
  });

  runFlow([
    'create',
    '--goal',
    feature,
    '--repo',
    repo,
    '--branch',
    branch,
    '--meta',
    meta,
  ]);
}

function agentPreview() {
  const payload = {
    feature: process.env.FORGE_FEATURE || null,
    repo: process.env.FORGE_REPO || null,
    branch: process.env.FORGE_BRANCH || null,
    issue: process.env.FORGE_ISSUE || null,
  };
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

function mergePreview() {
  const flow = readJsonStdin();
  const payload = {
    flowId: flow.flowId,
    mergeTarget: process.env.FORGE_BRANCH || null,
  };
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

function resumeStep(step) {
  const flow = readJsonStdin();
  runFlow(['resume', flow.flowId, '--step', step]);
}

function waitReason(reason) {
  const flow = readJsonStdin();
  runFlow(['wait', flow.flowId, '--reason', reason]);
}

function finishFlow() {
  const flow = readJsonStdin();
  runFlow(['finish', flow.flowId]);
}

const [, , action, value] = process.argv;

switch (action) {
  case 'create-flow':
    createFlow();
    break;
  case 'agent-preview':
    agentPreview();
    break;
  case 'merge-preview':
    mergePreview();
    break;
  case 'resume-step':
    if (!value) {
      die('step is required');
    }
    resumeStep(value);
    break;
  case 'wait':
    if (!value) {
      die('reason is required');
    }
    waitReason(value);
    break;
  case 'finish':
    finishFlow();
    break;
  default:
    die('usage: openspec-dev-step.js <create-flow|agent-preview|merge-preview|resume-step|wait|finish> [value]');
}
