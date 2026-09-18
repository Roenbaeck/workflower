const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');
const repo = require('./repo.js');

const html = fs.readFileSync(repo('webapp/index.html'), 'utf8');
const css = fs.readFileSync(repo('webapp/editor.css'), 'utf8');
const markup = html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, '');

function sourceBetween(start, end) {
  const startIndex = html.indexOf(start);
  const endIndex = html.indexOf(end, startIndex);
  assert.ok(startIndex >= 0 && endIndex > startIndex);
  return html.slice(startIndex, endIndex);
}

function element(dataset = {}) {
  const classes = new Set();
  return {
    dataset, hidden: false, attributes: {}, focused: false,
    classList: {
      contains: (name) => classes.has(name),
      toggle(name, force = !classes.has(name)) {
        if (force) classes.add(name);
        else classes.delete(name);
        return force;
      },
    },
    setAttribute(name, value) { this.attributes[name] = value; },
    focus() { this.focused = true; },
  };
}

function createWorkspace() {
  const names = ['workflow', 'task', 'steps', 'json', 'sql'];
  const tabs = names.map((name) => element({ tab: name }));
  const panels = names.map((name) => ({ ...element(), id: 'tab-' + name }));
  const views = ['graph', 'details'].map((view) => element({ view }));
  const elements = Object.fromEntries(['editor', 'app', 'task-buttons', 'btn-library',
    'library-backdrop', 'workflow-search', 'btn-inspector-expand'].map((name) => [name, element()]));
  const rendered = [];
  const context = vm.createContext({
    activeInspectorTab: 'task', selectedTask: 0,
    data: { TASKS: [{ name: 'First' }, { name: 'Second' }] },
    getId: (id) => elements[id],
    document: {
      querySelectorAll: (selector) => ({ '.tab': tabs, '.tab-content': panels, '[data-tab]': tabs, '[data-view]': views })[selector],
    },
    window: { matchMedia: () => ({ matches: true }) },
    renderTaskForm: () => rendered.push('task'),
    renderStepsForm: () => rendered.push('steps'),
    renderJsonPreview: () => rendered.push('json'),
    renderSqlTab: () => rendered.push('sql'),
    renderTaskButtons() {}, renderGraph() {}, persistCurrentDraft() {},
    // The width helpers live outside the evaluated region; this test is about the
    // expand button's state and label, not about the arithmetic.
    inspectorWidthBeforeExpand: null,
    INSPECTOR_DEFAULT_WIDTH: 360,
    currentInspectorWidth: () => 360,
    inspectorWidthLimits: () => ({ min: 280, max: 900 }),
    setInspectorWidth() {},
  });
  vm.runInContext(sourceBetween('function switchTab(', 'function renderTaskForm('), context);
  vm.runInContext(sourceBetween('function selectTask(', '// --- Graph ---'), context);
  return { context, tabs, panels, views, elements, rendered };
}

test('inline application scripts parse', () => {
  for (const match of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)) {
    assert.doesNotThrow(() => new vm.Script(match[1]));
  }
});

test('task inspector retains editable fields and the predecessor container', () => {
  const elements = { 'tab-task': { innerHTML: '' }, 'f-after': { innerHTML: '' } };
  const context = vm.createContext({
    data: { TASKS: [{ name: 'Task A', after: [{ name: 'Task B' }] }, { name: 'Task B' }] },
    selectedTask: 0,
    document: { getElementById: (id) => elements[id] },
    getId: (id) => elements[id],
    esc: (text) => text,
    associateFormLabels() {},
  });
  vm.runInContext(sourceBetween('function renderTaskForm(', 'function associateFormLabels('), context);
  context.renderTaskForm();
  for (const id of ['f-name', 'f-sched', 'f-desc', 'f-state', 'f-root', 'f-after']) {
    assert.ok(elements['tab-task'].innerHTML.includes('id="' + id + '"'), id);
  }
  assert.match(elements['f-after'].innerHTML, /value="Task B" checked/);
  assert.doesNotMatch(elements['tab-task'].innerHTML, /<script|<link|id="sidebar"/);
});

