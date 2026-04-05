#!/usr/bin/env node
/**
 * flow — ClawFlow state manager for Osiris workspace
 *
 * Usage:
 *   flow create --goal "<goal>" --repo <owner/repo> --branch <branch> [--meta '<json>']
 *   flow list [--state running|waiting|done|failed]
 *   flow show <flowId>
 *   flow set-output <flowId> <key> <value>
 *   flow wait <flowId> --reason <reason> [--target <url>]
 *   flow resume <flowId> --step <step>
 *   flow finish <flowId>
 *   flow fail <flowId> [--reason <reason>]
 */

const fs = require('fs');
const path = require('path');

const FLOW_ROOT = process.env.FLOW_ROOT || path.join(__dirname, '..', 'flows');
const FLOWS_DIR = process.env.FLOWS_DIR || path.join(FLOW_ROOT, 'active');
const DONE_DIR = process.env.DONE_DIR || path.join(FLOW_ROOT, 'done');

function ensureDirs() {
  fs.mkdirSync(FLOWS_DIR, { recursive: true });
  fs.mkdirSync(DONE_DIR, { recursive: true });
}

function flowPath(flowId) {
  return path.join(FLOWS_DIR, `${flowId}.json`);
}

function loadFlow(flowId) {
  const p = flowPath(flowId);
  if (!fs.existsSync(p)) {
    const archivedPath = path.join(DONE_DIR, `${flowId}.json`);
    if (fs.existsSync(archivedPath)) {
      return JSON.parse(fs.readFileSync(archivedPath, 'utf8'));
    }
    die(`Flow not found: ${flowId}`);
  }
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function saveFlow(flow) {
  ensureDirs();
  flow.updatedAt = new Date().toISOString();
  fs.writeFileSync(flowPath(flow.flowId), JSON.stringify(flow, null, 2) + '\n');
  return flow;
}

function listFlows(stateFilter) {
  ensureDirs();
  const files = fs.readdirSync(FLOWS_DIR).filter((file) => file.endsWith('.json'));
  return files
    .map((file) => JSON.parse(fs.readFileSync(path.join(FLOWS_DIR, file), 'utf8')))
    .filter((flow) => !stateFilter || flow.state === stateFilter)
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}

function die(msg) {
  console.error(`error: ${msg}`);
  process.exit(1);
}

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i].startsWith('--')) {
      const key = argv[i].slice(2);
      const val = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
      args[key] = val;
    } else {
      args._.push(argv[i]);
    }
  }
  return args;
}

function slug(text) {
  return String(text)
    .toLowerCase()
    .replace(/\//g, '-')
    .replace(/[^a-z0-9-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 64);
}

function cmdCreate(args) {
  const goal = args.goal || die('--goal is required');
  const meta = args.meta ? JSON.parse(args.meta) : {};
  const repo = args.repo || meta.repo || die('--repo is required');
  const branch = args.branch || meta.branch || die('--branch is required');
  const date = new Date().toISOString().slice(0, 10);
  const flowId = `${slug(repo)}--${slug(branch)}-${date}`;

  ensureDirs();
  if (fs.existsSync(flowPath(flowId))) {
    die(`Flow already exists: ${flowId}`);
  }

  const flow = {
    flowId,
    goal,
    ownerSessionKey: args['owner-session'] || 'main',
    currentStep: 'created',
    state: 'running',
    outputs: {
      ...meta,
      repo,
      branch,
    },
    waitReason: null,
    waitTarget: null,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };

  saveFlow(flow);
  console.log(JSON.stringify({ flowId, path: flowPath(flowId) }, null, 2));
}

function cmdList(args) {
  const state = args.state || null;
  const flows = listFlows(state);
  if (!flows.length) {
    console.log(state ? `No ${state} flows.` : 'No active flows.');
    return;
  }
  flows.forEach((flow) => {
    const wait = flow.waitReason ? ` [waiting: ${flow.waitReason}]` : '';
    console.log(`${flow.state.padEnd(8)} ${flow.flowId}  "${flow.goal}"${wait}`);
    if (flow.waitTarget) {
      console.log(`          → ${flow.waitTarget}`);
    }
  });
}

function cmdShow(args) {
  const flowId = args._[0] || die('flowId required');
  const flow = loadFlow(flowId);
  console.log(JSON.stringify(flow, null, 2));
}

function cmdSetOutput(args) {
  const [flowId, key, ...rest] = args._;
  if (!flowId || !key) {
    die('usage: flow set-output <flowId> <key> <value>');
  }
  const raw = rest.join(' ') || args.value;
  if (raw === undefined) {
    die('value required');
  }
  let value;
  try {
    value = JSON.parse(raw);
  } catch {
    value = raw;
  }
  const flow = loadFlow(flowId);
  flow.outputs[key] = value;
  saveFlow(flow);
  console.log(`set ${key} on ${flowId}`);
}

function cmdWait(args) {
  const flowId = args._[0] || die('flowId required');
  const reason = args.reason || die('--reason required');
  const flow = loadFlow(flowId);
  flow.state = 'waiting';
  flow.waitReason = reason;
  flow.waitTarget = args.target || null;
  saveFlow(flow);
  console.log(`${flowId} → waiting (${reason})`);
  if (flow.waitTarget) {
    console.log(`target: ${flow.waitTarget}`);
  }
}

function cmdResume(args) {
  const flowId = args._[0] || die('flowId required');
  const step = args.step || die('--step required');
  const flow = loadFlow(flowId);
  flow.state = 'running';
  flow.currentStep = step;
  flow.waitReason = null;
  flow.waitTarget = null;
  saveFlow(flow);
  console.log(`${flowId} → running (step: ${step})`);
}

function cmdFinish(args) {
  const flowId = args._[0] || die('flowId required');
  const flow = loadFlow(flowId);
  flow.state = 'done';
  flow.currentStep = 'finished';
  flow.updatedAt = new Date().toISOString();
  ensureDirs();
  fs.writeFileSync(
    path.join(DONE_DIR, `${flowId}.json`),
    JSON.stringify(flow, null, 2) + '\n',
  );
  fs.unlinkSync(flowPath(flowId));
  console.log(`${flowId} → done (archived)`);
}

function cmdFail(args) {
  const flowId = args._[0] || die('flowId required');
  const flow = loadFlow(flowId);
  flow.state = 'failed';
  flow.currentStep = 'failed';
  flow.failReason = args.reason || 'unknown';
  flow.updatedAt = new Date().toISOString();
  ensureDirs();
  fs.writeFileSync(
    path.join(DONE_DIR, `${flowId}.json`),
    JSON.stringify(flow, null, 2) + '\n',
  );
  fs.unlinkSync(flowPath(flowId));
  console.log(`${flowId} → failed: ${flow.failReason} (archived)`);
}

const [, , cmd, ...rest] = process.argv;
const args = parseArgs(rest);

switch (cmd) {
  case 'create':
    cmdCreate(args);
    break;
  case 'list':
    cmdList(args);
    break;
  case 'show':
    cmdShow(args);
    break;
  case 'set-output':
    cmdSetOutput(args);
    break;
  case 'wait':
    cmdWait(args);
    break;
  case 'resume':
    cmdResume(args);
    break;
  case 'finish':
    cmdFinish(args);
    break;
  case 'fail':
    cmdFail(args);
    break;
  default:
    console.log('Usage: flow <create|list|show|set-output|wait|resume|finish|fail> [args]');
    process.exit(1);
}
