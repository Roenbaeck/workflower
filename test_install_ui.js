const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');
const html = fs.readFileSync('webapp/index.html', 'utf8');
const source = html.slice(html.indexOf('async function installWorkflow('), html.indexOf('async function deleteWorkflow('));

for (const [name, chunks, expected] of [
  ['completed installation', ['[OK] Statement 1\n[DO', 'NE] Finished\n'], 'success'],
  ['truncated stream', ['[OK] Statement 1\n'], 'error'],
  ['explicit SQL failure', ['[OK] Statement 1\n[ERROR] SQL failed\n'], 'error'],
]) {
  test(name, async () => {
    const states = [];
    const context = vm.createContext({
      installing: false, currentCfId: 42, dirty: false, current: 'Workflow',
      openInstallModal() {}, appendInstallLog() {}, updateActionButtons() {}, showStatus() {},
      setInstallModalState: (state) => states.push(state), getId: () => null,
      TextDecoder,
      window: { fetch: async () => ({ ok: true, body: { getReader: () => ({
        read: async () => chunks.length ? { done: false, value: Buffer.from(chunks.shift()) } : { done: true },
      }) } }) },
    });
    vm.runInContext(source, context);
    await context.installWorkflow();
    assert.equal(states.at(-1), expected);
    assert.equal(context.installing, false);
  });
}

test('API preserves plain-text errors without reading the body twice', async () => {
  let reads = 0;
  const context = vm.createContext({
    showStatus() {},
    window: { fetch: async () => ({ ok: false, status: 502, text: async () => {
      assert.equal(++reads, 1);
      return 'Backend unavailable';
    } }) },
  });
  vm.runInContext(html.slice(html.indexOf('async function api('), html.indexOf('async function loadWorkflows(')), context);
  await assert.rejects(context.api('/api/workflows'), /Backend unavailable/);
});
