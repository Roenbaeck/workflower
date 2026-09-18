<center><img src="webapp/android-chrome-192x192.png" alt="Workflower icon" width="96" /></center>

# Workflower

Sisula for Snowflake: a template renderer, deployment surface, and workflow editor for
generating and managing Snowflake task graphs from JSON workflow definitions.

![Workflow Editor screenshot](docs/workflow-editor.png)

## What This Repo Contains

- A Snowflake implementation of the Sisula templating engine, exposed through the
  `SISULATE` function and helper procedures.
- A task-graph template flow that renders workflow JSON into Snowflake `CREATE TASK` SQL.
- Metadata deployment SQL for logging, configuration storage, and workflow support tables.
- A browser-based workflow editor, served by a small PowerShell HTTP server.

## Requirements

- **Snowflake CLI** (`snow`), with a configured connection profile
- **Windows PowerShell 5.1** or later
- Node.js 18+ only to run the JavaScript regression tests

There is no Python or bash dependency. Everything runs with what a Windows Server
installation provides plus the Snowflake CLI.

## Core Docs

- [Sisula language reference](docs/SISULA.md)
- [Workflow JSON format](docs/WorkflowFormat.md)
- [PowerShell backend architecture](docs/PowerShellArchitecture.md)

## Repo Layout

- `sql/`: deploys the Snowflake Sisula engine, plus SQL tests.
- `metadata/`: metadata schema, model, knot values, logging, configuration, stage and
  import procedures.
- `webapp/`: the editor UI, the PowerShell server and handlers, and browser assets.
- `webapp/templates/`: template sources deployed into Snowflake metadata storage; also used
  for the browser's offline preview.
- `examples/`: example workflow bindings.

## Quick Start

### 1. Deploy the Sisula engine

```
.\deploy.ps1 <connection_name>
```

### 2. Deploy metadata support

```
.\deploy_metadata.ps1 <connection_name>
```

This creates the metadata model, the `WORKFLOWER` stage, the file formats, the logging and
configuration procedures, and seeds the `CreateTaskGraph` template.

### 3. Start the editor

```
.\webapp\run.ps1 <connection_name>
```

Serves the editor on `http://localhost:8000/`.

### 4. Render or deploy workflow SQL from JSON

```
.\install.ps1 <connection_name> .\examples -DryRun
.\install.ps1 <connection_name> .\examples
```

Both use the **deployed** template in Snowflake metadata storage, so deploy metadata
support first. The installer writes the rendered SQL locally before executing and stops on
the first failure. It does not save its input as a configuration; save it through the
editor if you want it in the workflow library.

### 5. Import existing Snowflake tasks

```
.\read.ps1 <connection_name> .\imported -Schema MY_DATABASE.MY_SCHEMA
.\read.ps1 <connection_name> .\imported -Schema MY_DATABASE.MY_SCHEMA -Root ROOT_TASK
```

Read-only: it uses `SHOW TASKS` and `GET_DDL` and never alters a task. It creates one JSON
file per graph and refuses to overwrite existing files. Snowflake only exposes tasks
visible to the current role, so an entirely hidden child cannot be discovered and makes the
export fail rather than emit a partial graph.

Use **Import workflow JSON** in the editor to open an exported file. Native tasks run
directly without Workflower's logging wrappers; their `GET_DDL` header is preserved and
shown read-only. Imports default to **suspended**, with the original state kept as
metadata. Referenced procedures, tables, streams, integrations and grants are not exported
or reconstructed.

### 6. Run tests

```
.\test_all.ps1 <connection_name>
node test_local.js
node --test test_workflow_read.js test_editor_ui.js test_native_tasks.js
```

`test_all.ps1` runs the SQL suite in `sql/`. Most of those files render templates and print
the result for inspection; `sql/test_escaping.sql` asserts, reporting a `STATUS` column
that the runner checks.

## Architecture

The browser talks to a local PowerShell server, which shells out to the Snowflake CLI.

**No user data is ever interpolated into SQL.** The Snowflake CLI has no bind variables, so
instead of escaping values, payloads travel as staged files and objects are addressed by
their integer `CF_ID`. The only values that reach SQL from the client are integers and
GUIDs, both validated at the point of use.

Saving uploads the document to `@metadata.WORKFLOWER/in/<run_id>.json`; Snowflake reads the
workflow name out of the document and stores the original bytes. Installing renders to
`@metadata.WORKFLOWER/out/<run_id>.sql` and runs it with `EXECUTE IMMEDIATE FROM`.

All SQL is passed to the CLI through a temporary `.sql` file. `snow sql -q` corrupts dollar
signs, which matters for a template language built on `$token$` whose procedures are
delimited by doubled dollars.

Rendered SQL is kept on the stage as an audit trail of exactly what was executed.

### Stage retention

Snowflake has no expiry for staged files — storage lifecycle policies apply to table rows,
not to stages. `LIST` and `REMOVE` are both rejected inside a stored procedure, so the
prune cannot be a Snowflake task either. It is a script you schedule:

```
.\prune.ps1 <connection_name> -WhatIf
.\prune.ps1 <connection_name>
```

Defaults keep `out/` for 90 days and `in/` and `export/` for 7. `out/` holds the SQL that
was actually executed and is the audit trail; `in/` duplicates a configuration already
stored historized in the metadata model, and `export/` has already been downloaded.

To see what is there before choosing a window:

```sql
ALTER STAGE metadata.WORKFLOWER REFRESH;
SELECT AREA, COUNT(*) AS FILES, SUM(BYTES) AS BYTES, MAX(AGE_DAYS) AS OLDEST_DAYS
FROM metadata.WORKFLOWER_STAGE_FILES GROUP BY AREA;
```

On the server, schedule `prune.ps1` with Windows Task Scheduler.

### Installation is not atomic

`EXECUTE IMMEDIATE FROM` stops at the first failing statement and **leaves earlier
statements applied**. Failures are reported with the line Snowflake named and the run id of
the rendered file, never retried automatically. Inspect Snowflake before retrying.

### Connections

The server has no connection pool and no session of its own. Each operation invokes `snow`,
which authenticates from the named profile in `~/.snowflake/config.toml`. The editor's
connection panel reports which user, role, database and warehouse the server is acting as.

For an unattended server, prefer key-pair authentication in the connection profile. See the
[Snowflake CLI connection documentation](https://docs.snowflake.com/en/developer-guide/snowflake-cli/connecting/configure-connections).

### Security posture

The server binds to `127.0.0.1`, serves only an explicit allowlist of browser assets,
rejects cross-origin writes, and sets a restrictive CSP. It is a single-user administrative
tool with no authentication; shared hosting would require an authentication and
authorization design.

A non-administrator account may need a URL reservation before it can listen:

```
netsh http add urlacl url=http://127.0.0.1:8000/ user=DOMAIN\user
```

## Template escaping

Values interpolated into generated SQL must use an escaping token form. See
[docs/SISULA.md](docs/SISULA.md):

- `$'path'$` renders a quoted SQL string literal.
- `$|path|$` renders text that is safe on one SQL comment line.

The plain `$path$` form interpolates verbatim and is correct only where the value is
genuinely SQL, such as a step's `sql` or a native task body.
