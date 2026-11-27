/* Workflower: the interface. The page keeps one open graph (S.g) that the user edits; S.base is what was loaded, so that an edit can
   be told from no edit. Everything that comes from Snowflake (names, SQL, comments, errors) is put in the page as text. */
(function () {
  'use strict';

  var WL = window.WfLayout, K = window.WfKit;
  var h = K.h, s = K.s, icon = K.icon, toast = K.toast, api = K.api;
  var $ = function (id) { return document.getElementById(id); };

  var PARAM_NAMES = ['USER_TASK_TIMEOUT_MS', 'SUSPEND_TASK_AFTER_NUM_FAILURES', 'USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE',
    'USER_TASK_MINIMUM_TRIGGER_INTERVAL_IN_SECONDS', 'TARGET_COMPLETION_INTERVAL', 'SERVERLESS_TASK_MIN_STATEMENT_SIZE',
    'SERVERLESS_TASK_MAX_STATEMENT_SIZE', 'TASK_AUTO_RETRY_ATTEMPTS'];

  var S = {
    session: null, sessionError: '',
    databases: null, schemas: null, database: '', schema: '',
    graphs: null, graphsError: '', graphsLoading: false,
    g: null, base: null, sel: null, rev: 0, loadingGraph: false,
    problems: [], problemsError: '', validating: false,
    plan: null,            // {rev, data, error, loading, applied}
    sql: null,             // {rev, text, error, loading}
    runs: null,            // {key, hours, loading, error, list, sel}
    runHours: 24, tab: 'problems',
    view: { k: 1, x: 0, y: 0 }, layout: null, layoutKey: '', fitPending: false,
    paramRows: null, vp: null
  };


  /* ============================== the data provider ==============================
     Interactive mode reads from the server. Viewer mode (the page opened as a file, with data.js beside it defining
     window.WORKFLOWER_DATA = {session, graphs:[Graph], runs:{root: [run]}}) reads the same shapes from that object and never calls /api. */
  var VIEWER = typeof window.WORKFLOWER_DATA === 'object' && window.WORKFLOWER_DATA !== null;

  var D = (function () {
    if (!VIEWER) return { get: function (path, query) { return api('GET', path, { query: query }); } };
    var data = window.WORKFLOWER_DATA;
    var graphs = (data.graphs || []).map(function (g) {
      var c = WL.clone(g);
      c.tasks = (c.tasks || []).map(function (t) { var x = WL.makeTask(t.name, t); if (!x.parameters || Array.isArray(x.parameters)) x.parameters = {}; x.after = [].concat(t.after || []); return x; });
      c.root = c.root || WL.deriveRoot(c.tasks);
      c.state = c.state || WL.graphState(c.tasks);
      c.incomplete = !!c.incomplete;
      return c;
    });
    function uniq(list) { return list.filter(function (v, i) { return v && list.indexOf(v) === i; }).sort(); }
    return {
      get: function (path, q) {
        q = q || {};
        var out;
        if (path === '/api/session') out = Object.assign({ backend: 'Snapshot', account: '', warehouse: '', role: '' }, data.session || {});
        else if (path === '/api/databases') out = { databases: uniq(graphs.map(function (g) { return g.database; })) };
        else if (path === '/api/schemas') out = { schemas: uniq(graphs.filter(function (g) { return g.database === q.database; }).map(function (g) { return g.schema; })) };
        else if (path === '/api/graphs') out = { graphs: graphs.filter(function (g) { return g.database === q.database && g.schema === q.schema; }) };
        else if (path === '/api/graph') {
          var f = graphs.filter(function (g) { return g.database === q.database && g.schema === q.schema && g.root === q.root; })[0];
          if (!f) return Promise.reject(new Error('This snapshot has no graph ' + q.root + '.'));
          out = { graph: f, problems: [] };
        } else if (path === '/api/runs') {
          var runs = data.runs || {};
          out = { runs: runs[q.database + '.' + q.schema + '.' + q.root] || runs[q.root] || [] };
        } else return Promise.reject(new Error('The viewer cannot call ' + path + '.'));
        return Promise.resolve(WL.clone(out));
      }
    };
  })();
  /* ============================== small helpers ============================== */

  function selTask() { return S.g && S.sel ? WL.findTask(S.g.tasks, S.sel) : null; }
  function hasUnsaved() { return !!(S.g && WL.isDirty(S.g, S.base)); }
  function where(g) { return [g.database, g.schema].filter(Boolean).join('.') || '(no database and schema)'; }
  function fullName(g) { return where(g) + '.' + (g.root || ''); }
  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : (many || one + 's')); }
  function reportError(err, context) { toast((context ? context + ': ' : '') + (err && err.message ? err.message : String(err)), { kind: 'error' }); }
  function isTyping(el) { return !!el && (/^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName) || el.isContentEditable); }
  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  function fillSelect(sel, values, current, placeholder) {
    sel.textContent = '';
    sel.appendChild(h('option', { value: '', text: placeholder }));
    values.forEach(function (v) { sel.appendChild(h('option', { value: v, text: v })); });
    sel.value = values.indexOf(current) >= 0 ? current : '';
  }

  function prepareGraph(view) {
    var g = WL.clone(view);
    g.tasks = (g.tasks || []).map(function (t) {
      var c = WL.makeTask(t.name, t);
      if (!c.parameters || Array.isArray(c.parameters)) c.parameters = {};
      c.after = (c.after || []).slice();
      return c;
    });
    g.root = WL.deriveRoot(g.tasks);
    g.state = WL.graphState(g.tasks);
    return g;
  }

  /* ============================== header and selectors ============================== */

  function renderConnection() {
    var box = $('connection');
    box.textContent = '';
    if (S.sessionError) { box.appendChild(h('span', { text: 'Not connected: ' + S.sessionError })); return; }
    if (!S.session) { box.textContent = 'Connecting to the server...'; return; }
    var x = S.session;
    box.appendChild(h('span', null, 'Connected to ', h('strong', { text: x.account || '(unknown account)' }), ' as role ', h('strong', { text: x.role || '(none)' }),
      ', warehouse ', h('strong', { text: x.warehouse || '(none)' }), x.backend ? ' (' + x.backend + ')' : ''));
  }

  function renderSelectors() {
    var db = $('sel-db'), sc = $('sel-schema');
    if (S.databases) {
      fillSelect(db, S.databases, S.database, S.databases.length ? 'Choose a database' : 'No databases are visible');
      db.disabled = !S.databases.length;
    }
    if (!S.database) { fillSelect(sc, [], '', 'Choose a database first'); sc.disabled = true; }
    else if (S.schemas) { fillSelect(sc, S.schemas, S.schema, S.schemas.length ? 'Choose a schema' : 'This database has no schemas'); sc.disabled = !S.schemas.length; }
    else { fillSelect(sc, [], '', 'Loading schemas...'); sc.disabled = true; }
  }

  async function loadDatabases() {
    try {
      S.databases = (await D.get('/api/databases')).databases || [];
    } catch (e) { S.databases = []; reportError(e, 'Could not list the databases'); }
    renderSelectors();
  }

  async function loadSchemas() {
    S.schemas = null;
    renderSelectors();
    if (!S.database) return;
    var db = S.database;
    try {
      var data = await D.get('/api/schemas', { database: db });
      if (db === S.database) S.schemas = data.schemas || [];
    } catch (e) { S.schemas = []; reportError(e, 'Could not list the schemas of ' + db); }
    renderSelectors();
  }

  /* Ask before anything that would throw away unsaved edits. */
  async function guardEdits(what) {
    if (!hasUnsaved()) return true;
    var g = S.g;
    return K.askConfirm({
      title: 'Discard your unsaved edits?',
      body: 'The graph ' + (g.root || '(no root)') + ' has edits that are not applied to Snowflake. ' + what + ' would discard them.',
      okLabel: 'Discard edits', danger: true
    });
  }

  async function chooseDatabase(db, opts) {
    var o = opts || {};
    if (!o.noGuard && !(await guardEdits('Switching database'))) { renderSelectors(); return false; }
    closeGraph();
    S.database = db; S.schema = ''; S.graphs = null; S.graphsError = '';
    renderGraphList();
    await loadSchemas();
    return true;
  }

  async function chooseSchema(schema, opts) {
    var o = opts || {};
    if (!o.noGuard && !(await guardEdits('Switching schema'))) { renderSelectors(); return false; }
    closeGraph();
    S.schema = schema; S.graphs = null; S.graphsError = '';
    renderSelectors();
    renderGraphList();
    if (schema) await loadGraphs();
    return true;
  }

  /* ============================== the graphs of the schema ============================== */

  async function loadGraphs() {
    if (!S.database || !S.schema) return;
    var db = S.database, sc = S.schema;
    S.graphsLoading = true; S.graphsError = '';
    renderGraphList();
    try {
      var data = await D.get('/api/graphs', { database: db, schema: sc });
      if (db === S.database && sc === S.schema) {
        S.graphs = (data.graphs || []).slice().sort(function (a, b) { return a.root < b.root ? -1 : a.root > b.root ? 1 : 0; });
      }
    } catch (e) {
      if (db === S.database && sc === S.schema) { S.graphs = null; S.graphsError = e.message; }
      reportError(e, 'Could not read the graphs of ' + db + '.' + sc);
    }
    S.graphsLoading = false;
    renderGraphList();
  }

  function renderGraphList() {
    var box = $('graph-list');
    box.textContent = '';
    $('graphs-where').textContent = S.database && S.schema ? S.database + '.' + S.schema : '';
    var items = [];
    if (S.g && S.g.origin !== 'installed') {
      items.push(h('div', { class: 'list-section', text: 'Open, not installed' }));
      items.push(h('ul', null, h('li', null, h('button', { type: 'button', class: 'graph-item', 'aria-current': 'true', onclick: function () { selectTask(S.sel || S.g.root); } },
        h('span', { class: 'root-name', text: S.g.root || '(no root)' }),
        h('span', { class: 'meta' }, h('span', { class: 'badge notset' }, icon('pencil'), S.g.origin === 'new' ? 'new, not installed' : 'imported, not installed'),
          h('span', { text: plural(S.g.tasks.length, 'task') }))))));
    }
    if (!S.database) items.push(h('p', { class: 'empty-note', text: 'Choose a database and a schema above to list their task graphs.' }));
    else if (!S.schema) items.push(h('p', { class: 'empty-note', text: 'Choose a schema of ' + S.database + '.' }));
    else if (S.graphsLoading) items.push(h('p', { class: 'empty-note', text: 'Loading the graphs of ' + S.database + '.' + S.schema + '...' }));
    else if (S.graphsError) items.push(h('p', { class: 'empty-note', role: 'alert' }, 'The graphs could not be read: ' + S.graphsError));
    else if (S.graphs && !S.graphs.length) items.push(h('p', { class: 'empty-note', text: 'This schema has no tasks (that the role can see). Start with New graph, or import a file.' }));
    else if (S.graphs) {
      items.push(h('div', { class: 'list-section', text: plural(S.graphs.length, 'graph') + ' in this schema' }));
      var ul = h('ul');
      S.graphs.forEach(function (g) {
        var open = S.g && S.g.origin === 'installed' && S.g.root === g.root && S.g.database === g.database && S.g.schema === g.schema;
        var state = g.state === 'started' ? 'started' : 'suspended';
        ul.appendChild(h('li', null, h('button', { type: 'button', class: 'graph-item', 'aria-current': open ? 'true' : null, onclick: function () { openGraph(g.root); } },
          h('span', { class: 'root-name', text: g.root }),
          h('span', { class: 'meta' },
            h('span', { class: 'badge ' + state }, icon(state), state),
            h('span', { text: plural((g.tasks || []).length, 'task') }),
            g.incomplete ? h('span', { class: 'badge warn', title: 'The role cannot see every task of this graph, so what is shown is incomplete.' }, icon('warning'), 'incomplete') : null))));
      });
      items.push(ul);
    }
    K.appendKids(box, items);
  }

  /* ============================== opening, closing, and replacing the open graph ============================== */

  function closeGraph() {
    S.g = null; S.base = null; S.sel = null; S.problems = []; S.problemsError = ''; S.plan = null; S.sql = null; S.runs = null;
    S.rev++; S.layout = null; S.layoutKey = '';
    renderAll();
  }

  function setOpenGraph(view, problems, origin, extra) {
    var e = extra || {};
    S.g = prepareGraph(view);
    S.g.origin = origin;
    S.g.source = e.source || '';
    S.g.notes = e.notes || [];
    S.base = WL.clone(S.g);
    S.sel = e.keepSel && WL.findTask(S.g.tasks, e.keepSel) ? e.keepSel : S.g.root;
    S.problems = problems || []; S.problemsError = '';
    S.rev++;
    if (!e.keepPlan) S.plan = null;
    S.sql = null; S.paramRows = null;
    S.runs = null;
    if (!e.keepView) S.fitPending = true;
    renderAll();
    if (origin === 'installed') loadRuns();
  }

  async function openGraph(root, opts) {
    var o = opts || {};
    if (!o.noGuard && !(await guardEdits('Opening another graph'))) return false;
    S.loadingGraph = true;
    renderCanvas();
    try {
      var data = await D.get('/api/graph', { database: S.database, schema: S.schema, root: root });
      S.loadingGraph = false;
      setOpenGraph(data.graph, data.problems, 'installed');
      return true;
    } catch (e) {
      S.loadingGraph = false;
      renderCanvas();
      reportError(e, 'Could not open ' + root);
      return false;
    }
  }

  /* The open, installed graph read again; the selection stays. */
  async function reloadOpenGraph(opts) {
    var g = S.g;
    if (!g || g.origin !== 'installed') return false;
    try {
      var data = await D.get('/api/graph', { database: g.database, schema: g.schema, root: g.root });
      setOpenGraph(data.graph, data.problems, 'installed', { keepSel: S.sel, keepView: true, keepPlan: !!(opts && opts.keepPlan) });
      return true;
    } catch (e) { reportError(e, 'Could not read ' + g.root + ' again'); return false; }
  }

  async function refresh() {
    if (S.g && S.g.origin === 'installed' && hasUnsaved()) {
      var ok = await K.askConfirm({ title: 'Reload and discard your edits?', body: 'Refresh reads ' + S.g.root + ' from Snowflake again. Your unsaved edits to it would be discarded.', okLabel: 'Discard edits and refresh', danger: true });
      if (!ok) return;
    }
    await loadDatabases();
    if (S.database) await loadSchemas();
    if (S.database && S.schema) await loadGraphs();
    if (S.g && S.g.origin === 'installed') await reloadOpenGraph();
    toast('Read again from Snowflake.', { kind: 'ok', ms: 2500 });
  }

  /* ============================== editing ============================== */

  var validateTimer = null, canvasTimer = null, validateSeq = 0;

  /* Call after any change of the tasks. */
  function touch(opts) {
    var o = opts || {};
    S.g.root = WL.deriveRoot(S.g.tasks);
    S.g.state = WL.graphState(S.g.tasks);
    S.rev++;
    renderGraphBar();
    renderNotices();
    renderGraphList();
    if (o.canvas !== false) scheduleCanvas();
    renderPlan();
    if (S.tab === 'sql') scheduleSql();
    scheduleValidate();
    updateCanvasTools();
  }

  function scheduleCanvas() {
    if (canvasTimer) return;
    canvasTimer = setTimeout(function () { canvasTimer = null; renderCanvas(); }, 40);
  }

  function scheduleValidate() {
    if (VIEWER) return;
    clearTimeout(validateTimer);
    S.validating = true;
    renderProblems();
    validateTimer = setTimeout(runValidate, 450);
  }

  async function runValidate() {
    if (!S.g) { S.validating = false; return; }
    var seq = ++validateSeq;
    try {
      var data = await api('POST', '/api/validate', { body: { graph: WL.graphPayload(S.g) }, quiet: true });
      if (seq !== validateSeq) return;
      S.problems = data.problems || []; S.problemsError = '';
    } catch (e) {
      if (seq !== validateSeq) return;
      S.problemsError = e.message;
      toast('The graph could not be checked: ' + e.message, { kind: 'error' });
    }
    S.validating = false;
    renderProblems();
    renderTabCount();
    scheduleCanvas();
    if (S.tab === 'sql') scheduleSql();
  }

  function setField(name, key, value, canvas) {
    if (VIEWER) return;
    var t = WL.findTask(S.g.tasks, name);
    if (!t) return;
    t[key] = value;
    touch({ canvas: canvas });
  }

  function applyRename(oldName, newName) {
    if (VIEWER) return { ok: false, error: "The viewer is read-only." };
    var r = WL.renameTask(S.g.tasks, oldName, newName);
    if (!r.ok) return r;
    var refs = 0;
    S.g.tasks.forEach(function (t) { refs += (t.after || []).filter(function (a) { return a === oldName; }).length + (t.finalize === oldName ? 1 : 0); });
    S.g.tasks = r.tasks;
    if (S.sel === oldName) S.sel = newName;
    touch();
    renderInspector(true);
    if (refs) toast('Renamed ' + oldName + ' to ' + newName + '; ' + plural(refs, 'reference') + ' to it in other tasks updated.', { kind: 'info', ms: 4000 });
    r.refs = refs;
    return r;
  }

  function addTask() {
    if (VIEWER) return null;
    if (!S.g) { toast('Open a graph first, or start a new one.', { kind: 'info' }); return null; }
    var r = WL.addTask(S.g.tasks, S.sel);
    S.g.tasks = r.tasks;
    S.sel = r.name;
    touch();
    renderInspector();
    var el = $('f-name');
    if (el) { el.focus(); el.select(); }
    return r.name;
  }

  function deleteSelected() {
    if (VIEWER) return false;
    if (!S.g || !S.sel) { toast('Select a task first.', { kind: 'info' }); return false; }
    var name = S.sel, before = WL.clone(S.g.tasks);
    var t = WL.findTask(S.g.tasks, name);
    var r = WL.deleteTask(S.g.tasks, name);
    S.g.tasks = r.tasks;
    S.sel = (t && t.after && t.after[0] && WL.findTask(r.tasks, t.after[0]) ? t.after[0] : WL.deriveRoot(r.tasks));
    touch();
    renderInspector();
    var msg = 'Deleted task ' + name + '.';
    if (r.rewired.length) msg += ' ' + plural(r.rewired.length, 'task') + ' that came after it now follow its predecessors (' + r.rewired.join(', ') + ').';
    if (r.leftRootless.length) msg += ' ' + r.leftRootless.join(', ') + ' now has no predecessor, so it is a second root: see Problems.';
    toast(msg, { kind: 'info', action: { label: 'Undo', run: function () { S.g.tasks = before; S.sel = name; touch(); renderInspector(); } } });
    return true;
  }

  async function discardChanges() {
    if (VIEWER) return;
    if (!S.g) return;
    var g = S.g;
    if (g.origin === 'installed') {
      if (!hasUnsaved()) { toast('There are no unsaved edits.', { kind: 'info', ms: 2500 }); return; }
      var ok = await K.askConfirm({ title: 'Discard your edits?', body: 'The graph ' + g.root + ' goes back to how it was when it was read from Snowflake.', okLabel: 'Discard edits', danger: true });
      if (!ok) return;
      var keep = S.sel;
      S.g = WL.clone(S.base);
      S.sel = WL.findTask(S.g.tasks, keep) ? keep : S.g.root;
      S.rev++; S.plan = null; S.sql = null; S.paramRows = null;
      renderAll();
      scheduleValidate();
    } else {
      var ok2 = await K.askConfirm({ title: 'Discard this graph?', body: 'The graph ' + (g.root || '') + ' is not installed in Snowflake. Discarding closes it and its edits are lost.', okLabel: 'Discard graph', danger: true });
      if (!ok2) return;
      closeGraph();
    }
  }

  /* ============================== new graph and import ============================== */

  async function newGraph() {
    if (VIEWER) return;
    if (!S.database || !S.schema) { toast('Choose a database and a schema first: a new graph is made in the schema that is selected.', { kind: 'info' }); return; }
    if (!(await guardEdits('Starting a new graph'))) return;
    var dlg = $('dlg-new');
    var taken = {};
    (S.graphs || []).forEach(function (g) { (g.tasks || []).forEach(function (t) { taken[t.name] = true; }); });
    var root = 'NEW_ROOT', n = 2;
    while (taken[root]) root = 'NEW_ROOT_' + n++;
    var child = 'NEW_TASK'; n = 2;
    while (taken[child]) child = 'NEW_TASK_' + n++;
    $('new-root').value = root; $('new-child').value = child;
    $('dlg-new-error').textContent = '';
    $('dlg-new-where').textContent = 'It will be made for ' + S.database + '.' + S.schema + ' and is not installed until you plan and apply it.';
    var ok = $('dlg-new-ok'), cancel = $('dlg-new-cancel');
    var submit = function () {
      var r = $('new-root').value, c = $('new-child').value, err = '';
      if (!r.trim() || !c.trim()) err = 'Both names are needed.';
      else if (r === c) err = 'The two tasks need different names.';
      else if (taken[r] || taken[c]) err = "A task called '" + (taken[r] ? r : c) + "' already exists in this schema; task names are unique in a schema.";
      $('dlg-new-error').textContent = err;
      if (!err) dlg.close('ok');
    };
    ok.onclick = submit;
    cancel.onclick = function () { dlg.close('cancel'); };
    dlg.onkeydown = function (e) { if (e.key === 'Enter' && e.target.tagName === 'INPUT') { e.preventDefault(); submit(); } };
    dlg.returnValue = '';
    var closed = K.waitClose(dlg);
    dlg.showModal();
    $('new-root').focus(); $('new-root').select();
    if ((await closed) !== 'ok') return;
    makeNewGraph($('new-root').value, $('new-child').value);
  }

  function makeNewGraph(rootName, childName) {
    var wh = S.session && S.session.warehouse ? S.session.warehouse : null;
    var tasks = [
      WL.makeTask(rootName, { definition: 'SELECT 1', schedule: '1440 MINUTE', warehouse: wh }),
      WL.makeTask(childName, { definition: 'SELECT 1', after: [rootName], warehouse: wh })
    ];
    setOpenGraph({ database: S.database, schema: S.schema, root: rootName, tasks: tasks }, [], 'new');
    runValidate();
    toast('A skeleton graph: a root with a schedule and one child. Edit the SQL, then Plan changes and Apply.', { kind: 'info' });
    return true;
  }

  async function importText(text, fileName) {
    if (VIEWER) return false;
    if (!(await guardEdits('Importing a file'))) return false;
    try {
      var data = await api('POST', '/api/import', { body: { text: text } });
      var g = data.graph, notes = [];
      if (!g.database && S.database) { g.database = S.database; notes.push('The file names no database; ' + S.database + ' (selected) is used.'); }
      if (!g.schema && S.schema) { g.schema = S.schema; notes.push('The file names no schema; ' + S.schema + ' (selected) is used.'); }
      setOpenGraph(g, data.problems, 'imported', { source: fileName || 'file', notes: notes });
      return true;
    } catch (e) { reportError(e, 'Could not import ' + (fileName || 'the file')); return false; }
  }

  async function importFile(file) {
    var text;
    try { text = await file.text(); } catch (e) { reportError(e, 'Could not read ' + file.name); return false; }
    return importText(text, file.name);
  }

  /* ============================== the graph bar and the notices ============================== */

  function opReason() {
    if (!S.g) return 'Open a graph first.';
    if (S.g.origin !== 'installed') return 'this graph is not installed in Snowflake yet; plan and apply it first.';
    if (hasUnsaved()) return 'there are unsaved edits; apply or discard them first, so that the operation acts on what is installed.';
    return '';
  }

  function renderGraphBar() {
    var bar = $('graph-bar');
    bar.textContent = '';
    var g = S.g;
    if (!g) {
      bar.appendChild(h('div', { class: 'graph-title' }, h('span', { class: 'muted', text: S.loadingGraph ? 'Loading the graph...' : 'No graph is open.' })));
      return;
    }
    var dirty = hasUnsaved();
    if (VIEWER) {
      bar.appendChild(h('div', { class: 'graph-title' }, h('span', { class: 'root', text: g.root || '(no root task)' }), h('span', { class: 'where', text: where(g) }),
        h('span', { class: 'badge ' + (g.state === 'started' ? 'started' : 'suspended') }, icon(g.state === 'started' ? 'started' : 'suspended'), g.state === 'started' ? 'started' : 'suspended'),
        h('span', { class: 'badge notset' }, plural(g.tasks.length, 'task')),
        g.incomplete ? h('span', { class: 'badge warn' }, icon('warning'), 'incomplete') : null,
        h('span', { class: 'badge info' }, icon('info'), 'read-only snapshot')));
      return;
    }
    var state = g.state === 'started' ? 'started' : 'suspended';
    var title = h('div', { class: 'graph-title' },
      h('span', { class: 'root', text: g.root || '(no root task)' }),
      h('span', { class: 'where', text: where(g) }),
      h('span', { class: 'badge ' + state, title: 'The state of the root task' }, icon(state), state),
      h('span', { class: 'badge notset' }, plural(g.tasks.length, 'task')),
      g.incomplete ? h('span', { class: 'badge warn', title: 'The role cannot see every task of this graph.' }, icon('warning'), 'incomplete') : null,
      g.origin !== 'installed' ? h('span', { class: 'badge info' }, icon('pencil'), 'not installed') : null,
      dirty ? h('span', { class: 'badge warn unsaved', role: 'status' }, icon('pencil'), 'Unsaved edits') : h('span', { class: 'badge notset unsaved', role: 'status' }, icon('check'), 'No unsaved edits'));
    var reason = opReason();
    var opBtn = function (id, label, action, tip) {
      return h('button', { type: 'button', id: id, 'aria-disabled': reason ? 'true' : null, title: reason || tip, onclick: function () { operate(action); } }, label);
    };
    var actions = h('div', { class: 'graph-actions', role: 'toolbar', 'aria-label': 'Actions for this graph' },
      h('button', { type: 'button', id: 'btn-export', title: 'Download this graph as a .json file', onclick: exportGraph }, 'Export'),
      h('span', { class: 'sep' }),
      opBtn('btn-resume', 'Resume', 'resume', 'Start the graph'),
      opBtn('btn-suspend', 'Suspend', 'suspend', 'Stop the graph'),
      opBtn('btn-run', 'Run now', 'run', 'Run the graph now'),
      opBtn('btn-retry', 'Retry last run', 'retry', 'Continue the last run from the tasks that failed'),
      h('span', { class: 'sep' }),
      h('button', { type: 'button', id: 'btn-discard', 'aria-disabled': dirty || g.origin !== 'installed' ? null : 'true', title: dirty ? 'Throw away the edits' : g.origin === 'installed' ? 'There are no edits to discard' : 'Close this graph',
        onclick: discardChanges }, 'Discard changes'));
    bar.appendChild(title);
    bar.appendChild(actions);
    if (reason) bar.appendChild(h('div', { class: 'graph-hint', text: 'Resume, Suspend, Run now and Retry are off: ' + reason }));
  }

  function renderNotices() {
    var box = $('notices');
    box.textContent = '';
    var g = S.g;
    if (VIEWER) { box.appendChild(h('div', { class: 'notice info', role: 'status' }, icon('info'), 'Viewer: a read-only snapshot, opened without the Workflower server. Plan, Apply, running and editing need the server (Start-Workflower).')); }
    if (!g) return;
    if (g.origin === 'imported') {
      var differs = (g.database !== S.database || g.schema !== S.schema);
      box.appendChild(h('div', { class: 'notice info', role: 'status' }, icon('info'), h('div', null,
        'Imported from the file ', h('strong', { text: g.source || '(file)' }), '. It names ', h('strong', { text: where(g) }),
        differs ? (S.database && S.schema ? ', which is not the schema selected above (' + S.database + '.' + S.schema + '). Plan and Apply work on ' + where(g) + '.' : '.') : ', the schema selected above.',
        ' It is not installed until you plan and apply it.', (g.notes || []).map(function (n) { return ' ' + n; }))));
    } else if (g.origin === 'new') {
      box.appendChild(h('div', { class: 'notice info', role: 'status' }, icon('info'), 'A new graph for ' + where(g) + ', not installed. Edit it, then Plan changes and Apply to create it.'));
    }
    if (g.incomplete) {
      box.appendChild(h('div', { class: 'notice warn', role: 'status' }, icon('warning'),
        'This graph is incomplete: the role used here cannot see every one of its tasks, so what is drawn is only a part. A plan made from it may drop or change tasks you cannot see.'));
    }
  }

  async function exportGraph() {
    if (!S.g) return;
    try {
      var data = await api('POST', '/api/export', { body: { graph: WL.graphPayload(S.g) } });
      K.download(data.fileName, data.text, 'application/json;charset=utf-8');
      toast('Exported to ' + data.fileName + ' (see your downloads).', { kind: 'ok', ms: 3500 });
    } catch (e) { reportError(e, 'Could not export'); }
  }

  var OPS = {
    resume: { title: function (g) { return 'Resume ' + g.root + '?'; }, body: function (g) { return 'This starts every suspended task of ' + fullName(g) + ', the children before the root. The root then runs on its schedule or condition.'; }, ok: 'Resume graph', done: 'resumed' },
    suspend: { title: function (g) { return 'Suspend ' + g.root + '?'; }, body: function (g) { return 'This suspends the root of ' + fullName(g) + ' first, so that nothing new starts, then its other started tasks.'; }, ok: 'Suspend graph', done: 'suspended' },
    run: { title: function (g) { return 'Run ' + g.root + ' now?'; }, body: function (g) { return 'This executes the root task of ' + fullName(g) + ' now, outside its schedule. The graph then runs on its own.'; }, ok: 'Run now', done: 'started a run of' },
    retry: { title: function (g) { return 'Retry the last run of ' + g.root + '?'; }, body: function (g) { return 'This continues the last run of ' + fullName(g) + ' from the tasks that failed.'; }, ok: 'Retry last run', done: 'retried the last run of' }
  };

  async function operate(action) {
    var reason = opReason();
    if (reason) { toast(reason.charAt(0).toUpperCase() + reason.slice(1), { kind: 'info' }); return false; }
    var g = S.g, def = OPS[action];
    var ok = await K.askConfirm({ title: def.title(g), body: def.body(g), okLabel: def.ok });
    if (!ok) return false;
    try {
      var data = await api('POST', '/api/operate', { body: { database: g.database, schema: g.schema, root: g.root, action: action } });
      toast('Done: ' + def.done + ' ' + g.root + '.', { kind: 'ok' });
      if (!data.graph) toast('The graph ' + g.root + ' can no longer be read; it may have been dropped.', { kind: 'error' });
      await loadGraphs();
      await reloadOpenGraph();
      return true;
    } catch (e) { reportError(e, 'Could not ' + action + ' ' + g.root); return false; }
  }

  /* ============================== the canvas ============================== */

  

  function fitText(el, full, maxW) {
    el.textContent = full;
    var len;
    try { len = el.getComputedTextLength(); } catch (e) { return; }
    if (!len || len <= maxW) return;
    var lo = 0, hi = full.length;
    while (lo < hi) {
      var mid = Math.ceil((lo + hi) / 2);
      el.textContent = full.slice(0, mid) + '…';
      if (el.getComputedTextLength() <= maxW) lo = mid; else hi = mid - 1;
    }
    el.textContent = full.slice(0, lo) + '…';
  }

  function overlayRun() {
    if (!S.runs || !S.runs.list) return null;
    if (S.runs.sel) { for (var i = 0; i < S.runs.list.length; i++) if (S.runs.list[i].runId === S.runs.sel) return S.runs.list[i]; }
    return WL.pickOverlayRun(S.runs.list);
  }

  function outcomeMap(run) {
    var map = {};
    if (!run) return map;
    (run.tasks || []).forEach(function (t) {
      var cur = map[t.task];
      if (!cur || (Number(t.attempt) || 0) >= (Number(cur.attempt) || 0)) map[t.task] = t;
    });
    return map;
  }

  var OUT_ICON = { ok: 'check', bad: 'cross', skip: 'skip', run: 'run', wait: 'clock' };

  function describeNode(t, isRoot, outcome, sev, probs) {
    var parts = [t.name, (t.state ? t.state : 'state not set'), t.warehouse ? 'warehouse ' + t.warehouse : 'serverless'];
    if (t.schedule) parts.push('schedule ' + t.schedule);
    if (t.condition) parts.push('has a WHEN condition');
    if (t.finalize) parts.push('finalizer of ' + t.finalize);
    if (outcome) parts.push('last run: ' + WL.runStateInfo(outcome.state).label);
    if (sev) parts.push(probs.join('; '));
    if (isRoot) parts.push('root');
    return parts.join(', ');
  }

  function renderCanvas() {
    var svg = $('canvas');
    var focusName = null;
    if (document.activeElement && svg.contains(document.activeElement) && document.activeElement.getAttribute) focusName = document.activeElement.getAttribute('data-name');
    svg.textContent = '';
    var marker = function (id, cls) {
      return s('marker', { id: id, viewBox: '0 0 10 10', refX: '9', refY: '5', markerWidth: '10', markerHeight: '10', markerUnits: 'userSpaceOnUse', orient: 'auto' }, s('path', { d: 'M0,0 L10,5 L0,10 z', class: cls }));
    };
    svg.appendChild(s('defs', null, marker('arrow', 'arrow-fill'), marker('arrow-active', 'arrow-fill active')));
    S.vp = s('g', { id: 'viewport' });
    svg.appendChild(S.vp);
    var empty = $('canvas-empty');
    if (!S.g) {
      empty.textContent = S.loadingGraph ? 'Loading the graph...' : 'No graph is open. Choose a graph on the left, start a new one, or import a file.';
      $('canvas-legend').textContent = '';
      S.layout = null;
      updateCanvasTools();
      return;
    }
    if (!S.g.tasks.length) { empty.textContent = 'This graph has no tasks. Use Add task.'; } else { empty.textContent = ''; }
    var key = JSON.stringify(S.g.tasks.map(function (t) { return [t.name, t.after, t.finalize]; }));
    if (key !== S.layoutKey || !S.layout) { S.layout = WL.layoutGraph(S.g.tasks); S.layoutKey = key; }
    var layout = S.layout;
    var run = overlayRun(), outs = outcomeMap(run);
    var worst = WL.worstByTask(S.problems);
    var byTask = {};
    S.problems.forEach(function (p) { if (p.task) (byTask[p.task] = byTask[p.task] || []).push(p.message); });
    var rootName = S.g.root;
    var fits = [];

    var edgeLayer = s('g', { class: 'edges' });
    layout.edges.forEach(function (e) {
      var active = S.sel && (e.from === S.sel || e.to === S.sel);
      edgeLayer.appendChild(s('path', { d: e.d, class: 'edge ' + e.kind + (active ? ' active' : ''), 'marker-end': 'url(#' + (active ? 'arrow-active' : 'arrow') + ')' },
        s('title', null, e.kind === 'finalize' ? e.to + ' finalizes ' + e.from + ' (runs after the whole graph)' : e.to + ' runs after ' + e.from)));
    });
    S.vp.appendChild(edgeLayer);

    var nodeLayer = s('g', { class: 'nodes' });
    layout.nodes.forEach(function (n) {
      var t = WL.findTask(S.g.tasks, n.name);
      var out = outs[n.name] || null;
      var outInfo = out ? WL.runStateInfo(out.state) : null;
      var isRoot = n.name === rootName;
      var sev = worst[n.name] || null;
      var cls = 'node' + (S.sel === n.name ? ' selected' : '') + (outInfo ? ' out-' + outInfo.kind : '');
      var g = s('g', { class: cls, transform: 'translate(' + n.x + ',' + n.y + ')', tabindex: '0', role: 'button', 'data-name': n.name, 'aria-pressed': S.sel === n.name ? 'true' : 'false',
        'aria-label': describeNode(t, isRoot, out, sev, byTask[n.name] || []) });
      g.appendChild(s('title', null, describeNode(t, isRoot, out, sev, byTask[n.name] || [])));
      g.appendChild(s('rect', { class: 'sel-ring', x: -6, y: -6, width: n.w + 12, height: n.h + 12, rx: 15 }));
      g.appendChild(s('rect', { class: 'box', x: 0, y: 0, width: n.w, height: n.h, rx: 10 }));
      var nameEl = s('text', { class: 'name', x: 14, y: 24 });
      g.appendChild(nameEl);
      fits.push([nameEl, t.name, n.w - 28 - (sev ? 12 : 0)]);
      var st = t.state === 'started' ? 'started' : t.state === 'suspended' ? 'suspended' : 'notset';
      g.appendChild(s('circle', { class: 'state-dot ' + st, cx: 20, cy: 43, r: 5 }));
      g.appendChild(s('text', { class: 'line strong', x: 32, y: 47 }, st === 'notset' ? 'state not set' : st));
      var hasWhen = !!t.condition;
      if (hasWhen) {
        g.appendChild(s('rect', { class: 'pill-bg when', x: n.w - 14 - 50, y: 34, width: 50, height: 18, rx: 9 }));
        g.appendChild(s('text', { class: 'tiny pill-text when', x: n.w - 14 - 25, y: 47, 'text-anchor': 'middle' }, 'WHEN'));
      }
      var size = t.parameters && t.parameters.USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE;
      var compute = t.warehouse ? 'Warehouse ' + t.warehouse : 'Serverless' + (size ? ' (' + size + ')' : '');
      var cEl = s('text', { class: 'line', x: 14, y: 64 });
      g.appendChild(cEl);
      fits.push([cEl, compute, n.w - 28]);
      var third = t.schedule ? 'Schedule: ' + t.schedule : t.finalize ? 'Finalizer of ' + t.finalize : isRoot ? 'Root, no schedule' : '';
      if (third) {
        var sEl = s('text', { class: 'line', x: 14, y: 79 });
        g.appendChild(sEl);
        fits.push([sEl, third, n.w - 28]);
      }
      if (outInfo) {
        var label = outInfo.label, pw = 30 + label.length * 6.2;
        g.appendChild(s('rect', { class: 'pill-bg ' + outInfo.kind, x: n.w - pw - 8, y: -11, width: pw, height: 20, rx: 10 }));
        g.appendChild(K.iconAt(OUT_ICON[outInfo.kind] || 'clock', n.w - pw - 8 + 6, -8, 13, outInfo.kind));
        g.appendChild(s('text', { class: 'tiny pill-text ' + outInfo.kind, x: n.w - pw - 8 + 22, y: 3 }, label));
      }
      if (sev) {
        var mx = 4, my = -2;
        if (sev === 'warning') g.appendChild(s('path', { class: 'mark-bg warning', d: 'M' + mx + ',' + (my - 10) + ' L' + (mx + 11) + ',' + (my + 9) + ' L' + (mx - 11) + ',' + (my + 9) + ' Z' }));
        else if (sev === 'info') g.appendChild(s('rect', { class: 'mark-bg info', x: mx - 9, y: my - 9, width: 18, height: 18, rx: 4 }));
        else g.appendChild(s('circle', { class: 'mark-bg error', cx: mx, cy: my, r: 10 }));
        g.appendChild(s('text', { class: 'mark-glyph', x: mx, y: my + 4.5 }, sev === 'info' ? 'i' : '!'));
      }
      g.addEventListener('click', function (ev) { ev.stopPropagation(); selectTask(n.name); });
      g.addEventListener('keydown', function (ev) { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); selectTask(n.name); } });
      nodeLayer.appendChild(g);
    });
    S.vp.appendChild(nodeLayer);
    fits.forEach(function (f) { fitText(f[0], f[1], f[2]); });

    var legend = $('canvas-legend');
    if (S.g.origin !== 'installed') legend.textContent = 'Outlines show run outcomes; this graph is not installed, so it has no runs.';
    else if (!S.runs || S.runs.loading) legend.textContent = 'Loading the runs...';
    else if (S.runs.error) legend.textContent = 'Run outcomes are not shown: ' + S.runs.error;
    else if (run) legend.textContent = 'Outline and badge: outcome in the ' + (S.runs.sel ? 'selected' : 'last') + ' run, ' + WL.formatTime(run.scheduled || run.started) + ' (' + WL.runStateInfo(run.state).label + ').';
    else legend.textContent = 'No finished run in the last ' + S.runs.hours + ' hours, so no outcomes are shown.';

    applyView();
    updateCanvasTools();
    if (S.fitPending) { S.fitPending = false; fitView(); }
    if (focusName) { var again = svg.querySelector('[data-name="' + (window.CSS && CSS.escape ? CSS.escape(focusName) : focusName.replace(/"/g, '\\"')) + '"]'); if (again) again.focus(); }
  }

  function applyView() {
    if (S.vp) S.vp.setAttribute('transform', 'translate(' + S.view.x.toFixed(1) + ',' + S.view.y.toFixed(1) + ') scale(' + S.view.k.toFixed(4) + ')');
    $('zoom-level').textContent = Math.round(S.view.k * 100) + '%';
  }

  function canvasSize() { var r = $('canvas').getBoundingClientRect(); return { w: r.width, h: r.height, left: r.left, top: r.top }; }

  function fitView() {
    if (!S.layout || !S.layout.nodes.length) return;
    var c = canvasSize();
    if (!c.w || !c.h) return;
    var top = 46;
    var k = Math.min(1, (c.w - 24) / S.layout.width, (c.h - 24 - top) / S.layout.height);
    k = Math.max(0.08, k);
    S.view = { k: k, x: (c.w - S.layout.width * k) / 2, y: top + Math.max(0, (c.h - top - S.layout.height * k) / 2) };
    applyView();
  }

  function zoomAt(px, py, factor) {
    var k0 = S.view.k, k1 = Math.min(2.5, Math.max(0.08, k0 * factor));
    S.view.x = px - (px - S.view.x) * (k1 / k0);
    S.view.y = py - (py - S.view.y) * (k1 / k0);
    S.view.k = k1;
    applyView();
  }

  function zoomCentre(factor) { var c = canvasSize(); zoomAt(c.w / 2, c.h / 2, factor); }

  function actualSize() { var c = canvasSize(); zoomAt(c.w / 2, c.h / 2, 1 / S.view.k); }

  /* Pan so that a node is in view. */
  function revealNode(name) {
    if (!S.layout || !S.layout.nodeByName[name]) return;
    var n = S.layout.nodeByName[name], c = canvasSize(), v = S.view;
    var x0 = n.x * v.k + v.x, y0 = n.y * v.k + v.y, x1 = x0 + n.w * v.k, y1 = y0 + n.h * v.k;
    var m = 30, dx = 0, dy = 0;
    if (x0 < m) dx = m - x0; else if (x1 > c.w - m) dx = c.w - m - x1;
    if (y0 < m + 40) dy = m + 40 - y0; else if (y1 > c.h - m) dy = c.h - m - y1;
    if (dx || dy) { v.x += dx; v.y += dy; applyView(); }
  }

  function wireCanvas() {
    var svg = $('canvas'), drag = null;
    svg.addEventListener('pointerdown', function (e) {
      if (e.button !== 0 || (e.target.closest && e.target.closest('.node'))) return;
      drag = { x: e.clientX, y: e.clientY, vx: S.view.x, vy: S.view.y, moved: false, id: e.pointerId };
      try { svg.setPointerCapture(e.pointerId); } catch (err) { /* not capturable: the drag still works over the canvas */ }
      svg.classList.add('panning');
    });
    svg.addEventListener('pointermove', function (e) {
      if (!drag || e.pointerId !== drag.id) return;
      var dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      if (Math.abs(dx) + Math.abs(dy) > 4) drag.moved = true;
      S.view.x = drag.vx + dx; S.view.y = drag.vy + dy;
      applyView();
    });
    var end = function (e) {
      if (!drag || e.pointerId !== drag.id) return;
      var wasClick = !drag.moved;
      drag = null;
      svg.classList.remove('panning');
      if (wasClick && e.type === 'pointerup' && S.sel) { S.sel = null; renderCanvas(); renderInspector(); }
    };
    svg.addEventListener('pointerup', end);
    svg.addEventListener('pointercancel', end);
    svg.addEventListener('wheel', function (e) {
      e.preventDefault();
      var c = canvasSize();
      var dy = e.deltaY * (e.deltaMode === 1 ? 33 : 1);
      zoomAt(e.clientX - c.left, e.clientY - c.top, Math.exp(-dy * (e.ctrlKey ? 0.01 : 0.0016)));
    }, { passive: false });
    $('btn-fit').addEventListener('click', fitView);
    $('btn-100').addEventListener('click', actualSize);
    $('btn-zoom-in').addEventListener('click', function () { zoomCentre(1.25); });
    $('btn-zoom-out').addEventListener('click', function () { zoomCentre(0.8); });
    $('btn-add').addEventListener('click', addTask);
    $('btn-delete').addEventListener('click', deleteSelected);
  }

  function updateCanvasTools() {
    $('btn-add').disabled = !S.g;
    $('btn-delete').disabled = !S.g || !S.sel;
    $('btn-delete').title = !S.g ? 'Open a graph first' : !S.sel ? 'Select a task first' : 'Delete the selected task (' + S.sel + ') with the Del key';
    $('btn-fit').disabled = !S.g; $('btn-100').disabled = !S.g;
  }

  function selectTask(name, opts) {
    var o = opts || {};
    if (!S.g || !WL.findTask(S.g.tasks, name)) return;
    S.sel = name;
    S.paramRows = null;
    renderCanvas();
    renderInspector();
    renderTabsSelection();
    if (o.reveal) revealNode(name);
  }

  /* ============================== the inspector ============================== */

  function focusKeyOf(el) { return el && el.getAttribute ? el.getAttribute('data-focus') : null; }

  function renderInspector(keepFocus) {
    var box = $('inspector');
    var fk = keepFocus ? focusKeyOf(document.activeElement) : null;
    box.textContent = '';
    $('h-inspector').textContent = 'Task';
    if (!S.g) { box.appendChild(h('p', { class: 'empty-inspector', text: 'No graph is open. Choose a graph on the left, start a new one, or import a file.' })); return; }
    var t = selTask();
    if (!t) {
      box.appendChild(h('p', { class: 'empty-inspector', text: S.g.tasks.length ? 'Select a task in the graph to see and edit it. This graph has ' + plural(S.g.tasks.length, 'task') + '.' : 'This graph has no tasks. Use Add task.' }));
      return;
    }
    var name = t.name;
    var isRoot = name === S.g.root;

    box.appendChild(h('div', { class: 'inspector-head' },
      h('span', { class: 'task-name', text: name }),
      h('button', { type: 'button', class: 'danger small', onclick: deleteSelected, title: 'Delete this task' }, 'Delete task')));

    // name
    var nameErr = h('p', { class: 'field-error', id: 'f-name-err', role: 'alert' });
    var nameIn = h('input', { type: 'text', id: 'f-name', 'data-focus': 'name', autocomplete: 'off', spellcheck: 'false', 'aria-describedby': 'f-name-hint f-name-err' });
    nameIn.value = name;
    nameIn.addEventListener('input', function () {
      var v = nameIn.value;
      nameErr.textContent = v.trim() === '' ? 'The name cannot be empty.' : (v !== name && WL.findTask(S.g.tasks, v)) ? "There is already a task called '" + v + "'." : '';
    });
    nameIn.addEventListener('change', function () {
      if (nameIn.value === name) { nameErr.textContent = ''; return; }
      var r = applyRename(name, nameIn.value);
      if (!r.ok) { nameErr.textContent = r.error + ' The name was kept as ' + name + '.'; nameIn.value = name; }
    });
    box.appendChild(h('h3', { class: 'section', text: 'Basics' }));
    box.appendChild(h('div', { class: 'field' }, h('label', { for: 'f-name', text: 'Name' }), nameIn,
      h('span', { class: 'hint', id: 'f-name-hint', text: 'Names are exact: upper and lower case count. Renaming updates every task that is after this one.' }), nameErr));

    // definition
    var def = h('textarea', { id: 'f-definition', class: 'mono', rows: '8', wrap: 'off', spellcheck: 'false', 'data-focus': 'definition' });
    def.value = t.definition || '';
    def.addEventListener('input', function () { setField(name, 'definition', def.value, false); });
    box.appendChild(h('div', { class: 'field' }, h('label', { for: 'f-definition', text: 'Definition (the SQL the task runs)' }), def));

    // after
    var after = h('fieldset', { id: 'f-after-set' }, h('legend', { text: 'Runs after (predecessors)' }));
    var isFin = !!t.finalize;
    if (isFin) {
      after.disabled = true;
      after.appendChild(h('p', { class: 'hint muted', text: 'A finalizer has no predecessors: it runs after the whole graph.' }));
    } else {
      var desc = WL.descendants(S.g.tasks, name);
      var checks = h('div', { class: 'checks' });
      var any = false;
      S.g.tasks.forEach(function (o) {
        if (o.name === name) return;
        var checked = (t.after || []).indexOf(o.name) >= 0;
        if (o.finalize && !checked) return;
        var cyc = !checked && desc.has(o.name);
        any = true;
        var id = 'f-after-' + checks.children.length;
        var cb = h('input', { type: 'checkbox', id: id, 'data-focus': 'after:' + o.name, disabled: cyc ? true : null });
        cb.checked = checked;
        cb.addEventListener('change', function () {
          var tt = WL.findTask(S.g.tasks, name);
          var set = (tt.after || []).filter(function (a) { return a !== o.name; });
          if (cb.checked) set.push(o.name);
          tt.after = S.g.tasks.map(function (x) { return x.name; }).filter(function (n) { return set.indexOf(n) >= 0; }).concat(set.filter(function (n) { return !WL.findTask(S.g.tasks, n); }));
          touch();
          renderInspector(true);
        });
        checks.appendChild(h('div', { class: 'check' }, cb, h('label', { for: id }, o.name, o.finalize ? h('span', { class: 'note', text: ' (a finalizer: nothing can be after it)' }) : null,
          cyc ? h('span', { class: 'note', text: ' (comes after this task, so it would make a cycle)' }) : null)));
      });
      (t.after || []).forEach(function (a) {
        if (!WL.findTask(S.g.tasks, a)) {
          var cb2 = h('input', { type: 'checkbox', checked: true, 'data-focus': 'after:' + a });
          cb2.checked = true;
          cb2.addEventListener('change', function () { var tt = WL.findTask(S.g.tasks, name); tt.after = tt.after.filter(function (x) { return x !== a; }); touch(); renderInspector(true); });
          checks.appendChild(h('div', { class: 'check' }, cb2, h('label', null, a, h('span', { class: 'note', text: ' (not in this graph: uncheck to remove)' }))));
          any = true;
        }
      });
      if (!any) after.appendChild(h('p', { class: 'hint muted', text: 'There are no other tasks to come after.' }));
      else after.appendChild(checks);
      after.appendChild(h('p', { class: 'hint muted', style: 'margin:6px 0 0', text: (t.after || []).length ? 'After ' + t.after.join(', ') + '.' : 'No predecessor checked: this is a root.' }));
    }
    box.appendChild(after);

    // finalize
    var fin = WL.canFinalize(S.g.tasks, name);
    var finId = 'f-finalize';
    var finCb = h('input', { type: 'checkbox', id: finId, 'data-focus': 'finalize', disabled: fin.ok ? null : true });
    finCb.checked = isFin;
    finCb.addEventListener('change', function () {
      var tt = WL.findTask(S.g.tasks, name);
      if (finCb.checked) {
        var other = S.g.tasks.filter(function (x) { return x.name !== name && !(x.after && x.after.length) && !x.finalize; })[0];
        tt.finalize = other ? other.name : null;
      } else tt.finalize = null;
      touch();
      renderInspector(true);
    });
    box.appendChild(h('div', { class: 'field' }, h('div', { class: 'check' }, finCb, h('label', { for: finId, text: 'Finalizes the root (runs after the whole graph has finished, whatever happened)' })),
      h('span', { class: 'hint', text: fin.ok ? (isFin ? 'This task finalizes ' + t.finalize + '. A graph has at most one finalizer.' : 'Only a task with no predecessors can be the finalizer, and a graph has at most one.') : 'Not available: ' + fin.reason })));

    // run
    box.appendChild(h('h3', { class: 'section', text: 'Run' }));
    var text = function (id, label, key, hint, o) {
      var opt = o || {};
      var el = h(opt.multi ? 'textarea' : 'input', { id: 'f-' + id, type: opt.multi ? null : 'text', rows: opt.multi ? String(opt.rows || 2) : null, class: opt.mono ? 'mono' : null, spellcheck: 'false', autocomplete: 'off', 'data-focus': id,
        'aria-describedby': hint ? 'f-' + id + '-hint' : null });
      el.value = t[key] == null ? '' : t[key];
      el.addEventListener('input', function () { setField(name, key, WL.textOrNull(el.value), opt.canvas); });
      return h('div', { class: 'field' }, h('label', { for: 'f-' + id, text: label }), el, hint ? h('span', { class: 'hint', id: 'f-' + id + '-hint', text: hint }) : null);
    };
    box.appendChild(text('schedule', 'Schedule', 'schedule', 'Only the root has one. For example USING CRON 0 2 * * * UTC, or 60 MINUTE. Empty means none.', { canvas: true }));
    box.appendChild(text('warehouse', 'Warehouse', 'warehouse', 'Empty means serverless: then set USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE under Parameters.', { canvas: true }));
    box.appendChild(text('condition', 'Condition (WHEN)', 'condition', 'A boolean expression, for example SYSTEM$STREAM_HAS_DATA(\'MY_STREAM\'). Empty means none.', { multi: true, rows: 2, mono: true, canvas: true }));

    var tri = function (id, label, key, options, hint, toVal, fromVal, canvas) {
      var sel = h('select', { id: 'f-' + id, 'data-focus': id, 'aria-describedby': hint ? 'f-' + id + '-hint' : null });
      options.forEach(function (o) { sel.appendChild(h('option', { value: o[0], text: o[1] })); });
      sel.value = fromVal(t[key]);
      sel.addEventListener('change', function () { setField(name, key, toVal(sel.value), canvas); });
      return h('div', { class: 'field' }, h('label', { for: 'f-' + id, text: label }), sel, hint ? h('span', { class: 'hint', id: 'f-' + id + '-hint', text: hint }) : null);
    };
    box.appendChild(tri('overlap', 'Allow overlapping execution', 'allowOverlappingExecution', [['', 'Not set (Snowflake decides)'], ['true', 'true'], ['false', 'false']],
      'Meaningful on the root only.', WL.triToValue, WL.valueToTri, false));
    box.appendChild(tri('state', 'State', 'state', [['', 'Not set (leave as it is)'], ['started', 'started'], ['suspended', 'suspended']],
      'The state this task gets when the graph is applied.', function (v) { return v || null; }, function (v) { return v || ''; }, true));

    box.appendChild(h('h3', { class: 'section', text: 'More' }));
    box.appendChild(text('comment', 'Comment', 'comment', '', {}));
    box.appendChild(text('errorIntegration', 'Error integration', 'errorIntegration', 'The notification integration that is told about failures.', {}));
    box.appendChild(text('config', 'Config', 'config', 'JSON text, for the task\'s config. Empty means none.', { multi: true, rows: 2, mono: true }));

    // parameters
    box.appendChild(h('h3', { class: 'section', text: 'Parameters' }));
    if (!S.paramRows || S.paramRows.task !== name) S.paramRows = { task: name, rows: WL.paramsToRows(t.parameters) };
    var pbox = h('div', { id: 'params' });
    var dl = h('datalist', { id: 'param-names' });
    PARAM_NAMES.forEach(function (p) { dl.appendChild(h('option', { value: p })); });
    var dupNote = h('p', { class: 'field-error', role: 'alert' });
    var syncParams = function () {
      var rows = S.paramRows.rows;
      var dup = WL.duplicateKeys(rows);
      dupNote.textContent = dup.length ? 'Listed twice: ' + dup.join(', ') + '. The last one is used.' : '';
      setField(name, 'parameters', WL.rowsToParams(rows), false);
    };
    S.paramRows.rows.forEach(function (row, i) {
      var k = h('input', { type: 'text', list: 'param-names', 'aria-label': 'Parameter name, row ' + (i + 1), 'data-focus': 'pk' + i, autocomplete: 'off', spellcheck: 'false', class: 'mono' });
      var v = h('input', { type: 'text', 'aria-label': 'Value of ' + (row.key || 'parameter') + ', row ' + (i + 1), 'data-focus': 'pv' + i, autocomplete: 'off', spellcheck: 'false', class: 'mono' });
      k.value = row.key; v.value = row.value;
      k.addEventListener('input', function () { row.key = k.value; syncParams(); });
      k.addEventListener('change', function () { row.key = k.value.trim().toUpperCase(); k.value = row.key; syncParams(); });
      v.addEventListener('input', function () { row.value = v.value; syncParams(); });
      pbox.appendChild(h('div', { class: 'param-row' }, k, v, h('button', { type: 'button', class: 'small', 'aria-label': 'Remove parameter ' + (row.key || 'row ' + (i + 1)), 'data-focus': 'pr' + i,
        onclick: function () { S.paramRows.rows.splice(i, 1); syncParams(); renderInspector(); } }, 'Remove')));
    });
    if (!S.paramRows.rows.length) pbox.appendChild(h('p', { class: 'hint muted', text: 'No parameters set on this task.' }));
    box.appendChild(pbox);
    box.appendChild(dupNote);
    box.appendChild(h('button', { type: 'button', id: 'btn-add-param', 'data-focus': 'addparam', text: 'Add parameter', onclick: function () {
      S.paramRows.rows.push({ key: '', value: '' });
      renderInspector();
      var el = box.querySelector('[data-focus="pk' + (S.paramRows.rows.length - 1) + '"]');
      if (el) el.focus();
    } }));
    box.appendChild(dl);
    if (!(t.parameters && Object.keys(t.parameters).length) && !S.paramRows.rows.length) { /* the note above says it */ }

    // information from Snowflake
    box.appendChild(h('h3', { class: 'section', text: 'Information from Snowflake' }));
    var info = t.info;
    if (!info) box.appendChild(h('p', { class: 'hint muted', text: S.g.origin === 'installed' ? 'Snowflake gave no further information for this task (it is new in this edit, or the role cannot see it).' : 'This task is not installed yet, so Snowflake has nothing to say about it.' }));
    else {
      var dlist = h('dl', { class: 'info' });
      var row = function (label, value) { if (value !== null && value !== undefined && value !== '') { dlist.appendChild(h('dt', { text: label })); dlist.appendChild(h('dd', { text: String(value) })); } };
      row('Owner', info.owner); row('Id', info.id); row('Created', WL.formatTime(info.createdOn)); row('Last committed', WL.formatTime(info.lastCommittedOn));
      row('Last suspended', WL.formatTime(info.lastSuspendedOn)); row('Suspended because', info.lastSuspendedReason); row('Budget', info.budget);
      if (!dlist.children.length) dlist.appendChild(h('dt', { text: 'Nothing' }), h('dd', { text: 'Snowflake gave no details.' }));
      box.appendChild(dlist);
    }
    if (VIEWER) {
      Array.prototype.forEach.call(box.querySelectorAll('input, textarea, select'), function (el) { if (el.tagName === 'TEXTAREA' || el.type === 'text') el.readOnly = true; else el.disabled = true; });
      box.insertBefore(h('p', { class: 'hint muted', text: 'Read-only: this is a snapshot.' }), box.firstChild);
    }
    if (fk) { var again = box.querySelector('[data-focus="' + fk.replace(/"/g, '\\"') + '"]'); if (again) again.focus(); }
  }

  /* ============================== tabs ============================== */

  function setPanelHidden(hide) {
    $('bottom').classList.toggle('collapsed', hide);
    $('btn-panel-hide').setAttribute('aria-pressed', hide ? 'true' : 'false');
    $('btn-panel-hide').textContent = hide ? 'Show' : 'Hide';
    $('btn-panel-hide').setAttribute('aria-label', hide ? 'Show the panel' : 'Hide the panel');
    $('btn-panel-size').hidden = hide;
    if (S.g && S.layout) setTimeout(fitView, 0);
  }

  function setTab(name, focus) {
    if (VIEWER && (name === 'plan' || name === 'sql' || name === 'problems')) name = 'runs';
    S.tab = name;
    if ($('bottom').classList.contains('collapsed')) setPanelHidden(false);
    ['problems', 'plan', 'sql', 'runs'].forEach(function (n) {
      var tab = $('tab-' + n), on = n === name;
      tab.setAttribute('aria-selected', on ? 'true' : 'false');
      tab.tabIndex = on ? 0 : -1;
      $('panel-' + n).hidden = !on;
    });
    if (focus) $('tab-' + name).focus();
    if (name === 'sql') refreshSql();
    if (name === 'runs' && S.g && S.g.origin === 'installed' && !S.runs) loadRuns();
    if (name === 'plan') renderPlan();
    if (name === 'runs') renderRuns();
  }

  function wireTabs() {
    var tabs = ['problems', 'plan', 'sql', 'runs'];
    tabs.forEach(function (n) {
      $('tab-' + n).addEventListener('click', function () { setTab(n); });
      $('tab-' + n).addEventListener('keydown', function (e) {
        var i = tabs.indexOf(n), j = -1;
        if (e.key === 'ArrowRight') j = (i + 1) % tabs.length;
        else if (e.key === 'ArrowLeft') j = (i + tabs.length - 1) % tabs.length;
        else if (e.key === 'Home') j = 0;
        else if (e.key === 'End') j = tabs.length - 1;
        if (j >= 0) { e.preventDefault(); setTab(tabs[j], true); }
      });
    });
    $('btn-panel-size').addEventListener('click', function () {
      var tall = $('bottom').classList.toggle('tall');
      $('btn-panel-size').setAttribute('aria-pressed', tall ? 'true' : 'false');
      $('btn-panel-size').textContent = tall ? 'Shorter' : 'Taller';
      $('btn-panel-size').setAttribute('aria-label', tall ? 'Make the panel shorter' : 'Make the panel taller');
    });
    $('btn-panel-hide').addEventListener('click', function () { setPanelHidden(!$('bottom').classList.contains('collapsed')); });
  }

  function renderTabCount() {
    var e = S.problems.filter(function (p) { return p.severity === 'error'; }).length;
    var w = S.problems.filter(function (p) { return p.severity === 'warning'; }).length;
    var el = $('problem-count');
    if (!S.g) { el.textContent = ''; el.className = 'count'; return; }
    el.textContent = e ? plural(e, 'error') : w ? plural(w, 'warning') : S.problems.length ? plural(S.problems.length, 'note') : 'none';
    el.className = 'count' + (e ? ' has-errors' : '');
  }

  function renderTabsSelection() { /* the selection is shown in the lists by the buttons themselves */ }

  /* ---- problems ---- */
  function renderProblems() {
    var p = $('panel-problems');
    p.textContent = '';
    renderTabCount();
    if (VIEWER) { p.appendChild(h('p', { class: 'muted', text: 'The viewer does not check graphs: that needs the server.' })); return; }
    if (!S.g) { p.appendChild(h('p', { class: 'muted', text: 'Open a graph to see its problems. The graph is checked against what Snowflake enforces after every edit.' })); return; }
    if (S.problemsError) p.appendChild(h('div', { class: 'inline-banner', role: 'alert' }, icon('error'), 'The graph could not be checked: ' + S.problemsError));
    var list = WL.sortProblems(S.problems);
    var counts = { error: 0, warning: 0, info: 0 };
    list.forEach(function (x) { if (counts[x.severity] !== undefined) counts[x.severity]++; });
    p.appendChild(h('p', { class: 'muted', role: 'status' }, S.validating ? 'Checking...  ' : '',
      list.length ? plural(counts.error, 'error') + ', ' + plural(counts.warning, 'warning') + ', ' + plural(counts.info, 'note') + '.' : (S.validating ? '' : '')));
    if (!list.length) {
      if (!S.validating) p.appendChild(h('p', { class: 'all-good' }, icon('check'), 'No problems found. This graph passes the checks that Snowflake itself would make.'));
      return;
    }
    var ul = h('ul', { class: 'problem-list' });
    list.forEach(function (x) {
      var label = x.severity === 'error' ? 'Error' : x.severity === 'warning' ? 'Warning' : 'Note';
      var body = h('span', { class: 'what' }, h('span', { text: x.message }), h('div', { class: 'who' }, x.task ? ['Task ', h('code', { text: x.task })] : 'The whole graph', '  ·  ' + x.code));
      var sev = h('span', { class: 'sev' }, icon(x.severity === 'info' ? 'info' : x.severity), label);
      if (x.task && S.g && WL.findTask(S.g.tasks, x.task)) {
        ul.appendChild(h('li', null, h('button', { type: 'button', class: 'problem ' + x.severity, title: 'Select task ' + x.task, onclick: function () { selectTask(x.task, { reveal: true }); } }, sev, body)));
      } else {
        ul.appendChild(h('li', null, h('div', { class: 'problem ' + x.severity }, sev, body)));
      }
    });
    p.appendChild(ul);
  }

  /* ---- plan ---- */
  function planStale() { return !!(S.plan && S.plan.rev !== S.rev && !S.plan.applied); }

  function canApply() {
    var pl = S.plan;
    return !!(pl && !pl.loading && !pl.applied && pl.rev === S.rev && pl.data && pl.data.plan && !pl.data.plan.isEmpty && pl.data.plan.steps.length);
  }

  async function planChanges() {
    if (!S.g) return;
    var rev = S.rev;
    S.plan = { rev: rev, loading: true };
    setTab('plan');
    renderPlan();
    try {
      var data = await api('POST', '/api/plan', { body: { graph: WL.graphPayload(S.g) } });
      S.plan = { rev: rev, data: data };
      if (rev === S.rev) { S.problems = data.problems || S.problems; S.problemsError = ''; renderProblems(); scheduleCanvas(); }
    } catch (e) {
      S.plan = { rev: rev, error: e.message };
      reportError(e, 'Could not make the plan');
    }
    renderPlan();
  }

  function dropsOf(plan) {
    var names = (plan.removed || []).slice();
    (plan.steps || []).forEach(function (st) { if (st.phase === 'drop' && names.indexOf(st.task) < 0) names.push(st.task); });
    return names;
  }

  async function applyPlan() {
    if (!canApply()) { toast('Make a fresh plan first: Plan changes. Apply works only on a plan that matches the graph as it is now.', { kind: 'info' }); return false; }
    var plan = S.plan.data.plan, g = S.g;
    var drops = dropsOf(plan);
    var body = [h('p', null, 'This sends ', h('strong', { text: plural(plan.steps.length, 'step') }), ' to Snowflake for ', h('strong', { text: fullName(g) }), '.')];
    if (drops.length) body.push(h('p', null, h('strong', { text: 'It drops ' + plural(drops.length, 'task') + ': ' }), drops.join(', '), '. A dropped task cannot be brought back from here.'));
    else body.push(h('p', { class: 'muted', text: 'No task is dropped.' }));
    var ok = await K.askConfirm({ title: 'Apply ' + plural(plan.steps.length, 'step') + '?', body: body, okLabel: 'Apply ' + plural(plan.steps.length, 'step'), danger: drops.length > 0 });
    if (!ok) return false;
    S.plan = Object.assign({}, S.plan, { loading: true });
    renderPlan();
    try {
      var data = await api('POST', '/api/apply', { body: { graph: WL.graphPayload(g) } });
      if (data.graph) setOpenGraph(data.graph, data.problems, 'installed', { keepSel: S.sel, keepView: true, keepPlan: true });
      else toast('The plan was applied, but the graph could not be read back (it may have no root task now).', { kind: 'error' });
      S.plan = { rev: S.rev, data: { plan: data.plan, problems: data.problems || [] }, applied: true };
      var done = data.plan ? data.plan.executed : 0;
      toast('Applied: ' + plural(done, 'step') + ' executed.', { kind: 'ok' });
      if (data.graph && (data.graph.database !== S.database || data.graph.schema !== S.schema)) {
        S.database = data.graph.database; S.schema = data.graph.schema;
        await loadSchemas(); renderSelectors(); S.graphs = null;
      }
      await loadGraphs();
    } catch (e) {
      S.plan = { rev: S.rev, error: e.message + ' Some steps may already have run: use Refresh to see what is installed (your edits stay until you do).' };
      reportError(e, 'The apply stopped');
    }
    renderPlan();
    return true;
  }

  function renderPlan() {
    var p = $('panel-plan');
    p.textContent = '';
    if (!S.g) { p.appendChild(h('p', { class: 'muted', text: 'Open a graph, then use Plan changes to see what would be sent to Snowflake.' })); return; }
    var pl = S.plan, stale = planStale();
    var apply = h('button', { type: 'button', class: 'primary', id: 'btn-apply', disabled: canApply() ? null : true, onclick: applyPlan, title: 'Apply the planned steps to Snowflake' }, 'Apply...');
    var why = '';
    if (!pl) why = 'Plan the changes first.';
    else if (pl.loading) why = 'Working...';
    else if (pl.applied) why = 'The plan was applied. Edit the graph and plan again to change more.';
    else if (stale) why = 'The graph was edited after this plan was made: plan again.';
    else if (pl.error) why = 'The plan failed.';
    else if (pl.data && !pl.data.plan) why = 'There is no plan while the graph has errors.';
    else if (pl.data && pl.data.plan.isEmpty) why = 'Nothing has to change.';
    p.appendChild(h('div', { class: 'panel-actions' },
      h('button', { type: 'button', id: 'btn-plan', onclick: planChanges, title: 'Compare this graph with what is installed and list the steps. Nothing is changed.' }, 'Plan changes'),
      apply, h('span', { class: 'muted', id: 'apply-why', text: canApply() ? '' : why })));
    if (!pl) { p.appendChild(h('p', { class: 'muted', text: 'Plan changes compares this graph with what is installed in Snowflake and lists, step by step, the statements that would be sent. Planning changes nothing.' })); return; }
    if (pl.loading) { p.appendChild(h('p', { role: 'status', text: 'Working...' })); return; }
    if (pl.error) { p.appendChild(h('div', { class: 'inline-banner', role: 'alert' }, icon('error'), pl.error)); return; }
    var data = pl.data, plan = data.plan;
    if (stale) p.appendChild(h('div', { class: 'plan-summary stale', role: 'status' }, icon('warning'), ' The graph was edited after this plan was made, so it may no longer be right. Plan again before applying.'));
    if (!plan) {
      var errs = (data.problems || []).filter(function (x) { return x.severity === 'error'; });
      var box = h('div', { class: 'plan-summary none', role: 'status' }, h('strong', { text: 'There is no plan: the graph has ' + plural(errs.length, 'error') + '.' }),
        ' Snowflake would refuse it. Fix the errors (see Problems), then plan again.');
      errs.forEach(function (x) { box.appendChild(h('div', null, '• ' + (x.task ? x.task + ': ' : '') + x.message)); });
      p.appendChild(box);
      return;
    }
    var names = function (label, list) { return list && list.length ? h('div', null, h('strong', { text: label + ': ' }), list.join(', ')) : null; };
    if (pl.applied) {
      p.appendChild(h('div', { class: 'plan-summary nothing', role: 'status' }, h('strong', { text: 'Applied: ' + plural(plan.executed, 'step') + ' executed of ' + plan.steps.length + '.' }),
        ' The graph below was read back from Snowflake.'));
    } else if (plan.isEmpty) {
      p.appendChild(h('div', { class: 'plan-summary nothing', role: 'status' }, icon('check'), ' ', h('strong', { text: 'Nothing has to change.' }),
        ' The installed graph ' + plan.database + '.' + plan.schema + '.' + plan.root + ' already matches this graph.'));
      return;
    } else {
      p.appendChild(h('div', { class: 'plan-summary', role: 'status' },
        h('div', null, h('strong', { text: plural(plan.steps.length, 'step') }), plan.exists ? ' to change the installed graph ' : ' to create the graph ', h('strong', { text: plan.database + '.' + plan.schema + '.' + plan.root }), plan.exists ? '.' : ', which is not installed yet.'),
        names('Added tasks', plan.added), names('Changed tasks', plan.changed), names('Removed (dropped) tasks', plan.removed)));
    }
    var ol = h('ol', { class: 'steps' });
    plan.steps.forEach(function (st, i) {
      var doneMark = pl.applied ? (i < plan.executed ? h('span', { class: 'done-mark' }, icon('check'), ' done') : h('span', { class: 'muted', text: 'not run' })) : null;
      ol.appendChild(h('li', { class: 'step' },
        h('div', { class: 'step-head' }, h('span', { class: 'n', text: (i + 1) + '.' }), h('span', { class: 'phase ' + st.phase, text: st.phase }), h('strong', { text: st.task }),
          h('span', { class: 'reason', text: st.reason || '' }), doneMark),
        h('pre', { class: 'sql', text: st.sql })));
    });
    p.appendChild(ol);
  }

  /* ---- SQL ---- */
  var sqlTimer = null, sqlSeq = 0;
  function scheduleSql() { clearTimeout(sqlTimer); sqlTimer = setTimeout(refreshSql, 500); }

  async function refreshSql() {
    if (!S.g) { renderSql(); return; }
    if (S.sql && S.sql.rev === S.rev && !S.sql.error) { renderSql(); return; }
    var rev = S.rev, seq = ++sqlSeq;
    S.sql = { rev: rev, loading: true, text: S.sql ? S.sql.text : '' };
    renderSql();
    try {
      var data = await api('POST', '/api/sql', { body: { graph: WL.graphPayload(S.g) }, quiet: true });
      if (seq !== sqlSeq) return;
      S.sql = { rev: rev, text: data.sql };
    } catch (e) {
      if (seq !== sqlSeq) return;
      S.sql = { rev: rev, error: e.message, text: '' };
    }
    renderSql();
  }

  function renderSql() {
    var p = $('panel-sql');
    p.textContent = '';
    if (!S.g) { p.appendChild(h('p', { class: 'muted', text: 'Open a graph to see the SQL script that creates it.' })); return; }
    var sq = S.sql;
    var text = sq && sq.text ? sq.text : '';
    p.appendChild(h('div', { class: 'panel-actions' },
      h('button', { type: 'button', id: 'btn-sql-copy', disabled: text ? null : true, onclick: async function () { toast((await K.copyText(text)) ? 'The SQL is on the clipboard.' : 'Could not copy: select the text and copy it by hand.', { kind: 'info', ms: 3000 }); } }, 'Copy'),
      h('button', { type: 'button', id: 'btn-sql-download', disabled: text ? null : true, onclick: function () { K.download((S.g.root || 'graph') + '.sql', text, 'text/plain;charset=utf-8'); } }, 'Download'),
      h('button', { type: 'button', onclick: function () { S.sql = null; refreshSql(); } }, 'Refresh'),
      h('span', { class: 'muted', text: 'The script that would create this graph as it is now (all of it, not only the changes).' })));
    if (sq && sq.error) p.appendChild(h('div', { class: 'inline-banner', role: 'alert' }, icon('error'), 'The SQL could not be made: ' + sq.error));
    else if (!sq || (sq.loading && !text)) p.appendChild(h('p', { class: 'muted', role: 'status', text: 'Making the script...' }));
    else p.appendChild(h('pre', { class: 'script', id: 'sql-text', tabindex: '0', text: text }));
  }

  /* ---- runs ---- */
  var HOURS = [[6, 'last 6 hours'], [24, 'last 24 hours'], [72, 'last 3 days (72 hours)'], [168, 'last 7 days (168 hours)']];

  async function loadRuns() {
    var g = S.g;
    if (!g || g.origin !== 'installed') { S.runs = null; renderRuns(); return; }
    var key = g.database + '.' + g.schema + '.' + g.root;
    S.runs = { key: key, hours: S.runHours, loading: true, list: null, sel: null, error: '' };
    renderRuns(); scheduleCanvas();
    try {
      var data = await D.get('/api/runs', { database: g.database, schema: g.schema, root: g.root, hours: S.runHours });
      if (!S.runs || S.runs.key !== key) return;
      S.runs = { key: key, hours: S.runHours, loading: false, list: WL.sortRuns(data.runs || []), sel: null, error: '' };
    } catch (e) {
      if (!S.runs || S.runs.key !== key) return;
      S.runs = { key: key, hours: S.runHours, loading: false, list: null, sel: null, error: e.message };
      toast('Could not read the runs of ' + g.root + ': ' + e.message, { kind: 'error' });
    }
    renderRuns(); scheduleCanvas();
  }

  function selectRun(runId) {
    if (!S.runs) return;
    S.runs.sel = S.runs.sel === runId ? null : runId;
    renderRuns(); scheduleCanvas();
  }

  function renderRuns() {
    var p = $('panel-runs');
    p.textContent = '';
    if (!S.g) { p.appendChild(h('p', { class: 'muted', text: 'Open an installed graph to see its runs.' })); return; }
    if (S.g.origin !== 'installed') { p.appendChild(h('p', { class: 'muted', text: 'This graph is not installed in Snowflake yet, so it has no runs. Apply it first.' })); return; }
    if (VIEWER) { S.runHours = 168; p.appendChild(h('p', { class: 'muted', text: 'The runs saved in this snapshot, newest first.' })); }
    var sel = h('select', { id: 'runs-hours', 'aria-label': 'How far back to look', hidden: VIEWER ? true : null });
    HOURS.forEach(function (o) { sel.appendChild(h('option', { value: String(o[0]), text: o[1] })); });
    sel.value = String(S.runHours);
    sel.addEventListener('change', function () { S.runHours = Number(sel.value); loadRuns(); });
    if (!VIEWER) p.appendChild(h('div', { class: 'panel-actions' }, h('label', { for: 'runs-hours', text: 'Show runs of the' }), sel,
      h('button', { type: 'button', onclick: loadRuns }, 'Reload runs'),
      h('span', { class: 'muted', text: 'Newest first. Needs the MONITOR privilege on the tasks, or ownership.' })));
    var r = S.runs;
    if (!r || r.loading) { p.appendChild(h('p', { role: 'status', text: 'Loading the runs...' })); return; }
    if (r.error) { p.appendChild(h('div', { class: 'inline-banner', role: 'alert' }, icon('error'), 'The runs could not be read: ' + r.error)); return; }
    if (!r.list.length) { p.appendChild(h('p', { class: 'muted', text: 'There was no run of this graph in the last ' + r.hours + ' hours.' })); return; }
    var table = h('table', { class: 'runs' });
    table.appendChild(h('thead', null, h('tr', null, ['State', 'Scheduled', 'Started', 'Seconds', 'Tasks'].map(function (c) { return h('th', { scope: 'col', text: c }); }))));
    var tb = h('tbody');
    r.list.forEach(function (run) {
      var next = WL.isNextRun(run);
      var info = WL.runStateInfo(run.state);
      var badge = next ? h('span', { class: 'badge wait' }, icon('clock'), 'next run') : h('span', { class: 'badge ' + info.kind }, icon(OUT_ICON[info.kind] || 'clock'), info.label);
      var cell = next ? badge : h('button', { type: 'button', class: 'link', 'aria-pressed': r.sel === run.runId ? 'true' : 'false', title: 'Show the tasks of this run, and their states on the graph', onclick: function () { selectRun(run.runId); } }, badge);
      var failed = (run.tasks || []).filter(function (t) { return WL.runStateInfo(t.state).kind === 'bad'; }).length;
      tb.appendChild(h('tr', { class: (r.sel === run.runId ? 'selected ' : '') + (next ? 'next' : '') },
        h('td', null, cell), h('td', { text: WL.formatTime(run.scheduled) }), h('td', { text: next ? 'not started yet' : WL.formatTime(run.started) }),
        h('td', { class: 'num', text: WL.formatSeconds(run.seconds) }), h('td', { text: next ? '' : plural((run.tasks || []).length, 'task') + (failed ? ', ' + failed + ' failed' : '') })));
    });
    table.appendChild(tb);
    p.appendChild(h('div', { class: 'runs-wrap' }, table));
    var run = r.sel ? r.list.filter(function (x) { return x.runId === r.sel; })[0] : null;
    if (run) {
      var det = h('div', { class: 'run-detail' }, h('h3', { text: 'Tasks of the run scheduled ' + WL.formatTime(run.scheduled) + ' (shown on the graph)' }));
      var dt = h('table', { class: 'runs' });
      dt.appendChild(h('thead', null, h('tr', null, ['Task', 'State', 'Started', 'Completed', 'Attempt', 'Error'].map(function (c) { return h('th', { scope: 'col', text: c }); }))));
      var db = h('tbody');
      (run.tasks || []).forEach(function (t) {
        var inf = WL.runStateInfo(t.state);
        var inGraph = S.g && WL.findTask(S.g.tasks, t.task);
        db.appendChild(h('tr', null,
          h('td', null, inGraph ? h('button', { type: 'button', class: 'link', title: 'Select this task', onclick: function () { selectTask(t.task, { reveal: true }); } }, t.task) : t.task),
          h('td', null, h('span', { class: 'badge ' + inf.kind }, icon(OUT_ICON[inf.kind] || 'clock'), inf.label)),
          h('td', { text: WL.formatTime(t.started) }), h('td', { text: WL.formatTime(t.completed) }), h('td', { class: 'num', text: t.attempt == null ? '' : String(t.attempt) }),
          h('td', null, t.error ? h('div', { class: 'run-error' }, (t.errorCode ? '[' + t.errorCode + '] ' : '') + t.error) : (t.errorCode ? h('span', { class: 'run-error', text: '[' + t.errorCode + ']' }) : ''), t.queryId ? h('div', { class: 'muted mono', text: 'query ' + t.queryId }) : null)));
      });
      dt.appendChild(db);
      det.appendChild(h('div', { class: 'runs-wrap' }, dt));
      p.appendChild(det);
    } else {
      p.appendChild(h('p', { class: 'muted', style: 'margin-top:10px', text: 'Choose a run (its state) to see its tasks, with errors, and to draw its task states on the graph. Until then the graph shows the most recent run that is not merely scheduled.' }));
    }
  }

  /* ============================== everything ============================== */

  function renderAll() {
    renderSelectors();
    renderGraphList();
    renderGraphBar();
    renderNotices();
    renderCanvas();
    renderInspector();
    renderProblems();
    renderPlan();
    renderSql();
    renderRuns();
    renderTabCount();
    updateCanvasTools();
  }

  function wire() {
    K.onBusy(function (n) { $('busy').hidden = n <= 0; });
    $('sel-db').addEventListener('change', function (e) { chooseDatabase(e.target.value); });
    $('sel-schema').addEventListener('change', function (e) { chooseSchema(e.target.value); });
    $('btn-refresh').addEventListener('click', refresh);
    $('btn-new').addEventListener('click', newGraph);
    $('btn-import').addEventListener('click', function () { $('file-import').click(); });
    $('file-import').addEventListener('change', function (e) {
      var f = e.target.files && e.target.files[0];
      e.target.value = '';
      if (f) importFile(f);
    });
    wireCanvas();
    wireTabs();
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Delete' && !VIEWER && !isTyping(e.target) && S.g && S.sel && !document.querySelector('dialog[open]')) { e.preventDefault(); deleteSelected(); }
    });
    window.addEventListener('beforeunload', function (e) { if (hasUnsaved()) { e.preventDefault(); e.returnValue = ''; } });
    window.addEventListener('resize', function () { if (S.g && S.layout && !S.userMoved) { /* keep the view as it is */ } });
  }

  async function init() {
    var q = new URLSearchParams(location.search);
    var theme = q.get('theme');
    if (theme === 'dark' || theme === 'light') document.documentElement.setAttribute('data-theme', theme);
    if (VIEWER) { document.body.classList.add('viewer'); S.tab = 'runs'; setTab('runs'); }
    wire();
    renderAll();
    try { S.session = await D.get('/api/session'); }
    catch (e) { S.sessionError = e.message; reportError(e, 'Could not read the session'); }
    renderConnection();
    await loadDatabases();
    if (q.get('tab')) setTab(q.get('tab'));
    if (q.get('panel') === 'hide') setPanelHidden(true);
    var db = q.get('db'), sc = q.get('schema'), root = q.get('root');
    if (db && S.databases.indexOf(db) >= 0) {
      S.database = db; renderSelectors();
      await loadSchemas();
      if (sc && S.schemas.indexOf(sc) >= 0) {
        await chooseSchema(sc, { noGuard: true });
        if (root) await openGraph(root, { noGuard: true });
        if (root && q.get('z')) { S.view = { k: Number(q.get('z')), x: 10, y: 10 }; applyView(); }
      }
    }
    if (q.get('selftest')) {
      var sc2 = document.createElement('script');
      sc2.src = 'selftest.js';
      document.body.appendChild(sc2);
    }
  }

  window.WfApp = {
    S: S, init: init, loadDatabases: loadDatabases, chooseDatabase: chooseDatabase, chooseSchema: chooseSchema, loadGraphs: loadGraphs, openGraph: openGraph,
    selectTask: selectTask, addTask: addTask, deleteSelected: deleteSelected, applyRename: applyRename, touch: touch, setField: setField,
    runValidate: runValidate, planChanges: planChanges, applyPlan: applyPlan, refreshSql: refreshSql, loadRuns: loadRuns, selectRun: selectRun,
    operate: operate, importText: importText, makeNewGraph: makeNewGraph, discardChanges: discardChanges, exportGraph: exportGraph,
    hasUnsaved: hasUnsaved, guardEdits: guardEdits, setTab: setTab, renderCanvas: renderCanvas, renderInspector: renderInspector, refresh: refresh,
    fitView: fitView, closeGraph: closeGraph, setOpenGraph: setOpenGraph, sleep: sleep, selTask: selTask, renderAll: renderAll
  };

  init();
})();
