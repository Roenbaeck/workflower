<center><img src="Workflower/ui/android-chrome-192x192.png" alt="Workflower icon" width="96" /></center>

# Workflower

Read, check, compare, change and run **any** Snowflake task graph: one that was written by hand, by another tool, by an agent,
or by this one. Workflower keeps nothing in Snowflake. It reads the tasks with `SHOW TASKS`, and what it writes are ordinary
`CREATE TASK` and `ALTER TASK` statements.

- **Read** the graphs of a schema, a database or the account into one model, with their state, compute, schedule, conditions,
  parameters and dependencies, including finalizers.
- **Check** a graph against what Snowflake enforces (cycles, two roots, a schedule on a child, a missing predecessor, the limits
  of 1,000 tasks, 100 children and 100 predecessors, a finalizer that does not finalize the root, a root that cannot be resumed)
  before anything is sent.
- **Compare** a wanted graph with the installed one and get the steps that turn one into the other, in the order that Snowflake
  needs, before anything is changed. A graph that is already as wanted needs no steps.
- **Write** graphs as SQL, or as JSON files that belong in git, and install a file in another database or with another warehouse.
- **Operate**: start and stop a graph in the right order, run it, retry the last run, and see its runs, task by task, with the
  errors.
- **See and edit** all of it in a browser, on your own machine, with the plan shown before it is applied.

## Requirements

