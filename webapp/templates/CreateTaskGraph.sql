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
BEGIN
    grp_id := (SELECT COALESCE(
        SYSTEM$TASK_RUNTIME_INFO('CURRENT_ROOT_TASK_UUID'),
        UUID_STRING()
    ));

    cfg := (SELECT SYSTEM$GET_TASK_GRAPH_CONFIG('workflow'));

    tr_id := (CALL metadata._TaskRunStarting($'task.name'$, :grp_id, :cfg));
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

    -- Pass return value to child tasks
    CALL SYSTEM$SET_RETURN_VALUE($'step.message'$);
$/ endif
$/ endfor

    RETURN 'OK';
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
AS
    CALL sp_$task.name$();
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