test('markup has unique IDs and accessible tab targets', () => {
  const ids = Array.from(markup.matchAll(/\bid="([^"]+)"/g), (match) => match[1]);
  assert.equal(ids.length, new Set(ids).size);
  for (const match of markup.matchAll(/(?:aria-controls|aria-labelledby|for)="([^"]+)"/g)) {
    assert.ok(ids.includes(match[1]), match[1]);
  }
  assert.ok(markup.indexOf('id="workspace-header"') < markup.indexOf('id="editor"'));
  // The inspector width is driven by a variable so the drag handle, the expand button and
  // the stored preference all move the same thing.
  assert.match(css, /#editor\s*\{[^}]*grid-template-columns: minmax\(0, 1fr\) 5px var\(--inspector-width/);
  assert.match(css, /#split-handle\s*\{[^}]*cursor: col-resize/);
  assert.match(css, /\.tab-content\s*\{[^}]*overflow: auto/);
});

// The minimap framed itself on the graph alone, so whenever the view was wider than the
// graph -- the normal state for a freshly laid out workflow -- the viewport rectangle fell
// outside the frame and was clipped to a stray line.
function drawMinimapWith(bounds, view) {
  const svg = { children: [], firstChild: null, attributes: {},
    setAttribute(name, value) { this.attributes[name] = value; },
    appendChild(child) { this.children.push(child); },
    removeChild() {} };
  const context = vm.createContext({
    svgNS: 'http://www.w3.org/2000/svg',
    edges: [], selectedTask: 0, nodeMap: {}, data: { TASKS: [] },
    taskId: () => 'x',
    ensureMiniSvg: () => svg,
    getGraphBounds: () => bounds,
    currentViewBox: () => view,
    document: { createElementNS: (ns, tag) => ({ tag, attributes: {}, setAttribute(n, v) { this.attributes[n] = v; } }) },
  });
  vm.runInContext(sourceBetween('function drawMiniMap(', 'function screenToMiniature('), context);
  context.drawMiniMap();
  const frame = svg.attributes.viewBox.split(' ').map(Number);
  const rect = svg.children.find((child) => child.attributes.class === 'mini-viewport').attributes;
  return { frame, rect };
}

function contains(frame, rect) {
  return rect.x >= frame[0] && rect.y >= frame[1]
      && rect.x + rect.width <= frame[0] + frame[2]
      && rect.y + rect.height <= frame[1] + frame[3];
}

test('the minimap always shows the viewport, however far it is from the graph', () => {
  const graph = { x: 200, y: 50, width: 400, height: 300 };

  // Zoomed out past the graph: the case that used to clip the rectangle away.
  let drawn = drawMinimapWith(graph, { x: 0, y: 0, width: 800, height: 450 });
  assert.ok(contains(drawn.frame, drawn.rect), 'viewport escaped the frame when zoomed out');

  // Zoomed in: the rectangle is a small window on the graph.
  drawn = drawMinimapWith(graph, { x: 300, y: 150, width: 120, height: 90 });
  assert.ok(contains(drawn.frame, drawn.rect), 'viewport escaped the frame when zoomed in');

  // Panned clear of the graph: both still have to fit.
  drawn = drawMinimapWith(graph, { x: 2000, y: 1500, width: 120, height: 90 });
  assert.ok(contains(drawn.frame, drawn.rect), 'viewport escaped the frame when panned away');
  assert.ok(drawn.frame[0] <= graph.x && drawn.frame[1] <= graph.y, 'graph dropped out of the frame');
});

// Scrolling used to pan, and only Ctrl+scroll zoomed. Now the wheel zooms on the point
// under the pointer, which only feels right if that point does not drift.
function zoomWith(viewBox, anchor, factor) {
  let applied = null;
  const context = vm.createContext({
    currentViewBox: () => viewBox,
    screenToSVG: () => anchor,
    setViewBox: (x, y, width, height) => { applied = { x, y, width, height }; },
  });
  vm.runInContext(sourceBetween('const MIN_VIEW_WIDTH', 'function zoomGraphBy('), context);
  context.zoomViewBoxAt(factor, 10, 10);
  return applied;
}

test('wheel zoom keeps the point under the pointer still', () => {
  const viewBox = { x: 0, y: 0, width: 800, height: 450 };
  const anchor = { x: 200, y: 100 };
  // Where the anchor sits in the view, as a fraction. Zoom must not move it.
  const before = { x: (anchor.x - viewBox.x) / viewBox.width, y: (anchor.y - viewBox.y) / viewBox.height };

  for (const factor of [0.5, 0.9, 1.1, 2]) {
    const next = zoomWith(viewBox, anchor, factor);
    const after = { x: (anchor.x - next.x) / next.width, y: (anchor.y - next.y) / next.height };
    assert.ok(Math.abs(after.x - before.x) < 1e-9, 'anchor drifted horizontally at factor ' + factor);
    assert.ok(Math.abs(after.y - before.y) < 1e-9, 'anchor drifted vertically at factor ' + factor);
    assert.ok(Math.abs(next.width / next.height - viewBox.width / viewBox.height) < 1e-9, 'aspect changed');
  }
});

test('wheel zoom clamps, and still holds the anchor at the limit', () => {
  const viewBox = { x: 0, y: 0, width: 800, height: 450 };
  const anchor = { x: 200, y: 100 };
  const before = { x: (anchor.x - viewBox.x) / viewBox.width, y: (anchor.y - viewBox.y) / viewBox.height };

  // Far past both limits: the width stops, and the anchor must stop with it rather than
  // drifting because the requested factor was never applied.
  for (const [factor, expected] of [[0.00001, 100], [1000, 10000]]) {
    const next = zoomWith(viewBox, anchor, factor);
    assert.equal(Math.round(next.width), expected);
    const after = { x: (anchor.x - next.x) / next.width, y: (anchor.y - next.y) / next.height };
    assert.ok(Math.abs(after.x - before.x) < 1e-9, 'anchor drifted at the zoom limit');
    assert.ok(Math.abs(after.y - before.y) < 1e-9, 'anchor drifted at the zoom limit');
  }
});

test('the split handle sits between the panes and is reachable without a mouse', () => {
  // Grid column order follows DOM order, so the handle must fall between them.
  assert.ok(markup.indexOf('class="canvas-pane"') < markup.indexOf('id="split-handle"'));
  assert.ok(markup.indexOf('id="split-handle"') < markup.indexOf('id="inspector"'));

  const handle = markup.slice(markup.indexOf('id="split-handle"'), markup.indexOf('id="inspector"'));
  assert.match(handle, /role="separator"/);
  assert.match(handle, /aria-orientation="vertical"/);
  assert.match(handle, /tabindex="0"/);
  assert.match(handle, /aria-valuenow="\d+"/);

  // A drag handle is unusable without a keyboard equivalent.
  const resize = sourceBetween('function initInspectorResize(', '// --- Environments');
  assert.match(resize, /ArrowLeft/);
  assert.match(resize, /ArrowRight/);
  assert.match(resize, /dblclick/);
});

test('each inspector tab selects exactly one panel and updates accessibility state', () => {
  const workspace = createWorkspace();
  for (const name of ['workflow', 'task', 'steps', 'json', 'sql']) {
    workspace.context.switchTab(name);
    assert.deepEqual(workspace.tabs.filter((tab) => tab.classList.contains('active')).map((tab) => tab.dataset.tab), [name]);
    assert.deepEqual(workspace.panels.filter((panel) => panel.classList.contains('active')).map((panel) => panel.id), ['tab-' + name]);
    assert.equal(workspace.tabs.filter((tab) => tab.tabIndex === 0).length, 1);
    assert.equal(workspace.elements['task-buttons'].hidden, !['task', 'steps'].includes(name));
  }
});

test('task selection opens details and preserves the Steps view', () => {
  const workspace = createWorkspace();
  workspace.context.switchTab('steps');
  workspace.context.selectTask(1);
  assert.equal(workspace.context.selectedTask, 1);
  assert.equal(workspace.context.activeInspectorTab, 'steps');
  assert.equal(workspace.elements.editor.dataset.mobileView, 'details');
  workspace.context.switchTab('workflow');
  workspace.context.selectTask(0);
  assert.equal(workspace.context.activeInspectorTab, 'task');
});

test('mobile view switch keeps pressed state synchronized', () => {
  const workspace = createWorkspace();
  for (const view of ['details', 'graph']) {
    workspace.context.setMobileView(view);
    assert.equal(workspace.elements.editor.dataset.mobileView, view);
    workspace.views.forEach((button) => assert.equal(button.attributes['aria-pressed'], String(button.dataset.view === view)));
  }
});

test('inspector tabs support arrow-key wrapping', () => {
  const workspace = createWorkspace();
  let prevented = false;
  workspace.context.handleInspectorTabKey({ key: 'ArrowLeft', target: workspace.tabs[0], preventDefault() { prevented = true; } });
  assert.equal(prevented, true);
  assert.equal(workspace.context.activeInspectorTab, 'sql');
  assert.equal(workspace.tabs[4].focused, true);
});

test('library toggle updates visibility and restores focus', () => {
  const workspace = createWorkspace();
  workspace.context.toggleLibrary(true);
  assert.equal(workspace.elements['library-backdrop'].hidden, false);
  assert.equal(workspace.elements['workflow-search'].focused, true);
  workspace.context.toggleLibrary(false);
  assert.equal(workspace.elements['library-backdrop'].hidden, true);
  assert.equal(workspace.elements['btn-library'].focused, true);
});

test('inspector expansion updates state and accessible label', () => {
  const workspace = createWorkspace();
  workspace.context.toggleInspectorWidth();
  assert.equal(workspace.elements.editor.classList.contains('inspector-wide'), true);
  assert.equal(workspace.elements['btn-inspector-expand'].attributes['aria-pressed'], 'true');
  workspace.context.toggleInspectorWidth();
  assert.equal(workspace.elements['btn-inspector-expand'].attributes['aria-label'], 'Expand inspector');
});

test('fit uses graph bounds and zoom is centered', () => {
  let viewport = { x: 10, y: 20, width: 800, height: 450 };
  const context = vm.createContext({
    currentViewBox: () => viewport,
    getGraphBounds: () => ({ x: -50, y: -60, width: 500, height: 300 }),
    setViewBox: (x, y, width, height) => { viewport = { x, y, width, height }; },
  });
  vm.runInContext(sourceBetween('function resetViewport(', 'function beginGraphTouch('), context);
  context.zoomGraphBy(0.8);
  assert.deepEqual(viewport, { x: 90, y: 65, width: 640, height: 360 });
  context.resetViewport();
  assert.deepEqual(viewport, { x: -50, y: -60, width: 500, height: 300 });
});