/* Workflower: the pure functions of the interface. Nothing here touches the DOM, the network or the clock, so the same file runs in a
   browser (as the global WfLayout) and under a test runner (module.exports).

   A task is the object of the API: {name, definition, after:[names], finalize, schedule, warehouse, condition,
   allowOverlappingExecution, errorIntegration, comment, config, parameters:{}, state, info?}. Names are exact (case and all). */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.WfLayout = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var NODE_W = 200, NODE_H = 84, GAP_X = 46, GAP_Y = 22, DUMMY_H = 12, PAD = 28;

  var TASK_FIELDS = ['name', 'definition', 'after', 'finalize', 'schedule', 'warehouse', 'condition',
    'allowOverlappingExecution', 'errorIntegration', 'comment', 'config', 'parameters', 'state'];

  function clone(x) { return x === undefined ? x : JSON.parse(JSON.stringify(x)); }

  function isFinalizer(t) { return !!t.finalize && !(t.after && t.after.length); }

  /* The first task of each name; a later task of the same name is a duplicate (the checker reports it) and is not drawn. */
  function uniqueTasks(tasks) {
    var seen = new Set(), out = [];
    (tasks || []).forEach(function (t) { if (!seen.has(t.name)) { seen.add(t.name); out.push(t); } });
    return out;
  }

  /* The layer of each task: one more than its deepest predecessor; the finalizer (finalize set, no after) in a column after all
     the others. A predecessor that is not in the graph, a task after itself and the edge that closes a cycle are ignored, so a graph
     with a cycle still gets a layer for every task (cyclic lists the tasks where a cycle was cut). */
  function computeLayers(tasks) {
    var list = uniqueTasks(tasks);
    var byName = new Map();
    list.forEach(function (t) { byName.set(t.name, t); });
    var layer = new Map(), mark = new Map(), cyclic = [];
    function visit(name) {
      if (mark.get(name) === 2) return layer.get(name);
      if (mark.get(name) === 1) { if (cyclic.indexOf(name) < 0) cyclic.push(name); return -1; }
      mark.set(name, 1);
      var t = byName.get(name), best = -1;
      (t.after || []).forEach(function (a) {
        if (a === name || !byName.has(a) || isFinalizer(byName.get(a))) return;
        var l = visit(a);
        if (l > best) best = l;
      });
      mark.set(name, 2);
      layer.set(name, best + 1);
      return best + 1;
    }
    var max = -1;
    list.forEach(function (t) { if (!isFinalizer(t)) { var l = visit(t.name); if (l > max) max = l; } });
    var out = {};
    list.forEach(function (t) { if (!isFinalizer(t)) out[t.name] = layer.get(t.name); });
    var last = Math.max(max, 0) + (max < 0 ? 0 : 1);
    list.forEach(function (t) { if (isFinalizer(t)) out[t.name] = last; });
    var maxLayer = 0;
    Object.keys(out).forEach(function (k) { if (out[k] > maxLayer) maxLayer = out[k]; });
    return { layers: out, maxLayer: maxLayer, cyclic: cyclic };
  }

  /* Pool adjacent violators: the nondecreasing sequence closest (least squares) to z. */
  function isotonic(z) {
    var blocks = [];
    z.forEach(function (v) {
      blocks.push({ sum: v, n: 1 });
      while (blocks.length > 1) {
        var b = blocks[blocks.length - 1], a = blocks[blocks.length - 2];
        if (a.sum / a.n <= b.sum / b.n) break;
        blocks.pop();
        a.sum += b.sum; a.n += b.n;
      }
    });
    var out = [];
    blocks.forEach(function (b) { for (var i = 0; i < b.n; i++) out.push(b.sum / b.n); });
    return out;
  }

  function stableSortBy(items, key) {
    return items.map(function (it, i) { return { it: it, i: i, k: key(it) }; })
      .sort(function (a, b) { return a.k - b.k || a.i - b.i; })
      .map(function (x) { return x.it; });
  }

  /* The drawing of a graph: boxes in layers, left to right, and a curve for every edge. An edge across several layers goes through
     a free slot in each layer between (a dummy), so that it does not run through a box. The finalizer's dashed edge from the root
     keeps to the bottom of the layers.

     Returns {nodes:[{name,x,y,w,h,layer}], nodeByName, edges:[{from,to,kind:'after'|'finalize'|'back',points,d}], width, height,
     layerCount, cyclic}. */
  function layoutGraph(tasks, options) {
    var o = options || {};
    var W = o.nodeWidth || NODE_W, H = o.nodeHeight || NODE_H, gx = o.gapX || GAP_X, gy = o.gapY || GAP_Y;
    var list = uniqueTasks(tasks);
    var res = { nodes: [], nodeByName: {}, edges: [], width: 2 * PAD, height: 2 * PAD, layerCount: 0, cyclic: [] };
    if (!list.length) return res;
    var L = computeLayers(list);
    res.cyclic = L.cyclic;
    var layerOf = L.layers;
    var layerCount = L.maxLayer + 1;
    res.layerCount = layerCount;
    var byName = {};
    list.forEach(function (t) { byName[t.name] = t; });

    // items: the real boxes and the dummies
    var items = [], cols = [];
    for (var i = 0; i < layerCount; i++) cols.push([]);
    function addItem(it) { it.id = items.length; it.up = []; it.down = []; items.push(it); cols[it.layer].push(it); return it; }
    var realItem = {};
    list.forEach(function (t) { realItem[t.name] = addItem({ name: t.name, dummy: false, layer: layerOf[t.name], h: H, pin: false }); });

    var edgeDefs = [];
    list.forEach(function (t) {
      (t.after || []).forEach(function (a) {
        if (a === t.name || !byName[a]) return;
        edgeDefs.push({ from: a, to: t.name, kind: 'after' });
      });
      if (t.finalize && byName[t.finalize] && t.finalize !== t.name) edgeDefs.push({ from: t.finalize, to: t.name, kind: 'finalize' });
    });
    edgeDefs.forEach(function (e) {
      var l1 = layerOf[e.from], l2 = layerOf[e.to];
      e.chain = [realItem[e.from]];
      if (l2 <= l1) { e.kind = 'back'; e.chain.push(realItem[e.to]); return; }
      for (var l = l1 + 1; l < l2; l++) e.chain.push(addItem({ name: null, dummy: true, layer: l, h: DUMMY_H, pin: e.kind === 'finalize', edge: e }));
      e.chain.push(realItem[e.to]);
      for (var k = 0; k + 1 < e.chain.length; k++) { e.chain[k].down.push(e.chain[k + 1]); e.chain[k + 1].up.push(e.chain[k]); }
    });

    // the order in each layer: the mean position of the neighbours, a few sweeps down and up
    function positions() { cols.forEach(function (c) { c.forEach(function (it, i) { it.pos = i; }); }); }
    positions();
    function sweep(l, side) {
      var c = cols[l];
      var sorted = stableSortBy(c, function (it) {
        if (it.pin) return 1e9 + it.pos;
        var ns = it[side];
        if (!ns.length) return it.pos;
        var s = 0; ns.forEach(function (n) { s += n.pos; });
        return s / ns.length;
      });
      cols[l] = sorted;
      sorted.forEach(function (it, i) { it.pos = i; });
    }
    for (var iter = 0; iter < 8; iter++) {
      for (var l = 1; l < layerCount; l++) sweep(l, 'up');
      for (var m = layerCount - 2; m >= 0; m--) sweep(m, 'down');
    }

    // the vertical place: close to the neighbours, in the order above, with a gap
    cols.forEach(function (c) {
      var y = 0;
      c.forEach(function (it) { it.y = y; y += it.h + gy; });
    });
    var tallest = 0;
    cols.forEach(function (c) {
      var hgt = c.length ? c[c.length - 1].y + c[c.length - 1].h : 0;
      c.total = hgt;
      if (hgt > tallest) tallest = hgt;
    });
    cols.forEach(function (c) { var d = (tallest - c.total) / 2; c.forEach(function (it) { it.y += d; }); });
    function place(c, side) {
      if (!c.length) return;
      var offsets = [], acc = 0, z = [];
      c.forEach(function (it) { offsets.push(acc); acc += it.h + gy; });
      c.forEach(function (it, i) {
        var ns = side === 'both' ? it.up.concat(it.down) : it[side];
        var top = it.y;
        if (ns.length) {
          var s = 0; ns.forEach(function (n) { s += n.y + n.h / 2; });
          top = s / ns.length - it.h / 2;
        }
        z.push(top - offsets[i]);
      });
      var fit = isotonic(z);
      c.forEach(function (it, i) { it.y = fit[i] + offsets[i]; });
    }
    for (var r = 0; r < 6; r++) {
      for (var a = 1; a < layerCount; a++) place(cols[a], 'up');
      for (var b = layerCount - 2; b >= 0; b--) place(cols[b], 'down');
    }
    for (var f = 0; f < layerCount; f++) place(cols[f], 'both');
    var minY = Infinity, maxY = -Infinity;
    items.forEach(function (it) { if (it.y < minY) minY = it.y; if (it.y + it.h > maxY) maxY = it.y + it.h; });
    items.forEach(function (it) { it.y = it.y - minY + PAD; });
    maxY = maxY - minY + PAD;
    items.forEach(function (it) { it.x = PAD + it.layer * (W + gx); });

    // the result
    items.forEach(function (it) {
      if (it.dummy) return;
      var n = { name: it.name, x: it.x, y: it.y, w: W, h: H, layer: it.layer };
      res.nodes.push(n);
      res.nodeByName[n.name] = n;
    });
    res.width = PAD * 2 + layerCount * W + (layerCount - 1) * gx;
    res.height = maxY + PAD;
    edgeDefs.forEach(function (e) {
      var src = realItem[e.from], dst = realItem[e.to];
      var pts;
      if (e.kind === 'back') {
        var sx = src.x + W, sy = src.y + H / 2, tx = dst.x, ty = dst.y + H / 2;
        var top = Math.min(src.y, dst.y) - 36;
        pts = [{ x: sx, y: sy }, { x: sx + 40, y: top }, { x: tx - 40, y: top }, { x: tx, y: ty }];
        e.points = pts;
        e.d = 'M' + r1(sx) + ',' + r1(sy) + ' C' + r1(sx + 70) + ',' + r1(top) + ' ' + r1(tx - 70) + ',' + r1(top) + ' ' + r1(tx) + ',' + r1(ty);
      } else {
        pts = e.chain.map(function (it, idx) {
          if (idx === 0) return { x: it.x + W, y: it.y + it.h / 2 };
          if (idx === e.chain.length - 1) return { x: it.x, y: it.y + it.h / 2 };
          return { x: it.x + W / 2, y: it.y + it.h / 2 };
        });
        e.points = pts;
        e.d = smoothPath(pts);
      }
      res.edges.push({ from: e.from, to: e.to, kind: e.kind, points: e.points, d: e.d });
    });
    return res;
  }

  function r1(v) { return Math.round(v * 10) / 10; }

  /* A smooth curve through the points, horizontal where it passes each of them. */
  function smoothPath(pts) {
    var d = 'M' + r1(pts[0].x) + ',' + r1(pts[0].y);
    for (var i = 1; i < pts.length; i++) {
      var p = pts[i - 1], q = pts[i], dx = (q.x - p.x) * 0.5;
      d += ' C' + r1(p.x + dx) + ',' + r1(p.y) + ' ' + r1(q.x - dx) + ',' + r1(q.y) + ' ' + r1(q.x) + ',' + r1(q.y);
    }
    return d;
  }

  /* Pairs of boxes that overlap (none should); for the tests. */
  function findOverlaps(layout) {
    var out = [], n = layout.nodes;
    for (var i = 0; i < n.length; i++) {
      for (var j = i + 1; j < n.length; j++) {
        var a = n[i], b = n[j];
        if (a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h) out.push([a.name, b.name]);
      }
    }
    return out;
  }

  /* ---- the tasks of a graph ---- */

  function findTask(tasks, name) {
    for (var i = 0; i < tasks.length; i++) if (tasks[i].name === name) return tasks[i];
    return null;
  }

  /* The first task that has no predecessor and does not finalize: the root (null when there is none). */
  function deriveRoot(tasks) {
    for (var i = 0; i < tasks.length; i++) {
      var t = tasks[i];
      if (!(t.after && t.after.length) && !t.finalize) return t.name;
    }
    return null;
  }

  /* started or suspended, as the root says (a root with no state is suspended). */
  function graphState(tasks) {
    var r = deriveRoot(tasks), t = r === null ? null : findTask(tasks, r);
    return t && t.state === 'started' ? 'started' : 'suspended';
  }

  /* A task renamed everywhere: its own name, every `after` and every `finalize` that mentions it. Returns {ok, error, tasks}; the
     tasks given are not changed. A name is refused when it is empty (blank) or another task has it (names are exact: case counts). */
  function renameTask(tasks, oldName, newName) {
    if (typeof newName !== 'string' || newName.trim() === '') return { ok: false, error: 'The name cannot be empty.', tasks: tasks };
    if (!findTask(tasks, oldName)) return { ok: false, error: "There is no task called '" + oldName + "'.", tasks: tasks };
    if (newName !== oldName && findTask(tasks, newName)) return { ok: false, error: "There is already a task called '" + newName + "'.", tasks: tasks };
    var out = tasks.map(function (t) {
      var c = clone(t);
      if (c.name === oldName) c.name = newName;
      if (c.after) c.after = c.after.map(function (a) { return a === oldName ? newName : a; });
      if (c.finalize === oldName) c.finalize = newName;
      return c;
    });
    return { ok: true, error: '', tasks: out };
  }

  /* The names of the tasks that come after a task, directly or not. */
  function descendants(tasks, name) {
    var kids = {};
    tasks.forEach(function (t) { (t.after || []).forEach(function (a) { (kids[a] = kids[a] || []).push(t.name); }); });
    var seen = new Set(), stack = [name];
    while (stack.length) {
      var n = stack.pop();
      (kids[n] || []).forEach(function (k) { if (!seen.has(k)) { seen.add(k); stack.push(k); } });
    }
    return seen;
  }

  /* May this task be the finalizer? It must have no predecessor and no successor, the graph must have no other finalizer, and
     some other task must be left to be the root. Returns {ok, reason} (reason says why not). */
  function canFinalize(tasks, name) {
    var t = findTask(tasks, name);
    if (!t) return { ok: false, reason: 'There is no such task.' };
    if (t.finalize) return { ok: true, reason: '' };
    if (t.after && t.after.length) return { ok: false, reason: 'A finalizer has no predecessors; this task has some.' };
    for (var i = 0; i < tasks.length; i++) {
      if (tasks[i].name !== name && tasks[i].finalize) return { ok: false, reason: 'The graph already has a finalizer (' + tasks[i].name + ').' };
    }
    for (var j = 0; j < tasks.length; j++) {
      if ((tasks[j].after || []).indexOf(name) >= 0) return { ok: false, reason: 'Other tasks come after this one; nothing can come after a finalizer.' };
    }
    var another = tasks.some(function (x) { return x.name !== name && !(x.after && x.after.length) && !x.finalize; });
    if (!another) return { ok: false, reason: 'This is the only root; a finalizer needs a root to finalize.' };
    return { ok: true, reason: '' };
  }

  function makeTask(name, props) {
    var t = { name: name, definition: '', after: [], finalize: null, schedule: null, warehouse: null, condition: null,
      allowOverlappingExecution: null, errorIntegration: null, comment: null, config: null, parameters: {}, state: null };
    if (props) Object.keys(props).forEach(function (k) { t[k] = props[k]; });
    return t;
  }

  function uniqueName(tasks, base) {
    if (!findTask(tasks, base)) return base;
    for (var i = 2; ; i++) if (!findTask(tasks, base + '_' + i)) return base + '_' + i;
  }

  /* A task added. It comes after `afterName` when that is a task that can have successors, else after the root; the first task of
     an empty graph has no predecessor. Returns {tasks, name}. */
  function addTask(tasks, afterName) {
    var out = clone(tasks);
    var name = uniqueName(out, 'NEW_TASK');
    var pred = findTask(out, afterName || '');
    if (pred && pred.finalize) pred = null;
    var predName = pred ? pred.name : deriveRoot(out);
    out.push(makeTask(name, { definition: 'SELECT 1', after: predName ? [predName] : [] }));
    return { tasks: out, name: name };
  }

  /* A task deleted. Its successors are not left hanging: each is put after the predecessors of the deleted task (when it had
     some). Returns {tasks, rewired:[names of the tasks whose `after` changed], leftRootless:[successors left with no predecessor]}. */
  function deleteTask(tasks, name) {
    var gone = findTask(tasks, name);
    if (!gone) return { tasks: tasks, rewired: [], leftRootless: [] };
    var rewired = [], rootless = [];
    var out = [];
    tasks.forEach(function (t) {
      if (t.name === name) return;
      var c = clone(t);
      if ((c.after || []).indexOf(name) >= 0) {
        var next = [];
        c.after.forEach(function (a) { if (a !== name && next.indexOf(a) < 0) next.push(a); });
        (gone.after || []).forEach(function (a) { if (next.indexOf(a) < 0) next.push(a); });
        c.after = next;
        rewired.push(c.name);
        if (!next.length && !c.finalize) rootless.push(c.name);
      }
      if (c.finalize === name) c.finalize = null;
      out.push(c);
    });
    return { tasks: out, rewired: rewired, leftRootless: rootless };
  }

  /* ---- the unsaved-edits check ---- */

  function nz(v) { return v === undefined || v === null || v === '' ? null : v; }

  function normalizeTask(t) {
    var params = {};
    Object.keys(t.parameters || {}).sort().forEach(function (k) { params[String(k).toUpperCase()] = String(t.parameters[k]); });
    var after = [];
    (t.after || []).forEach(function (a) { if (after.indexOf(a) < 0) after.push(a); });
    after.sort();
    return {
      name: t.name, definition: t.definition || '', after: after, finalize: nz(t.finalize), schedule: nz(t.schedule),
      warehouse: nz(t.warehouse), condition: nz(t.condition),
      allowOverlappingExecution: t.allowOverlappingExecution === true || t.allowOverlappingExecution === false ? t.allowOverlappingExecution : null,
      errorIntegration: nz(t.errorIntegration), comment: nz(t.comment), config: nz(t.config), parameters: params, state: nz(t.state)
    };
  }

  function normalizeGraph(g) {
    var tasks = (g && g.tasks ? g.tasks : []).map(normalizeTask);
    tasks.sort(function (a, b) { return a.name < b.name ? -1 : a.name > b.name ? 1 : 0; });
    return { database: (g && g.database) || '', schema: (g && g.schema) || '', tasks: tasks };
  }

  /* Do two graphs differ in anything that would be written (info, the order of the tasks and of `after`, and null against the
     empty string do not count)? */
  function isDirty(a, b) {
    return JSON.stringify(normalizeGraph(a)) !== JSON.stringify(normalizeGraph(b));
  }

  /* The body that the API takes for a graph: only the fields it knows (it refuses others), without info. */
  function graphPayload(g) {
    return {
      database: g.database || '', schema: g.schema || '', root: deriveRoot(g.tasks),
      tasks: g.tasks.map(function (t) {
        var o = {};
        TASK_FIELDS.forEach(function (k) {
          var v = t[k];
          if (k === 'after') v = (v || []).slice();
          else if (k === 'parameters') v = clone(v || {});
          else if (k === 'definition') v = v == null ? '' : v;
          else if (v === undefined || v === '') v = null;
          o[k] = v;
        });
        return o;
      })
    };
  }

  /* ---- small helpers for the fields ---- */

  /* The empty text field is null. */
  function textOrNull(text) { return text === null || text === undefined || String(text).trim() === '' ? null : String(text); }

  function triToValue(s) { return s === 'true' ? true : s === 'false' ? false : null; }
  function valueToTri(v) { return v === true ? 'true' : v === false ? 'false' : ''; }

  function paramsToRows(p) { return Object.keys(p || {}).map(function (k) { return { key: k, value: String(p[k]) }; }); }

  /* Rows of the parameter editor to the object: the name in capitals, a row with no name left out, the last of equal names wins. */
  function rowsToParams(rows) {
    var out = {};
    rows.forEach(function (r) {
      var k = String(r.key || '').trim().toUpperCase();
      if (k) out[k] = String(r.value == null ? '' : r.value);
    });
    return out;
  }

  function duplicateKeys(rows) {
    var seen = {}, dup = [];
    rows.forEach(function (r) {
      var k = String(r.key || '').trim().toUpperCase();
      if (!k) return;
      if (seen[k] && dup.indexOf(k) < 0) dup.push(k);
      seen[k] = true;
    });
    return dup;
  }

  var SEVERITY_ORDER = { error: 0, warning: 1, info: 2 };

  function sortProblems(problems) {
    return (problems || []).map(function (p, i) { return { p: p, i: i }; })
      .sort(function (a, b) { return (SEVERITY_ORDER[a.p.severity] === undefined ? 3 : SEVERITY_ORDER[a.p.severity]) -
        (SEVERITY_ORDER[b.p.severity] === undefined ? 3 : SEVERITY_ORDER[b.p.severity]) || a.i - b.i; })
      .map(function (x) { return x.p; });
  }

  /* The worst severity of each task: {NAME: 'error'|'warning'|'info'}. */
  function worstByTask(problems) {
    var out = {};
    (problems || []).forEach(function (p) {
      if (!p.task) return;
      var cur = out[p.task];
      if (cur === undefined || SEVERITY_ORDER[p.severity] < SEVERITY_ORDER[cur]) out[p.task] = p.severity;
    });
    return out;
  }

  /* A state of a run or of a task in a run, in words and in a class name. */
  function runStateInfo(state) {
    var s = String(state || '').toUpperCase();
    var map = {
      SUCCEEDED: ['succeeded', 'ok'], FAILED: ['failed', 'bad'], SKIPPED: ['skipped', 'skip'], RUNNING: ['running', 'run'],
      EXECUTING: ['running', 'run'], SCHEDULED: ['scheduled', 'wait'], CANCELLED: ['cancelled', 'skip'], CANCELED: ['cancelled', 'skip'],
      UPSTREAM_FAILED: ['upstream failed', 'bad'], UPSTREAM_CANCELLED: ['upstream cancelled', 'skip']
    };
    if (map[s]) return { label: map[s][0], kind: map[s][1] };
    return { label: s ? s.toLowerCase().replace(/_/g, ' ') : 'unknown', kind: 'wait' };
  }

  /* A time as the API gives it ("2026-11-26T02:00:00.000Z" or "2026-11-26 02:00:00.000") in short, with UTC said when it is UTC. */
  function formatTime(t) {
    if (t === null || t === undefined || t === '') return '';
    var s = String(t);
    var utc = /Z$/.test(s);
    s = s.replace('T', ' ').replace(/Z$/, '').replace(/\.\d+$/, '');
    return utc ? s + ' UTC' : s;
  }

  function formatSeconds(v) {
    if (v === null || v === undefined || v === '') return '';
    var n = Number(v);
    if (isNaN(n)) return String(v);
    return n < 10 ? String(Math.round(n * 10) / 10) : String(Math.round(n));
  }

  /* Runs newest first (by scheduled time, else started). */
  function sortRuns(runs) {
    return (runs || []).map(function (r, i) { return { r: r, i: i }; })
      .sort(function (a, b) {
        var ka = String(a.r.scheduled || a.r.started || ''), kb = String(b.r.scheduled || b.r.started || '');
        return ka < kb ? 1 : ka > kb ? -1 : a.i - b.i;
      }).map(function (x) { return x.r; });
  }

  /* A run that has not started: the upcoming run of a scheduled graph (state SCHEDULED). It is shown as the next run. */
  function isNextRun(run) { return String((run && run.state) || '').toUpperCase() === 'SCHEDULED'; }

  /* The run whose task states are drawn on the canvas: the most recent run that is not merely scheduled (runs are newest first). */
  function pickOverlayRun(runs) {
    var sorted = sortRuns(runs);
    for (var i = 0; i < sorted.length; i++) if (!isNextRun(sorted[i])) return sorted[i];
    return null;
  }

  /* A graph of n tasks for trying the layout: a root, layers of the given width that follow each other, some cross links and
     a finalizer. */
  function syntheticTasks(n, width) {
    var w = width || 4, tasks = [makeTask('SYN_ROOT', { definition: 'SELECT 1', schedule: '60 MINUTE', warehouse: 'WH', state: 'started' })];
    var prev = ['SYN_ROOT'], count = 1, layer = 1;
    while (count < n - 1) {
      var cur = [];
      for (var i = 0; i < w && count < n - 1; i++, count++) {
        var name = 'SYN_L' + layer + '_T' + (i + 1);
        var after = [prev[i % prev.length]];
        if (prev.length > 1 && i % 2 === 1) after.push(prev[(i + 1) % prev.length]);
        if (layer > 2 && i === 0) after.push('SYN_ROOT');
        var uniq = [];
        after.forEach(function (a) { if (uniq.indexOf(a) < 0) uniq.push(a); });
        tasks.push(makeTask(name, { definition: 'SELECT ' + count, after: uniq, warehouse: i % 3 === 0 ? null : 'WH', state: 'started' }));
        cur.push(name);
      }
      prev = cur;
      layer++;
    }
    tasks.push(makeTask('SYN_FINALIZER', { definition: 'CALL done()', finalize: 'SYN_ROOT', warehouse: 'WH', state: 'started' }));
    return tasks;
  }

  return {
    NODE_W: NODE_W, NODE_H: NODE_H, TASK_FIELDS: TASK_FIELDS,
    clone: clone, isFinalizer: isFinalizer, uniqueTasks: uniqueTasks, computeLayers: computeLayers, layoutGraph: layoutGraph,
    smoothPath: smoothPath, findOverlaps: findOverlaps, findTask: findTask, deriveRoot: deriveRoot, graphState: graphState,
    renameTask: renameTask, descendants: descendants, canFinalize: canFinalize, makeTask: makeTask, uniqueName: uniqueName,
    addTask: addTask, deleteTask: deleteTask, normalizeGraph: normalizeGraph, isDirty: isDirty, graphPayload: graphPayload,
    textOrNull: textOrNull, triToValue: triToValue, valueToTri: valueToTri, paramsToRows: paramsToRows, rowsToParams: rowsToParams,
    duplicateKeys: duplicateKeys, sortProblems: sortProblems, worstByTask: worstByTask, runStateInfo: runStateInfo,
    formatTime: formatTime, formatSeconds: formatSeconds, sortRuns: sortRuns,
    isNextRun: isNextRun, pickOverlayRun: pickOverlayRun, syntheticTasks: syntheticTasks
  };
});