- **Windows**: Windows PowerShell 5.1 or later. Nothing else has to be installed.
- **macOS and Linux**: a POSIX shell, the usual tools (`sed`, `tr`, `grep`, `base64`) and the Snowflake CLI. Nothing else; see
  [macOS and Linux](#macos-and-linux).
- A way to Snowflake, either of
  - the SQL REST API with a token (a [programmatic access token](https://docs.snowflake.com/en/user-guide/programmatic-access-tokens),
    an OAuth token or a key-pair JWT), or
  - the [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index) (`snow`) with a connection
    profile, which is what to use for single sign-on.
- A role that can see the tasks (`SHOW TASKS` lists only what the role can see; a graph with a hidden task is marked
  incomplete), and for changes the privileges that tasks need: `CREATE TASK` and `EXECUTE TASK`, and `EXECUTE MANAGED TASK` for
  serverless tasks. Run history needs `MONITOR` on the tasks, or to own them.

## The interface

```powershell
.\workflower.ps1 -Connection default                         # the Snowflake CLI, a connection profile
.\workflower.ps1 -Account myorg-myaccount -TokenFile ~\.snowflake\pat.txt -Warehouse ETL_WH -Role SYSADMIN
.\workflower.ps1 -Demo                                      # invented graphs, no account
```

It opens a page on this machine (`127.0.0.1`, port 8765; `-Port` changes it); Ctrl+C stops it. The token or connection stays
in the PowerShell process and never reaches the browser, every call carries a secret that the process made up when it started,
and a request for any other host is refused.

Choose a database and a schema, and the graphs in it are listed. A graph is drawn left to right, with the state of every task
and the outcome of its last run. Select a task to edit it. **Plan changes** shows exactly what will be sent, step by step;
**Apply** runs it. Nothing changes before that.

## macOS and Linux

The same things, from a shell script that needs nothing but the Snowflake CLI (`snow`) and a connection (`snow connection add`):

```sh
unix/workflower graphs  -c default -d ETL -s LOAD                     # the graphs of a schema
unix/workflower export  -c default -d ETL -s LOAD -o graphs --split   # JSON files, one per graph, and each task's SQL in its own file
unix/workflower check   -c default graphs/ETL.LOAD.LOAD_ROOT.json     # the rules of Snowflake
unix/workflower plan    -c default graphs/ETL.LOAD.LOAD_ROOT.json     # what would change, step by step
unix/workflower apply   -c default graphs/ETL.LOAD.LOAD_ROOT.json     # asks, then changes (-y does not ask)
unix/workflower plan    -c default graphs/ETL.LOAD.LOAD_ROOT.json -d ETL_PROD --warehouse PROD_WH   # the same file for production
unix/workflower resume  -c default -d ETL -s LOAD -r LOAD_ROOT        # also suspend, run, retry
unix/workflower runs    -c default -d ETL -s LOAD -r LOAD_ROOT --hours 48
unix/workflower view    -c default -d ETL -s LOAD                     # a read-only page of the graphs and their runs, opened in the browser
unix/workflower help
```

The files are the same as on Windows, so a graph exported on one system is planned and applied on the other, and the plan is the same
steps with the same SQL (a differential test runs every case through both). `-c` can be left out when `WORKFLOWER_CONNECTION` is set;
`--role` and `--session-warehouse` choose the role and warehouse of the session.

How it works, because a shell script can neither parse JSON nor plan a change: the logic is `unix/engine.js`, JavaScript that the script
sends to Snowflake as an anonymous procedure (`WITH wf AS PROCEDURE ... CALL wf(...)`), which **creates nothing** in the account and runs
with the rights of your role. The script sends the request through `snow sql` and shows the answer (the protocol is in
`unix/PROTOCOL.md`). So the account must allow JavaScript procedures, as accounts do by default.

What differs from Windows: there is no editing page, since a page that edits needs a local server, which a shell script cannot be.
`view` gives the same canvas, inspector and run history as a static, read-only page (a folder with the page and a `data.js`; nothing is
sent anywhere). To change a graph, edit its file and `plan` and `apply` it.

What has been checked: the shell script's own work on Linux and macOS in CI (`unix/tests/test-shell.sh`, with a canned `snow`, which
includes the differences between GNU and BSD `base64`); the engine under an ES5 interpreter (249 checks) and against the PowerShell module
(506 assertions over 60 cases); and the engine in Snowflake (108 checks) and the whole script and engine against a real account through
a stand-in for `snow` that sends the same file through the REST API. **What has not been run is the script with the real Snowflake CLI**:
the options it passes (`snow sql --enable-templating NONE --format JSON -f <file>`, `-c`, `--role`, `--warehouse`) are the ones that the
CLI documents, but if a version of the CLI prints a result in another form the script will say that the answer had no result.

## The commands

```powershell
Import-Module .\Workflower\Workflower.psd1
$s = New-WfSession -Account myorg-myaccount -TokenFile ~\.snowflake\pat.txt -Warehouse ETL_WH -Role SYSADMIN
# or: $s = New-WfSession -Connection default
```

| | |
|---|---|
| `Get-TaskGraph $s -Database ETL -Schema LOAD [-Root LOAD_ROOT]` | the graphs; without `-Schema` the database, without `-Database` the account |
| `Test-TaskGraph $graph` | the problems found: `Severity` (error, warning, info), `Code`, `Message` |
| `ConvertTo-TaskGraphSql $graph [-AsScript] [-IncludeState]` | the `CREATE TASK` statements, parents first |
| `Export-TaskGraph $graph -Directory .\graphs [-SplitDefinitions]` | JSON files, one per graph |
| `Import-TaskGraph .\graphs [-Database X] [-Schema Y] [-Warehouse Z]` | graphs from files, optionally moved |
| `Compare-TaskGraph $wanted -Session $s` | the plan: ordered steps with SQL and reason, or none |
| `Publish-TaskGraph $wanted -Session $s [-WhatIf]` | plans, then runs the steps |
| `Resume-TaskGraph`, `Suspend-TaskGraph`, `Start-TaskGraph [-Retry]` | operate an installed graph |
| `Get-TaskGraphRun $graph -Session $s [-Hours 24]` | the runs, newest first, each with its tasks |
| `Start-Workflower -Session $s` | the interface |

Back up every graph in a schema, change one in an editor, and look at what would change:

```powershell
Get-TaskGraph $s -Database ETL -Schema LOAD | Export-TaskGraph -Directory .\graphs -SplitDefinitions
# edit .\graphs\ETL.LOAD.LOAD_ROOT.d\LOAD_A.sql, then
Import-TaskGraph .\graphs\ETL.LOAD.LOAD_ROOT.json | Publish-TaskGraph -Session $s -WhatIf
Import-TaskGraph .\graphs\ETL.LOAD.LOAD_ROOT.json | Publish-TaskGraph -Session $s
```

Promote the same file to production:

```powershell
Import-TaskGraph .\graphs\ETL.LOAD.LOAD_ROOT.json -Database ETL_PROD -Warehouse PROD_WH | Publish-TaskGraph -Session $p
```

### How a plan is ordered

Snowflake refuses to change a graph whose root is not suspended ("Unable to update graph ... since that root task is not
suspended") and has no transaction for DDL, so a plan is
a list of steps that are run one by one, and the first that fails stops the rest:

1. **suspend** the root, if the graph is started and something has to change;
2. **unlink**: dependencies that go are removed (`ALTER TASK ... REMOVE AFTER`, `UNSET FINALIZE`);
3. **drop** the tasks that go, children first;
4. **create** the new tasks, parents first;
5. **alter** the changed ones: `SET` and `UNSET` for properties and parameters, `MODIFY AS` for the SQL, `MODIFY WHEN` or
   `REMOVE WHEN` for the condition, `ADD AFTER`, `SET FINALIZE`;
6. **resume** (children before the root) what is to be started, or **suspend** what is to be stopped.

If a step fails, the error says which steps were done; run the command again to continue from there, since the plan is made
from what is installed.

A graph is either on or off: the state of the root decides, unless a task says otherwise in its own `state`. A new graph is made
suspended unless its tasks say `started`.

### A graph file

```json
{
  "format": "workflower-graph",
  "version": 1,
  "database": "ETL",
  "schema": "LOAD",
  "tasks": [
    { "name": "LOAD_ROOT", "schedule": "USING CRON 0 2 * * * Europe/Stockholm", "warehouse": "ETL_WH",
      "parameters": { "USER_TASK_TIMEOUT_MS": "3600000" }, "state": "started", "definition": "CALL load_start()" },
    { "name": "LOAD_A", "after": ["LOAD_ROOT"], "warehouse": "ETL_WH", "definitionFile": "ETL.LOAD.LOAD_ROOT.d/LOAD_A.sql" },
    { "name": "LOAD_DONE", "finalize": "LOAD_ROOT", "condition": "SYSTEM$STREAM_HAS_DATA('S')", "definition": "CALL notify()" }
  ]
}
```

Per task: `name`, `definition` (or `definitionFile`, a path relative to the file), `after` (names of predecessors), `finalize`
(the root, for a finalizer), `schedule`, `warehouse`, `condition` (the `WHEN` expression), `allowOverlappingExecution`,
`errorIntegration`, `comment`, `config`, `parameters` (task and session parameters set on the task, by name) and `state`
(`started` or `suspended`; left out, a task keeps the state it has). A field that is not in the list is refused, so that a
misspelling is not ignored. All tasks of a graph are in one schema, which Snowflake requires.

**Names are exact.** They are written as Snowflake stores them, upper case unless the task was made with a quoted name, and
every identifier is written quoted, so a file made by `Export-TaskGraph` always means what it says.

## What was checked, and against what

- 81 tests need no Snowflake (`tests\Test-Offline.ps1`): fixtures shaped like `SHOW TASKS`, validation, rendering, the files
  and every kind of plan.
- 31 tests run the web server and its API over HTTP with the demo session (`tests\Test-Api.ps1`), and the interface has a self-test of
  193 checks that runs in a headless Edge or Chrome against the demo server (`tests\Test-Ui.ps1`): layout, editing, renaming,
  planning, applying, importing, the guards against losing edits, and that markup in names and SQL stays text.
- 41 tests run against a real account (`tests\Test-Live.ps1`, in a scratch database that it drops): every statement of the
  plan is accepted, a graph that was installed reads back as what was wanted so that the next plan is empty, a graph made by
  hand with a name with a space, a cron schedule in a time zone, a serverless task, a finalizer and a body in `BEGIN ... END`
  is read, copied and reinstalled unchanged, a started graph is changed and started again, a graph is suspended and run and its
  run is found in the history.

  ```powershell
  .\tests\Test-Live.ps1 -Account myorg-myaccount -TokenFile ~\.snowflake\pat.txt -Warehouse WH -Role SYSADMIN
  ```

Things that Snowflake does and that are good to know:

- A root with no schedule and no condition cannot be resumed (`Test-TaskGraph` says so), and a graph can still be run by hand.
- A `WHEN` condition allows only a few functions (`SYSTEM$STREAM_HAS_DATA`, `SYSTEM$GET_PREDECESSOR_RETURN_VALUE`,
  `SYSTEM$PREDECESSORS_STATE`, `SYSTEM$TASK_COMPLETION_STATE`); Snowflake refuses the rest when the plan is applied.
- The SQL REST API returns times as seconds since 1970; Workflower turns them into ISO text.
- A programmatic access token may need a network policy, or an authentication policy that does not require one.

## Layout

```
workflower.ps1            the interface (Windows)
Workflower/               the module (Public: the commands; Private: the model, the connection, the JSON)
Workflower/ui/            the page (HTML, CSS, JavaScript; nothing is loaded from outside)
tests/                    Test-Offline.ps1, Test-Api.ps1, Test-Ui.ps1, Test-Live.ps1
unix/                     macOS and Linux: workflower (the script), engine.js (the logic, run in Snowflake), PROTOCOL.md, tests/
```

The first version of this tool kept workflows and run logs in an Anchor-modelled schema in Snowflake and rendered tasks with
Sisula templates. That is gone: it could only manage graphs that went through it. It is in the history, at the tag
`pre-rebuild`.
