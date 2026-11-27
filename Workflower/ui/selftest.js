/* Workflower self-test. Loaded only by app.js when the page is opened with ?selftest=1. It drives the real functions of the page
   against the demo server and writes a PASS/FAIL list into <pre id="selftest">. With ?big=N it then leaves an imported graph of N
   tasks open (with one long name and one 60-line SQL body) for a screenshot. Run: Start-Workflower -Session (New-WfSession -Demo). */
(function () {
  'use strict';
  var A = window.WfApp, S = A.S, WL = window.WfLayout, K = window.WfKit;
  var $ = function (id) { return document.getElementById(id); };
  var results = [], failures = 0;
  var pre = document.createElement('pre');
  pre.id = 'selftest';
  document.body.appendChild(pre);

  function check(name, ok, detail) {
    var line = (ok ? 'PASS ' : 'FAIL ') + name + (ok || detail === undefined ? '' : '  -> ' + detail);
    if (!ok) failures++;
    results.push(line);
    pre.textContent = results.join('\n');
  }
  function eq(name, actual, expected) { check(name, JSON.stringify(actual) === JSON.stringify(expected), 'got ' + JSON.stringify(actual) + ', wanted ' + JSON.stringify(expected)); }
  async function until(fn, ms) {
    var end = Date.now() + (ms || 6000);
    while (Date.now() < end) { try { if (await fn()) return true; } catch (e) { /* not yet */ } await A.sleep(40); }
    return false;
  }
  function typeInto(el, value) { el.value = value; el.dispatchEvent(new Event('input', { bubbles: true })); }
  function changeTo(el, value) { el.value = value; el.dispatchEvent(new Event('change', { bubbles: true })); }
  function nodes() { return Array.prototype.slice.call(document.querySelectorAll('#canvas .node')); }
  function node(name) { return document.querySelector('#canvas .node[data-name="' + name + '"]'); }
  function task(name) { return WL.findTask(S.g.tasks, name); }
  function toastText() { return $('toasts').textContent; }
  function clearToasts() { $('toasts').textContent = ''; }
  var asked = [];
  var answer = true;
  K.setConfirmHook(function (o) { asked.push(o); return answer; });
  var downloads = [];
  K.setDownloadHook(function (name, text) { downloads.push({ name: name, text: text }); });

  /* ---- the pure functions ---- */
  function pureTests() {
    var mk = function (name, after, extra) { return WL.makeTask(name, Object.assign({ definition: 'SELECT 1', after: after || [] }, extra || {})); };
    // a diamond
    var diamond = [mk('A'), mk('B', ['A']), mk('C', ['A']), mk('D', ['B', 'C'])];
    var L = WL.computeLayers(diamond);
    eq('layers of a diamond', L.layers, { A: 0, B: 1, C: 1, D: 2 });
    var lay = WL.layoutGraph(diamond);
    eq('diamond has 4 boxes and 4 edges', [lay.nodes.length, lay.edges.length], [4, 4]);
    eq('diamond boxes do not overlap', WL.findOverlaps(lay), []);
    check('diamond is left to right', lay.nodeByName.A.x < lay.nodeByName.B.x && lay.nodeByName.B.x < lay.nodeByName.D.x);
    check('B and C are in the same column, one above the other', lay.nodeByName.B.x === lay.nodeByName.C.x && lay.nodeByName.B.y !== lay.nodeByName.C.y);
    var mid = (lay.nodeByName.B.y + lay.nodeByName.C.y) / 2;
    check('A and D sit between B and C', Math.abs(lay.nodeByName.A.y - mid) < 2 && Math.abs(lay.nodeByName.D.y - mid) < 2, JSON.stringify([lay.nodeByName.A.y, lay.nodeByName.D.y, mid]));
    // a long edge goes through a slot of its own, not through a box
    var longEdge = [mk('A'), mk('B', ['A']), mk('C', ['B']), mk('D', ['A', 'C'])];
    var le = WL.layoutGraph(longEdge);
    var ad = le.edges.filter(function (e) { return e.from === 'A' && e.to === 'D'; })[0];
    eq('an edge over two layers has 4 points (two slots)', ad.points.length, 4);
    check('the long edge keeps clear of the boxes in between', !['B', 'C'].some(function (n) {
      var b = le.nodeByName[n];
      return ad.points.some(function (p) { return p.x > b.x && p.x < b.x + b.w && p.y > b.y && p.y < b.y + b.h; });
    }));
    // a finalizer is in the last column, with a dashed edge from the root
    var fin = [mk('R'), mk('X', ['R']), mk('Y', ['X']), mk('F', [], { finalize: 'R' })];
    var fl = WL.layoutGraph(fin);
    eq('finalizer layer is after the deepest task', WL.computeLayers(fin).layers, { R: 0, X: 1, Y: 2, F: 3 });
    check('finalizer is drawn in the last column', fl.nodeByName.F.x > fl.nodeByName.Y.x);
    check('there is a finalize edge from R to F', fl.edges.some(function (e) { return e.kind === 'finalize' && e.from === 'R' && e.to === 'F'; }));
    eq('finalizer layout has no overlaps', WL.findOverlaps(fl), []);
    // a cycle, a missing predecessor, a task after itself: still a drawing of every task
    var cyc = [mk('P', ['Q']), mk('Q', ['P']), mk('S', ['S', 'GONE'])];
    var cl = WL.layoutGraph(cyc);
    eq('a cycle still gets a box for every task', cl.nodes.length, 3);
    check('a cycle is reported', WL.computeLayers(cyc).cyclic.length > 0);
    eq('an empty graph lays out to nothing', WL.layoutGraph([]).nodes.length, 0);
    // size and speed
    var big = WL.syntheticTasks(40, 5), t0 = Date.now(), bl = WL.layoutGraph(big), ms40 = Date.now() - t0;
    eq('40 tasks: 40 boxes', bl.nodes.length, 40);
    eq('40 tasks: no overlaps', WL.findOverlaps(bl), []);
    check('40 tasks laid out in under 300 ms (took ' + ms40 + ')', ms40 < 300);
    var huge = WL.syntheticTasks(400, 12);
    t0 = Date.now();
    var hl = WL.layoutGraph(huge);
    var ms400 = Date.now() - t0;
    check('400 tasks laid out in under 1500 ms (took ' + ms400 + ')', ms400 < 1500);
    eq('400 tasks: no overlaps', WL.findOverlaps(hl).length, 0);
    // rename
    var r = WL.renameTask(fin, 'R', 'ROOT2');
    check('rename ok', r.ok);
    eq('rename updates after and finalize', [r.tasks[1].after, r.tasks[3].finalize, r.tasks[0].name], [['ROOT2'], 'ROOT2', 'ROOT2']);
    eq('rename does not change its input', fin[1].after, ['R']);
    check('rename to an existing name is refused', !WL.renameTask(fin, 'X', 'Y').ok);
    check('rename to a name that differs only by case is a new name', WL.renameTask(fin, 'X', 'x').ok);
    check('rename to blank is refused', !WL.renameTask(fin, 'X', '   ').ok);
    check('rename to the same name is fine', WL.renameTask(fin, 'X', 'X').ok);
    // dirty
    var a = { database: 'D', schema: 'S', tasks: [mk('A', [], { comment: null, parameters: { K: '1' } }), mk('B', ['A'])] };
    var b = WL.clone(a);
    check('equal graphs are not dirty', !WL.isDirty(a, b));
    b.tasks[0].comment = '';
    check('null and the empty string are the same', !WL.isDirty(a, b));
    b.tasks.reverse();
    check('the order of tasks does not count', !WL.isDirty(a, b));
    b.tasks[0].info = { owner: 'X' };
    check('info does not count', !WL.isDirty(a, b));
    b.tasks[1].definition = 'SELECT 2';
    check('a changed definition is dirty', WL.isDirty(a, b));
    b = WL.clone(a); b.tasks[0].parameters.K = '2';
    check('a changed parameter is dirty', WL.isDirty(a, b));
    b = WL.clone(a); b.tasks[1].after = [];
    check('a changed after is dirty', WL.isDirty(a, b));
    b = WL.clone(a); b.schema = 'T';
    check('a changed schema is dirty', WL.isDirty(a, b));
    // delete, add, finalize
    var d = WL.deleteTask([mk('R'), mk('X', ['R']), mk('Y', ['X'])], 'X');
    eq('deleting a task puts its successors after its predecessors', d.tasks.map(function (t) { return [t.name, t.after]; }), [['R', []], ['Y', ['R']]]);
    var ad2 = WL.addTask([mk('R'), mk('X', ['R'])], 'X');
    eq('a task is added after the selected one', [ad2.name, ad2.tasks[2].after], ['NEW_TASK', ['X']]);
    check('a second added task gets another name', WL.addTask(ad2.tasks, 'X').name === 'NEW_TASK_2');
    check('a lone root cannot finalize', !WL.canFinalize([mk('R')], 'R').ok);
    check('a task with predecessors cannot finalize', !WL.canFinalize([mk('R'), mk('X', ['R'])], 'X').ok);
    check('a second root may finalize', WL.canFinalize([mk('R'), mk('X'), mk('Y', ['R'])], 'X').ok);
    check('no second finalizer', !WL.canFinalize([mk('R'), mk('X', [], { finalize: 'R' }), mk('Y')], 'Y').ok);
    // payload and helpers
    var pay = WL.graphPayload({ database: 'D', schema: 'S', tasks: [mk('A', [], { comment: '', schedule: '1 MINUTE' })] });
    eq('payload: an empty field is null', pay.tasks[0].comment, null);
    check('payload has no info and only the known fields', Object.keys(pay.tasks[0]).every(function (k) { return WL.TASK_FIELDS.indexOf(k) >= 0; }));
    eq('textOrNull of blank', [WL.textOrNull(''), WL.textOrNull('  '), WL.textOrNull('x')], [null, null, 'x']);
    eq('parameter rows', WL.rowsToParams([{ key: ' a ', value: '1' }, { key: '', value: 'x' }, { key: 'A', value: '2' }]), { A: '2' });
    eq('duplicate parameter keys', WL.duplicateKeys([{ key: 'a' }, { key: 'A' }, { key: 'b' }]), ['A']);
    eq('runs: next run is picked out', [WL.isNextRun({ state: 'SCHEDULED' }), WL.isNextRun({ state: 'FAILED' })], [true, false]);
    var picked = WL.pickOverlayRun([{ runId: 'n', state: 'SCHEDULED', scheduled: '2026-11-28T02:00:00Z' }, { runId: 'o', state: 'FAILED', scheduled: '2026-11-27T02:00:00Z' }, { runId: 'p', state: 'SUCCEEDED', scheduled: '2026-11-26T02:00:00Z' }]);
    eq('the overlay run is the newest that is not scheduled', picked && picked.runId, 'o');
    eq('time format', [WL.formatTime('2026-11-26T02:00:00.000Z'), WL.formatTime('2026-11-26 02:00:00.000'), WL.formatTime('')], ['2026-11-26 02:00:00 UTC', '2026-11-26 02:00:00', '']);
    eq('run state words', [WL.runStateInfo('EXECUTING').label, WL.runStateInfo('SKIPPED').label], ['running', 'skipped']);
  }

  /* ---- the page against the demo ---- */
  async function pageTests() {
    check('the session was read', !!S.session && S.session.backend === 'Demo', JSON.stringify(S.session));
    check('the connection is in the header', $('connection').textContent.indexOf('demo') >= 0);
    check('databases are listed', S.databases && S.databases.indexOf('SALES') >= 0 && S.databases.indexOf('FINANCE') >= 0, JSON.stringify(S.databases));
    check('before a choice the list asks for one', $('graph-list').textContent.indexOf('Choose a database') >= 0);
    await A.chooseDatabase('SALES');
    check('schemas of SALES are listed without INFORMATION_SCHEMA', S.schemas && S.schemas.indexOf('LOAD') >= 0 && S.schemas.indexOf('INFORMATION_SCHEMA') < 0, JSON.stringify(S.schemas));
    await A.chooseSchema('LOAD');
    eq('three graphs in SALES.LOAD', S.graphs.map(function (g) { return g.root; }), ['CLEAN_UP', 'EVENT_ROOT', 'NIGHTLY_ROOT']);
    var items = document.querySelectorAll('#graph-list .graph-item');
    eq('three items in the list', items.length, 3);
    check('the list shows a state and a task count', $('graph-list').textContent.indexOf('7 tasks') >= 0 && $('graph-list').textContent.indexOf('suspended') >= 0);
    await A.chooseSchema('MAINTENANCE');
    check('an empty schema says so', $('graph-list').textContent.indexOf('has no tasks') >= 0, $('graph-list').textContent);
    await A.chooseSchema('LOAD');

    // open
    await A.openGraph('NIGHTLY_ROOT');
    eq('NIGHTLY_ROOT has 7 tasks', S.g.tasks.length, 7);
    eq('the root is selected', S.sel, 'NIGHTLY_ROOT');
    eq('7 boxes are drawn', nodes().length, 7);
    eq('one dashed finalizer edge', document.querySelectorAll('#canvas .edge.finalize').length, 1);
    eq('edges: 7 tasks have 6 after-edges and one finalizer edge', document.querySelectorAll('#canvas .edge').length, 8);
    check('LOAD_PRODUCTS is drawn as serverless', node('LOAD_PRODUCTS').textContent.indexOf('Serverless') >= 0);
    check('the root shows its schedule', node('NIGHTLY_ROOT').textContent.indexOf('Schedule: USING CRON') >= 0);
    check('the finalizer says what it finalizes', node('NOTIFY_DONE').textContent.indexOf('Finalizer of NIGHTLY_ROOT') >= 0);
    check('every box has a state in words', nodes().every(function (n) { return /started|suspended/.test(n.textContent); }));
    check('the inspector shows the name', $('f-name') && $('f-name').value === 'NIGHTLY_ROOT');
    check('the unsaved indicator says none', $('graph-bar').textContent.indexOf('No unsaved edits') >= 0);
    check('the operations are on (installed, clean)', $('btn-resume').getAttribute('aria-disabled') !== 'true');
    check('the problems tab says it is fine', $('panel-problems').textContent.indexOf('No problems') >= 0, $('panel-problems').textContent);
    // outcomes from the runs
    check('the runs were loaded', await until(function () { return S.runs && S.runs.list && S.runs.list.length > 0; }), JSON.stringify(S.runs && S.runs.error));
    check('4 runs in 24 hours? at least 1', S.runs.list.length >= 1);
    await A.sleep(150);
    check('boxes show the last run outcome as outline and word', document.querySelectorAll('#canvas .node.out-ok').length === 7 && node('BUILD_FACTS').textContent.indexOf('succeeded') >= 0,
      document.querySelectorAll('#canvas .node.out-ok').length);
    // a SCHEDULED run first (the next run) and a RUNNING run: the overlay uses the newest run that is not merely scheduled
    var realList = S.runs.list;
    S.runs.list = WL.sortRuns([
      { runId: 'next', state: 'SCHEDULED', scheduled: '2026-11-28T02:00:00Z', started: '', completed: '', seconds: null, tasks: [{ task: 'NIGHTLY_ROOT', state: 'SCHEDULED', started: '', completed: '', error: null, errorCode: null, queryId: null, attempt: 1 }] },
      { runId: 'live', state: 'RUNNING', scheduled: '2026-11-27T02:00:00Z', started: '2026-11-27T02:00:01Z', completed: '', seconds: null, tasks: [
        { task: 'NIGHTLY_ROOT', state: 'SUCCEEDED', started: '2026-11-27T02:00:01Z', completed: '2026-11-27T02:00:05Z', attempt: 1 },
        { task: 'LOAD_CUSTOMERS', state: 'EXECUTING', started: '2026-11-27T02:00:06Z', completed: '', attempt: 1 },
        { task: 'LOAD_ORDERS', state: 'SCHEDULED', started: '', completed: '', attempt: 1 }] }].concat(realList));
    A.setTab('runs');
    A.renderCanvas();
    check('a SCHEDULED run is shown as the next run, not as failed', $('panel-runs').textContent.indexOf('next run') >= 0 && $('panel-runs').textContent.indexOf('not started yet') >= 0);
    check('the overlay skips the scheduled run and shows the running one as it is', node('LOAD_CUSTOMERS').classList.contains('out-run') && node('LOAD_CUSTOMERS').textContent.indexOf('running') >= 0 &&
      node('LOAD_ORDERS').textContent.indexOf('scheduled') >= 0 && node('NIGHTLY_ROOT').classList.contains('out-ok'));
    S.runs.list = realList;
    A.renderCanvas();
    A.setTab('problems');
    var failedRun = S.runs.list.filter(function (r) { return r.state === 'FAILED'; })[0];
    check('a failed run exists in the demo history', !!failedRun, JSON.stringify(S.runs.list.map(function (r) { return r.state; })));
    A.setTab('runs');
    A.selectRun(failedRun.runId);
    await A.sleep(150);
    check('choosing the failed run shows failed and skipped on the boxes', node('LOAD_ORDERS').classList.contains('out-bad') && node('BUILD_FACTS').classList.contains('out-skip') &&
      node('LOAD_ORDERS').textContent.indexOf('failed') >= 0);
    check('the run detail shows the error message and code', $('panel-runs').textContent.indexOf('does not exist or not authorized') >= 0 && $('panel-runs').textContent.indexOf('2003') >= 0);
    A.selectRun(failedRun.runId);
    A.setTab('problems');

    // select and edit
    A.selectTask('LOAD_ORDERS');
    eq('selecting a task shows its name', $('f-name').value, 'LOAD_ORDERS');
    check('the selected box is marked', node('LOAD_ORDERS').classList.contains('selected') && node('LOAD_ORDERS').getAttribute('aria-pressed') === 'true');
    check('the definition is in the textarea', $('f-definition').value.indexOf('INSERT INTO orders') >= 0);
    typeInto($('f-definition'), 'SELECT 1;\nSELECT 2;');
    eq('editing the definition changes the task', task('LOAD_ORDERS').definition, 'SELECT 1;\nSELECT 2;');
    check('the page now says unsaved edits', $('graph-bar').textContent.indexOf('Unsaved edits') >= 0 && A.hasUnsaved());
    check('the operations are off with a reason', $('btn-run').getAttribute('aria-disabled') === 'true' && $('graph-bar').textContent.indexOf('unsaved edits') >= 0);
    typeInto($('f-comment'), 'a comment');
    eq('a comment is set', task('LOAD_ORDERS').comment, 'a comment');
    typeInto($('f-comment'), '');
    eq('an empty text field is null, not an empty string', task('LOAD_ORDERS').comment, null);
    typeInto($('f-warehouse'), 'BIG_WH');
    eq('warehouse set', task('LOAD_ORDERS').warehouse, 'BIG_WH');
    typeInto($('f-warehouse'), '   ');
    eq('a blank warehouse is null', task('LOAD_ORDERS').warehouse, null);
    changeTo($('f-overlap'), 'true');
    eq('three-way: true', task('LOAD_ORDERS').allowOverlappingExecution, true);
    changeTo($('f-overlap'), 'false');
    eq('three-way: false', task('LOAD_ORDERS').allowOverlappingExecution, false);
    changeTo($('f-overlap'), '');
    eq('three-way: not set', task('LOAD_ORDERS').allowOverlappingExecution, null);
    changeTo($('f-state'), 'suspended');
    eq('state: suspended', task('LOAD_ORDERS').state, 'suspended');
    await A.sleep(150);
    check('the box says suspended', node('LOAD_ORDERS').textContent.indexOf('suspended') >= 0);
    // parameters
    $('btn-add-param').click();
    var keyIn = document.querySelector('#params [data-focus="pk' + (Object.keys(task('LOAD_ORDERS').parameters).length) + '"]') || document.querySelector('#params .param-row:last-child input');
    typeInto(keyIn, 'user_task_timeout_ms');
    changeTo(keyIn, 'user_task_timeout_ms');
    var valIn = keyIn.parentNode.querySelectorAll('input')[1];
    typeInto(valIn, '60000');
    eq('a parameter row is set, with its name in capitals', task('LOAD_ORDERS').parameters.USER_TASK_TIMEOUT_MS, '60000');
    keyIn.parentNode.querySelector('button').click();
    check('a parameter row can be removed', !('USER_TASK_TIMEOUT_MS' in task('LOAD_ORDERS').parameters));
    // after checklist
    var boxes = document.querySelectorAll('#f-after-set input[type=checkbox]');
    var cb = Array.prototype.filter.call(boxes, function (b) { return b.getAttribute('data-focus') === 'after:LOAD_CUSTOMERS'; })[0];
    check('the checklist offers the other tasks', !!cb && boxes.length >= 5);
    check('a task is not offered as after itself', !document.querySelector('[data-focus="after:LOAD_ORDERS"]'));
    var cyc = document.querySelector('#f-after-set [data-focus="after:BUILD_FACTS"]');
    check('a task that comes after it is disabled (cycle)', cyc && cyc.disabled);
    cb.checked = true; cb.dispatchEvent(new Event('change', { bubbles: true }));
    check('checking a predecessor adds it', task('LOAD_ORDERS').after.indexOf('LOAD_CUSTOMERS') >= 0 && task('LOAD_ORDERS').after.indexOf('NIGHTLY_ROOT') >= 0);
    await A.sleep(100);
    check('the canvas has the new edge', document.querySelectorAll('#canvas .edge').length === 9, document.querySelectorAll('#canvas .edge').length);
    check('the finalize box is disabled with a reason for a task with predecessors', $('f-finalize').disabled && $('f-finalize').parentNode.parentNode.textContent.indexOf('Not available') >= 0);
    // validation after a moment
    check('validation after an edit found no errors', await until(function () { return !S.validating; }, 4000) && S.problems.filter(function (p) { return p.severity === 'error'; }).length === 0, JSON.stringify(S.problems));
    // a deliberate error: schedule on a child
    A.selectTask('LOAD_CUSTOMERS');
    typeInto($('f-schedule'), '5 MINUTE');
    check('a schedule on a child is reported', await until(function () { return S.problems.some(function (p) { return p.code === 'schedule-on-child' && p.task === 'LOAD_CUSTOMERS'; }); }, 5000), JSON.stringify(S.problems));
    await A.sleep(150);
    check('the box has a problem mark', !!node('LOAD_CUSTOMERS').querySelector('.mark-bg.error'));
    check('the problems tab lists it with the word Error', $('panel-problems').textContent.indexOf('Error') >= 0 && $('panel-problems').textContent.indexOf('only the root task can have one') >= 0);
    check('the tab count says errors', $('problem-count').textContent.indexOf('error') >= 0, $('problem-count').textContent);
    A.selectTask('NIGHTLY_ROOT');
    var pb = document.querySelector('#panel-problems button.problem');
    pb.click();
    eq('clicking a problem selects its task', S.sel, 'LOAD_CUSTOMERS');
    typeInto($('f-schedule'), '');
    eq('the schedule is null again', task('LOAD_CUSTOMERS').schedule, null);

    // plan with errors: a second root
    A.selectTask('LOAD_PRODUCTS');
    var prodCb = document.querySelector('#f-after-set [data-focus="after:NIGHTLY_ROOT"]');
    prodCb.checked = false; prodCb.dispatchEvent(new Event('change', { bubbles: true }));
    await A.planChanges();
    check('with an error the plan says there is none', S.plan.data && S.plan.data.plan === null && $('panel-plan').textContent.indexOf('There is no plan') >= 0, $('panel-plan').textContent);
    check('Apply is disabled without a plan', $('btn-apply').disabled);
    prodCb = document.querySelector('#f-after-set [data-focus="after:NIGHTLY_ROOT"]');
    prodCb.checked = true; prodCb.dispatchEvent(new Event('change', { bubbles: true }));

    // rename
    A.selectTask('LOAD_ORDERS');
    var nameIn = $('f-name');
    changeTo(nameIn, 'LOAD_ORDERS_V2');
    check('renamed in the task list', !!task('LOAD_ORDERS_V2') && !task('LOAD_ORDERS'));
    eq('the selection follows the rename', S.sel, 'LOAD_ORDERS_V2');
    check('BUILD_FACTS is now after the new name', task('BUILD_FACTS').after.indexOf('LOAD_ORDERS_V2') >= 0 && task('BUILD_FACTS').after.indexOf('LOAD_ORDERS') < 0);
    eq('the inspector shows the new name', $('f-name').value, 'LOAD_ORDERS_V2');
    changeTo($('f-name'), 'LOAD_CUSTOMERS');
    check('renaming to a taken name is refused with a message', $('f-name-err').textContent.indexOf('already a task') >= 0 && $('f-name').value === 'LOAD_ORDERS_V2', $('f-name-err').textContent);
    A.selectTask('NIGHTLY_ROOT');
    changeTo($('f-name'), 'NIGHTLY_X');
    eq('the root is renamed in the graph', S.g.root, 'NIGHTLY_X');
    eq('the finalizer follows the root rename', task('NOTIFY_DONE').finalize, 'NIGHTLY_X');
    check('children are after the new root name', task('LOAD_CUSTOMERS').after.indexOf('NIGHTLY_X') >= 0 && task('LOAD_PRODUCTS').after.indexOf('NIGHTLY_X') >= 0);
    check('the graph bar shows the new root name', $('graph-bar').textContent.indexOf('NIGHTLY_X') >= 0);
    await A.sleep(100);
    check('the canvas was redrawn with the new name', !!node('NIGHTLY_X') && !node('NIGHTLY_ROOT'));

    // add and delete
    A.selectTask('PUBLISH');
    var n0 = S.g.tasks.length;
    var added = A.addTask();
    eq('add task: one more', S.g.tasks.length, n0 + 1);
    eq('the new task is selected and comes after the selected one', [S.sel, task(added).after], [added, ['PUBLISH']]);
    check('the name field is focused for typing', document.activeElement === $('f-name'));
    A.deleteSelected();
    eq('delete task: back again', S.g.tasks.length, n0);
    A.selectTask('BUILD_FACTS');
    A.deleteSelected();
    check('deleting a middle task rewires its successor', task('PUBLISH').after.indexOf('LOAD_CUSTOMERS') >= 0, JSON.stringify(task('PUBLISH').after));
    var undo = Array.prototype.filter.call($('toasts').querySelectorAll('.toast button'), function (b) { return b.textContent === 'Undo'; })[0];
    check('the delete toast offers Undo', !!undo && undo.textContent === 'Undo');
    undo.click();
    check('undo brings the task back', !!task('BUILD_FACTS') && task('PUBLISH').after.indexOf('BUILD_FACTS') >= 0);
    // the Del key
    A.selectTask('PUBLISH');
    document.body.dispatchEvent(new KeyboardEvent('keydown', { key: 'Delete', bubbles: true }));
    check('the Del key deletes the selected task', !task('PUBLISH'));
    A.selectTask('LOAD_PRODUCTS');
    typeInto($('f-definition'), 'x');
    document.getElementById('f-definition').dispatchEvent(new KeyboardEvent('keydown', { key: 'Delete', bubbles: true }));
    check('the Del key in a text field does not delete the task', !!task('LOAD_PRODUCTS'));

    // plan of the edited graph (valid): rename means drop and create
    await until(function () { return !S.validating; }, 4000);
    await A.planChanges();
    var pl = S.plan.data && S.plan.data.plan;
    check('the plan of the edited graph has steps', !!pl && pl.steps.length > 0, JSON.stringify(S.plan));
    check('the plan names its phases and tasks', !!pl && pl.steps.every(function (st) { return st.phase && st.task && st.sql; }));
    check('the plan shows SQL in monospace blocks', document.querySelectorAll('#panel-plan pre.sql').length === pl.steps.length);
    check('the plan reports removed tasks', pl.removed.length > 0 || pl.steps.some(function (st) { return st.phase === 'drop'; }));
    check('Apply is enabled for this plan', !$('btn-apply').disabled);
    typeInto($('f-definition'), 'y');
    check('after another edit the plan is stale and Apply is off', $('btn-apply').disabled && $('panel-plan').textContent.indexOf('plan again') >= 0 || $('panel-plan').textContent.indexOf('Plan again') >= 0, $('panel-plan').textContent.slice(0, 200));
    await A.sleep(100);
    // SQL
    A.setTab('sql');
    check('the SQL script appears', await until(function () { return S.sql && S.sql.text && S.sql.rev === S.rev; }, 5000) && /CREATE/i.test($('sql-text').textContent), JSON.stringify(S.sql));
    check('Copy and Download are available', !$('btn-sql-copy').disabled && !$('btn-sql-download').disabled);
    $('btn-sql-download').click();
    check('Download gives a .sql file', downloads.length === 1 && /\.sql$/.test(downloads[0].name) && downloads[0].text.indexOf('CREATE') >= 0, JSON.stringify(downloads.map(function (d) { return d.name; })));
    A.setTab('problems');

    // discard
    answer = false; asked.length = 0;
    await A.discardChanges();
    check('discard asks first, and "no" keeps the edits', asked.length === 1 && A.hasUnsaved());
    answer = true;
    await A.discardChanges();
    check('discard brings the graph back', !A.hasUnsaved() && S.g.tasks.length === 7 && !!task('LOAD_ORDERS') && S.g.root === 'NIGHTLY_ROOT');
    await A.sleep(150);
    check('the canvas is back with 7 boxes', nodes().length === 7 && !!node('NIGHTLY_ROOT'));

    // plan of an unedited graph is empty
    await A.planChanges();
    check('an unedited graph needs no changes, and says so', S.plan.data.plan && S.plan.data.plan.isEmpty && $('panel-plan').textContent.indexOf('Nothing has to change') >= 0, $('panel-plan').textContent);
    check('Apply is disabled for an empty plan', $('btn-apply').disabled);

    // apply
    A.selectTask('LOAD_CUSTOMERS');
    typeInto($('f-comment'), 'from the self-test');
    await A.planChanges();
    pl = S.plan.data.plan;
    check('a comment edit gives a plan with steps', pl && !pl.isEmpty && pl.steps.length >= 1, JSON.stringify(pl));
    answer = false; asked.length = 0;
    await A.applyPlan();
    check('apply asks for confirmation naming the steps', asked.length === 1 && asked[0].title.indexOf(pl.steps.length + ' step') >= 0, asked[0] && asked[0].title);
    check('"no" applies nothing', !S.plan.applied);
    answer = true; asked.length = 0;
    await A.applyPlan();
    check('after the apply the plan is shown as applied', S.plan.applied === true && S.plan.data.plan.executed >= 1 && $('panel-plan').textContent.indexOf('Applied') >= 0, JSON.stringify(S.plan.data && S.plan.data.plan && S.plan.data.plan.executed));
    check('the graph was read back and is clean', !A.hasUnsaved() && S.g.origin === 'installed');

    // guard on switching
    A.selectTask('LOAD_CUSTOMERS');
    typeInto($('f-comment'), 'edit that must not be lost');
    answer = false; asked.length = 0;
    var moved = await A.openGraph('CLEAN_UP');
    check('switching graph with unsaved edits asks, and "no" stays', moved === false && S.g.root === 'NIGHTLY_ROOT' && asked.length === 1 && A.hasUnsaved());
    var changedSchema = await A.chooseSchema('MAINTENANCE');
    check('switching schema asks too', changedSchema === false && S.schema === 'LOAD' && asked.length === 2);
    answer = true;
    moved = await A.openGraph('CLEAN_UP');
    check('"yes" switches', moved === true && S.g.root === 'CLEAN_UP' && !A.hasUnsaved());
    eq('CLEAN_UP is a single task', S.g.tasks.length, 1);
    check('a single-task graph has a box and no edge', nodes().length === 1 && document.querySelectorAll('#canvas .edge').length === 0);
    await A.openGraph('EVENT_ROOT');
    check('EVENT_ROOT: the condition mark WHEN is drawn', node('EVENT_ROOT').textContent.indexOf('WHEN') >= 0);
    check('EVENT_ROOT is suspended in the bar', $('graph-bar').textContent.indexOf('suspended') >= 0);

    // operate
    await A.openGraph('NIGHTLY_ROOT');
    asked.length = 0;
    await A.operate('suspend');
    check('suspend asks, naming the graph', asked.length === 1 && asked[0].title.indexOf('NIGHTLY_ROOT') >= 0);
    check('after suspend the graph is suspended', S.g.state === 'suspended' && S.graphs.filter(function (g) { return g.root === 'NIGHTLY_ROOT'; })[0].state === 'suspended', S.g.state);
    await A.operate('resume');
    check('after resume it is started', S.g.state === 'started');
    await A.operate('run');
    check('run now is accepted', asked.length === 3 && toastText().indexOf('started a run of NIGHTLY_ROOT') >= 0);
    await A.operate('retry');
    check('retry is accepted', toastText().indexOf('retried the last run of NIGHTLY_ROOT') >= 0);
    // export
    downloads.length = 0;
    await A.exportGraph();
    check('export downloads the text under fileName', downloads.length === 1 && /NIGHTLY_ROOT\.json$/.test(downloads[0].name) && downloads[0].text.indexOf('"tasks"') >= 0, JSON.stringify(downloads.map(function (d) { return d.name; })));
    var exported = downloads[0].text;

    // import
    var fileText = JSON.stringify({ format: 'workflower-graph', version: 1, database: 'FINANCE', schema: 'GL', tasks: [
      { name: 'GL_ROOT', definition: 'SELECT 1', schedule: '60 MINUTE' }, { name: 'GL_CHILD', after: ['GL_ROOT'], definition: 'SELECT 2' }] });
    await A.importText(fileText, 'gl.json');
    check('import opens an unsaved graph', S.g.origin === 'imported' && S.g.tasks.length === 2 && S.g.root === 'GL_ROOT');
    check('import shows which database and schema it names', $('notices').textContent.indexOf('FINANCE.GL') >= 0 && $('notices').textContent.indexOf('not the schema selected') >= 0, $('notices').textContent);
    check('the imported graph is in the list as not installed', $('graph-list').textContent.indexOf('not installed') >= 0);
    check('operations are off for it with a reason', $('btn-resume').getAttribute('aria-disabled') === 'true' && $('graph-bar').textContent.indexOf('not installed') >= 0);
    check('the runs tab says it has no runs', (A.setTab('runs'), $('panel-runs').textContent.indexOf('no runs') >= 0));
    A.setTab('problems');
    await A.planChanges();
    check('the plan of an imported graph is a creation', S.plan.data.plan && S.plan.data.plan.exists === false && S.plan.data.plan.database === 'FINANCE' && S.plan.data.plan.steps.length >= 2, JSON.stringify(S.plan.data && S.plan.data.plan && S.plan.data.plan.exists));
    check('the plan says the graph is not installed yet', $('panel-plan').textContent.indexOf('not installed yet') >= 0);
    clearToasts();
    answer = true;
    check('a file that is not a graph gives an error message, not silence', (await A.importText('{"x":1}', 'bad.json')) === false && toastText().indexOf('no "tasks"') >= 0, toastText());
    check('the open graph stays after a failed import', S.g.root === 'GL_ROOT');
    clearToasts();
    await A.importText('this is not json', 'bad2.json');
    check('invalid JSON also gives a message', toastText().length > 10 && toastText().indexOf('Error') >= 0, toastText());
    // the imported graph is "dirty" only when edited
    check('an untouched imported graph is not "unsaved edits"', !A.hasUnsaved());
    // import of the exported text again
    await A.importText(exported, 'NIGHTLY.json');
    eq('the exported file imports to 7 tasks', S.g.tasks.length, 7);
    eq('with its own database and schema', [S.g.database, S.g.schema], ['SALES', 'LOAD']);

    // new graph
    A.makeNewGraph('MY_ROOT', 'MY_CHILD');
    check('a new graph is a root with a schedule and one child', S.g.origin === 'new' && S.g.tasks.length === 2 && !!task('MY_ROOT').schedule && task('MY_CHILD').after[0] === 'MY_ROOT');
    check('it lives in the selected schema', S.g.database === 'SALES' && S.g.schema === 'LOAD');
    await until(function () { return !S.validating; }, 4000);
    check('a new graph is valid', S.problems.filter(function (p) { return p.severity === 'error'; }).length === 0, JSON.stringify(S.problems));
    check('the list shows it as not installed', $('graph-list').textContent.indexOf('new, not installed') >= 0);
    await A.planChanges();
    check('the plan creates it', S.plan.data.plan && S.plan.data.plan.exists === false && S.plan.data.plan.steps.some(function (st) { return st.phase === 'create'; }));
    // finalize checkbox: add a second root-capable task
    A.selectTask('MY_CHILD');
    check('a child with predecessors cannot be a finalizer', $('f-finalize').disabled);
    var extra = A.addTask();
    A.selectTask(extra);
    var ecb = document.querySelector('#f-after-set [data-focus="after:MY_CHILD"]');
    ecb.checked = false; ecb.dispatchEvent(new Event('change', { bubbles: true }));
    var rootCb = document.querySelector('#f-after-set [data-focus="after:MY_ROOT"]');
    if (rootCb && rootCb.checked) { rootCb.checked = false; rootCb.dispatchEvent(new Event('change', { bubbles: true })); }
    check('a task with no predecessors, with another root present, may finalize', !$('f-finalize').disabled, $('f-finalize').parentNode.parentNode.textContent);
    $('f-finalize').checked = true; $('f-finalize').dispatchEvent(new Event('change', { bubbles: true }));
    eq('checking it sets finalize to the root', task(extra).finalize, 'MY_ROOT');
    await A.sleep(200);
    check('and it is drawn as a finalizer in the last column', S.layout.nodeByName[extra].x > S.layout.nodeByName.MY_CHILD.x);
    check('the second finalizer is no longer offered on another task', (function () { A.selectTask('MY_CHILD'); return $('f-finalize').disabled; })());
    // discarding a new graph closes it
    answer = true;
    await A.discardChanges();
    check('discarding a new graph closes it', S.g === null && $('canvas-empty').textContent.indexOf('No graph is open') >= 0);
    check('with no graph the inspector and bar say so', $('inspector').textContent.indexOf('No graph is open') >= 0 && $('graph-bar').textContent.indexOf('No graph is open') >= 0);

    // refresh with unsaved edits
    await A.openGraph('NIGHTLY_ROOT');
    A.selectTask('PUBLISH'); typeInto($('f-comment'), 'x');
    answer = false; asked.length = 0;
    await A.refresh();
    check('refresh with unsaved edits asks', asked.length === 1 && A.hasUnsaved());
    answer = true;
    await A.refresh();
    check('"yes" reloads and drops the edits', !A.hasUnsaved() && task('PUBLISH').comment === null);

    // the security of the page: text from Snowflake is text
    var evil = JSON.stringify({ format: 'workflower-graph', version: 1, database: 'SALES', schema: 'LOAD', tasks: [
      { name: '<img src=x onerror=window.__pwned=1>', definition: '</pre><script>window.__pwned=1</script>', schedule: '1 MINUTE', comment: '"><svg onload=window.__pwned=1>' },
      { name: 'KID', after: ['<img src=x onerror=window.__pwned=1>'], definition: 'SELECT 1' }] });
    await A.importText(evil, '<b>evil</b>.json');
    A.selectTask('<img src=x onerror=window.__pwned=1>');
    await A.planChanges();
    await A.sleep(300);
    check('markup in names and SQL stays text', !window.__pwned && document.querySelectorAll('#canvas image, #inspector img, #panel-plan img').length === 0 && $('f-comment').value === '"><svg onload=window.__pwned=1>');
    check('the name is shown as text in the box', node('<img src=x onerror=window.__pwned=1>').textContent.indexOf('<img') >= 0);
    await A.importText(fileText, 'gl.json');
  }

  async function bigGraph(n) {
    var tasks = WL.syntheticTasks(n, 6).map(function (t) {
      var c = WL.clone(t);
      c.state = null;
      return c;
    });
    tasks[3].name = 'A_TASK_WITH_A_VERY_LONG_NAME_THAT_KEEPS_GOING_AND_GOING_UNTIL_IT_DOES_NOT_FIT_IN_ANY_BOX';
    tasks.forEach(function (t, i) { t.after = t.after.map(function (a) { return a === 'SYN_L1_T3' ? tasks[3].name : a; }); });
    var lines = [];
    for (var i = 1; i <= 60; i++) lines.push('  INSERT INTO target_table_' + i + ' SELECT col_a, col_b, col_c FROM source_table_' + i + ' WHERE load_date = CURRENT_DATE() AND flag = ' + i + ';');
    tasks[4].definition = 'BEGIN\n' + lines.join('\n') + '\nEND;';
    var text = JSON.stringify({ format: 'workflower-graph', version: 1, database: 'SALES', schema: 'LOAD', tasks: tasks });
    await A.importText(text, 'big.json');
    A.selectTask(tasks[4].name);
    return tasks;
  }

  async function run() {
    var t0 = Date.now();
    try {
      pureTests();
      await pageTests();
    } catch (e) {
      failures++;
      results.push('FAIL the self-test stopped with an exception: ' + (e && e.stack ? e.stack : e));
    }
    results.push((failures ? 'FAILED' : 'ALL PASSED') + ': ' + results.filter(function (r) { return r.indexOf('PASS') === 0; }).length + ' passed, ' + failures + ' failed, ' + (Date.now() - t0) + ' ms');
    pre.textContent = results.join('\n');
    pre.setAttribute('data-done', failures ? 'failed' : 'passed');
    var scene = new URLSearchParams(location.search).get('scene');
    if (scene) {
      clearToasts();
      answer = true;
      await A.chooseSchema('LOAD', { noGuard: true });
      await A.openGraph('NIGHTLY_ROOT', { noGuard: true });
      await A.sleep(300);
      A.selectTask('LOAD_ORDERS');
      document.getElementById('f-comment').value = 'x';
      document.getElementById('f-comment').dispatchEvent(new Event('input', { bubbles: true }));
      A.applyRename('LOAD_ORDERS', 'LOAD_ORDERS_V2');
      if (scene === 'errors') {
        A.selectTask('LOAD_CUSTOMERS');
        var sch = document.getElementById('f-schedule');
        sch.value = '5 MINUTE'; sch.dispatchEvent(new Event('input', { bubbles: true }));
        await A.sleep(700);
        A.setTab('problems');
      } else if (scene === 'plan') {
        await A.sleep(700);
        await A.planChanges();
      } else if (scene === 'sql') {
        A.setTab('sql');
        await A.sleep(700);
      }
    }
    var big = new URLSearchParams(location.search).get('big');
    if (big) {
      answer = true;
      await bigGraph(Number(big));
      A.fitView();
    }
  }

  run();
})();
