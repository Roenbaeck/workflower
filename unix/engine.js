// Workflower engine: the body of an anonymous Snowflake JavaScript procedure (see PROTOCOL.md).
//
// It is the logic of the PowerShell module (Workflower/Private/*.ps1, Workflower/Public/*.ps1) in plain ES5, so that it can run inside
// Snowflake and be driven by a shell script. It is ASCII only and has no two dollar signs in a row, because it sits between a pair of
// dollar-quote marks. OP and ARGS are the arguments of the procedure; the last line returns the answer (base64 text of answer lines).
//
// Layout: the answer, small helpers, names and literals, JSON text, the model, reading graphs, graph files, the checks, the SQL,
// the plan, applying, operating, runs, export, and the operations.

// ---------------------------------------------------------------------------------------------------------------------------
// The answer
// ---------------------------------------------------------------------------------------------------------------------------

// A reply collects the lines of the answer; encodeReply turns it into the one base64 string that is returned.
function Reply() {
  this.status = 'ok';
  this.exit = null;
  this.steps = null;
  this.items = [];
}
Reply.prototype.text = function (t) { this.items.push(['TEXT', '', t]); return this; };
Reply.prototype.json = function (o) { this.items.push(['JSON', '', JSON.stringify(o)]); return this; };
Reply.prototype.file = function (path, t) { this.items.push(['FILE', path, t]); return this; };

var BASE64_DIGITS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

// The UTF-8 bytes of a string. A lone surrogate becomes U+FFFD, as a decoder would make it.
function utf8Bytes(s) {
  var bytes = [], i, c, d;
  for (i = 0; i < s.length; i++) {
    c = s.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      d = s.charCodeAt(i + 1);
      if (d >= 0xDC00 && d <= 0xDFFF) { c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00); i++; }
    }
    if (c >= 0xD800 && c <= 0xDFFF) { c = 0xFFFD; }
    if (c < 0x80) { bytes.push(c); }
    else if (c < 0x800) { bytes.push(0xC0 | (c >> 6), 0x80 | (c & 63)); }
    else if (c < 0x10000) { bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63)); }
    else { bytes.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63)); }
  }
  return bytes;
}

// Base64 of the UTF-8 text. Done here (Snowflake's JavaScript has no btoa) rather than with a statement for each piece of the answer.
function base64Of(s) {
  var b = utf8Bytes(s), out = [], i, n, x;
  for (i = 0; i < b.length; i += 3) {
    n = b.length - i;
    x = (b[i] << 16) | ((n > 1 ? b[i + 1] : 0) << 8) | (n > 2 ? b[i + 2] : 0);
    out.push(BASE64_DIGITS.charAt((x >> 18) & 63), BASE64_DIGITS.charAt((x >> 12) & 63),
      n > 1 ? BASE64_DIGITS.charAt((x >> 6) & 63) : '=', n > 2 ? BASE64_DIGITS.charAt(x & 63) : '=');
  }
  return out.join('');
}

// The lines of the answer. EXIT is always written, which also keeps the answer above the 24 characters that the protocol promises.
function encodeReply(r) {
  var lines = ['STATUS ' + r.status], exit = r.exit, i, item;
  if (r.steps !== null) { lines.push('STEPS ' + r.steps); }
  if (exit === null) { exit = r.status === 'ok' ? 0 : 1; }
  lines.push('EXIT ' + exit);
  for (i = 0; i < r.items.length; i++) {
    item = r.items[i];
    lines.push(item[0] + (item[1] ? ' ' + item[1] : '') + ' ' + base64Of(item[2]));
  }
  return base64Of(lines.join('\n') + '\n');
}

function failure(message) {
  var r = new Reply();
  r.status = 'error';
  r.text(message);
  return r;
}

// ---------------------------------------------------------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------------------------------------------------------

// A dictionary that keeps the order of insertion and has no trouble with keys such as "constructor" or "__proto__".
function Dict() { this.map = {}; this.order = []; }
Dict.prototype.has = function (k) { return Object.prototype.hasOwnProperty.call(this.map, 'k:' + k); };
Dict.prototype.get = function (k) { return this.has(k) ? this.map['k:' + k] : null; };
Dict.prototype.set = function (k, v) { if (!this.has(k)) { this.order.push(k); } this.map['k:' + k] = v; };
Dict.prototype.keys = function () { return this.order.slice(); };

function hasOwn(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }
function isObject(v) { return v !== null && typeof v === 'object' && !Array.isArray(v) && !(v instanceof Date); }

// Names are compared and ordered ordinally (UTF-16 code units), the same on every machine.
function cmp(a, b) { return a < b ? -1 : (a > b ? 1 : 0); }
function sortedStrings(list) { return list.slice().sort(cmp); }
function contains(list, x) { return list.indexOf(x) >= 0; }

// Any value from Snowflake as text, the way a person reads it: nothing is '', a time is ISO text, a structure is JSON.
function str(v) {
  if (v === null || v === undefined) { return ''; }
  if (v instanceof Date) { return isNaN(v.getTime()) ? '' : v.toISOString(); }
  if (typeof v === 'object') { return JSON.stringify(v); }
  return String(v);
}

function trimEnd(s) { return str(s).replace(/\s+$/, ''); }
function padRight(s, n) { s = str(s); while (s.length < n) { s += ' '; } return s; }
function nullIfEmpty(v) { var s = str(v); return (v === null || v === undefined || s === '') ? null : s; }

// A flag from a file, a column or the request: true, false, or null when it says nothing.
function toBool(v) {
  var s;
  if (v === null || v === undefined) { return null; }
  if (typeof v === 'boolean') { return v; }
  s = str(v).replace(/^\s+|\s+$/g, '').toLowerCase();
  if (s === 'true' || s === '1' || s === 'yes') { return true; }
  if (s === 'false' || s === '0' || s === 'no') { return false; }
  return null;
}

