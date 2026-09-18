/*
    REVERSE ENGINEER NATIVE SNOWFLAKE TASK GRAPHS

    Reads existing tasks with SHOW TASKS and GET_DDL and writes Workflower JSON to the
    stage. Read-only with respect to the task graph: nothing here alters tasks.

    This runs as the caller. SHOW TASKS only returns tasks visible to the invoking role,
    and the import contract depends on that visibility being the user's rather than the
    procedure owner's. An entirely hidden child cannot be discovered, which is why an
    incomplete graph is an error rather than a partial export.

    The body deliberately contains no adjacent dollar signs, so the delimiter holds.
*/

CREATE OR REPLACE PROCEDURE metadata._ExportTaskGraphs(PARAMS_RUN_ID VARCHAR, OUT_RUN_ID VARCHAR)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
function fail(message) { throw new Error(message); }

var RUN_ID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
if (!RUN_ID.test(PARAMS_RUN_ID) || !RUN_ID.test(OUT_RUN_ID)) fail("Run id must be a GUID");

function run(sqlText, binds) {
    return snowflake.createStatement({ sqlText: sqlText, binds: binds || [] }).execute();
}

function rowsOf(statement, resultSet) {
    var columns = [], i;
    for (i = 1; i <= statement.getColumnCount(); i++) columns.push(statement.getColumnName(i).toLowerCase());
    var out = [];
    while (resultSet.next()) {
        var row = {};
        for (i = 1; i <= columns.length; i++) row[columns[i - 1]] = resultSet.getColumnValue(i);
        out.push(row);
    }
    return out;
}

// Parse SQL identifiers, including quoted dots and escaped double quotes.
function identifierParts(value) {
    var parts = [], position = 0;
    var pattern = /^\s*(?:"((?:[^"]|"")*)"|([A-Za-z_][A-Za-z0-9_$]*))\s*/;
    while (position < value.length) {
        var match = pattern.exec(value.slice(position));
        if (!match) fail("Invalid Snowflake identifier: " + value);
        parts.push(match[1] !== undefined ? match[1].replace(/""/g, '"') : match[2].toUpperCase());
        position += match[0].length;
        if (position === value.length) return parts;
        if (value.charAt(position) !== ".") break;
        position += 1;
    }
    fail("Invalid Snowflake identifier: " + value);
}

function quoted(parts) {
    return parts.map(function (part) { return '"' + String(part).replace(/"/g, '""') + '"'; }).join(".");
}

function parseJsonOr(value, fallback) {
    if (value === null || value === undefined || value === "") return fallback;
    if (typeof value !== "string") return value;
    try { return JSON.parse(value); } catch (e) { fail("Invalid task relationship metadata"); }
}

function isArray(value) { return Object.prototype.toString.call(value) === "[object Array]"; }

// Locate the task AS clause outside comments, strings and identifiers. Both pieces are
// preserved verbatim. EXECUTE AS USER is not the body delimiter, and the body is never
// parsed or rewritten, since it can contain scripting.
function splitTaskDdl(ddl) {
    var tokenizer = /--[^\n]*|\/\*[\s\S]*?\*\/|'(?:''|\\.|[^'\\])*'|"(?:""|[^"])*"|\$\$[\s\S]*?\$\$|[A-Za-z_][A-Za-z0-9_]*/g;
    var words = [], match;
    while ((match = tokenizer.exec(ddl)) !== null) {
        if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(match[0])) words.push({ text: match[0], end: tokenizer.lastIndex });
    }
    var opening = words.slice(0, 4).map(function (w) { return w.text.toUpperCase(); }).join(" ");
    if (opening !== "CREATE OR REPLACE TASK") fail("Expected CREATE OR REPLACE TASK from GET_DDL");
    for (var i = 0; i < words.length; i++) {
        if (words[i].text.toUpperCase() === "AS" && (i === 0 || words[i - 1].text.toUpperCase() !== "EXECUTE")) {
            var header = ddl.slice(0, words[i].end);
            var body = ddl.slice(words[i].end).replace(/^\s+/, "").replace(/\s+$/, "");
            if (!body) break;
            return { header: header, body: body.charAt(body.length - 1) === ";" ? body.slice(0, -1) : body };
        }
    }
    fail("Could not identify the task SQL body in GET_DDL");
}

