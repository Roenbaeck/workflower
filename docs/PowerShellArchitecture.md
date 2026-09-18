# PowerShell backend architecture

Workflower must run on a restricted Windows Server: only in-box software plus the
Snowflake CLI (`snow`). No Python. This document describes the replacement for the
Python backend, the Snowflake objects it depends on, and what changes in the repo.

Every Snowflake behaviour asserted here was verified against Snowflake CLI 3.27.0
and the `SISULA` database on 2026-09-18. See [Verified behaviour](#verified-behaviour).

## The design invariant

> **No user data ever enters SQL text. The only values interpolated into SQL are
> integers and GUIDs, both regex-validated at the point of use.**

This is the whole design in one line, and it is mechanically checkable — a reviewer can
grep the PowerShell for string concatenation into SQL and expect to find only
`^[0-9]+$` and `^[0-9a-f-]{36}$` values.

It matters because `snow sql` has **no bind variables**. The options are `--query`,
`--filename`, `--stdin` and `-D/--variable`; `-D` is client-side text substitution
(`<% var %>`), not binding. The alternative to this invariant is hand-rolled escaping of
Snowflake string literals (`'` to `''` *and* `\` to `\\`) at every call site, where one
missed site silently corrupts a stored workflow.

Two mechanisms uphold it:

1. **Payloads travel as staged files.** Workflow JSON is uploaded with `snow stage copy`
   and read back inside Snowflake. The workflow name is not passed as a parameter — it is
   read out of the document itself (`$1:WORKFLOW::STRING`).
2. **Objects are addressed by `CF_ID`, not by name.** The existing anchor model already
   gives every configuration an integer identity, and the editor already tracks it as
   `currentCfId`.

## Second rule: `-f` only, never `-q`

`snow sql -q` corrupts dollar signs:

    snow sql -q 'SELECT $$a;b$$ AS X'   ->  Session variable '$A' does not exist
    snow sql -f file.sql                ->  {"X": "a;b"}

`--enable-templating NONE` does not prevent it. For a project whose template language is
`$token$` and whose stored procedures are delimited by `$$`, this is load-bearing.

**All SQL goes through a temporary `.sql` file, written UTF-8 without BOM.** On
PowerShell 5.1 that means `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)` —
never `Out-File`, `>` or `Set-Content`, whose defaults emit UTF-16 or a BOM and break the
first statement.

## Component map

| Layer | Where | Lines (est.) | Status |
|---|---|---|---|
| Editor UI | `webapp/index.html`, `sisula.js`, `LayoutEngine.js`, `editor.css` | 4,159 | Near-unchanged |
| HTTP + transport | `webapp/*.ps1` | ~250 | New |
| Domain logic | `metadata/` stored procedures | ~250 SQL | New, replaces Python |
| Template rendering | `SISULATE` UDF + stored templates | existing | Unchanged |

The Python backend was 739 lines. Roughly a third becomes PowerShell, a third moves into
Snowflake, and a third — the connection pool — disappears, because there is no longer a
persistent session to manage.

## Stage contract

One named stage and two file formats, created by metadata deployment:

```sql
CREATE STAGE IF NOT EXISTS metadata.WORKFLOWER;

CREATE FILE FORMAT IF NOT EXISTS metadata.WF_JSON
    TYPE = JSON COMPRESSION = NONE;

CREATE FILE FORMAT IF NOT EXISTS metadata.WF_RAW
    TYPE = CSV COMPRESSION = NONE
    FIELD_DELIMITER = NONE RECORD_DELIMITER = NONE
    ESCAPE_UNENCLOSED_FIELD = NONE FIELD_OPTIONALLY_ENCLOSED_BY = NONE;
```

`WF_RAW` reads a whole file back as one byte-exact string. `WF_JSON` gives VARIANT access
for pulling fields out server-side. Both are needed.

| Path | Written by | Read by | Retention |
|---|---|---|---|
| `@WORKFLOWER/in/<run_id>.json` | `snow stage copy` | `_ConfigurationUpsertFromStage` | Removed after successful upsert |
| `@WORKFLOWER/out/<run_id>.sql` | `_RenderToStage` (COPY INTO) | `EXECUTE IMMEDIATE FROM` | **Kept** — audit trail of exactly what ran |
| `@WORKFLOWER/export/<run_id>.json` | `_ExportTaskGraphs` | `snow stage copy` (download) | Removed after download |

`<run_id>` is a fresh GUID per operation. **Unique filenames are mandatory**, not
stylistic: `COPY INTO ... SINGLE = TRUE` cannot overwrite an existing file, and
`OVERWRITE = TRUE` is not supported alongside `SINGLE = TRUE`.

Uploads need `--no-auto-compress`; unloads need `COMPRESSION = NONE`. `EXECUTE IMMEDIATE
FROM` requires uncompressed UTF-8 and caps the file at **10 MB**.

Files under `in/` and `out/` are workflow SQL, as sensitive as the warehouse they target.
Grant on the stage accordingly.

## New Snowflake procedures

### `_ConfigurationUpsertFromStage(run_id VARCHAR)`

Reads `@WORKFLOWER/in/<run_id>.json`, takes the name from the document, upserts, returns
`CF_ID` and name. Replaces the `save_workflow` path.

```sql
doc := (SELECT $1 FROM @metadata.WORKFLOWER/in/<run_id>.json
        (FILE_FORMAT => metadata.WF_JSON));
CALL metadata._ConfigurationUpsert(doc:WORKFLOW::STRING, TO_JSON(doc), 'Workflow');
```

`TO_JSON` reserialises: key order within objects is not preserved (array order is).
Semantically irrelevant — nothing downstream depends on key order — but exported JSON will
not be byte-identical to what was imported. If that matters, read with `WF_RAW` and store
the exact text, at the cost of not being able to extract the name server-side. See
[Open decisions](#open-decisions).

### `_RenderToStage(cf_id NUMBER, template VARCHAR, run_id VARCHAR)`

Renders a stored configuration and writes the DDL to the stage. Absorbs the native-task
guard currently in `WorkflowService.render`.

```sql
COPY INTO @metadata.WORKFLOWER/out/<run_id>.sql
  FROM (SELECT SISULATE(tpl, cfg))
  FILE_FORMAT = (FORMAT_NAME => metadata.WF_RAW)
  SINGLE = TRUE;
```

Returns byte and line counts so the UI can report something meaningful before execution
starts.

### `_ExportTaskGraphs(params_run_id VARCHAR, out_run_id VARCHAR)`

The port of [`reverse_engineer.py`](../webapp/reverse_engineer.py) — 188 lines of
`SHOW TASKS` pagination, graph traversal and regex DDL splitting — as a **JavaScript**
stored procedure, precedent being `SP_SISULA_TEMPLATE_CRUD` in
[`sql/deploy.sql`](../sql/deploy.sql). Schema and root name arrive as a staged params file,
so they never touch SQL text either.

**Must be `EXECUTE AS CALLER`.** `SHOW TASKS` returns only what the invoking role can see,
and the whole import contract depends on that visibility being the user's, not the
procedure owner's.

This is the single largest simplification: it removes the biggest PowerShell port, and the
regex logic moves to a language it was already written against.

### `_TemplateUpsertFromStage(run_id VARCHAR)`

Replaces template seeding in `deploy_metadata.sh`, which currently escapes quotes with
`perl` and builds one enormous `CALL`. PUT the template file, read it with `WF_RAW`, store
it byte-exact. Removes the last place a large payload was inlined into SQL.

## HTTP API

Eight endpoints today; the new set is smaller and addresses by `CF_ID`.

| Method | Path | Change |
|---|---|---|
| GET | `/api/workflows` | Unchanged. Fixed SQL, no parameters. |
| GET | `/api/workflows/{cf_id}` | **Was `{name}`.** Integer-addressed. |
| PUT | `/api/workflows` | **Was `PUT /{name}`.** Body is staged; name comes from the document. Returns `cf_id`. |
| DELETE | `/api/workflows/{cf_id}` | **Was `{name}`.** Integer-addressed. |
| POST | `/api/workflows/{cf_id}/install` | Non-streaming. Returns status, line count, and on failure the reported line number. |
| POST | `/api/workflows/{cf_id}/install/stream` | **Removed.** See below. |
| POST | `/api/connection/reconnect` | **Removed.** `snow` authenticates per invocation. |
| GET | `/api/connection/status` | **New, optional.** Wraps `snow connection test`. |
| POST | `/api/import` | **New.** Replaces `read.sh` for the editor's *Read from Snowflake*. |
| GET | `/{path}` | Unchanged, keeps the `PUBLIC_FILES` allowlist. |

### Why the install stream goes away

`EXECUTE IMMEDIATE FROM` is one statement. There is no per-statement callback to stream,
so the current log — and the `[ERROR]` / `[DONE]` substring protocol the browser parses in
`installWorkflow()` — has nothing to carry.

What replaces it is better than it sounds. The error identifies the failure precisely:

    Uncaught exception of type 'STATEMENT_ERROR' in file @WORKFLOWER/out/<run_id>.sql
    on line 3 at position 0: SQL compilation error: Object 'X' does not exist

File, line and position — and the file persists on the stage, so the editor can fetch it
and highlight the offending line. Today the rendered SQL exists only transiently in a
browser log. This is a net gain in diagnosability, traded against live progress.

It also resolves the standing TODO that install failures return HTTP 200: the CLI exits
non-zero, so the endpoint can return a real status code.

If live progress is wanted later, the template can log progress rows into the metadata
model between statements and the editor can poll. Not needed for v1.

## Flows

### Save

    1. run_id = [guid]::NewGuid()
    2. write body to %TEMP%\<run_id>.json        (UTF-8, no BOM)
    3. snow stage copy <file> @metadata.WORKFLOWER/in/ --no-auto-compress
    4. snow sql -f <call>.sql  ->  CALL metadata._ConfigurationUpsertFromStage('<run_id>')
    5. return { cf_id, name } from --format JSON

Rename-on-save becomes atomic, which the current two-request PUT-then-DELETE is not: the
procedure does both in one statement. That closes another TODO item.

### Install

    1. CALL metadata._RenderToStage(<cf_id>, 'CreateTaskGraph', '<run_id>')
    2. EXECUTE IMMEDIATE FROM @metadata.WORKFLOWER/out/<run_id>.sql
    3. exit code 0 -> success; non-zero -> parse "on line N", return with run_id

Two `snow` invocations, each a fresh process and a fresh login. With the current
password-auth profile that is unattended. **If the profile later moves to MFA, this becomes
two prompts per install** — a reason to prefer key-pair auth on the server.

Semantics are unchanged from today and still need saying in the UI: execution stops at the
first failure and **earlier statements remain applied**. Installations are not atomic.

### Import (Read from Snowflake)

    1. stage a params file { schema, root }
    2. CALL metadata._ExportTaskGraphs('<params_run_id>', '<out_run_id>')
    3. snow stage copy @metadata.WORKFLOWER/export/<out_run_id>.json <localdir>
    4. read the file, return it as the response body

## PowerShell backend

Three files in `webapp/`, PowerShell 5.1 compatible:

- **`Server.ps1`** — `System.Net.HttpListener` loop, routing, static files, headers.
- **`Snow.ps1`** — the only place that shells out. Writes the temp `.sql`, invokes
  `snow ... -f`, captures exit code and stderr, parses `--format JSON`, maps failures to
  HTTP status. Deletes temp files in a `finally`.
- **`Workflows.ps1`** — the endpoint handlers.

Points that need care on 5.1:

- **Encoding.** `[System.IO.File]::WriteAllText($path, $sql, (New-Object System.Text.UTF8Encoding($false)))`. A BOM breaks the first statement.
- **`ConvertTo-Json` defaults to `-Depth 2`** and truncates silently. Workflow JSON is
  deeper than that. Pass `-Depth 100` — or better, never round-trip workflow JSON through
  PowerShell at all. In this design the request body is written to disk as received, so the
  hazard only applies to small API responses.
- **`HttpListener` needs a URL ACL** for a non-admin account:
  `netsh http add urlacl url=http://127.0.0.1:8000/ user=<account>`.
- **Execution policy** may block unsigned `.ps1`. Decide between signing and an explicit
  `-ExecutionPolicy Bypass` in the launcher.
- **Exit codes**: trust `$LASTEXITCODE`, not output parsing. On failure the CLI's JSON
  output can be truncated and unparseable.

Keep from the current server: the `PUBLIC_FILES` allowlist, the `127.0.0.1` bind, and the
cross-origin write rejection. Add a **CSP header**, which closes another TODO item and is
cheap while writing the response path from scratch.

The connection pool has no successor. There is no shared session, so nothing to lease,
nothing to validate and no busy state — `ConnectionBusy`, `ConnectionRequired` and the
428/409 responses all disappear.

## Deployment scripts

Bash is not available on the target. Each script gets a PowerShell equivalent:

| Current | Replacement | Note |
|---|---|---|
| `deploy.sh` | `deploy.ps1` | Must reimplement the `awk` splice of `sisula.js` into the `__SISULA_JS_SOURCE__` marker, including the `$$` guard and dropping the `module.exports` line. |
| `deploy_metadata.sh` | `deploy_metadata.ps1` | Template seeding becomes stage + `_TemplateUpsertFromStage`. |
| `install.sh` | `install.ps1` | Same three-step flow as the API. |
| `read.sh` | `read.ps1` | Thin wrapper over `_ExportTaskGraphs`. |
| `test_all.sh` | `test_all.ps1` | Already just `snow sql -f` per file; a direct port. |
| `webapp/run.sh` | `webapp/run.ps1` | No venv bootstrap needed. |

## Browser changes

Small and mechanical:

1. Address workflows by `cf_id` in API calls (the editor already holds `currentCfId`).
2. Replace the streaming install reader in `installWorkflow()` with a single request plus
   result handling; surface the failing line number and a link to the rendered SQL.
3. Remove or repurpose the Snowflake connection panel and `reconnectSnowflake()`.

Everything else — the graph, the layout engine, the inspector, the offline SQL preview via
`sisula.js` — is untouched.

## Repo streamlining

### Remove

| Path | Lines | Why |
|---|---|---|
| `webapp/server.py`, `workflows.py`, `connections.py`, `reverse_engineer.py`, `install.py`, `read.py` | 739 | Replaced |
| `test_workflows.py`, `test_connections.py`, `test_reverse_engineer.py` | 496 | Test the removed backend |
| `webapp/requirements.txt`, `requirements-dev.txt`, `python_env.sh` | — | No Python |
| `deploy.sh`, `deploy_metadata.sh`, `install.sh`, `read.sh`, `test_all.sh`, `webapp/run.sh` | — | No bash on target |
| `examples/rendered/` | — | Build output; belongs in `.gitignore` |
| `examples/GolfWorkflow.sql` | — | Byte-identical duplicate of `examples/rendered/GolfWorkflow.sql` |
| `.github/copilot-instructions.md` | — | Describes `sisula-mssql`, which is gitignored and not in the repo |

### Revisit

- **`.github/workflows/static.yml`** publishes all of `webapp/` to GitHub Pages. The
  standing TODO is that this exposes the Python backend; after the rewrite it would expose
  the PowerShell backend instead. The fix is the same either way: stage only the
  `PUBLIC_FILES` set into a separate directory and upload that. Or drop Pages if the hosted
  demo is no longer wanted.
- **`test_connection_ui.js`** tests the connection panel being removed.
- **`test_install_ui.js`** tests the `[ERROR]`/`[DONE]` protocol being removed.
- **README** documents a `sisula-mssql/` reference implementation that is gitignored and
  absent. Either restore the description or drop it.

### Keep unchanged

`sql/` (SQL tests already run through `snow`), `metadata/` (grows), `docs/`, all browser
assets, and the four JS regression tests covering browser behaviour.

Net: about **1,500 lines of Python and bash removed**, against roughly 400 lines of
PowerShell and 250 of SQL added.

## What this does *not* fix

The staged-file design solves **transport**. It does nothing for **generation**, and the
distinction matters because the most serious open bug is on the generation side.

[`TODO.md`](../TODO.md) records that the `CreateTaskGraph` template interpolates raw values
into SQL comments and string literals with no escaping:

```sql
-- Execute: $step.description$
COMMENT = '$task.description$'
CALL SYSTEM$SET_RETURN_VALUE('$step.message$');
```

The task description is a `<textarea>`, so a two-line description puts line 2 outside the
`--` comment as executable SQL, and a single `'` in any name, description, source, target
or message terminates its literal. **This is unaffected by anything in this document** and
becomes the top correctness issue once the rewrite lands, because it is the only remaining
path by which ordinary user input reaches Snowflake as SQL. It needs fixing in the renderer
— an escaping token form such as `$'value'$`, or a `sqlEscape()` applied at the quoted
sites.

Also still live and untouched: the Lucide CDN script without SRI, the undefined
`NodeType.ROOT_TASK` / `NodeType.TASK` constants in `LayoutEngine.js`, duplicate task names
merging graph nodes, `step._open` persisted into stored configurations, the one unescaped
`innerHTML` interpolation, and layout state discarded before a delete is confirmed.

Resolved as a side effect: `python_env.sh` on Windows, the `mktemp` permissions in
`deploy_metadata.sh`, install failures returning HTTP 200, non-atomic rename-on-save, and
the missing CSP header.

## Open decisions

1. **Key-pair auth on the server?** The profile currently uses a password. Key-pair avoids
   a stored password and keeps per-invocation logins unattended if MFA is ever enforced.
2. **Byte-exact storage or `TO_JSON`?** Determines whether exported JSON round-trips
   identically.
3. **Keep GitHub Pages?** Determines whether `static.yml` is fixed or deleted.
4. **Stage retention** for `out/`: kept indefinitely as an audit trail, or aged out.

## Verified behaviour

Tested 2026-09-18, Snowflake CLI 3.27.0, connection `Teracom`, database `SISULA`.

| Claim | Evidence |
|---|---|
| `WF_RAW` read is byte-exact | Server `MD5($1)` equalled local file MD5 for content with `'`, `\`, `$$`, `--`, embedded newlines, non-ASCII |
| `WF_JSON` gives VARIANT access | `$1:WORKFLOW::STRING` returned `Nasty'Test` intact |
| `-q` corrupts `$` | `SELECT $$a;b$$` failed as session variable `$A`; `-f` returned `a;b` |
| `--enable-templating NONE` does not fix `-q` | Same failure with the flag set |
| `EXECUTE IMMEDIATE FROM` runs multiple statements | Four-statement file executed in order |
| Stops on first error, prior work applied | Statement 3 failed; `WF_T1` existed with 1 row, `WF_T2` absent |
| Error reports file, line and position | `in file @WORKFLOWER/out/test1.sql on line 3 at position 0` |
| `SINGLE = TRUE` cannot overwrite | `Files already existing at the unload destination` |
| Multi-statement `--format JSON` | One result array per statement |
| Failure exit code | 1 |
