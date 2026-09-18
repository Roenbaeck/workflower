-- ============================================================
-- Workflower task graph
-- Generated from sisula-snowflake template
-- ============================================================

-- Suspend existing imported roots before modifying their graphs.
$/ foreach task in TASKS
$/ if task.native
$/ if task.is_root == true
ALTER TASK IF EXISTS $task.name$ SUSPEND;
$/ endif
$/ endif
$/ endfor

$/ foreach task in TASKS
$/ if task.native
$task.native.header$
$task.native.body$
;
$/ else

----------------------------------------------------------------
-- $|task.name|$
----------------------------------------------------------------
-- Procedure (wraps metadata logging + work)
CREATE OR REPLACE PROCEDURE sp_$task.name$()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    tr_id INT;
    op_id INT;
    grp_id VARCHAR;
    row_count INT;
    cfg VARCHAR;
    return_value VARCHAR;
BEGIN
$- SYSTEM$TASK_RUNTIME_INFO raises outside a task rather than returning null, so a
$- COALESCE around it can never fall back. Catching it instead lets this procedure be
$- called directly, which is how a workflow is tested without executing the whole graph.
    BEGIN
        grp_id := (SELECT SYSTEM$TASK_RUNTIME_INFO('CURRENT_ROOT_TASK_UUID'));
    EXCEPTION
        WHEN OTHER THEN
            grp_id := (SELECT UUID_STRING());
    END;

$- Guarded separately from the run id above: this one also raises when the graph simply
$- has no CONFIG set, and sharing a handler would replace a perfectly good run id with a
$- fresh UUID and break correlation across the graph's task runs.
$- The whole graph CONFIG, not one key out of it: the workflow name is passed explicitly
$- below, and a hard-coded key name assumed a convention that nothing enforced. This is in
$- scope for sql steps, which can read graph-level settings as :cfg.
    BEGIN
        cfg := (SELECT SYSTEM$GET_TASK_GRAPH_CONFIG());
    EXCEPTION
        WHEN OTHER THEN
            cfg := NULL;
    END;

$- The workflow name comes from the bindings, not from :cfg. _TaskRunStarting looks up a
$- configuration by name, and :cfg holds the graph CONFIG document, so passing it meant the
$- tie to the configuration never matched and every run reported an unknown workflow.
    tr_id := (CALL metadata._TaskRunStarting($'task.name'$, :grp_id, $'WORKFLOW'$));
$/ foreach step in task.steps
$/ if step.type == "proc"

    -- Execute: $|step.description|$
    CALL $step.call$;
$/ endif
$/ if step.type == "lineage"

    -- Record lineage: $|step.description|$
    op_id := (CALL metadata._TaskRunSourceToTarget(:tr_id, $'step.source'$, $'step.target'$));
$/ endif
$/ if step.type == "sql"

    -- $|step.description|$
    op_id := (CALL metadata._TaskRunSourceToTarget(:tr_id, $'step.lineage.source'$, $'step.lineage.target'$));
    $step.sql$;
    row_count := SQLROWCOUNT;
    CALL metadata._TaskRunSetRows(:op_id, :row_count, 0, 0, 0);
$/ endif
$/ if step.type == "rows"

    -- Log row counts: $|step.description|$
$- Counts are authored as numbers but reach this template from imported JSON too, so
$- TRY_TO_NUMBER turns a non-numeric value into NULL rather than into SQL.
    CALL metadata._TaskRunSetRows(:op_id, TRY_TO_NUMBER($'step.inserted'$), TRY_TO_NUMBER($'step.updated'$), TRY_TO_NUMBER($'step.deleted'$), TRY_TO_NUMBER($'step.merged'$));
$/ endif
$/ if step.type == "return_value"

    -- Pass return value to child tasks. SYSTEM$SET_RETURN_VALUE cannot be called from a
    -- SQL stored procedure, which rejects functions with side effects, so the message is
    -- returned to the task body and set there instead.
    return_value := $'step.message'$;
$/ endif
$/ endfor

    CALL metadata._TaskRunFinished(:tr_id);
    $- Null unless a return_value step set one; the task body only publishes a non-null.
    RETURN return_value;
EXCEPTION
    WHEN OTHER THEN
        $- Record the failure, then re-raise so Snowflake still marks the task failed and
        $- dependent tasks do not run. Without this the task run row stayed open and a
        $- graph that failed every night looked healthy in the metadata.
        CALL metadata._TaskRunFailed(:tr_id, :SQLERRM);
        RAISE;
END;
$$;

-- Task (calls the procedure)
CREATE OR REPLACE TASK $task.name$
    WAREHOUSE = $WAREHOUSE$
    USER_TASK_TIMEOUT_MS = $TASK_TIMEOUT$
$/ if task.is_root == true
    SUSPEND_TASK_AFTER_NUM_FAILURES = $MAX_FAILURES$
$/ endif
    COMMENT = $'task.description'$
$/ if task.schedule
    SCHEDULE = $'task.schedule'$
$/ endif
$/ if task.after
    AFTER $/ foreach t in task.after $/ if t.first() $t.name$$/ else ,$t.name$$/ endif $/ endfor
$/ endif
$/ if task.is_root == true
    CONFIG = $'CONFIG'$
$/ endif
$- The body is a scripting block, not a bare CALL, because SYSTEM$SET_RETURN_VALUE is
$- rejected inside a SQL stored procedure and has to be called here. EXECUTE IMMEDIATE
$- with dollar quoting is how a task body holds a multi-statement block.
AS
EXECUTE IMMEDIATE $$
DECLARE
    return_value VARCHAR;
BEGIN
    return_value := (CALL sp_$task.name$());
    IF (return_value IS NOT NULL) THEN
        CALL SYSTEM$SET_RETURN_VALUE(:return_value);
    END IF;
    RETURN return_value;
END;
$$;
$/ endif

$/ endfor

-- ============================================================
-- Store workflow definition as a configuration
-- ============================================================
$/ if CF_ID

-- Link tasks to existing configuration
$/ foreach task in TASKS
-- Task linked to configuration $CF_ID$
$/ endfor
$/ else

-- No configuration ID provided; tasks log without provenance
$/ endif

-- ============================================================
-- Set task state
-- ============================================================
$/ foreach task in TASKS
$/ if task.state == "running"
$/ if task.native and task.is_root == true
$/ else
ALTER TASK $task.name$ RESUME;
$/ endif
$/ else
$/ if task.native
$/ else
ALTER TASK $task.name$ SUSPEND;
$/ endif
$/ endif
$/ endfor

-- Start imported roots only after their children have been enabled.
$/ foreach task in TASKS
$/ if task.native and task.is_root == true and task.state == "running"
ALTER TASK $task.name$ RESUME;
$/ endif
$/ endfor
