const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');
const sisulate = require('./webapp/sisula.js');
const template = fs.readFileSync('webapp/templates/CreateTaskGraph.sql', 'utf8');
const html = fs.readFileSync('webapp/index.html', 'utf8');
const root = { name: '"DB"."SC"."ROOT"', is_root: true, state: 'suspended', steps: [], native: {
  header: 'create or replace task "DB"."SC"."ROOT" USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE=\'XSMALL\' WHEN SYSTEM$STREAM_HAS_DATA(\'s\') AS',
  body: "BEGIN SELECT '$value$;'; END", source_state: 'started',
} };

test('native tasks retain their DDL and body without logging wrappers', () => {
  const sql = sisulate(template, JSON.stringify({ TASKS: [root] }));
  assert.ok(sql.includes(root.native.header));
  assert.ok(sql.includes(root.native.body));
  assert.doesNotMatch(sql, /CREATE OR REPLACE PROCEDURE|_TaskRunStarting|WAREHOUSE =/);
  assert.match(sql, /ALTER TASK IF EXISTS "DB"\."SC"\."ROOT" SUSPEND/);
  assert.doesNotMatch(sql, /RESUME/);
});

test('explicitly enabled native roots resume after children', () => {
  const child = { ...root, name: '"DB"."SC"."CHILD"', is_root: false, state: 'running', native: { header: 'CREATE OR REPLACE TASK "DB"."SC"."CHILD" AFTER "DB"."SC"."ROOT" AS', body: 'SELECT 1' } };
  const sql = sisulate(template, JSON.stringify({ TASKS: [{ ...root, state: 'running' }, child] }));
  assert.ok(sql.indexOf('ALTER TASK "DB"."SC"."CHILD" RESUME') < sql.indexOf('ALTER TASK "DB"."SC"."ROOT" RESUME'));
});

test('ordinary workflows still render logging procedures', () => {
  const data = JSON.parse(fs.readFileSync('examples/GolfWorkflow.json', 'utf8'));
  const sql = sisulate(template, JSON.stringify(data));
  assert.match(sql, /CREATE OR REPLACE PROCEDURE sp_tsk_import_files/);
  assert.match(sql, /_TaskRunStarting/);
  assert.match(sql, /ALTER TASK tsk_import_files SUSPEND/);
});

test('native inspector displays preserved settings and editable SQL body', () => {
  const elements = { 'tab-task': {innerHTML: ''}, 'tab-steps': {innerHTML: ''} };
  const context = vm.createContext({ data: {TASKS: [root]}, selectedTask: 0,
    document: {getElementById: id => elements[id]}, esc: s => s.replaceAll('<','&lt;'),
  });
  vm.runInContext(html.slice(html.indexOf('function renderTaskForm('), html.indexOf('function associateFormLabels(')), context);
  vm.runInContext(html.slice(html.indexOf('function renderStepsForm('), html.indexOf('function stepTitle(')), context);
  context.renderTaskForm(); context.renderStepsForm();
  assert.match(elements['tab-task'].innerHTML, /id="native-header"[^>]*readonly/);
  assert.match(elements['tab-steps'].innerHTML, /id="native-body"[^>]*oninput=/);
  assert.doesNotMatch(elements['tab-task'].innerHTML, /id="f-name"/);
});
