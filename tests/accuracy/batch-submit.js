#!/usr/bin/env node
'use strict';

// DashScope batch lifecycle: submit, status, download.
// Based on DashScope batch API patterns.
//
// Usage:
//   DASHSCOPE_API_KEY=<key> node batch-submit.js submit
//   DASHSCOPE_API_KEY=<key> node batch-submit.js status
//   DASHSCOPE_API_KEY=<key> node batch-submit.js download

const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');

const API_KEY = process.env.DASHSCOPE_API_KEY;
if (!API_KEY) { process.stderr.write('ERROR: Set DASHSCOPE_API_KEY\n'); process.exit(1); }

const BASE_URL = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
const INPUT_DIR = path.join(__dirname, 'batch-input');
const OUTPUT_DIR = path.join(__dirname, 'batch-output');
const STATE_PATH = path.join(__dirname, 'batch-state.json');

fs.mkdirSync(OUTPUT_DIR, { recursive: true });

function loadState() {
  if (fs.existsSync(STATE_PATH)) return JSON.parse(fs.readFileSync(STATE_PATH, 'utf8'));
  return { batches: {} };
}

function saveState(state) {
  fs.writeFileSync(STATE_PATH, JSON.stringify(state, null, 2) + '\n');
}

function apiRequest(method, endpoint, body, isFile) {
  return new Promise((resolve, reject) => {
    const url = new URL(BASE_URL + endpoint);
    const options = {
      method,
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname + url.search,
      headers: {
        'Authorization': `Bearer ${API_KEY}`,
      },
    };

    if (body && !isFile) {
      const data = JSON.stringify(body);
      options.headers['Content-Type'] = 'application/json';
      options.headers['Content-Length'] = Buffer.byteLength(data);
    }

    const req = https.request(options, (res) => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        const raw = Buffer.concat(chunks);
        if (res.headers['content-type']?.includes('application/json')) {
          try { resolve(JSON.parse(raw.toString())); }
          catch { resolve(raw); }
        } else {
          resolve(raw);
        }
      });
    });
    req.on('error', reject);

    if (body && !isFile) req.write(JSON.stringify(body));
    req.end();
  });
}

function uploadFile(filePath) {
  // Use curl for multipart upload — Node.js manual multipart is fragile
  const { execSync } = require('child_process');
  const result = execSync(
    `curl -s -X POST "${BASE_URL}/files" ` +
    `-H "Authorization: Bearer ${API_KEY}" ` +
    `-F "purpose=batch" ` +
    `-F "file=@${filePath}"`,
    { encoding: 'utf8', timeout: 300000 }
  );
  return JSON.parse(result);
}

async function downloadFile(fileId) {
  const resp = await apiRequest('GET', `/files/${fileId}/content`);
  return resp;
}

async function cmdSubmit() {
  const state = loadState();
  const files = fs.readdirSync(INPUT_DIR)
    .filter(f => f.startsWith('batch_') && f.endsWith('.jsonl'))
    .sort();

  if (files.length === 0) {
    console.log('No batch files found in batch-input/. Run batch-prepare.js first.');
    return;
  }

  console.log(`Found ${files.length} batch file(s), ${Object.keys(state.batches).length} already submitted\n`);

  for (const fname of files) {
    if (state.batches[fname]) {
      console.log(`  SKIP ${fname} (already submitted)`);
      continue;
    }

    const filePath = path.join(INPUT_DIR, fname);
    const sizeMB = (fs.statSync(filePath).size / 1024 / 1024).toFixed(1);
    process.stdout.write(`  Uploading ${fname} (${sizeMB}MB)...`);

    try {
      const uploaded = await uploadFile(filePath);
      if (!uploaded.id) throw new Error(JSON.stringify(uploaded));
      process.stdout.write(` file_id=${uploaded.id}`);

      const batch = await apiRequest('POST', '/batches', {
        input_file_id: uploaded.id,
        endpoint: '/v1/chat/completions',
        completion_window: '24h',
      });
      if (!batch.id) throw new Error(JSON.stringify(batch));
      console.log(` batch_id=${batch.id} OK`);

      state.batches[fname] = {
        file_id: uploaded.id,
        batch_id: batch.id,
        status: batch.status || 'validating',
        submitted_at: new Date().toISOString(),
      };
      saveState(state);
    } catch (e) {
      console.log(` ERROR: ${e.message}`);
    }
  }

  console.log(`\nDone. ${Object.keys(state.batches).length} batch(es) tracked.`);
}

async function cmdStatus() {
  const state = loadState();
  if (Object.keys(state.batches).length === 0) {
    console.log('No batches submitted yet. Run: node batch-submit.js submit');
    return;
  }

  let totalDone = 0;
  let totalAll = 0;

  for (const [name, info] of Object.entries(state.batches).sort()) {
    const batch = await apiRequest('GET', `/batches/${info.batch_id}`);
    info.status = batch.status;
    if (batch.output_file_id) info.output_file_id = batch.output_file_id;
    if (batch.error_file_id) info.error_file_id = batch.error_file_id;

    const completed = batch.request_counts?.completed || 0;
    const failed = batch.request_counts?.failed || 0;
    const total = batch.request_counts?.total || 0;
    totalDone += completed + failed;
    totalAll += total;

    const icon = { completed: 'OK', in_progress: '..', failed: 'XX', validating: '??' }[batch.status] || '??';
    console.log(`  [${icon}] ${name}: ${batch.status}  (${completed}/${total} done, ${failed} failed)`);
  }

  saveState(state);
  if (totalAll > 0) {
    console.log(`\nProgress: ${totalDone.toLocaleString()} / ${totalAll.toLocaleString()} (${(totalDone / totalAll * 100).toFixed(1)}%)`);
  }
}

async function cmdDownload() {
  const state = loadState();
  let downloaded = 0;

  for (const [name, info] of Object.entries(state.batches).sort()) {
    if (info.status !== 'completed') continue;
    if (!info.output_file_id) continue;

    const outPath = path.join(OUTPUT_DIR, name);
    if (fs.existsSync(outPath)) {
      console.log(`  SKIP ${name} (already downloaded)`);
      continue;
    }

    process.stdout.write(`  Downloading ${name}...`);
    try {
      const content = await downloadFile(info.output_file_id);
      fs.writeFileSync(outPath, content);
      downloaded++;
      const sizeMB = (fs.statSync(outPath).size / 1024 / 1024).toFixed(1);
      console.log(` OK (${sizeMB}MB)`);
    } catch (e) {
      console.log(` ERROR: ${e.message}`);
    }

    // Download error file too
    if (info.error_file_id) {
      const errPath = path.join(OUTPUT_DIR, name.replace('.jsonl', '_errors.jsonl'));
      if (!fs.existsSync(errPath)) {
        try {
          const content = await downloadFile(info.error_file_id);
          if (content.length > 0) fs.writeFileSync(errPath, content);
        } catch { /* ignore */ }
      }
    }
  }

  console.log(`\nDownloaded ${downloaded} result file(s) to ${OUTPUT_DIR}/`);
}

// CLI
const cmd = process.argv[2];
switch (cmd) {
  case 'submit': cmdSubmit().catch(e => { console.error(e); process.exit(1); }); break;
  case 'status': cmdStatus().catch(e => { console.error(e); process.exit(1); }); break;
  case 'download': cmdDownload().catch(e => { console.error(e); process.exit(1); }); break;
  default:
    console.log('Usage: node batch-submit.js <submit|status|download>');
    process.exit(1);
}
