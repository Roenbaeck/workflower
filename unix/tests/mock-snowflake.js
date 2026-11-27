// A stand-in for Snowflake, for tests that have no account. Plain ES5 with no Node APIs, so that it runs under Jint (Test-Mock.ps1) as
// well as under Node (mock-snow.js, which is the stand-in for the Snowflake CLI).
//
// It answers, from fixtures, the statements that the engine and the server send: SHOW TASKS, SHOW PARAMETERS IN TASK, SHOW DATABASES,
// SHOW SCHEMAS, the history of the tasks, the session queries and the decoding of base64. ALTER TASK ... RESUME and SUSPEND change
// the state of that task; every other statement is only recorded (state.recorded), as the demo session of the PowerShell module does.
//
// The fixtures are those of the demo session (Workflower/Private/Demo.ps1): the databases SALES and FINANCE, the schema SALES.LOAD
// with the graphs NIGHTLY_ROOT (seven tasks, a finalizer and a serverless task, parameters on the root), EVENT_ROOT (suspended, with a
// condition) and CLEAN_UP, and four days of runs of NIGHTLY_ROOT with one failed LOAD_ORDERS.
//
//   var state = MockSnowflake.newState();                 // plain data: keep it as JSON between calls
//   var snowflake = MockSnowflake.makeSnowflake(state);   // the global of a procedure: execute({sqlText, binds}) and a result set
//   MockSnowflake.handleFile(state, sqlText)              // what the CLI prints for a file: an array of row objects
var MockSnowflake = (function () {

  var TASK_COLUMNS = ['created_on', 'name', 'id', 'database_name', 'schema_name', 'owner', 'comment', 'warehouse', 'schedule', 'predecessors',
    'state', 'definition', 'condition', 'allow_overlapping_execution', 'error_integration', 'last_committed_on', 'last_suspended_on',
    'owner_role_type', 'config', 'budget', 'task_relations', 'last_suspended_reason', 'scheduling_mode', 'success_integration',
    'execute_as_user', 'overlap_policy', 'target_completion_interval'];
  var TIME_COLUMNS = ['created_on', 'last_committed_on', 'last_suspended_on'];
  var HISTORY_COLUMNS = ['GRAPH_RUN_GROUP_ID', 'RUN_ID', 'QUERY_ID', 'NAME', 'STATE', 'ERROR_CODE', 'ERROR_MESSAGE', 'ATTEMPT_NUMBER',
    'SCHEDULED_FROM', 'SCHEDULED', 'STARTED', 'COMPLETED'];
  var NIGHTLY_ID = '101';

  // ---- fixtures ------------------------------------------------------------------------------------------------------------

  // A row of SHOW TASKS as a procedure sees it: the predecessors as an array, the relations as an object, times as ISO text (they
  // become Dates when they are read).
  function taskRow(name, id, o) {
    var after = o.after || [], rel = { Predecessors: [] }, i;
    for (i = 0; i < after.length; i++) { rel.Predecessors.push('SALES.LOAD.' + after[i]); }
    if (o.finalizes) { rel.FinalizedRootTask = 'SALES.LOAD.' + o.finalizes; }
    return { created_on: '2026-11-20T08:00:00.000Z', name: name, id: id, database_name: 'SALES', schema_name: 'LOAD', owner: 'DEMO', comment: '',
      warehouse: o.warehouse === undefined ? 'DEMO_WH' : o.warehouse, schedule: o.schedule || '', predecessors: rel.Predecessors.slice(),
      state: o.state || 'started', definition: o.definition || 'SELECT 1', condition: o.condition || '', allow_overlapping_execution: 'null',
      error_integration: 'null', last_committed_on: '2026-11-25T10:00:00.000Z', last_suspended_on: null, owner_role_type: 'ROLE', config: '',
      budget: '', task_relations: rel, last_suspended_reason: '', scheduling_mode: 'Normal', success_integration: 'null', execute_as_user: 'null',
      overlap_policy: 'null', target_completion_interval: null };
  }

  function fixtureTasks() {
    return [
      taskRow('NIGHTLY_ROOT', '101', { schedule: 'USING CRON 0 2 * * * Europe/Stockholm' }),
      taskRow('LOAD_CUSTOMERS', '102', { after: ['NIGHTLY_ROOT'], definition: 'CALL load_customers()' }),
      taskRow('LOAD_ORDERS', '103', { after: ['NIGHTLY_ROOT'], definition: 'INSERT INTO orders SELECT * FROM staging.orders WHERE loaded = FALSE' }),
      taskRow('LOAD_PRODUCTS', '104', { after: ['NIGHTLY_ROOT'], definition: 'CALL load_products()', warehouse: '' }),
      taskRow('BUILD_FACTS', '105', { after: ['LOAD_CUSTOMERS', 'LOAD_ORDERS', 'LOAD_PRODUCTS'], definition: 'CALL build_facts()' }),
      taskRow('PUBLISH', '106', { after: ['BUILD_FACTS'], definition: 'CALL publish_marts()' }),
      taskRow('NOTIFY_DONE', '107', { finalizes: 'NIGHTLY_ROOT', definition: "CALL notify('nightly finished')" }),
      taskRow('EVENT_ROOT', '201', { state: 'suspended', condition: "SYSTEM$STREAM_HAS_DATA('EVENTS_STREAM')", definition: 'CALL handle_events()' }),
      taskRow('CLEAN_UP', '301', { schedule: '1440 MINUTE', definition: 'DELETE FROM audit WHERE ts < DATEADD(day, -90, CURRENT_TIMESTAMP())' })
    ];
  }

  function pad(n, width) { var s = String(n); while (s.length < width) { s = '0' + s; } return s; }
  function iso(ms) {
    var d = new Date(ms);
    return d.getUTCFullYear() + '-' + pad(d.getUTCMonth() + 1, 2) + '-' + pad(d.getUTCDate(), 2) + 'T' + pad(d.getUTCHours(), 2) + ':' +
      pad(d.getUTCMinutes(), 2) + ':' + pad(d.getUTCSeconds(), 2) + '.' + pad(d.getUTCMilliseconds(), 3) + 'Z';
  }

  // Four days of NIGHTLY_ROOT, newest first, each task 20 seconds after the one before and running 15. On the second day LOAD_ORDERS
  // failed and the two tasks after it were skipped.
  function historyRows() {
    var names = ['NIGHTLY_ROOT', 'LOAD_CUSTOMERS', 'LOAD_ORDERS', 'LOAD_PRODUCTS', 'BUILD_FACTS', 'PUBLISH', 'NOTIFY_DONE'], rows = [], day, i, date, state, err, code, start;
    for (day = 0; day < 4; day++) {
      date = iso(Date.UTC(2026, 10, 26 - day)).substring(0, 10);
      for (i = 0; i < names.length; i++) {
        state = 'SUCCEEDED'; err = null; code = null;
        if (day === 1 && names[i] === 'LOAD_ORDERS') { state = 'FAILED'; err = 'SQL compilation error: Object ORDERS does not exist or not authorized.'; code = '2003'; }
        if (day === 1 && (names[i] === 'BUILD_FACTS' || names[i] === 'PUBLISH')) { state = 'SKIPPED'; }
        start = Date.UTC(2026, 10, 26 - day, 2, 0, 20 * i);
        rows.push({ GRAPH_RUN_GROUP_ID: 'run-' + date, RUN_ID: '1', QUERY_ID: 'q-' + date + '-' + i, NAME: names[i], STATE: state, ERROR_CODE: code,
          ERROR_MESSAGE: err, ATTEMPT_NUMBER: '1', SCHEDULED_FROM: 'SCHEDULE', SCHEDULED: date + 'T02:00:00.000Z',
          STARTED: state === 'SKIPPED' ? null : iso(start), COMPLETED: state === 'SKIPPED' ? null : iso(start + 15000) });
      }
    }
    return rows;
  }

  function newState() { return { tasks: fixtureTasks(), recorded: [] }; }

  // ---- text helpers --------------------------------------------------------------------------------------------------------

  var DIGITS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  function utf8Decode(bytes) {
    var out = '', i = 0, c, n;
    while (i < bytes.length) {
      c = bytes[i++];
      if (c < 0x80) { out += String.fromCharCode(c); continue; }
      n = c >= 0xF0 ? 3 : (c >= 0xE0 ? 2 : 1);
      c = c & (n === 3 ? 7 : (n === 2 ? 15 : 31));
      while (n-- > 0 && i < bytes.length) { c = (c << 6) | (bytes[i++] & 63); }
      if (c >= 0x10000) { c -= 0x10000; out += String.fromCharCode(0xD800 + (c >> 10), 0xDC00 + (c & 1023)); } else { out += String.fromCharCode(c); }
    }
    return out;
  }

  function utf8Encode(s) {
    var bytes = [], i, c, d;
    for (i = 0; i < s.length; i++) {
      c = s.charCodeAt(i);
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) { d = s.charCodeAt(i + 1); c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00); i++; }
      if (c < 0x80) { bytes.push(c); }
      else if (c < 0x800) { bytes.push(0xC0 | (c >> 6), 0x80 | (c & 63)); }
      else if (c < 0x10000) { bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63)); }
      else { bytes.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63)); }
    }
    return bytes;
  }

  // Base64 text to the text it holds, as BASE64_DECODE_STRING does; a text that is not base64 is an error.
  function base64Decode(text) {
    var clean = String(text).replace(/=+$/, ''), bytes = [], bits = 0, acc = 0, i, v;
    if (!/^[A-Za-z0-9+\/]*$/.test(clean) || String(text).length % 4 !== 0) { throw new Error("The following string is not a legal base64-encoded value: '" + text + "'"); }
    for (i = 0; i < clean.length; i++) {
      v = DIGITS.indexOf(clean.charAt(i));
      acc = (acc << 6) | v;
      bits += 6;
      if (bits >= 8) { bits -= 8; bytes.push((acc >> bits) & 255); acc = acc & ((1 << bits) - 1); }
    }
    return utf8Decode(bytes);
  }

  function base64Encode(text) {
    var b = utf8Encode(String(text)), out = '', i, n, x;
    for (i = 0; i < b.length; i += 3) {
      n = b.length - i;
      x = (b[i] << 16) | ((n > 1 ? b[i + 1] : 0) << 8) | (n > 2 ? b[i + 2] : 0);
      out += DIGITS.charAt((x >> 18) & 63) + DIGITS.charAt((x >> 12) & 63) + (n > 1 ? DIGITS.charAt((x >> 6) & 63) : '=') + (n > 2 ? DIGITS.charAt(x & 63) : '=');
    }
    return out;
  }

  // A dotted name such as "DB"."SC".T into its parts.
  function splitName(text) {
    var parts = [], i = 0, sb, start;
    while (i < text.length) {
      if (text.charAt(i) === '"') {
        sb = ''; i++;
        while (i < text.length) {
          if (text.charAt(i) === '"') { if (text.charAt(i + 1) === '"') { sb += '"'; i += 2; continue; } i++; break; }
          sb += text.charAt(i++);
        }
        parts.push(sb);
      } else {
        start = i;
        while (i < text.length && text.charAt(i) !== '.') { i++; }
        parts.push(text.substring(start, i));
      }
      if (text.charAt(i) === '.') { i++; }
    }
    return parts;
  }

  // ---- statements ----------------------------------------------------------------------------------------------------------

  function result(columns, rows) { return { columns: columns, rows: rows }; }
  function status(text) { return result(['status'], [[text]]); }

  // A time column of a row is a Date to a procedure.
  function taskValues(row) {
    var out = [], i, k, v;
    for (i = 0; i < TASK_COLUMNS.length; i++) {
      k = TASK_COLUMNS[i];
      v = row[k];
      if (typeof v === 'string' && v !== '' && TIME_COLUMNS.indexOf(k) >= 0) { v = new Date(v); }
      out.push(v);
    }
    return out;
  }

  function showTasks(state, scope, name) {
    var parts = name ? splitName(name) : [], rows = [], i, t;
    for (i = 0; i < state.tasks.length; i++) {
      t = state.tasks[i];
      if (scope === 'ACCOUNT' || (scope === 'DATABASE' && t.database_name === parts[0]) ||
          (scope === 'SCHEMA' && t.database_name === parts[0] && t.schema_name === parts[1])) { rows.push(taskValues(t)); }
    }
    return result(TASK_COLUMNS, rows);
  }

  // What is set on a task: the root of the nightly graph has two parameters at the task level, the others only defaults.
  function showParameters(name) {
    var last = splitName(name).pop(), columns = ['key', 'value', 'default', 'level', 'description', 'type'];
    if (last === 'NIGHTLY_ROOT') {
      return result(columns, [['USER_TASK_TIMEOUT_MS', '3600000', '3600000', 'TASK', '', 'NUMBER'], ['SUSPEND_TASK_AFTER_NUM_FAILURES', '3', '10', 'TASK', '', 'NUMBER']]);
    }
    return result(columns, [['USER_TASK_TIMEOUT_MS', '3600000', '3600000', '', '', 'NUMBER']]);
  }

  // The history is that of the nightly graph; the root task id in the statement says whose it is.
  function history(sql) {
    var id = /ROOT_TASK_ID\s*=>\s*'([^']*)'/.exec(sql), rows = [], all, i, k, row;
    if (id && id[1] === NIGHTLY_ID) {
      all = historyRows();
      for (i = 0; i < all.length; i++) {
        row = [];
        for (k = 0; k < HISTORY_COLUMNS.length; k++) { row.push(all[i][HISTORY_COLUMNS[k]]); }
        rows.push(row);
      }
    }
    return result(HISTORY_COLUMNS, rows);
  }

  function sessionQuery(sql) {
    var re = /CURRENT_(ACCOUNT_NAME|ACCOUNT|ROLE|WAREHOUSE)\(\)/g, columns = [], values = [], m;
    while ((m = re.exec(sql)) !== null) {
      if (m[1] === 'ROLE') { columns.push('ROLE'); values.push('DEMO'); }
      else if (m[1] === 'WAREHOUSE') { columns.push('WAREHOUSE'); values.push('DEMO_WH'); }
      else { columns.push('ACCOUNT'); values.push('demo'); }
    }
    return result(columns, [values]);
  }

  // One statement: the rows it gives as {columns, rows}. A statement that fails throws, as in Snowflake.
  function runSql(state, sqlText, binds) {
    var sql = String(sqlText).replace(/^\s+|[\s;]+$/g, ''), m, i, parts, values, marks;
    if ((m = /^SHOW TASKS IN (SCHEMA|DATABASE|ACCOUNT)(?: (.+))?$/.exec(sql)) !== null) { return showTasks(state, m[1], m[2]); }
    if ((m = /^SHOW PARAMETERS IN TASK (.+)$/.exec(sql)) !== null) { return showParameters(m[1]); }
    if (/^SHOW DATABASES/.test(sql)) { return result(['name'], [['SALES'], ['FINANCE']]); }
    if ((m = /^SHOW SCHEMAS IN DATABASE (.+)$/.exec(sql)) !== null) {
      return result(['name'], splitName(m[1])[0] === 'SALES' ? [['LOAD'], ['MAINTENANCE'], ['INFORMATION_SCHEMA']] : [['PUBLIC'], ['INFORMATION_SCHEMA']]);
    }
    if (/^SELECT BASE64_DECODE_STRING\(\?\)(, BASE64_DECODE_STRING\(\?\))*$/.test(sql)) {
      values = []; marks = [];
      for (i = 0; i < binds.length; i++) { values.push(base64Decode(binds[i])); marks.push('BASE64_DECODE_STRING(?)'); }
      return result(marks, [values]);
    }
    if (/^SELECT BASE64_ENCODE\(\?\)$/.test(sql)) { return result(['BASE64_ENCODE(?)'], [[base64Encode(binds[0])]]); }
    if (/INFORMATION_SCHEMA\.TASK_HISTORY/.test(sql)) { return history(sql); }
    if (/^SELECT\s+CURRENT_/.test(sql)) { return sessionQuery(sql); }
    state.recorded.push(sql);
    if ((m = /^ALTER TASK\s+(.+?)\s+(RESUME|SUSPEND)$/.exec(sql)) !== null) {
      parts = splitName(m[1]);
      state.tasks.forEach(function (t) {
        if (t.name === parts[parts.length - 1] && (parts.length < 3 || (t.database_name === parts[0] && t.schema_name === parts[1]))) { t.state = m[2] === 'RESUME' ? 'started' : 'suspended'; }
      });
    }
    return status('Statement executed successfully.');
  }

  // ---- the objects that a procedure and the CLI use -------------------------------------------------------------------------

  // The global `snowflake` of a procedure: execute returns a result set that is walked with next() and getColumnValue(i) (1-based).
  function makeSnowflake(state) {
    return {
      execute: function (cmd) {
        var out = runSql(state, cmd.sqlText, cmd.binds || []), pos = -1;
        return {
          next: function () { pos++; return pos < out.rows.length; },
          getColumnValue: function (i) {
            if (pos < 0 || pos >= out.rows.length || i < 1 || i > out.columns.length) { throw new Error('no such column or row'); }
            return out.rows[pos][i - 1];
          },
          getColumnName: function (i) { return out.columns[i - 1]; },
          getColumnCount: function () { return out.columns.length; }
        };
      }
    };
  }

  // The rows of a result as the CLI prints them: one object for each row.
  function rowObjects(out) {
    return out.rows.map(function (r) {
      var o = {}, i;
      for (i = 0; i < out.columns.length; i++) { o[out.columns[i]] = r[i] instanceof Date ? r[i].toISOString() : r[i]; }
      return o;
    });
  }

  // The contents of a file for `snow sql -f`: either the request of the engine (an anonymous procedure and a call of it), which is run
  // against the mock, or a plain statement. The answer is what the CLI prints: an array of row objects.
  function handleFile(state, text) {
    var m = /^\s*WITH wf AS PROCEDURE \(OP VARCHAR, ARGS VARCHAR\) RETURNS VARCHAR LANGUAGE JAVASCRIPT AS\s*\$\$\r?\n([\s\S]*)\r?\n\$\$\s*CALL wf\('([^']*)',\s*(?:BASE64_DECODE_STRING\('([^']*)'\)|'((?:[^']|'')*)')\)\s*;?\s*$/.exec(text), args, engine;
    if (m === null) { return rowObjects(runSql(state, text, [])); }
    args = m[3] !== undefined ? base64Decode(m[3]) : m[4].replace(/''/g, "'").replace(/\\\\/g, '\\');
    engine = new Function('OP', 'ARGS', 'snowflake', m[1]);
    return [{ WF: engine(m[2], args, makeSnowflake(state)) }];
  }

  return { newState: newState, makeSnowflake: makeSnowflake, runSql: runSql, handleFile: handleFile, base64Decode: base64Decode, base64Encode: base64Encode };
}());

if (typeof module !== 'undefined' && module.exports) { module.exports = MockSnowflake; }