// The value of a key of a loose object, the key matched without regard to case; null when it is not there.
function getValue(o, key) {
  var k, lower = key.toLowerCase();
  if (!isObject(o)) { return null; }
  for (k in o) {
    if (hasOwn(o, k) && k.toLowerCase() === lower) { return o[k]; }
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------
// Talking to Snowflake
// ---------------------------------------------------------------------------------------------------------------------------

function run(sqlText, binds) {
  var cmd = { sqlText: sqlText };
  if (binds) { cmd.binds = binds; }
  return snowflake.execute(cmd);
}

// The rows of a result as objects whose keys are the column names in lower case (SHOW gives lower case already).
function readRows(rs) {
  var out = [], names = [], n = rs.getColumnCount(), i, row;
  for (i = 1; i <= n; i++) { names.push(String(rs.getColumnName(i)).toLowerCase()); }
  while (rs.next()) {
    row = {};
    for (i = 1; i <= n; i++) { row[names[i - 1]] = rs.getColumnValue(i); }
    out.push(row);
  }
  return out;
}

function query(sqlText, binds) { return readRows(run(sqlText, binds)); }

// Base64 to text with SQL, many at a time (one statement for up to 50). An invalid text makes Snowflake raise an error.
function decodeAll(list) {
  var out = [], start, chunk, marks, i, row, sqlText;
  for (start = 0; start < list.length; start += 50) {
    chunk = list.slice(start, start + 50);
    marks = [];
    for (i = 0; i < chunk.length; i++) { marks.push('BASE64_DECODE_STRING(?)'); }
    sqlText = 'SELECT ' + marks.join(', ');
    row = run(sqlText, chunk);
    row.next();
    for (i = 1; i <= chunk.length; i++) { out.push(str(row.getColumnValue(i))); }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------------
// Names and literals. Every identifier is written double quoted, because names are exact.
// ---------------------------------------------------------------------------------------------------------------------------

function ident(name) { return '"' + str(name).replace(/"/g, '""') + '"'; }

function qualified(db, sc, name) {
  var parts = [];
  if (db) { parts.push(ident(db)); }
  if (sc) { parts.push(ident(sc)); }
  parts.push(ident(name));
  return parts.join('.');
}

// A string literal. Snowflake treats a backslash in a single-quoted string as an escape, so both it and the quote are doubled.
function literal(t) {
  if (t === null || t === undefined) { return 'NULL'; }
  return "'" + str(t).replace(/\\/g, '\\\\').replace(/'/g, "''") + "'";
}

// The value of a parameter in a SET: numbers and TRUE/FALSE as they are, anything else as a string.
function parameterValue(v) {
  var s;
  if (v === null || v === undefined) { return 'NULL'; }
  if (typeof v === 'boolean') { return v ? 'TRUE' : 'FALSE'; }
  s = str(v);
  if (/^-?\d+(\.\d+)?$/.test(s)) { return s; }
  if (/^(true|false)$/i.test(s)) { return s.toUpperCase(); }
  return literal(s);
}

// Splits a dotted name such as DB.SC.T or "My Db"."s"."t" into its parts; a quoted part may hold dots.
function splitQualified(text) {
  var parts = [], i = 0, n = text.length, sb, start;
  while (i < n) {
    if (text.charAt(i) === '"') {
      sb = '';
      i++;
      while (i < n) {
        if (text.charAt(i) === '"') {
          if (i + 1 < n && text.charAt(i + 1) === '"') { sb += '"'; i += 2; continue; }
          i++;
          break;
        }
        sb += text.charAt(i);
        i++;
      }
      parts.push(sb);
    } else {
      start = i;
      while (i < n && text.charAt(i) !== '.') { i++; }
      parts.push(text.substring(start, i).replace(/^\s+|\s+$/g, ''));
    }
    if (i < n && text.charAt(i) === '.') { i++; }
  }
  return parts;
}

// The last part of a name, which is the task's own name.
function lastPart(text) {
  var parts = splitQualified(text);
  return parts.length === 0 ? text : parts[parts.length - 1];
}

// ---------------------------------------------------------------------------------------------------------------------------
// JSON text for graph files: the same layout as the PowerShell module (two spaces, short arrays on one line, ASCII only), so that
// a file made here and a file made there are the same in a diff.
// ---------------------------------------------------------------------------------------------------------------------------

function jsonString(s) {
  var out = ['"'], i, c, hex;
  for (i = 0; i < s.length; i++) {
    c = s.charCodeAt(i);
    if (c === 34) { out.push('\\"'); }
    else if (c === 92) { out.push('\\\\'); }
    else if (c === 10) { out.push('\\n'); }
    else if (c === 13) { out.push('\\r'); }
    else if (c === 9) { out.push('\\t'); }
    else if (c < 32 || c > 126) { hex = c.toString(16); while (hex.length < 4) { hex = '0' + hex; } out.push('\\u' + hex); }
    else { out.push(s.charAt(i)); }
  }
  out.push('"');
  return out.join('');
}

function jsonText(v, indent) {
  var pad = repeat('  ', indent), pad2 = repeat('  ', indent + 1), items = [], i, k, simple;
  if (v === null || v === undefined) { return 'null'; }
  if (typeof v === 'boolean') { return v ? 'true' : 'false'; }
  if (typeof v === 'number') { return String(v); }
  if (typeof v === 'string') { return jsonString(v); }
  if (Array.isArray(v)) {
    if (v.length === 0) { return '[]'; }
    simple = true;
    for (i = 0; i < v.length; i++) { if (v[i] !== null && typeof v[i] === 'object') { simple = false; } }
    if (simple) {
      for (i = 0; i < v.length; i++) { items.push(jsonText(v[i], indent + 1)); }
      return '[' + items.join(', ') + ']';
    }
    for (i = 0; i < v.length; i++) { items.push(pad2 + jsonText(v[i], indent + 1)); }
    return '[\n' + items.join(',\n') + '\n' + pad + ']';
  }
  k = Object.keys(v);
  if (k.length === 0) { return '{}'; }
  for (i = 0; i < k.length; i++) { items.push(pad2 + jsonString(k[i]) + ': ' + jsonText(v[k[i]], indent + 1)); }
  return '{\n' + items.join(',\n') + '\n' + pad + '}';
}

function repeat(s, n) { var out = '', i; for (i = 0; i < n; i++) { out += s; } return out; }

// ---------------------------------------------------------------------------------------------------------------------------
// The model of a task graph (Model.ps1): a graph has database, schema, root and tasks (root first, a finalizer last); a task has
// name, definition, after, finalize, schedule, warehouse, condition, allowOverlappingExecution, errorIntegration, comment, config,
// parameters and state (started, suspended or null when it is not said).
// ---------------------------------------------------------------------------------------------------------------------------

var TASK_FIELDS = ['name', 'definition', 'after', 'finalize', 'schedule', 'warehouse', 'condition', 'allowOverlappingExecution',
  'errorIntegration', 'comment', 'config', 'parameters', 'state'];

function newTask(name) {
  return { name: name, definition: '', after: [], finalize: null, schedule: null, warehouse: null, condition: null,
    allowOverlappingExecution: null, errorIntegration: null, comment: null, config: null, parameters: {}, state: null };
}

function newGraph(db, sc, root, tasks) { return { database: db, schema: sc, root: root, tasks: tasks }; }

function paramKeys(t) { return Object.keys(t.parameters); }

// A copy of the parameters with the keys in order.
function sortedParameters(p) {
  var out = {}, keys = sortedStrings(Object.keys(p)), i;
  for (i = 0; i < keys.length; i++) { out[keys[i]] = p[keys[i]]; }
  return out;
}

// A task from an object with the task's fields. An unknown field is an error, so that a misspelling is not silently ignored.
function convertTask(src) {
  var name = str(getValue(src, 'name')), keys = Object.keys(src), i, j, known, t, v, after, params, pk, state;
  if (!name) { throw new Error('A task has no name.'); }
  for (i = 0; i < keys.length; i++) {
    known = false;
    for (j = 0; j < TASK_FIELDS.length; j++) { if (TASK_FIELDS[j].toLowerCase() === keys[i].toLowerCase()) { known = true; } }
    if (!known) {
      throw new Error("Task '" + name + "': unknown field '" + keys[i] + "' (the fields are " + TASK_FIELDS.join(', ') + ').');
    }
  }
  t = newTask(name);
  v = getValue(src, 'definition');
  if (v !== null) { t.definition = str(v); }
  after = getValue(src, 'after');
  if (after !== null) {
    if (!Array.isArray(after)) { after = [after]; }
    for (i = 0; i < after.length; i++) { if (str(after[i])) { t.after.push(str(after[i])); } }
  }
  t.finalize = nullIfEmpty(getValue(src, 'finalize'));
  t.schedule = nullIfEmpty(getValue(src, 'schedule'));
  t.warehouse = nullIfEmpty(getValue(src, 'warehouse'));
  t.condition = nullIfEmpty(getValue(src, 'condition'));
  t.allowOverlappingExecution = toBool(getValue(src, 'allowOverlappingExecution'));
  t.errorIntegration = nullIfEmpty(getValue(src, 'errorIntegration'));
  t.comment = nullIfEmpty(getValue(src, 'comment'));
  t.config = nullIfEmpty(getValue(src, 'config'));
  params = getValue(src, 'parameters');
  if (params !== null) {
    if (!isObject(params)) { throw new Error("Task '" + name + "': parameters must be an object (name and value)."); }
    // the names are upper case and in order, the values are text; a boolean is TRUE or FALSE
    pk = Object.keys(params);
    for (i = 0; i < pk.length; i++) { pk[i] = [pk[i].toUpperCase(), params[pk[i]]]; }
    pk.sort(function (a, b) { return cmp(a[0], b[0]); });
    for (i = 0; i < pk.length; i++) {
      v = pk[i][1];
      if (typeof v === 'boolean') { v = v ? 'TRUE' : 'FALSE'; }
      t.parameters[pk[i][0]] = str(v);
    }
  }
  state = nullIfEmpty(getValue(src, 'state'));
  if (state) {
    state = state.toLowerCase();
    if (state !== 'started' && state !== 'suspended') {
      throw new Error("Task '" + name + "': state must be started or suspended, not '" + state + "'.");
    }
  }
  t.state = state;
  return t;
}

// The tasks in an order in which each comes after its predecessors; the root first and a finalizer last. Tasks that are in a cycle,
// or wait for a predecessor that is not there, are unplaced.
function taskOrder(tasks) {
  var placed = [], done = new Dict(), rest = [], finalizers = [], progress = true, next, i, j, t, ready;
  for (i = 0; i < tasks.length; i++) { if (tasks[i].finalize) { finalizers.push(tasks[i]); } else { rest.push(tasks[i]); } }
  while (progress && rest.length > 0) {
    progress = false;
    next = [];
    for (i = 0; i < rest.length; i++) {
      t = rest[i];
      ready = true;
      for (j = 0; j < t.after.length; j++) { if (!done.has(t.after[j])) { ready = false; } }
      if (ready) { placed.push(t); done.set(t.name, true); progress = true; } else { next.push(t); }
    }
    rest = next;
  }
  for (i = 0; i < finalizers.length; i++) { placed.push(finalizers[i]); done.set(finalizers[i].name, true); }
  return { order: placed, unplaced: rest };
}

// Order plus unplaced, which is every task, in the order to create them.
function allInOrder(tasks) { var o = taskOrder(tasks); return o.order.concat(o.unplaced); }

// Brings a graph into the form that a comparison needs: the tasks in order, the root named.
function updateGraph(g) {
  var tasks = g.tasks, sorted = allInOrder(tasks), i;
  g.root = null;
  for (i = 0; i < tasks.length; i++) {
    if (tasks[i].after.length === 0 && !tasks[i].finalize) { g.root = tasks[i].name; break; }
  }
  g.tasks = sorted;
  return g;
}

function findTask(g, name) {
  var i;
  for (i = 0; i < g.tasks.length; i++) { if (g.tasks[i].name === name) { return g.tasks[i]; } }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------------------
// Reading graphs from SHOW TASKS (Get-TaskGraph.ps1)
// ---------------------------------------------------------------------------------------------------------------------------

function scopeOf(db, sc) {
  if (sc && !db) { throw new Error('A schema needs a database.'); }
  if (sc) { return 'SCHEMA ' + ident(db) + '.' + ident(sc); }
  if (db) { return 'DATABASE ' + ident(db); }
  return 'ACCOUNT';
}

// SHOW TASKS gives the relations as a VARIANT, which arrives as an object or as text.
function relationsOf(v) {
  var o = v;
  if (typeof v === 'string') {
    if (!v) { return null; }
    try { o = JSON.parse(v); } catch (e) { return null; }
  }
  return isObject(o) ? o : null;
}

// The names of the predecessors, as Snowflake writes them (qualified). The relations are the better source; the column
// predecessors arrives as an array in a procedure, and as JSON text or a comma separated list elsewhere.
function predecessorsOf(rel, row) {
  var pred = getValue(rel, 'Predecessors'), pt, out = [], i, parts;
  if (pred !== null) {
    if (!Array.isArray(pred)) { pred = [pred]; }
    for (i = 0; i < pred.length; i++) { out.push(str(pred[i])); }
    return out;
  }
  pt = row.predecessors;
  if (Array.isArray(pt)) {
    for (i = 0; i < pt.length; i++) { out.push(str(pt[i])); }
    return out;
  }
  pt = str(pt).replace(/^\s+|\s+$/g, '');
  if (pt.charAt(0) === '[') {
    pred = JSON.parse(pt);
    for (i = 0; i < pred.length; i++) { out.push(str(pred[i])); }
  } else if (pt) {
    parts = pt.split(',');
    for (i = 0; i < parts.length; i++) { if (parts[i].replace(/^\s+|\s+$/g, '')) { out.push(parts[i].replace(/^\s+|\s+$/g, '')); } }
  }
  return out;
}

// A task from a row of SHOW TASKS; what is only known about an installed task (owner, ids, times) is kept under info.
function taskFromRow(row) {
  var t = newTask(str(row.name)), ei, cfg, st;
  t.definition = str(row.definition);
  t.schedule = nullIfEmpty(row.schedule);
  t.warehouse = nullIfEmpty(row.warehouse);
  t.condition = nullIfEmpty(row.condition);
  t.allowOverlappingExecution = toBool(row.allow_overlapping_execution);
  ei = nullIfEmpty(row.error_integration);
  if (ei && ei.toLowerCase() !== 'null') { t.errorIntegration = ei; }
  t.comment = nullIfEmpty(row.comment);
  cfg = nullIfEmpty(row.config);
  if (cfg && cfg.toLowerCase() !== 'null') { t.config = cfg; }
  st = str(row.state).toLowerCase();
  if (st === 'started' || st === 'suspended') { t.state = st; }
  t.info = { id: str(row.id), owner: str(row.owner), createdOn: str(row.created_on), lastCommittedOn: str(row.last_committed_on),
    lastSuspendedOn: str(row.last_suspended_on), lastSuspendedReason: str(row.last_suspended_reason), budget: str(row.budget) };
  return t;
}

// The graphs of the rows of one schema: tasks that are connected by AFTER or FINALIZE are a graph (union-find), a task that stands
// alone is a graph of one. A predecessor that is not among the rows (hidden from the role) makes the graph incomplete.
function graphsOfSchema(rows) {
  var db = str(rows[0].database_name), sc = str(rows[0].schema_name);
  var tasks = new Dict(), links = [], names = [], parent = new Dict(), incomplete = new Dict(), groups = new Dict(), out = [];
  var i, j, t, rel, l, r, g, sortedNames, c, isIncomplete;

  function resolve(text) {
    var last = lastPart(text), hit = [], k;
    if (tasks.has(last)) { return last; }
    for (k = 0; k < names.length; k++) { if (names[k].toLowerCase() === last.toLowerCase()) { hit.push(names[k]); } }
    return hit.length === 1 ? hit[0] : null;
  }
  function find(x) {
    while (parent.get(x) !== x) { parent.set(x, parent.get(parent.get(x))); x = parent.get(x); }
    return x;
  }
  function join(a, b) { var ra = find(a), rb = find(b); if (ra !== rb) { parent.set(ra, rb); } }

  for (i = 0; i < rows.length; i++) {
    t = taskFromRow(rows[i]);
    rel = relationsOf(rows[i].task_relations);
    tasks.set(t.name, t);
    links.push({ task: t.name, after: predecessorsOf(rel, rows[i]), finalizerOf: str(getValue(rel, 'FinalizedRootTask')) });
  }
  names = tasks.keys();
  for (i = 0; i < names.length; i++) { parent.set(names[i], names[i]); }
  for (i = 0; i < links.length; i++) {
    l = links[i];
    t = tasks.get(l.task);
    for (j = 0; j < l.after.length; j++) {
      r = resolve(l.after[j]);
      if (r) { t.after.push(r); join(r, t.name); } else { t.after.push(lastPart(l.after[j])); incomplete.set(t.name, true); }
    }
    if (l.finalizerOf) {
      r = resolve(l.finalizerOf);
      if (r) { t.finalize = r; join(r, t.name); } else { t.finalize = lastPart(l.finalizerOf); incomplete.set(t.name, true); }
    }
  }
  sortedNames = sortedStrings(names);
  for (i = 0; i < sortedNames.length; i++) {
    c = find(sortedNames[i]);
    if (!groups.has(c)) { groups.set(c, []); }
    groups.get(c).push(tasks.get(sortedNames[i]));
  }
  groups.keys().forEach(function (key) {
    g = updateGraph(newGraph(db, sc, null, groups.get(key)));
    isIncomplete = false;
    for (j = 0; j < g.tasks.length; j++) { if (incomplete.has(g.tasks[j].name)) { isIncomplete = true; } }
    g.incomplete = isIncomplete;
    out.push(g);
  });
  return out;
}

function compareGraphs(a, b) {
  return cmp(a.database, b.database) || cmp(a.schema, b.schema) || cmp(a.root || '', b.root || '');
}

// The graphs of a schema, a database or the account, whoever made them (without the parameters of the tasks).
function readGraphs(db, sc, root) {
  var rows = query('SHOW TASKS IN ' + scopeOf(db, sc)), bySchema = new Dict(), graphs = [], i, key;
  for (i = 0; i < rows.length; i++) {
    key = str(rows[i].database_name) + '\u0001' + str(rows[i].schema_name);
    if (!bySchema.has(key)) { bySchema.set(key, []); }
    bySchema.get(key).push(rows[i]);
  }
  bySchema.keys().forEach(function (k) { graphs = graphs.concat(graphsOfSchema(bySchema.get(k))); });
  if (root) { graphs = graphs.filter(function (g) { return g.root === root; }); }
  return graphs.sort(compareGraphs);
}

// What is set on each task (SHOW PARAMETERS IN TASK): the task level only, in order of name.
function loadParameters(g) {
  g.tasks.forEach(function (t) {
    var rows = query('SHOW PARAMETERS IN TASK ' + qualified(g.database, g.schema, t.name)), i;
    for (i = 0; i < rows.length; i++) {
      if (str(rows[i].level).toUpperCase() === 'TASK') { t.parameters[str(rows[i].key)] = str(rows[i].value); }
    }
    t.parameters = sortedParameters(t.parameters);
  });
}

// ---------------------------------------------------------------------------------------------------------------------------
// Graph files (Files.ps1, GraphView.ps1)
// ---------------------------------------------------------------------------------------------------------------------------

// A task as a file holds it, without the SQL it runs (a file holds that under definition, or beside it).
function taskDocument(t, noState) {
  var o = { name: t.name };
  if (t.after.length > 0) { o.after = t.after.slice(); }
  if (t.finalize) { o.finalize = t.finalize; }
  if (t.schedule) { o.schedule = t.schedule; }
  if (t.warehouse) { o.warehouse = t.warehouse; }
  if (t.condition) { o.condition = t.condition; }
  if (t.allowOverlappingExecution !== null) { o.allowOverlappingExecution = t.allowOverlappingExecution; }
  if (t.errorIntegration) { o.errorIntegration = t.errorIntegration; }
  if (t.comment) { o.comment = t.comment; }
  if (t.config) { o.config = t.config; }
  if (paramKeys(t).length > 0) { o.parameters = t.parameters; }
  if (t.state && !noState) { o.state = t.state; }
  return o;
}

function graphDocumentText(g, tasks) {
  return jsonText({ format: 'workflower-graph', version: 1, database: g.database, schema: g.schema, tasks: tasks }, 0) + '\n';
}

// A task for the interface and the JSON answers: all its fields, and info for an installed task.
function taskView(t) {
  var o = { name: t.name, definition: t.definition, after: t.after, finalize: t.finalize, schedule: t.schedule, warehouse: t.warehouse,
    condition: t.condition, allowOverlappingExecution: t.allowOverlappingExecution, errorIntegration: t.errorIntegration,
    comment: t.comment, config: t.config, parameters: t.parameters, state: t.state };
  if (t.info) { o.info = t.info; }
  return o;
}

function graphState(g) {
  var root = g.root === null ? null : findTask(g, g.root);
  return (root && root.state) ? root.state : 'suspended';
}

function graphView(g) {
  return { database: g.database, schema: g.schema, root: g.root, state: graphState(g), incomplete: g.incomplete === true,
    tasks: g.tasks.map(taskView) };
}

// The graph of a request: the file text (doc), the definition files (files), and the overrides of Import-TaskGraph.
function readInput(args) {
  var files = isObject(args.files) ? args.files : {}, fileNames = Object.keys(files), encoded = [], decoded, docText, doc, texts = {};
  var items, tasks = [], i, k, item, copy, ref, fileKey, task, db, sc, format, hasTasks = false;
  if (!args.doc) { throw new Error('The request has no graph file (doc).'); }
  encoded.push(String(args.doc));
  for (i = 0; i < fileNames.length; i++) { encoded.push(String(files[fileNames[i]])); }
  decoded = decodeAll(encoded);
  docText = decoded[0].replace(/^\uFEFF/, '');
  for (i = 0; i < fileNames.length; i++) { texts[fileNames[i]] = decoded[i + 1]; }
  try { doc = JSON.parse(docText); } catch (e) { throw new Error('The graph file is not valid JSON: ' + e.message); }
  if (isObject(doc)) { for (k in doc) { if (hasOwn(doc, k) && k.toLowerCase() === 'tasks') { hasTasks = true; } } }
  if (!hasTasks) { throw new Error('The graph file is not a task graph file (it has no "tasks").'); }
  format = getValue(doc, 'format');
  if (format && String(format).toLowerCase() !== 'workflower-graph') { throw new Error("The graph file has an unknown format '" + format + "'."); }
  items = getValue(doc, 'tasks');
  if (items === null) { items = []; }
  if (!Array.isArray(items)) { items = [items]; }
  for (i = 0; i < items.length; i++) {
    item = items[i];
    if (!isObject(item)) { throw new Error('A task of the graph file is not an object.'); }
    copy = {};
    ref = null;
    for (k in item) {
      if (!hasOwn(item, k)) { continue; }
      if (k.toLowerCase() === 'definitionfile') { ref = item[k]; } else { copy[k] = item[k]; }
    }
    if (ref !== null) {
      fileKey = str(ref);
      if (!hasOwn(texts, fileKey)) {
        throw new Error("Task '" + str(getValue(item, 'name')) + "': the definition file " + fileKey + ' is not there.');
      }
      copy.definition = trimEnd(texts[fileKey]);
    }
    task = convertTask(copy);
    if (args.warehouse && task.warehouse) { task.warehouse = String(args.warehouse); }
    tasks.push(task);
  }
  db = str(getValue(doc, 'database'));
  sc = str(getValue(doc, 'schema'));
  if (args.database) { db = String(args.database); }
  if (args.schema) { sc = String(args.schema); }
  return updateGraph(newGraph(db, sc, null, tasks));
}

// ---------------------------------------------------------------------------------------------------------------------------
// The checks (Test-TaskGraph.ps1): the rules that Snowflake enforces, before anything is sent
// ---------------------------------------------------------------------------------------------------------------------------

function checkGraph(g) {
  var problems = [], tasks = g.tasks, names = new Dict(), children = new Dict(), i, j, t, a, order, unplaced, inCycle, finalizers = [];
  var roots = [], rootName = null, root, f, isRoot;

  function add(severity, task, code, message) { problems.push({ severity: severity, task: task, code: code, message: message }); }
  function list(ts) { return ts.map(function (x) { return x.name; }).join(', '); }

  for (i = 0; i < tasks.length; i++) {
    if (names.has(tasks[i].name)) { add('error', tasks[i].name, 'duplicate-name', "There are two tasks called '" + tasks[i].name + "'."); }
    names.set(tasks[i].name, tasks[i]);
  }
  if (tasks.length === 0) { add('error', null, 'empty', 'The graph has no tasks.'); }
  if (tasks.length > 1000) { add('error', null, 'too-many-tasks', 'A graph has at most 1,000 tasks; this one has ' + tasks.length + '.'); }

  for (i = 0; i < tasks.length; i++) {
    t = tasks[i];
    if (!str(t.definition).replace(/^\s+|\s+$/g, '')) { add('error', t.name, 'no-definition', "Task '" + t.name + "' has nothing to run (definition)."); }
    for (j = 0; j < t.after.length; j++) {
      a = t.after[j];
      if (a === t.name) { add('error', t.name, 'self', "Task '" + t.name + "' is after itself."); }
      else if (!names.has(a)) { add('error', t.name, 'missing-predecessor', "Task '" + t.name + "' is after '" + a + "', which is not in the graph."); }
      else { children.set(a, (children.has(a) ? children.get(a) : 0) + 1); }
    }
    if (t.after.length > 100) {
      add('error', t.name, 'too-many-predecessors', "Task '" + t.name + "' has " + t.after.length + ' predecessors; the most is 100.');
    }
  }
  children.keys().forEach(function (k) {
    if (children.get(k) > 100) { add('error', k, 'too-many-children', "Task '" + k + "' has " + children.get(k) + ' child tasks; the most is 100.'); }
  });

  order = taskOrder(tasks);
  unplaced = order.unplaced.map(function (x) { return x.name; });
  inCycle = order.unplaced.filter(function (x) {
    return x.after.filter(function (n) { return names.has(n) && contains(unplaced, n); }).length > 0;
  });
  if (inCycle.length > 0) { add('error', null, 'cycle', 'The tasks wait for each other (a cycle): ' + list(inCycle) + '.'); }

  for (i = 0; i < tasks.length; i++) {
    if (tasks[i].finalize) { finalizers.push(tasks[i]); }
    if (tasks[i].after.length === 0 && !tasks[i].finalize) { roots.push(tasks[i]); }
  }
  if (tasks.length > 0) {
    if (roots.length === 0) { add('error', null, 'no-root', 'The graph has no root task (a task with no predecessors).'); }
    else if (roots.length > 1) { add('error', null, 'several-roots', 'The graph has more than one task with no predecessors: ' + list(roots) + '. A graph has one root.'); }
  }
  if (roots.length >= 1) { rootName = roots[0].name; }

  for (i = 0; i < tasks.length; i++) {
    t = tasks[i];
    isRoot = rootName !== null && t.name === rootName;
    if (t.schedule && !isRoot) { add('error', t.name, 'schedule-on-child', "Task '" + t.name + "' has a schedule, but only the root task can have one."); }
    if (t.warehouse && hasOwn(t.parameters, 'USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE')) {
      add('error', t.name, 'two-computes', "Task '" + t.name + "' names a warehouse and a serverless size; it can have only one of them.");
    }
    if (t.allowOverlappingExecution !== null && !isRoot) {
      add('warning', t.name, 'overlap-on-child', 'ALLOW_OVERLAPPING_EXECUTION is set on \'' + t.name + '\', which is not the root; Snowflake takes it from the root.');
    }
  }
  if (finalizers.length > 1) { add('error', null, 'several-finalizers', 'A graph has at most one finalizer task: ' + list(finalizers) + '.'); }
  for (i = 0; i < finalizers.length; i++) {
    f = finalizers[i];
    if (!names.has(f.finalize)) { add('error', f.name, 'finalize-missing', "Task '" + f.name + "' finalizes '" + f.finalize + "', which is not in the graph."); }
    else if (rootName !== null && f.finalize !== rootName) {
      add('error', f.name, 'finalize-not-root', "Task '" + f.name + "' finalizes '" + f.finalize + "', which is not the root of the graph ('" + rootName + "').");
    }
    if (f.after.length > 0) { add('error', f.name, 'finalizer-after', "The finalizer '" + f.name + "' has predecessors; a finalizer runs after the whole graph and has none."); }
    for (j = 0; j < tasks.length; j++) {
      if (contains(tasks[j].after, f.name)) {
        add('error', tasks[j].name, 'after-finalizer', "Task '" + tasks[j].name + "' is after the finalizer '" + f.name + "'; nothing can be after a finalizer.");
      }
    }
  }

  if (rootName !== null) {
    root = names.get(rootName);
    if (!root.schedule && !root.condition) {
      if (root.state === 'started') {
        add('error', rootName, 'root-cannot-start', "The root '" + rootName + "' has no schedule and no condition, and Snowflake does not resume such a task; it can only be run by hand (EXECUTE TASK).");
      } else {
        add('info', rootName, 'manual-root', "The root '" + rootName + "' has no schedule and no condition, so the graph runs only when it is run by hand (EXECUTE TASK).");
      }
    }
    if (root.state === 'started') {
      for (i = 0; i < tasks.length; i++) {
        if (tasks[i].state === 'suspended' && tasks[i].name !== rootName) {
          add('warning', tasks[i].name, 'suspended-child', "'" + tasks[i].name + "' is suspended while the root is started, so it does not run, and neither does anything after it.");
        }
      }
    }
  }
  return problems;
}

function errorsOf(problems) { return problems.filter(function (p) { return p.severity === 'error'; }); }

// ---------------------------------------------------------------------------------------------------------------------------
// The SQL that makes a graph (ConvertTo-TaskGraphSql.ps1)
// ---------------------------------------------------------------------------------------------------------------------------

// One CREATE TASK, with the properties in the order that the statement has them.
function createTask(g, t, replace) {
  var lines = [], db = g.database, sc = g.schema, keys = paramKeys(t), i;
  lines.push((replace ? 'CREATE OR REPLACE TASK ' : 'CREATE TASK ') + qualified(db, sc, t.name));
  if (t.warehouse) { lines.push('  WAREHOUSE = ' + ident(t.warehouse)); }
  if (t.schedule) { lines.push('  SCHEDULE = ' + literal(t.schedule)); }
  if (t.config) { lines.push('  CONFIG = ' + literal(t.config)); }
  if (t.allowOverlappingExecution !== null) { lines.push('  ALLOW_OVERLAPPING_EXECUTION = ' + (t.allowOverlappingExecution ? 'TRUE' : 'FALSE')); }
  for (i = 0; i < keys.length; i++) { lines.push('  ' + keys[i] + ' = ' + parameterValue(t.parameters[keys[i]])); }
  if (t.errorIntegration) { lines.push('  ERROR_INTEGRATION = ' + ident(t.errorIntegration)); }
  if (t.comment) { lines.push('  COMMENT = ' + literal(t.comment)); }
  if (t.finalize) { lines.push('  FINALIZE = ' + qualified(db, sc, t.finalize)); }
  if (t.after.length > 0) {
    lines.push('  AFTER ' + t.after.map(function (a) { return qualified(db, sc, a); }).join(', '));
  }
  if (t.condition) { lines.push('  WHEN ' + t.condition); }
  lines.push('AS');
  lines.push(trimEnd(t.definition));
  return lines.join('\n');
}

// The statements of ConvertTo-TaskGraphSql -IncludeState: a CREATE OR REPLACE for each task, then a RESUME for each started task,
// the children before the root.
function graphStatements(g) {
  var tasks = allInOrder(g.tasks), out = [], i;
  for (i = 0; i < tasks.length; i++) { out.push(createTask(g, tasks[i], true)); }
  for (i = tasks.length - 1; i >= 0; i--) {
    if (tasks[i].state === 'started') { out.push('ALTER TASK ' + qualified(g.database, g.schema, tasks[i].name) + ' RESUME'); }
  }
  return out;
}

function graphScript(g) {
  var statements = graphStatements(g), out = '', i;
  for (i = 0; i < statements.length; i++) {
    out += statements[i];
    if (!/;\s*$/.test(statements[i])) { out += ';'; }
    out += '\n\n';
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------------
// The plan (Compare-TaskGraph.ps1): the steps that turn the installed graph into the wanted one, in the order Snowflake needs
// ---------------------------------------------------------------------------------------------------------------------------

function comparable(v) {
  if (v === null || v === undefined) { return ''; }
  return trimEnd(String(v).replace(/\r\n?/g, '\n'));
}

// The names of the fields in which a wanted task is not the installed one.
function taskDifference(w, inst) {
  var d = [], fields = ['schedule', 'warehouse', 'comment', 'config', 'errorIntegration'], i, keys, k, wv, iv, seen = {};
  if (comparable(w.definition) !== comparable(inst.definition)) { d.push('definition'); }
  if (comparable(w.condition) !== comparable(inst.condition)) { d.push('condition'); }
  for (i = 0; i < fields.length; i++) { if (comparable(w[fields[i]]) !== comparable(inst[fields[i]])) { d.push(fields[i]); } }
  // a flag that is not said (null) is not compared, since Snowflake gives the root a value and a child none
  if (w.allowOverlappingExecution !== null && w.allowOverlappingExecution !== inst.allowOverlappingExecution) { d.push('allowOverlappingExecution'); }
  if (sortedStrings(w.after).join('\n') !== sortedStrings(inst.after).join('\n')) { d.push('after'); }
  if (comparable(w.finalize) !== comparable(inst.finalize)) { d.push('finalize'); }
  keys = [];
  paramKeys(w).concat(paramKeys(inst)).forEach(function (key) { if (!hasOwn(seen, key)) { seen[key] = true; keys.push(key); } });
  keys.sort(cmp);
  for (i = 0; i < keys.length; i++) {
    k = keys[i];
    wv = hasOwn(w.parameters, k) ? str(w.parameters[k]) : null;
    iv = hasOwn(inst.parameters, k) ? str(inst.parameters[k]) : null;
    if (wv === null || iv === null || wv.toLowerCase() !== iv.toLowerCase()) { d.push('parameter ' + k); }
  }
  return d;
}

// The ALTER TASK statements that turn an installed task into a wanted one (the dependencies that go are removed before).
function alterStatements(db, sc, w, inst) {
  var q = qualified(db, sc, w.name), out = [], diff = taskDifference(w, inst), sets = [], unsets = [], labels = [];
  var scalar = [['warehouse', 'WAREHOUSE'], ['schedule', 'SCHEDULE'], ['config', 'CONFIG'], ['errorIntegration', 'ERROR_INTEGRATION'], ['comment', 'COMMENT']];
  var i, f, value, added, k, label;
  for (i = 0; i < scalar.length; i++) {
    f = scalar[i][0];
    if (contains(diff, f)) {
      labels.push(f);
      value = w[f];
      if (value) {
        sets.push(scalar[i][1] + ' = ' + ((f === 'warehouse' || f === 'errorIntegration') ? ident(value) : literal(value)));
      } else { unsets.push(scalar[i][1]); }
    }
  }
  if (contains(diff, 'allowOverlappingExecution')) {
    labels.push('allowOverlappingExecution');
    sets.push('ALLOW_OVERLAPPING_EXECUTION = ' + (w.allowOverlappingExecution ? 'TRUE' : 'FALSE'));
  }
  for (i = 0; i < diff.length; i++) {
    if (diff[i].substring(0, 10) === 'parameter ') {
      k = diff[i].substring(10);
      labels.push(diff[i]);
      if (hasOwn(w.parameters, k)) { sets.push(k + ' = ' + parameterValue(w.parameters[k])); } else { unsets.push(k); }
    }
  }
  label = labels.join(', ');
  if (unsets.length > 0) { out.push({ sql: 'ALTER TASK ' + q + ' UNSET ' + unsets.join(', '), reason: "Task '" + w.name + "': " + label + ' is unset.' }); }
  if (sets.length > 0) { out.push({ sql: 'ALTER TASK ' + q + ' SET ' + sets.join(', '), reason: "Task '" + w.name + "': " + label + ' is changed.' }); }
  if (contains(diff, 'definition')) {
    out.push({ sql: 'ALTER TASK ' + q + ' MODIFY AS\n' + trimEnd(w.definition), reason: "Task '" + w.name + "': the definition is changed." });
  }
  if (contains(diff, 'condition')) {
    if (w.condition) { out.push({ sql: 'ALTER TASK ' + q + ' MODIFY WHEN ' + w.condition, reason: "Task '" + w.name + "': the condition is changed." }); }
    else { out.push({ sql: 'ALTER TASK ' + q + ' REMOVE WHEN', reason: "Task '" + w.name + "': the condition is removed." }); }
  }
  added = w.after.filter(function (a) { return !contains(inst.after, a); });
  if (added.length > 0) {
    out.push({ sql: 'ALTER TASK ' + q + ' ADD AFTER ' + added.map(function (a) { return qualified(db, sc, a); }).join(', '),
      reason: "Task '" + w.name + "' is now after " + added.join(', ') + '.' });
  }
  if (w.finalize && w.finalize !== inst.finalize) {
    out.push({ sql: 'ALTER TASK ' + q + ' SET FINALIZE = ' + qualified(db, sc, w.finalize), reason: "Task '" + w.name + "' now finalizes '" + w.finalize + "'." });
  }
  return out;
}

// The plan for a wanted graph and the installed graph (null when it is not installed).
function makePlan(desired, actual) {
  var db = desired.database, sc = desired.schema, steps = [], wanted = new Dict(), have = new Dict(), changes = new Dict();
  var i, j, t, cur, order, rootState = null, startAll, final, existing, now, touched, graphStateNow = 'suspended';
  var actualRoot, actualOrder, added, removed, needsChange, desiredRoot, suspendedRoot = false, gone, wantedOrder, plan, reverseActual, diff, alters;

  function q(name) { return qualified(db, sc, name); }
  function step(phase, task, sqlText, reason) { steps.push({ phase: phase, task: task, sql: sqlText, reason: reason }); }
  function result(exists) {
    return { database: db, schema: sc, root: desired.root, exists: exists, isEmpty: steps.length === 0, steps: steps, added: [], removed: [], changed: [] };
  }

  if (!db || !sc) { throw new Error('The graph says no database and schema; give them in the file or with the database and schema arguments.'); }
  for (i = 0; i < desired.tasks.length; i++) { wanted.set(desired.tasks[i].name, desired.tasks[i]); }

  // a graph that is not installed is made, and started if the root says started
  if (!actual) {
    for (i = 0; i < desired.tasks.length; i++) { if (desired.tasks[i].name === desired.root) { rootState = desired.tasks[i].state; } }
    order = allInOrder(desired.tasks);
    for (i = 0; i < order.length; i++) { step('create', order[i].name, createTask(desired, order[i], false), "Task '" + order[i].name + "' is new."); }
    startAll = rootState === 'started';
    for (i = order.length - 1; i >= 0; i--) {
      final = order[i].state;
      if (!final && startAll) { final = 'started'; }
      if (final === 'started') { step('resume', order[i].name, 'ALTER TASK ' + q(order[i].name) + ' RESUME', "Task '" + order[i].name + "' is to be started."); }
    }
    return result(false);
  }

  for (i = 0; i < actual.tasks.length; i++) { have.set(actual.tasks[i].name, actual.tasks[i]); }
  actualRoot = actual.root === null ? null : have.get(actual.root);
  actualOrder = taskOrder(actual.tasks);
  added = desired.tasks.filter(function (x) { return !have.has(x.name); });
  removed = actualOrder.order.filter(function (x) { return !wanted.has(x.name); });
  for (i = 0; i < desired.tasks.length; i++) {
    t = desired.tasks[i];
    if (have.has(t.name)) {
      diff = taskDifference(t, have.get(t.name));
      if (diff.length > 0) { changes.set(t.name, diff); }
    }
  }
  needsChange = added.length > 0 || removed.length > 0 || changes.keys().length > 0;

  // the state that the graph ends in: the wanted root's, else the installed root's, else suspended
  desiredRoot = desired.root === null ? null : wanted.get(desired.root);
  if (actualRoot && actualRoot.state) { graphStateNow = actualRoot.state; }
  if (desiredRoot && desiredRoot.state) { graphStateNow = desiredRoot.state; }
  function finalState(task) { return task.state ? task.state : graphStateNow; }

  if (needsChange && actualRoot && actualRoot.state === 'started') {
    step('suspend', actual.root, 'ALTER TASK ' + q(actual.root) + ' SUSPEND', 'The root is suspended while the graph is changed.');
    suspendedRoot = true;
  }
  // dependencies that go, before the tasks that go
  for (i = 0; i < desired.tasks.length; i++) {
    t = desired.tasks[i];
    if (!changes.has(t.name)) { continue; }
    cur = have.get(t.name);
    gone = cur.after.filter(function (a) { return !contains(t.after, a); });
    if (gone.length > 0) {
      step('unlink', t.name, 'ALTER TASK ' + q(t.name) + ' REMOVE AFTER ' + gone.map(q).join(', '), "Task '" + t.name + "' is no longer after " + gone.join(', ') + '.');
    }
    if (cur.finalize && !t.finalize) {
      step('unlink', t.name, 'ALTER TASK ' + q(t.name) + ' UNSET FINALIZE', "Task '" + t.name + "' no longer finalizes '" + cur.finalize + "'.");
    }
  }
  reverseActual = actualOrder.order.slice().reverse();
  for (i = 0; i < reverseActual.length; i++) {
    if (!wanted.has(reverseActual[i].name)) {
      step('drop', reverseActual[i].name, 'DROP TASK ' + q(reverseActual[i].name), "Task '" + reverseActual[i].name + "' is not in the wanted graph.");
    }
  }
  wantedOrder = allInOrder(desired.tasks);
  for (i = 0; i < wantedOrder.length; i++) {
    if (!have.has(wantedOrder[i].name)) {
      step('create', wantedOrder[i].name, createTask(desired, wantedOrder[i], false), "Task '" + wantedOrder[i].name + "' is new.");
    }
  }
  for (i = 0; i < wantedOrder.length; i++) {
    if (!changes.has(wantedOrder[i].name)) { continue; }
    alters = alterStatements(db, sc, wantedOrder[i], have.get(wantedOrder[i].name));
    for (j = 0; j < alters.length; j++) { step('alter', wantedOrder[i].name, alters[j].sql, alters[j].reason); }
  }
  // the state: started tasks are resumed with the root last, tasks that are to stop are suspended with the root first
  for (i = wantedOrder.length - 1; i >= 0; i--) {
    t = wantedOrder[i];
    existing = have.get(t.name);
    if (finalState(t) === 'started') {
      now = existing ? existing.state : null;
      touched = !existing || (t.name === desired.root && suspendedRoot);
      if (now !== 'started' || touched) { step('resume', t.name, 'ALTER TASK ' + q(t.name) + ' RESUME', "Task '" + t.name + "' is to be started."); }
    }
  }
  for (i = 0; i < wantedOrder.length; i++) {
    t = wantedOrder[i];
    if (!have.has(t.name)) { continue; }
    existing = have.get(t.name);
    if (finalState(t) === 'suspended' && existing.state === 'started' && !(t.name === desired.root && suspendedRoot)) {
      step('suspend', t.name, 'ALTER TASK ' + q(t.name) + ' SUSPEND', "Task '" + t.name + "' is to be suspended.");
    }
  }
  plan = result(true);
  plan.added = added.map(function (x) { return x.name; });
  plan.removed = removed.map(function (x) { return x.name; });
  plan.changed = sortedStrings(changes.keys());
  return plan;
}

// The installed graph that holds the tasks of the wanted one (the first, in the order of the graphs), with its parameters.
function readInstalled(desired) {
  var graphs, wanted = new Dict(), i, j, found = null;
  if (!desired.database || !desired.schema) { throw new Error('The graph says no database and schema; give them in the file or with the database and schema arguments.'); }
  graphs = readGraphs(desired.database, desired.schema, null);
  for (i = 0; i < desired.tasks.length; i++) { wanted.set(desired.tasks[i].name, true); }
  for (i = 0; i < graphs.length && found === null; i++) {
    for (j = 0; j < graphs[i].tasks.length; j++) { if (wanted.has(graphs[i].tasks[j].name)) { found = graphs[i]; } }
  }
  if (found) { loadParameters(found); }
  return found;
}

// The plan as text: a heading, then each step with its reason and the SQL (a body of many lines is indented as a whole).
function planText(plan) {
  var n = plan.steps.length, name = plan.database + '.' + plan.schema + (plan.root ? '.' + plan.root : ''), lines = [], i, s;
  lines.push('Graph ' + name + ': ' + (n === 0 ? 'nothing to change' : n + (n === 1 ? ' step' : ' steps')));
  for (i = 0; i < n; i++) {
    s = plan.steps[i];
    lines.push('  ' + (i + 1) + '. ' + padRight(s.phase, 7) + '  ' + s.task + '   ' + s.reason);
    lines.push(s.sql.split('\n').map(function (l) { return '       ' + l; }).join('\n'));
  }
  return lines.join('\n');
}

// ---------------------------------------------------------------------------------------------------------------------------
// Applying a plan (Publish-TaskGraph.ps1)
// ---------------------------------------------------------------------------------------------------------------------------

function firstLine(s) { return s.split('\n')[0]; }

// Runs the steps one by one. There is no transaction for DDL, so the first that fails stops the rest and the message says which
// steps were done.
function applyPlan(plan, reply) {
  var done = 0, i, j, s, applied, lines;
  for (i = 0; i < plan.steps.length; i++) {
    s = plan.steps[i];
    try {
      run(s.sql);
    } catch (e) {
      applied = '';
      if (done > 0) {
        lines = [];
        for (j = 0; j < done; j++) { lines.push('  ' + firstLine(plan.steps[j].sql)); }
        applied = ' Steps 1 to ' + done + ' were done:\n' + lines.join('\n');
      }
      reply.status = 'error';
      reply.text('Step ' + (done + 1) + ' of ' + plan.steps.length + ' failed (' + firstLine(s.sql) + '): ' + sentence(errorMessage(e)) + applied +
        '\nThe graph is left as it is; run the command again to continue from here.');
      return done;
    }
    done++;
  }
  return done;
}

function errorMessage(e) { return (e && e.message !== undefined) ? String(e.message) : String(e); }

// A message from Snowflake ends with a full stop already, mostly.
function sentence(s) { return /[.!?]\s*$/.test(s) ? s : s + '.'; }

// ---------------------------------------------------------------------------------------------------------------------------
// Operations on an installed graph (Operations.ps1)
// ---------------------------------------------------------------------------------------------------------------------------

function needNames(args) {
  if (!args.database || !args.schema || !args.root) { throw new Error('Say which graph: database, schema and root.'); }
}

function installedGraph(args) {
  var found;
  needNames(args);
  found = readGraphs(String(args.database), String(args.schema), String(args.root));
  if (found.length === 0) {
    throw new Error("There is no graph with the root '" + args.root + "' in " + args.database + '.' + args.schema + ' (or the role cannot see it).');
  }
  return found[0];
}

function operate(args) {
  var g = installedGraph(args), action = String(args.action || '').toLowerCase(), tasks = allInOrder(g.tasks), reply = new Reply(), statements = [], i, t, label;
  if (action === 'resume') {
    // the children before the root, so that the graph never runs with a part of it off
    for (i = tasks.length - 1; i >= 0; i--) {
      if (tasks[i].state !== 'started') { statements.push(['resume', tasks[i].name, 'ALTER TASK ' + qualified(g.database, g.schema, tasks[i].name) + ' RESUME']); }
    }
  } else if (action === 'suspend') {
    // the root first, so that nothing new starts
    for (i = 0; i < tasks.length; i++) {
      if (tasks[i].state === 'started') { statements.push(['suspend', tasks[i].name, 'ALTER TASK ' + qualified(g.database, g.schema, tasks[i].name) + ' SUSPEND']); }
    }
  } else if (action === 'run' || action === 'retry') {
    statements.push(['run', g.root, 'EXECUTE TASK ' + qualified(g.database, g.schema, g.root) + (action === 'retry' ? ' RETRY LAST' : '')]);
  } else {
    throw new Error("The action must be resume, suspend, run or retry, not '" + action + "'.");
  }
  label = g.database + '.' + g.schema + '.' + g.root;
  if (statements.length === 0) {
    return reply.text('Graph ' + label + ': nothing to ' + action + ' (' + (action === 'resume' ? 'every task is started' : 'no task is started') + ').');
  }
  for (i = 0; i < statements.length; i++) {
    t = statements[i];
    try { run(t[2]); } catch (e) {
      reply.status = 'error';
      return reply.text(action + ' failed at ' + firstLine(t[2]) + ': ' + sentence(errorMessage(e)) + (i > 0 ? ' ' + i + ' of ' + statements.length + ' statements were done.' : ''));
    }
    reply.text(padRight(t[0], 8) + t[1]);
  }
  return reply.text('Graph ' + label + ': done, ' + statements.length + (statements.length === 1 ? ' statement.' : ' statements.'));
}

// ---------------------------------------------------------------------------------------------------------------------------
// The runs of a graph (Get-TaskGraphRun)
// ---------------------------------------------------------------------------------------------------------------------------

// The history with its times as ISO text made by Snowflake: a time that Snowflake keeps with a zone is not turned into text here.
function isoSql(column) { return "TO_VARCHAR(CONVERT_TIMEZONE('UTC', " + column + "), 'YYYY-MM-DD\"T\"HH24:MI:SS.FF3') || 'Z'"; }

function historySql(g, hours, rootId) {
  return 'SELECT GRAPH_RUN_GROUP_ID, RUN_ID, QUERY_ID, NAME, STATE, ERROR_CODE, ERROR_MESSAGE, ATTEMPT_NUMBER, SCHEDULED_FROM, ' +
    isoSql('SCHEDULED_TIME') + ' AS SCHEDULED, ' + isoSql('QUERY_START_TIME') + ' AS STARTED, ' + isoSql('COMPLETED_TIME') + ' AS COMPLETED' +
    ' FROM TABLE(' + ident(g.database) + '.INFORMATION_SCHEMA.TASK_HISTORY(SCHEDULED_TIME_RANGE_START => DATEADD(hour, -' + hours +
    ', CURRENT_TIMESTAMP()), RESULT_LIMIT => 10000, ROOT_TASK_ID => ' + literal(rootId) + ')) ORDER BY SCHEDULED_TIME DESC';
}

function countState(tasks, state) { return tasks.filter(function (t) { return t.state.toUpperCase() === state; }).length; }

function isoSeconds(d) { return d.toISOString().substring(0, 19); }

// The rows of the history as runs: a run is the tasks that share a graph run group.
function runsFromRows(rows, root) {
  var groups = new Dict(), runs = [];
  rows.forEach(function (r) {
    var key = str(r.graph_run_group_id) || str(r.run_id) || str(r.query_id);
    if (!groups.has(key)) { groups.set(key, []); }
    groups.get(key).push(r);
  });
  groups.keys().forEach(function (key) {
    var tasks = groups.get(key).map(function (r) {
      return { task: str(r.name), state: str(r.state), scheduled: str(r.scheduled), started: str(r.started), completed: str(r.completed),
        error: str(r.error_message), errorCode: str(r.error_code), queryId: str(r.query_id), attempt: str(r.attempt_number), scheduledFrom: str(r.scheduled_from) };
    });
    var rootRow = tasks.filter(function (t) { return t.task === root; })[0], state = 'SUCCEEDED', starts = [], ends = [], seconds = null, scheduled = '';
    if (countState(tasks, 'EXECUTING') > 0) { state = 'RUNNING'; }
    else if (countState(tasks, 'SCHEDULED') === tasks.length) { state = 'SCHEDULED'; }
    else if (countState(tasks, 'SCHEDULED') > 0) { state = 'RUNNING'; }
    else if (countState(tasks, 'FAILED') > 0) { state = 'FAILED'; }
    else if (rootRow) { state = rootRow.state; }
    tasks.forEach(function (t) {
      if (t.started) { starts.push(new Date(t.started)); }
      if (t.completed) { ends.push(new Date(t.completed)); }
    });
    starts.sort(function (a, b) { return a.getTime() - b.getTime(); });
    ends.sort(function (a, b) { return a.getTime() - b.getTime(); });
    if (starts.length > 0 && ends.length > 0) { seconds = Math.round((ends[ends.length - 1].getTime() - starts[0].getTime()) / 100) / 10; }
    if (rootRow) { scheduled = rootRow.scheduled; } else if (tasks.length > 0) { scheduled = tasks[0].scheduled; }
    runs.push({ runId: key, state: state, scheduled: scheduled, started: starts.length > 0 ? isoSeconds(starts[0]) : '',
      completed: (ends.length > 0 && state !== 'RUNNING') ? isoSeconds(ends[ends.length - 1]) : '', seconds: seconds, tasks: tasks });
  });
  return runs;
}

function numberArg(v, dflt, name) {
  var n;
  if (v === null || v === undefined || v === '') { return dflt; }
  n = parseInt(v, 10);
  if (isNaN(n) || n < 0) { throw new Error(name + ' must be a number, not ' + v + '.'); }
  return n;
}

// A run in the shape of the web interface API (the task's scheduled time and origin are not part of it).
function runView(r) {
  return { runId: r.runId, state: r.state, scheduled: r.scheduled, started: r.started, completed: r.completed, seconds: r.seconds,
    tasks: r.tasks.map(function (t) {
      return { task: t.task, state: t.state, started: t.started, completed: t.completed, error: t.error, errorCode: t.errorCode, queryId: t.queryId, attempt: t.attempt };
    }) };
}

function runs(args) {
  var g = installedGraph(args), hours = numberArg(args.hours, 24, 'hours'), limit = numberArg(args.limit, 20, 'limit'), rootTask = findTask(g, g.root);
  var found, reply = new Reply(), lines = [], i, j, r;
  found = runsFromRows(query(historySql(g, hours, rootTask.info.id)), g.root).slice(0, limit);
  if (found.length === 0) { return reply.text('Graph ' + g.database + '.' + g.schema + '.' + g.root + ': no runs in the last ' + hours + ' hours.').json({ runs: [] }); }
  found = found.map(runView);
  lines.push(padRight('RUN', 40) + padRight('STATE', 11) + padRight('STARTED', 21) + padRight('SECONDS', 9) + 'TASKS');
  for (i = 0; i < found.length; i++) {
    r = found[i];
    lines.push(padRight(r.runId, 40) + padRight(r.state, 11) + padRight(r.started || r.scheduled, 21) + padRight(r.seconds === null ? '' : r.seconds, 9) + r.tasks.length);
    for (j = 0; j < r.tasks.length; j++) {
      if (r.tasks[j].state.toUpperCase() === 'FAILED') { lines.push('    ' + r.tasks[j].task + ' failed: ' + r.tasks[j].errorCode + ' ' + r.tasks[j].error); }
    }
  }
  return reply.text(lines.join('\n')).json({ runs: found });
}

// The data of the static viewer: the graphs with their parameters, and the runs of each (an empty list for a graph whose history
// the role cannot read, which is what Snowflake says as an error or as no rows).
function opView(args) {
  var graphs = selectedGraphs(args, true), hours = numberArg(args.hours, 24, 'hours'), runsByRoot = {}, reply = new Reply();
  graphs.forEach(function (g) {
    var found = [], key;
    if (g.root === null) { return; }
    try { found = runsFromRows(query(historySql(g, hours, findTask(g, g.root).info.id)), g.root).slice(0, 50).map(runView); } catch (e) { found = []; }
    key = hasOwn(runsByRoot, g.root) ? g.database + '.' + g.schema + '.' + g.root : g.root;
    runsByRoot[key] = found;
  });
  reply.text(graphs.length + (graphs.length === 1 ? ' graph' : ' graphs'));
  return reply.json({ session: { backend: 'Cli', account: '', warehouse: '', role: '' }, graphs: graphs.map(graphView), runs: runsByRoot });
}

// ---------------------------------------------------------------------------------------------------------------------------
// The operations
// ---------------------------------------------------------------------------------------------------------------------------

// The graphs of a request, with the parameters of their tasks when they are asked for.
function selectedGraphs(args, withParameters) {
  var graphs = readGraphs(args.database ? String(args.database) : '', args.schema ? String(args.schema) : '', args.root ? String(args.root) : '');
  if (withParameters) { graphs.forEach(loadParameters); }
  return graphs;
}

function opGraphs(args) {
  var graphs = selectedGraphs(args, toBool(args.parameters) === true), reply = new Reply(), lines = [], anyIncomplete = false, g, i;
  if (graphs.length === 0) { return reply.text('no graphs').json({ graphs: [] }); }
  lines.push('  ' + padRight('ROOT', 32) + padRight('STATE', 11) + padRight('TASKS', 7) + 'SCHEMA');
  for (i = 0; i < graphs.length; i++) {
    g = graphs[i];
    if (g.incomplete) { anyIncomplete = true; }
    lines.push((g.incomplete ? '! ' : '  ') + padRight(g.root === null ? '(no root)' : g.root, 32) + padRight(graphState(g), 11) + padRight(g.tasks.length, 7) + g.database + '.' + g.schema);
  }
  if (anyIncomplete) { lines.push('! a task of the graph is hidden from the role, or is not in the same schema'); }
  return reply.text(lines.join('\n')).json({ graphs: graphs.map(graphView) });
}

// A name as a part of a file name: letters, digits and _ . - only, never starting with a dot, and not used before.
function fileSafe(name, used, suffix) {
  var base = name.replace(/[^A-Za-z0-9_.\-]+/g, '_'), candidate, n = 1;
  if (base.charAt(0) === '.') { base = '_' + base; }
  candidate = base;
  while (used.has(candidate + suffix)) { n++; candidate = base + '_' + n; }
  used.set(candidate + suffix, true);
  return candidate;
}

function opExport(args) {
  var graphs = selectedGraphs(args, true), reply = new Reply(), split = toBool(args.split) === true, noState = toBool(args.noState) === true;
  var usedBases = new Dict(), written = [];
  graphs.forEach(function (g) {
    var parts = [g.database, g.schema, g.root].filter(function (x) { return x; }), base = fileSafe(parts.join('.'), usedBases, '.json'), docs = [], usedNames = new Dict();
    g.tasks.forEach(function (t) {
      var o = taskDocument(t, noState), file;
      if (split) {
        file = fileSafe(t.name, usedNames, '.sql') + '.sql';
        reply.file(base + '.d/' + file, trimEnd(t.definition) + '\n');
        written.push(base + '.d/' + file);
        o.definitionFile = base + '.d/' + file;
      } else { o.definition = t.definition; }
      docs.push(o);
    });
    reply.file(base + '.json', graphDocumentText(g, docs));
    written.push(base + '.json');
  });
  if (graphs.length === 0) { return reply.text('no graphs'); }
  return reply.text('exported ' + graphs.length + (graphs.length === 1 ? ' graph' : ' graphs') + ' in ' + written.length + (written.length === 1 ? ' file' : ' files') + ': ' + written.join(', '));
}

function opCheck(args) {
  var g = readInput(args), problems = checkGraph(g), reply = new Reply(), lines = problems.map(function (p) {
    return padRight(p.severity, 7) + ' ' + (p.task === null ? '-' : p.task) + '  ' + p.message;
  });
  if (errorsOf(problems).length > 0) { reply.exit = 1; }
  return reply.text(problems.length === 0 ? 'no problems' : lines.join('\n')).json({ problems: problems });
}

function opSql(args) { return new Reply().text(graphScript(readInput(args))); }

// A plan, or the errors that keep it from being made (the graph is checked first, as Publish-TaskGraph does).
function opPlan(args, apply) {
  var g = readInput(args), errors = errorsOf(checkGraph(g)), plan, reply = new Reply(), done;
  if (errors.length > 0) {
    reply = failure('The graph is not valid:\n' + errors.map(function (p) { return '  ' + p.message; }).join('\n'));
    return reply;
  }
  plan = makePlan(g, readInstalled(g));
  reply.steps = plan.steps.length;
  reply.text(planText(plan));
  if (apply && plan.steps.length > 0) {
    done = applyPlan(plan, reply);
    if (reply.status === 'ok') { reply.text('done: ' + done + (done === 1 ? ' step' : ' steps')); }
  }
  return reply.json(plan);
}

function dispatch(op, args) {
  if (op === 'graphs') { return opGraphs(args); }
  if (op === 'export') { return opExport(args); }
  if (op === 'check') { return opCheck(args); }
  if (op === 'sql') { return opSql(args); }
  if (op === 'plan') { return opPlan(args, false); }
  if (op === 'apply') { return opPlan(args, true); }
  if (op === 'operate') { return operate(args); }
  if (op === 'runs') { return runs(args); }
  if (op === 'view') { return opView(args); }
  throw new Error("Unknown operation '" + op + "'.");
}

function main() {
  var reply, args;
  try {
    args = ARGS ? JSON.parse(String(ARGS)) : {};
    if (!isObject(args)) { throw new Error('The arguments are not a JSON object.'); }
    reply = dispatch(String(OP).replace(/^\s+|\s+$/g, '').toLowerCase(), args);
  } catch (e) {
    reply = failure(errorMessage(e));
  }
  return encodeReply(reply);
}

return main();
