# Workflow JSON format

A workflow definition is a JSON document rendered by the `CreateTaskGraph` sisula template
from metadata-backed template storage into `CREATE TASK` DDL. Store it via `metadata._ConfigurationUpsert` and deploy with
`./install.sh`.

## Top-level fields

| Field | Type | Required | Description |
|---|---|---|---|
| `WORKFLOW` | string | yes | Unique workflow name, used as configuration key |
| `SYSTEM` | string | no | System/project identifier |
| `SOURCE` | string | no | Source system name |
| `WAREHOUSE` | string | authored tasks | Snowflake warehouse for all tasks. Omit when `SERVERLESS` is set. |
| `SERVERLESS` | boolean | no | Run tasks on Snowflake-managed compute instead of a warehouse. Mutually exclusive with `WAREHOUSE`. Requires the `EXECUTE MANAGED TASK` privilege. |
| `TASK_SIZE` | string | `SERVERLESS` | Initial warehouse size Snowflake starts from, e.g. `XSMALL` |
| `TASK_TIMEOUT` | number | authored tasks | Milliseconds before task timeout |
| `MAX_FAILURES` | number | authored tasks | Consecutive failures before auto-suspend (root only) |
| `CONFIG` | string | no | JSON string for graph-level config, set on root task |
| `CF_ID` | number | no | Existing configuration ID for provenance linking |
| `TASKS` | array | yes | Ordered list of task definitions |

## Task object

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Task name (must be unique within schema) |
| `description` | string | yes | Snowflake COMMENT on the task |
| `schedule` | string | no | Cron expression or interval. Only on the root task. Example: `"USING CRON 0 2 * * * UTC"` or `"60 MINUTES"` |
| `after` | array | no | Predecessor task objects. Each element: `{"name": "task_name"}`. Multiple entries create parallel siblings; a task with multiple `after` entries waits for all. |
| `is_root` | boolean | no | Set `true` on the root task to enable `SUSPEND_TASK_AFTER_NUM_FAILURES` and `CONFIG` |
| `stream` | string | no | Run only when this stream has data. Renders `WHEN SYSTEM$STREAM_HAS_DATA('<stream>')`. |
| `condition` | string | no | Run only when this expression is true. Rendered verbatim as `WHEN <condition>`. Mutually exclusive with `stream`. |
| `state` | string | no | `"suspended"` (default) or `"running"`. Controls whether `ALTER TASK ... RESUME` or `SUSPEND` is generated |
| `steps` | array | yes | Ordered list of work steps executed within the task |

## Conditions, and why they are the cheapest lever

`stream` and `condition` both render a `WHEN` clause, allowed on **any** task, not just the
root. A condition is evaluated in the cloud services layer, so when it is false the
warehouse is never resumed and the run consumes no credits.

On the **root** that is the whole graph: a pipeline scheduled every five minutes that
usually has nothing to do costs essentially nothing until it does. On a **child** it is
control flow — skip a branch — and the saving is smaller because the warehouse is usually
already running by then.

```json
{ "name": "tsk_load", "is_root": true, "schedule": "5 MINUTES", "stream": "raw.public.orders_stream" }
```

A task with only a `WHEN` and no schedule or predecessor can still be resumed; Snowflake
requires one of `SCHEDULE`, `AFTER`, `FINALIZE` or `WHEN`.

Two things to know about `SYSTEM$STREAM_HAS_DATA`: it avoids false negatives but not false
positives, and **if it returns true the task must consume the stream in a DML operation** —
otherwise it keeps returning true and the task runs, and bills, on every schedule.

An unqualified stream name resolves in the schema the task is created in, which is usually
the right per-environment behaviour without any templating.

## Step types

Each step has a `type` field and a `description`. The type determines which additional fields are needed.

### `proc` — call a stored procedure

```json
{
    "type": "proc",
    "description": "Create destination tables",
    "call": "my_schema.sp_CreateTables()"
}
```

| Field | Description |
|---|---|
| `call` | The `CALL` statement to execute |

### `sql` — inline SQL with lineage logging

```json
{
    "type": "sql",
    "description": "Insert players into anchor",
    "lineage": {
        "source": "raw_db.public.PlayerImport",
        "target": "dw_db.public.lPL_Player"
    },
    "sql": "INSERT INTO dw_db.lPL_Player SELECT DISTINCT player_id, player_name FROM raw_db.PlayerImport"
}
```

| Field | Description |
|---|---|
| `lineage.source` | Source container name for metadata logging |
| `lineage.target` | Target container name for metadata logging |
| `sql` | SQL statement to execute. Row count is captured via `SQLROWCOUNT` |

### `lineage` — record source→target without row counts

```json
{
    "type": "lineage",
    "description": "Stage → Raw table",
    "source": "sisula.public.@golf_stage",
    "target": "golf_raw.public.PlayerImport"
}
```

| Field | Description |
|---|---|
| `source` | Source container name |
| `target` | Target container name |

### `rows` — log pre-computed row counts

```json
{
    "type": "rows",
    "description": "Log merge results",
    "inserted": 100,
    "updated": 50,
    "deleted": 0,
    "merged": 75
}
```

| Field | Description |
|---|---|
| `inserted` | Rows inserted |
| `updated` | Rows updated |
| `deleted` | Rows deleted |
| `merged` | Rows merged |

**A `rows` step must follow a `lineage` or `sql` step in the same task.** Its counts attach
to the operation that step opened; with no operation to attach to there is nothing to
record against. Validation rejects the wrong ordering, and the logging procedure ignores a
missing operation rather than failing the task.