function readTasks(schemaParts) {
    var rows = [], last = null;
    while (true) {
        var sql = "SHOW TASKS IN SCHEMA " + quoted(schemaParts) + " LIMIT 10000";
        if (last !== null) sql += " FROM '" + last.replace(/'/g, "''").replace(/\\/g, "\\\\") + "'";
        var statement = snowflake.createStatement({ sqlText: sql });
        var page = rowsOf(statement, statement.execute());
        rows = rows.concat(page);
        if (page.length < 10000) break;
        var nextName = page[page.length - 1].name;
        if (nextName === last) fail("Task pagination did not advance");
        last = nextName;
    }
    return rows;
}

// ---- parameters ------------------------------------------------------------
var params = {};
var paramsResult = run("SELECT $1 FROM @metadata.WORKFLOWER/in/" + PARAMS_RUN_ID +
                       ".json (FILE_FORMAT => metadata.WF_RAW)");
if (paramsResult.next()) params = JSON.parse(paramsResult.getColumnValue(1));
var schemaParts = identifierParts(params.schema || "");
if (schemaParts.length !== 2) fail("Schema must be fully qualified as DATABASE.SCHEMA");
var root = params.root || null;

// ---- collect tasks ---------------------------------------------------------
var rows = readTasks(schemaParts);
var byName = {}, order = [];
for (var r = 0; r < rows.length; r++) {
    var key = quoted([rows[r].database_name, rows[r].schema_name, rows[r].name]);
    if (byName[key]) fail("Duplicate task names in Snowflake metadata");
    byName[key] = rows[r];
    order.push(key);
}

// ---- links and finalizers --------------------------------------------------
var links = {}, finalizes = {};
for (var n = 0; n < order.length; n++) {
    var name = order[n], row = byName[name];
    var relations = parseJsonOr(row.task_relations, {});
    var predecessors = parseJsonOr(row.predecessors, relations.Predecessors || []);
    if (!isArray(predecessors)) fail("Unexpected task relationship metadata");
    links[name] = {};
    for (var p = 0; p < predecessors.length; p++) links[name][quoted(identifierParts(predecessors[p]))] = true;
    if (relations.FinalizedRootTask) {
        finalizes[name] = quoted(identifierParts(relations.FinalizedRootTask));
        links[name][finalizes[name]] = true;
    }
    // The root-side relation also exposes a missing or invisible finalizer.
    if (relations.FinalizerTask) {
        var finalizer = quoted(identifierParts(relations.FinalizerTask));
        if (!byName[finalizer]) fail("Missing or inaccessible finalizer: " + finalizer);
        finalizes[finalizer] = name;
    }
}
for (var fk in finalizes) if (finalizes.hasOwnProperty(fk)) links[fk][finalizes[fk]] = true;

for (var lk in links) {
    if (!links.hasOwnProperty(lk)) continue;
    var missing = [];
    for (var parent in links[lk]) if (links[lk].hasOwnProperty(parent) && !byName[parent]) missing.push(parent);
    if (missing.length) fail("Incomplete graph for " + lk + "; missing predecessors: " + missing.sort().join(", "));
}

// ---- connected components --------------------------------------------------
var neighbours = {};
for (var k in links) if (links.hasOwnProperty(k)) neighbours[k] = Object.keys(links[k]).slice();
for (var k2 in links) {
    if (!links.hasOwnProperty(k2)) continue;
    for (var par in links[k2]) if (links[k2].hasOwnProperty(par)) neighbours[par].push(k2);
}

var components = [], remaining = {};
for (var m = 0; m < order.length; m++) remaining[order[m]] = true;
while (Object.keys(remaining).length) {
    var todo = [Object.keys(remaining).sort()[0]], component = {};
    while (todo.length) {
        var current = todo.pop();
        if (component[current]) continue;
        component[current] = true;
        for (var q = 0; q < neighbours[current].length; q++) {
            if (!component[neighbours[current][q]]) todo.push(neighbours[current][q]);
        }
    }
    for (var c in component) if (component.hasOwnProperty(c)) delete remaining[c];
    components.push(Object.keys(component));
}

if (root) {
    var requested = identifierParts(root);
    if (requested.length === 1) requested = schemaParts.concat(requested);
    var requestedKey = quoted(requested);
    if (!byName[requestedKey]) fail("Task not found or not visible: " + root);
    if (Object.keys(links[requestedKey]).length) fail("root must name a root or standalone task");
    components = components.filter(function (comp) { return comp.indexOf(requestedKey) >= 0; });
}

// ---- order and emit --------------------------------------------------------
var graphs = [];
for (var ci = 0; ci < components.length; ci++) {
    var comp = components[ci];
    var roots = comp.filter(function (nm) { return Object.keys(links[nm]).length === 0; }).sort();
    if (roots.length !== 1) fail("Expected exactly one root per task graph; metadata may be incomplete or cyclic");

    // Finalizers must be created after the rest of their graph, not as normal children.
    var pending = {};
    for (var pi = 0; pi < comp.length; pi++) {
        var nm = comp[pi], waits = {};
        if (finalizes.hasOwnProperty(nm)) {
            for (var pj = 0; pj < comp.length; pj++) if (comp[pj] !== nm) waits[comp[pj]] = true;
        } else {
            for (var pk in links[nm]) if (links[nm].hasOwnProperty(pk)) waits[pk] = true;
        }
        pending[nm] = waits;
    }
    var ordered = [];
    while (Object.keys(pending).length) {
        var ready = [];
        for (var pn in pending) {
            if (pending.hasOwnProperty(pn) && Object.keys(pending[pn]).length === 0) ready.push(pn);
        }
        ready.sort();
        if (!ready.length) fail("Cycle in task graph");
        ordered = ordered.concat(ready);
        for (var ri = 0; ri < ready.length; ri++) delete pending[ready[ri]];
        for (var rem in pending) {
            if (!pending.hasOwnProperty(rem)) continue;
            for (var rj = 0; rj < ready.length; rj++) delete pending[rem][ready[rj]];
        }
    }

    var tasks = [];
    for (var oi = 0; oi < ordered.length; oi++) {
        var taskName = ordered[oi], taskRow = byName[taskName];
        var ddlResult = run("SELECT GET_DDL('TASK', ?, TRUE)", [taskName]);
        if (!ddlResult.next()) fail("No DDL available for " + taskName);
        var ddl = ddlResult.getColumnValue(1);
        if (!ddl) fail("No DDL available for " + taskName);
        var split = splitTaskDdl(ddl);
        var after = Object.keys(links[taskName]).sort().map(function (par2) { return { name: par2 }; });
        tasks.push({
            name: taskName,
            description: taskRow.comment || "",
            schedule: taskRow.schedule || null,
            is_root: taskName === roots[0],
            after: after.length ? after : null,
            state: "suspended",
            steps: [],
            native: {
                header: split.header,
                body: split.body,
                source_state: taskRow.state || null,
                finalizes: finalizes.hasOwnProperty(taskName) ? finalizes[taskName] : null,
                metadata: taskRow
            }
        });
    }

    graphs.push({
        WORKFLOW: roots[0],
        TASKS: tasks,
        IMPORT: {
            format: "snowflake-native-v1",
            schema: quoted(schemaParts),
            notes: [
                "Imported tasks are set to suspended for installation.",
                "Native headers retain schedules, warehouses, conditions and other task options.",
                "Finalizer edges identify the finalized root; they are not AFTER dependencies.",
                "Referenced procedures, tables, streams, grants and integrations are not exported.",
                "Only tasks visible to the connection role can be discovered."
            ]
        }
    });
}

// ---- write the result to the stage -----------------------------------------
var payload = JSON.stringify(graphs, null, 2);
run("CREATE OR REPLACE TEMPORARY TABLE metadata._ExportBuffer (content VARCHAR)");
run("INSERT INTO metadata._ExportBuffer (content) SELECT ?", [payload]);
run("COPY INTO @metadata.WORKFLOWER/export/" + OUT_RUN_ID + ".json " +
    "FROM (SELECT content FROM metadata._ExportBuffer) " +
    "FILE_FORMAT = (FORMAT_NAME = 'metadata.WF_RAW') SINGLE = TRUE");

return { run_id: OUT_RUN_ID, graphs: graphs.length, tasks: rows.length };
$$;
