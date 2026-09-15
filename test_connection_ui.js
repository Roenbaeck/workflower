const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');
const html = fs.readFileSync('webapp/index.html', 'utf8');
const source = html.slice(html.indexOf('function requireSnowflakeConnection('), html.indexOf('async function loadWorkflows('));

function editor(response) {
  const elements = {
    'connection-panel': { open: false }, 'connection-status': { textContent: '' },
    'btn-connect-snowflake': { disabled: false }, 'mfa-passcode': { value: '123456' },
  };
  const requests = [];
  let refreshes = 0;
  const context = vm.createContext({
    installing: false, getId: id => elements[id], showStatus() {},
    loadWorkflows: async () => { refreshes++; },
    window: { fetch: async (url, options) => { requests.push({ url, options }); return response; } },
  });
  vm.runInContext(source, context);
  return { context, elements, requests, refreshes: () => refreshes };
}

test('reconnect clears the one-time code and only refreshes the library', async () => {
  const state = editor({ ok: true, json: async () => ({ status: 'connected' }) });
  await state.context.reconnectSnowflake();
  assert.equal(state.elements['mfa-passcode'].value, '');
  assert.equal(state.requests[0].url, '/api/connection/reconnect');
  assert.equal(JSON.parse(state.requests[0].options.body).passcode, '123456');
  assert.equal(state.requests.length, 1);
  assert.equal(state.refreshes(), 1);
  assert.equal(state.elements['btn-connect-snowflake'].disabled, false);
});

test('authentication failure opens the panel without replaying the failed request', async () => {
  const state = editor({ ok: false, status: 428, text: async () => JSON.stringify({ code: 'connection_required', detail: 'Reconnect to Snowflake' }) });
  await assert.rejects(state.context.api('/api/workflows/Test', { method: 'PUT' }), /Reconnect/);
  assert.equal(state.elements['connection-panel'].open, true);
  assert.equal(state.elements['connection-status'].textContent, 'Reconnect to Snowflake');
  assert.equal(state.requests.length, 1);
  assert.equal(state.refreshes(), 0);
});

test('failed reconnect clears the code and permits another attempt', async () => {
  const state = editor({ ok: false, status: 428, text: async () => JSON.stringify({ code: 'connection_required', detail: 'Sign-in failed' }) });
  await state.context.reconnectSnowflake();
  assert.equal(state.elements['mfa-passcode'].value, '');
  assert.equal(state.elements['btn-connect-snowflake'].disabled, false);
  assert.equal(state.refreshes(), 0);
});

test('library refresh after reconnect preserves an unsaved draft', async () => {
  const draft = { WORKFLOW: 'Draft', TASKS: [] };
  const context = vm.createContext({
    current: '__new__', currentCfId: null, data: draft, dirty: true, workflows: [],
    api: async () => [{ name: 'Other' }], renderSidebar() {}, updateActionButtons() {},
    selectWorkflow() { assert.fail('Reconnect must not select another workflow'); },
    hideEditor() { assert.fail('Reconnect must not hide the draft'); },
  });
  vm.runInContext(html.slice(html.indexOf('async function loadWorkflows('), html.indexOf('async function loadWorkflow(')), context);
  await context.loadWorkflows(false, true);
  assert.equal(context.data, draft);
  assert.equal(context.dirty, true);
  assert.equal(context.current, '__new__');
});

test('startup restores the local draft before requesting authentication', async () => {
  let restored = false;
  const context = vm.createContext({
    restoreCurrentDraft: () => { restored = true; return true; },
    api: async () => { assert.equal(restored, true); throw new Error('Connect first'); },
  });
  vm.runInContext(html.slice(html.indexOf('async function loadWorkflows('), html.indexOf('async function loadWorkflow(')), context);
  await assert.rejects(context.loadWorkflows(true), /Connect first/);
  assert.equal(restored, true);
});
