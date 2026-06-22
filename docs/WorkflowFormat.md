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
| `WAREHOUSE` | string | yes | Snowflake warehouse for all tasks |
| `TASK_TIMEOUT` | number | yes | Milliseconds before task timeout |
| `MAX_FAILURES` | number | yes | Consecutive failures before auto-suspend (root only) |
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
| `state` | string | no | `"suspended"` (default) or `"running"`. Controls whether `ALTER TASK ... RESUME` or `SUSPEND` is generated |
| `steps` | array | yes | Ordered list of work steps executed within the task |

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

### `return_value` — pass a message to child tasks

```json
{
    "type": "return_value",
    "message": "players loaded"
}
```

Child tasks can retrieve this with `SYSTEM$GET_PREDECESSOR_RETURN_VALUE('parent_task_name')`.

## Execution model

Each task body is a stored procedure (`sp_<task_name>`) that:

1. Reads the graph config via `SYSTEM$GET_TASK_GRAPH_CONFIG('workflow')`
2. Calls `metadata._TaskRunStarting` to log the task run
3. Executes each step in order
4. Calls `metadata._TaskRunSourceToTarget` for lineage steps
5. Calls `metadata._TaskRunSetRows` for sql steps
6. Calls `SYSTEM$SET_RETURN_VALUE` for return_value steps

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
