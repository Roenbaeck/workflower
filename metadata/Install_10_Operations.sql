/*
    OPERATING AN INSTALLED WORKFLOW

    Installing a graph is not the same as running one. These let the editor report what a
    workflow's tasks are actually doing and change their state, without the client having
    to name a task: it passes a CF_ID and the task names come from the stored
    configuration.

    A task name cannot be a bind variable in ALTER TASK, so these build identifiers by
    concatenation. The names come from the workflow definition, which already becomes DDL
    at install time, so this adds no surface that installing did not.

    DESCRIBE TASK rather than SHOW TASKS: it accepts both the unqualified names authored
    workflows use and the fully qualified ones imports carry.

    All three run EXECUTE AS CALLER. An owner's rights procedure resolves unqualified names
    against its own schema, so a task created unqualified in the caller's schema was simply
    not found here, and ALTER TASK IF EXISTS reported success having done nothing. Running
    as the caller keeps the session's schema context, and operating on tasks should use the
    caller's privileges anyway.
*/

CREATE OR REPLACE PROCEDURE metadata._WorkflowTaskStates(CF_ID FLOAT)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
function config(cfId) {
    var rs = snowflake.createStatement({
        sqlText: "SELECT CF_CNT_Configuration_Content FROM metadata.lCF_Configuration " +
                 "WHERE CF_ID = ? AND CF_TYP_CFT_ConfigurationType = 'Workflow'",
        binds: [cfId]
    }).execute();
    if (!rs.next()) throw new Error('Configuration not found');
    return JSON.parse(rs.getColumnValue(1));
}

var doc = config(CF_ID);
var tasks = doc.TASKS || [];
var out = [];

for (var i = 0; i < tasks.length; i++) {
    var name = tasks[i].name;
    var row = { name: name, is_root: tasks[i].is_root === true, installed: false };
    try {
        var stmt = snowflake.createStatement({ sqlText: 'DESCRIBE TASK ' + name });
        var rs = stmt.execute();
        var columns = {};
        for (var c = 1; c <= stmt.getColumnCount(); c++) columns[stmt.getColumnName(c).toLowerCase()] = c;
        if (rs.next()) {
            row.installed = true;
            row.state = columns.state ? rs.getColumnValue(columns.state) : null;
            row.schedule = columns.schedule ? rs.getColumnValue(columns.schedule) : null;
            row.warehouse = columns.warehouse ? rs.getColumnValue(columns.warehouse) : null;
            row.condition = columns.condition ? rs.getColumnValue(columns.condition) : null;
        }
    } catch (e) {
        // Not installed yet, or not visible to this role. Both are reportable states, not
        // errors: the editor shows a workflow that has been saved but never installed.
        row.error = e.message;
    }
    out.push(row);
}
return out;
$$;


-- Resume or suspend a whole graph in the order Snowflake requires: children before the
-- root when resuming, the root first when suspending, so the graph is never left able to
-- fire with a partially enabled body.
CREATE OR REPLACE PROCEDURE metadata._SetWorkflowState(CF_ID FLOAT, STATE VARCHAR)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
if (STATE !== 'running' && STATE !== 'suspended') throw new Error("STATE must be 'running' or 'suspended'");

var rs = snowflake.createStatement({
    sqlText: "SELECT CF_CNT_Configuration_Content FROM metadata.lCF_Configuration " +
             "WHERE CF_ID = ? AND CF_TYP_CFT_ConfigurationType = 'Workflow'",
    binds: [CF_ID]
}).execute();
if (!rs.next()) throw new Error('Configuration not found');

var tasks = (JSON.parse(rs.getColumnValue(1)).TASKS) || [];
var roots = [], children = [];
for (var i = 0; i < tasks.length; i++) {
    (tasks[i].is_root === true ? roots : children).push(tasks[i].name);
}

var action = STATE === 'running' ? 'RESUME' : 'SUSPEND';
var order = STATE === 'running' ? children.concat(roots) : roots.concat(children);

var changed = [], failed = [];
for (var t = 0; t < order.length; t++) {
    try {
        snowflake.createStatement({ sqlText: 'ALTER TASK IF EXISTS ' + order[t] + ' ' + action }).execute();
        changed.push(order[t]);
    } catch (e) {
        failed.push({ task: order[t], error: e.message });
    }
}
return { state: STATE, changed: changed, failed: failed };
$$;


-- Run a graph now, without waiting for its schedule. EXECUTE TASK needs the EXECUTE TASK
-- privilege granted to the task owner's role; without it this reports that rather than
-- failing opaquely.
CREATE OR REPLACE PROCEDURE metadata._ExecuteWorkflow(CF_ID FLOAT)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
var rs = snowflake.createStatement({
    sqlText: "SELECT CF_CNT_Configuration_Content FROM metadata.lCF_Configuration " +
             "WHERE CF_ID = ? AND CF_TYP_CFT_ConfigurationType = 'Workflow'",
    binds: [CF_ID]
}).execute();
if (!rs.next()) throw new Error('Configuration not found');

var tasks = (JSON.parse(rs.getColumnValue(1)).TASKS) || [];
var root = null;
for (var i = 0; i < tasks.length; i++) if (tasks[i].is_root === true) root = tasks[i].name;
if (!root) throw new Error('This workflow has no root task to execute');

try {
    snowflake.createStatement({ sqlText: 'EXECUTE TASK ' + root }).execute();
    return { executed: root };
} catch (e) {
    return { executed: null, task: root, error: e.message };
}
$$;