Counts are read with `TRY_TO_NUMBER`, so a non-numeric value from imported JSON becomes
null rather than becoming SQL.

### `return_value` — pass a message to child tasks

```json
{
    "type": "return_value",
    "message": "players loaded"
}
```

Child tasks can retrieve this with `SYSTEM$GET_PREDECESSOR_RETURN_VALUE('parent_task_name')`.

`SYSTEM$SET_RETURN_VALUE` cannot be called from a SQL stored procedure — Snowflake rejects
functions with side effects there, and a task whose body was a plain `CALL sp_<task>()`
failed at run time. The step therefore sets the message as the procedure's return value,
and the task body publishes it:

```sql
CREATE OR REPLACE TASK <task> ... AS
EXECUTE IMMEDIATE $$
DECLARE
    return_value VARCHAR;
BEGIN
    return_value := (CALL sp_<task>());
    IF (return_value IS NOT NULL) THEN
        CALL SYSTEM$SET_RETURN_VALUE(:return_value);
    END IF;
    RETURN return_value;
END;
$$;
```

A task with no `return_value` step returns null and publishes nothing. With several, the
last one wins.

## Execution model

Each task body is a stored procedure (`sp_<task_name>`) that:

1. Reads the whole graph config via `SYSTEM$GET_TASK_GRAPH_CONFIG()` into `:cfg`, which
   `sql` steps can read. Both this and the run-id lookup are guarded, because they raise
   outside a task rather than returning null; that guard is also what lets `sp_<task_name>`
   be called directly to test a workflow without executing the graph.
2. Calls `metadata._TaskRunStarting` to open the task run, recording its name, the graph
   run it belongs to, the workflow it came from, and when it started
3. Executes each step in order
4. Calls `metadata._TaskRunSourceToTarget` for lineage steps
5. Calls `metadata._TaskRunSetRows` for sql steps
6. Calls `SYSTEM$SET_RETURN_VALUE` for return_value steps
7. Calls `metadata._TaskRunFinished` on success, or `metadata._TaskRunFailed` from its
   exception handler and then re-raises, so a failure is recorded and Snowflake still fails
   the task

The rendered SQL generates both the stored procedures and the `CREATE TASK` DDL, then
sets each task to the state specified by `state` (`suspended` or `running`).

## Example

Minimal two-task graph with a fan-out:

```json
{
    "WORKFLOW": "MyETL_Workflow",
    "WAREHOUSE": "COMPUTE_WH",
    "TASK_TIMEOUT": 3600000,
    "MAX_FAILURES": 3,
    "CONFIG": "{\"workflow\":\"MyETL_Workflow\",\"environment\":\"production\"}",
    "TASKS": [
        {
            "name": "tsk_extract",
            "schedule": "USING CRON 0 3 * * * UTC",
            "is_root": true,
            "description": "Extract from source",
            "state": "suspended",
            "steps": [
                {
                    "type": "proc",
                    "description": "Run extraction",
                    "call": "etl.sp_Extract()"
                }
            ]
        },
        {
            "name": "tsk_load_a",
            "description": "Load table A",
            "after": [{"name": "tsk_extract"}],
            "state": "suspended",
            "steps": [
                {
                    "type": "sql",
                    "description": "Insert into A",
                    "lineage": {"source": "stage.t1", "target": "dw.A"},
                    "sql": "INSERT INTO dw.A SELECT * FROM stage.t1"
                }
            ]
        },
        {
            "name": "tsk_load_b",
            "description": "Load table B",
            "after": [{"name": "tsk_extract"}],
            "state": "suspended",
            "steps": [
                {
                    "type": "proc",
                    "description": "Custom loader for B",
                    "call": "etl.sp_LoadB()"
                }
            ]
        }
    ]
}
```

This renders a root task `tsk_extract` on a daily schedule, and two child tasks
`tsk_load_a` and `tsk_load_b` that run in parallel after extraction completes.
All tasks start suspended.


## Imported native tasks

`read.sh` produces the same `WORKFLOW` / `TASKS` structure with an additional `IMPORT` provenance object and a `native` object on each task. Native tasks do not use the workflow-level warehouse, timeout, config, or logging steps. Their own DDL is authoritative:

```json
{
  "WORKFLOW": "ImportedGraph",
  "TASKS": [{
    "name": "\"DB\".\"SC\".\"ROOT\"",
    "is_root": true,
    "description": "Imported task",
    "schedule": null,
    "after": null,
    "state": "suspended",
    "steps": [],
    "native": {
      "header": "CREATE OR REPLACE TASK \"DB\".\"SC\".\"ROOT\" WAREHOUSE=COMPUTE_WH AS",
      "body": "SELECT 1",
      "source_state": "started",
      "finalizes": null,
      "metadata": {}
    }
  }]
}
```

`native.header` contains the original `GET_DDL` prefix through the task-body `AS` keyword. `native.body` contains the SQL body, without its final statement terminator; the template appends a terminator. SQL scripting blocks, procedure calls and conditions are preserved without attempting to infer lineage or extract stored-procedure internals. The editor exposes the body for editing and displays the header read-only.

Task names and predecessor names are fully qualified SQL identifiers, including quotes. The display fields `description`, `schedule` and `after` are a metadata snapshot, not overrides of the header. For a finalizer, `native.finalizes` is its root and `after` contains a display edge to that root; the actual header retains `FINALIZE`, not `AFTER`. Tasks are emitted in creation order with finalizers last. Native roots are resumed after their children when explicitly enabled.

Imports install suspended by default even when `native.source_state` is `started`. Native task recreation does not restore external dependencies, ownership or grants. Import reads are not a transactional schema snapshot; avoid changing task graphs while exporting.
