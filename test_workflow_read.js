const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');

const html = fs.readFileSync('webapp/index.html', 'utf8');
const helpers = html.slice(html.indexOf('async function api('), html.indexOf('async function saveWorkflow('));
const selection = html.slice(html.indexOf('async function selectWorkflow('), html.indexOf('function newWorkflow('));

function createEditor(responses, initial = {}) {
  const button = { disabled: false, textContent: 'Read from Snowflake' };
  const requests = [];
  const statuses = [];
  const context = vm.createContext({
    current: null, currentCfId: null, data: null, dirty: false, workflows: [],
    selectedTask: 0, needsInitialLayout: false,
    confirm: () => true,
    getId: () => button,
    showStatus: (message, type) => statuses.push({ message, type }),
    renderSidebar() {}, renderEditor() {}, persistCurrentDraft() {},
    loadLayoutState() {}, extractLegacyLayout() {}, clearSqlPreview() {},
    window: { fetch: async (url) => {
      requests.push(url);
      const response = responses.shift();
      if (response instanceof Error) throw response;
      return { ok: true, json: async () => response };
    } },
    ...initial,
  });
  vm.runInContext(helpers + selection, context);
  return { context, button, requests, statuses };
}

test('read is available without an open workflow', () => {
  assert.ok(html.indexOf('id="btn-read-snowflake"') < html.indexOf('id="editor"'));
});

test('cold start reads a saved definition and its configuration ID', async () => {
  const editor = createEditor([
    [{ name: 'Golf / workflow', cf_id: 42 }, { name: 'Other', cf_id: 7 }],
    { name: 'Golf / workflow', cf_id: 42, content: '{"WORKFLOW":"Golf","TASKS":[]}' },
  ]);
  await editor.context.readFromSnowflake();
  assert.deepEqual(editor.requests, ['/api/workflows', '/api/workflows/42']);
  assert.equal(editor.context.data.WORKFLOW, 'Golf');
  assert.equal(editor.context.currentCfId, 42);
  assert.equal(editor.context.dirty, false);
  assert.equal(editor.context.workflows.length, 2);
  assert.equal(editor.button.disabled, false);
});

test('explicit read reloads current workflow instead of the first entry', async () => {
  const editor = createEditor([
    [{ name: 'First', cf_id: 1 }, { name: 'Current', cf_id: 2 }],
    { name: 'Current', cf_id: 2, content: '{"WORKFLOW":"Current"}' },
  ], { current: 'Current', dirty: true });
  await editor.context.readFromSnowflake();
  assert.equal(editor.requests[1], '/api/workflows/2');
  assert.equal(editor.context.data.TASKS.length, 0);
  assert.equal(editor.context.dirty, false);
});

test('cancel preserves unsaved changes without fetching', async () => {
  const data = { WORKFLOW: 'Draft' };
  const editor = createEditor([], { data, dirty: true, confirm: () => false });
  await editor.context.readFromSnowflake();
  await editor.context.selectWorkflow('Other');
  assert.equal(editor.requests.length, 0);
  assert.equal(editor.context.data, data);
  assert.equal(editor.context.dirty, true);
});

test('empty Snowflake list preserves the current draft', async () => {
  const data = { WORKFLOW: 'Draft' };
  const editor = createEditor([[]], { data, dirty: true });
  await editor.context.readFromSnowflake();
  assert.equal(editor.context.data, data);
  assert.equal(editor.context.dirty, true);
  assert.equal(editor.statuses.at(-1).message, 'No saved workflows in Snowflake');
});

test('network failure allows retry without replacing the draft', async () => {
  const data = { WORKFLOW: 'Draft' };
  const editor = createEditor([new Error('Offline')], { data, dirty: true });
  await editor.context.readFromSnowflake();
  assert.equal(editor.context.data, data);
  assert.equal(editor.button.disabled, false);
  assert.equal(editor.button.textContent, 'Read from Snowflake');
  assert.equal(editor.statuses.at(-1).type, 'error');
});

test('invalid stored definitions do not partially replace editor state', async () => {
  for (const content of ['invalid', 'null', '[]']) {
    const data = { WORKFLOW: 'Draft' };
    const editor = createEditor([
      [{ name: 'Saved', cf_id: 42 }], { name: 'Saved', cf_id: 42, content },
    ], { current: '__new__', data, dirty: true });
    await editor.context.readFromSnowflake();
    assert.equal(editor.context.current, '__new__');
    assert.equal(editor.context.currentCfId, null);
    assert.equal(editor.context.data, data);
    assert.equal(editor.context.dirty, true);
    assert.equal(editor.statuses.at(-1).type, 'error');
  }
});

test('sidebar selection reads a different saved workflow', async () => {
  // The library listing carries the CF_ID that loadWorkflow resolves the name against.
  const editor = createEditor([
    { name: 'Other', cf_id: 7, content: '{"WORKFLOW":"Other"}' },
  ], { workflows: [{ name: 'Other', cf_id: 7 }] });
  await editor.context.selectWorkflow('Other');
  assert.equal(editor.requests[0], '/api/workflows/7');
  assert.equal(editor.context.currentCfId, 7);
});